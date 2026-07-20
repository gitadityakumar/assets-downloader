//! Anubis / BotStopper (Techaro) PoW for Unsplash HTML access.
//! "fast": SHA256(randomData + decimal_nonce) with leading zero-nibble difficulty.

const std = @import("std");
const http_client = @import("http_client.zig");
const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const AnubisError = error{
    Network,
    ChallengeMissing,
    ChallengeParse,
    PassFailed,
    OutOfMemory,
    InvalidUri,
};

const ChallengePayload = struct {
    rules: struct {
        algorithm: []const u8,
        difficulty: u32,
    },
    challenge: struct {
        id: []const u8,
        randomData: []const u8,
        difficulty: ?u32 = null,
        method: ?[]const u8 = null,
    },
};

fn isSolved(hash: *const [32]u8, difficulty: u32) bool {
    const p = difficulty / 2;
    const odd = difficulty % 2 != 0;
    var i: u32 = 0;
    while (i < p) : (i += 1) {
        if (hash[i] != 0) return false;
    }
    if (odd and (hash[p] >> 4) != 0) return false;
    return true;
}

pub fn solvePow(random_data: []const u8, difficulty: u32) struct { nonce: u64, hash_hex: [64]u8 } {
    var nonce: u64 = 0;
    var hash_hex: [64]u8 = undefined;
    while (true) {
        var nonce_buf: [32]u8 = undefined;
        const nonce_str = std.fmt.bufPrint(&nonce_buf, "{d}", .{nonce}) catch unreachable;

        var hasher = Sha256.init(.{});
        hasher.update(random_data);
        hasher.update(nonce_str);
        var digest: [32]u8 = undefined;
        hasher.final(&digest);

        if (isSolved(&digest, difficulty)) {
            const hex = std.fmt.bytesToHex(digest, .lower);
            @memcpy(&hash_hex, &hex);
            return .{ .nonce = nonce, .hash_hex = hash_hex };
        }
        nonce += 1;
    }
}

fn extractChallengeJson(html: []const u8) ?[]const u8 {
    const marker = "id=\"anubis_challenge\"";
    const start_m = std.mem.indexOf(u8, html, marker) orelse return null;
    const gt = std.mem.indexOfPos(u8, html, start_m, ">") orelse return null;
    const end = std.mem.indexOfPos(u8, html, gt + 1, "</script>") orelse return null;
    return std.mem.trim(u8, html[gt + 1 .. end], " \t\n\r");
}

fn pathFromUrl(url: []const u8) []const u8 {
    if (std.mem.indexOf(u8, url, "://")) |scheme| {
        const after = url[scheme + 3 ..];
        if (std.mem.indexOfScalar(u8, after, '/')) |slash| {
            return after[slash..];
        }
        return "/";
    }
    if (std.mem.startsWith(u8, url, "/")) return url;
    return "/";
}

/// Ensure cookie jar has Anubis auth so `target_url` HTML can be fetched.
pub fn ensureAccess(
    client: *std.http.Client,
    allocator: Allocator,
    jar: *http_client.CookieJar,
    target_url: []const u8,
) AnubisError!void {
    const cookie_hdr = jar.headerValue(allocator) catch return error.OutOfMemory;
    defer if (cookie_hdr) |c| allocator.free(c);

    var resp = http_client.get(client, allocator, target_url, .{
        .cookie = cookie_hdr,
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .max_redirects = 0,
    }) catch return error.Network;
    defer resp.deinit();
    jar.absorbResponse(&resp);

    if (resp.status == 200 and std.mem.indexOf(u8, resp.body, "anubis_challenge") == null) {
        return;
    }

    var challenge_body: []u8 = undefined;
    var free_challenge = false;
    defer if (free_challenge) allocator.free(challenge_body);

    if (resp.status == 301 or resp.status == 302 or resp.status == 303 or resp.status == 307 or resp.status == 308) {
        const loc = resp.location orelse return error.ChallengeMissing;
        const full = if (std.mem.startsWith(u8, loc, "http"))
            allocator.dupe(u8, loc) catch return error.OutOfMemory
        else
            std.fmt.allocPrint(allocator, "https://unsplash.com{s}", .{loc}) catch return error.OutOfMemory;
        defer allocator.free(full);

        const cookie2 = jar.headerValue(allocator) catch return error.OutOfMemory;
        defer if (cookie2) |c| allocator.free(c);

        var resp2 = http_client.get(client, allocator, full, .{
            .cookie = cookie2,
            .accept = "text/html,*/*",
            .max_redirects = 0,
        }) catch return error.Network;
        defer resp2.deinit();
        jar.absorbResponse(&resp2);

        if (std.mem.indexOf(u8, resp2.body, "anubis_challenge") == null) {
            return error.ChallengeMissing;
        }
        challenge_body = allocator.dupe(u8, resp2.body) catch return error.OutOfMemory;
        free_challenge = true;
    } else if (std.mem.indexOf(u8, resp.body, "anubis_challenge") != null) {
        challenge_body = allocator.dupe(u8, resp.body) catch return error.OutOfMemory;
        free_challenge = true;
    } else {
        return error.ChallengeMissing;
    }

    try solveAndPass(client, allocator, jar, challenge_body, target_url);
}

fn solveAndPass(
    client: *std.http.Client,
    allocator: Allocator,
    jar: *http_client.CookieJar,
    html: []const u8,
    target_url: []const u8,
) AnubisError!void {
    const json_slice = extractChallengeJson(html) orelse return error.ChallengeMissing;

    const parsed = std.json.parseFromSlice(ChallengePayload, allocator, json_slice, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return error.ChallengeParse;
    defer parsed.deinit();

    const ch = parsed.value;
    if (!std.mem.eql(u8, ch.rules.algorithm, "fast")) return error.ChallengeParse;

    const solved = solvePow(ch.challenge.randomData, ch.rules.difficulty);

    const redir_path = pathFromUrl(target_url);
    const redir_enc = http_client.queryEscape(allocator, redir_path) catch return error.OutOfMemory;
    defer allocator.free(redir_enc);

    const pass_url = std.fmt.allocPrint(
        allocator,
        "https://unsplash.com/.within.website/x/cmd/anubis/api/pass-challenge?id={s}&response={s}&nonce={d}&redir={s}&elapsedTime=50",
        .{ ch.challenge.id, solved.hash_hex[0..], solved.nonce, redir_enc },
    ) catch return error.OutOfMemory;
    defer allocator.free(pass_url);

    const cookie_hdr = jar.headerValue(allocator) catch return error.OutOfMemory;
    defer if (cookie_hdr) |c| allocator.free(c);

    var pass_resp = http_client.get(client, allocator, pass_url, .{
        .cookie = cookie_hdr,
        .accept = "text/html,*/*",
        .max_redirects = 0,
    }) catch return error.Network;
    defer pass_resp.deinit();
    jar.absorbResponse(&pass_resp);

    if (pass_resp.status != 302 and pass_resp.status != 301 and pass_resp.status != 200 and pass_resp.status != 303) {
        return error.PassFailed;
    }

    // Mirror browser: verification cookie = challenge id
    const ver = std.fmt.allocPrint(allocator, "techaro.lol-anubis-cookie-verification={s}", .{ch.challenge.id}) catch return error.OutOfMemory;
    defer allocator.free(ver);
    jar.putFromSetCookie(ver) catch {};
}
