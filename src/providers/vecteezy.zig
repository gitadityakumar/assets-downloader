//! Vecteezy provider — free stock photos, vectors, and design assets.
//! Search: GET https://www.vecteezy.com/search?qterm={query}&content_type=photo&license_class=free
//! Download: Direct master full-resolution media from CloudFront / Vecteezy CDN.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "vecteezy";
pub const name = "Vecteezy";

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) {
            return true;
        }
    }
    return false;
}

fn htmlUnescape(allocator: Allocator, s: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (std.mem.startsWith(u8, s[i..], "&amp;")) {
                try list.append(allocator, '&');
                i += 5;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&quot;")) {
                try list.append(allocator, '"');
                i += 6;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&#8211;")) {
                try list.append(allocator, '-');
                i += 7;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&#8212;")) {
                try list.append(allocator, '-');
                i += 7;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&#038;")) {
                try list.append(allocator, '&');
                i += 6;
                continue;
            }
            if (std.mem.startsWith(u8, s[i..], "&#39;") or std.mem.startsWith(u8, s[i..], "&apos;")) {
                try list.append(allocator, '\'');
                i += if (std.mem.startsWith(u8, s[i..], "&#39;")) 5 else 6;
                continue;
            }
        }
        try list.append(allocator, s[i]);
        i += 1;
    }
    return list.toOwnedSlice(allocator);
}

fn extractResourceId(allocator: Allocator, url: []const u8) ![]u8 {
    // URL looks like: https://static.vecteezy.com/system/resources/previews/004/572/561/non_2x/sunset-sky...
    const marker = "/previews/";
    if (std.mem.indexOf(u8, url, marker)) |idx| {
        const sub = url[idx + marker.len ..];
        if (std.mem.indexOf(u8, sub, "/non_2x/")) |end_idx| {
            const raw_id_part = sub[0..end_idx];
            var digits: std.ArrayList(u8) = .empty;
            defer digits.deinit(allocator);
            for (raw_id_part) |c| {
                if (std.ascii.isDigit(c)) {
                    try digits.append(allocator, c);
                }
            }
            if (digits.items.len > 0) {
                return try std.fmt.allocPrint(allocator, "vecteezy-{s}", .{digits.items});
            }
        }
    }
    // Fallback: use filename stem
    const last_slash = std.mem.lastIndexOfScalar(u8, url, '/') orelse return allocator.dupe(u8, "vecteezy-photo");
    var fn_stem = url[last_slash + 1 ..];
    if (std.mem.lastIndexOfScalar(u8, fn_stem, '.')) |dot| {
        fn_stem = fn_stem[0..dot];
    }
    return try std.fmt.allocPrint(allocator, "vecteezy-{s}", .{fn_stem});
}

fn parseSearch(allocator: Allocator, html: []const u8, query: []const u8, limit: u32) ![]Asset {
    var assets: std.ArrayList(Asset) = .empty;
    errdefer {
        for (assets.items) |*a| a.deinit(allocator);
        assets.deinit(allocator);
    }

    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var it = seen.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        seen.deinit(allocator);
    }

    const trimmed_query = std.mem.trim(u8, query, " \t\r\n");
    const script_marker = "<script";

    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, script_marker) orelse break;
        pos = found + script_marker.len;

        const script_end_tag = "</script>";
        const close_tag = std.mem.indexOfPos(u8, html, found, script_end_tag) orelse continue;
        const full_script = html[found .. close_tag + script_end_tag.len];
        pos = close_tag + script_end_tag.len;

        if (std.mem.indexOf(u8, full_script, "media_schema") == null or
            std.mem.indexOf(u8, full_script, "application/ld+json") == null)
        {
            continue;
        }

        const tag_close = std.mem.indexOfScalar(u8, full_script, '>') orelse continue;
        const json_body = full_script[tag_close + 1 .. full_script.len - script_end_tag.len];

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_body, .{}) catch continue;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;

        const name_val = root.object.get("name");
        const name_str = if (name_val) |nv| switch (nv) {
            .string => |s| s,
            else => "",
        } else "";

        const thumb_val = root.object.get("thumbnailUrl");
        const thumb_str = if (thumb_val) |tv| switch (tv) {
            .string => |s| s,
            else => "",
        } else "";

        const content_val = root.object.get("contentUrl");
        const content_str = if (content_val) |cv| switch (cv) {
            .string => |s| s,
            else => "",
        } else "";

        if (content_str.len == 0 and thumb_str.len == 0) continue;

        const active_url = if (content_str.len > 0) content_str else thumb_str;
        const res_id = try extractResourceId(allocator, active_url);
        errdefer allocator.free(res_id);

        if (seen.contains(res_id)) {
            allocator.free(res_id);
            continue;
        }
        try seen.put(allocator, try allocator.dupe(u8, res_id), {});

        // Build master URL by substituting /non_2x/ with /original/
        const master_url = if (std.mem.indexOf(u8, content_str, "/non_2x/")) |n_idx| blk: {
            const before = content_str[0..n_idx];
            const after = content_str[n_idx + "/non_2x/".len ..];
            break :blk try std.fmt.allocPrint(allocator, "{s}/original/{s}", .{ before, after });
        } else try allocator.dupe(u8, active_url);
        errdefer allocator.free(master_url);

        const thumb_owned = if (thumb_str.len > 0)
            try allocator.dupe(u8, thumb_str)
        else
            try allocator.dupe(u8, master_url);
        errdefer allocator.free(thumb_owned);

        const clean_desc = try htmlUnescape(allocator, if (name_str.len > 0) name_str else res_id);
        errdefer allocator.free(clean_desc);

        const prompt_owned = try allocator.dupe(u8, clean_desc);
        errdefer allocator.free(prompt_owned);

        const prov_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(prov_owned);

        const auth_owned = try allocator.dupe(u8, "Vecteezy Contributor");
        errdefer allocator.free(auth_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"vecteezy\",\"page\":\"https://www.vecteezy.com/\"}}", .{});
        const meta = try meta_aw.toOwnedSlice();

        _ = trimmed_query;

        try assets.append(allocator, .{
            .id = res_id,
            .description = clean_desc,
            .prompt = prompt_owned,
            .image_url = master_url,
            .thumbnail_url = thumb_owned,
            .provider = prov_owned,
            .author = auth_owned,
            .width = null,
            .height = null,
            .metadata_json = meta,
        });
    }

    return try assets.toOwnedSlice(allocator);
}

pub fn search(
    client: *std.http.Client,
    allocator: Allocator,
    query: []const u8,
    limit: u32,
) !SearchResult {
    const trimmed = std.mem.trim(u8, query, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyQuery;

    const enc = try http_client.queryEscape(allocator, trimmed);
    defer allocator.free(enc);

    const lim = @min(@max(limit, 1), 50);

    const search_url = try std.fmt.allocPrint(
        allocator,
        "https://www.vecteezy.com/search?qterm={s}&content_type=photo&license_class=free",
        .{enc},
    );
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://www.vecteezy.com/",
        .max_redirects = 5,
    });
    defer resp.deinit();
    if (resp.status != 200) return error.HttpStatus;

    const assets = try parseSearch(allocator, resp.body, trimmed, lim);

    return .{
        .assets = assets,
        .total = null,
        .provider = try allocator.dupe(u8, id),
        .query = try allocator.dupe(u8, trimmed),
        .allocator = allocator,
    };
}

pub fn download(
    client: *std.http.Client,
    allocator: Allocator,
    io: Io,
    a: Asset,
    output_dir: []const u8,
) !download_mod.Saved {
    const url = a.image_url orelse return error.NoUrl;

    // Try primary master original URL first
    var body_opt: ?[]u8 = http_client.getBody(client, allocator, url, .{
        .referer = "https://www.vecteezy.com/",
        .accept = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        .max_redirects = 5,
    }) catch null;

    // If master /original/ was not found or forbidden, fallback to /large_2x/ or thumbnail URL
    if (body_opt == null) {
        if (std.mem.indexOf(u8, url, "/original/")) |o_idx| {
            const fallback_url = try std.fmt.allocPrint(
                allocator,
                "{s}/non_2x/{s}",
                .{ url[0..o_idx], url[o_idx + "/original/".len ..] },
            );
            defer allocator.free(fallback_url);
            body_opt = http_client.getBody(client, allocator, fallback_url, .{
                .referer = "https://www.vecteezy.com/",
                .accept = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
                .max_redirects = 5,
            }) catch null;
        }
    }

    // Final fallback to thumbnail
    if (body_opt == null and a.thumbnail_url != null) {
        body_opt = http_client.getBody(client, allocator, a.thumbnail_url.?, .{
            .referer = "https://www.vecteezy.com/",
            .accept = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
            .max_redirects = 5,
        }) catch null;
    }

    const body = body_opt orelse return error.HttpStatus;
    defer allocator.free(body);
    if (body.len == 0) return error.HttpStatus;

    try download_mod.ensureDir(io, output_dir);
    const ext = download_mod.guessExtension(url);
    const path = try download_mod.uniquePath(allocator, io, output_dir, a.id, ext);
    errdefer allocator.free(path);
    const cwd = Io.Dir.cwd();
    cwd.writeFile(io, .{ .sub_path = path, .data = body }) catch return error.Io;
    return .{
        .path = path,
        .filename = std.fs.path.basename(path),
        .bytes = body.len,
        .allocator = allocator,
    };
}

pub fn getPrompt(a: Asset) ?[]const u8 {
    if (a.prompt) |p| if (p.len > 0) return p;
    if (a.description.len > 0) return a.description;
    return null;
}

pub fn getUrl(a: Asset) ?[]const u8 {
    return a.image_url;
}
