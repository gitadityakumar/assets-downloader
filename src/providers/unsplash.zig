//! Unsplash provider — browser-style, no API key.
//! Search: HTML /s/photos/{query} after Anubis PoW.
//! Download: right-click style GET of urls.regular CDN URL.
//! See docs/unsplash.md

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const anubis = @import("../anubis.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "unsplash";
pub const name = "Unsplash";

/// Process-lifetime cookie jar (Anubis auth). Must call `deinitGlobals` before exit
/// so DebugAllocator does not report leaks.
var global_jar: ?http_client.CookieJar = null;

fn jar(allocator: Allocator) *http_client.CookieJar {
    if (global_jar == null) {
        global_jar = http_client.CookieJar.init(allocator);
    }
    return &global_jar.?;
}

/// Free Anubis/session cookies. Safe to call multiple times.
pub fn deinitGlobals() void {
    if (global_jar) |*j| {
        j.deinit();
        global_jar = null;
    }
}

fn slugify(allocator: Allocator, query: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    var prev_dash = false;
    for (query) |c| {
        const lower = std.ascii.toLower(c);
        if ((lower >= 'a' and lower <= 'z') or (lower >= '0' and lower <= '9')) {
            try list.append(allocator, lower);
            prev_dash = false;
        } else if (c == ' ' or c == '-' or c == '_') {
            if (!prev_dash and list.items.len > 0) {
                try list.append(allocator, '-');
                prev_dash = true;
            }
        }
    }
    // trim trailing dash
    while (list.items.len > 0 and list.items[list.items.len - 1] == '-') {
        _ = list.pop();
    }
    if (list.items.len == 0) try list.appendSlice(allocator, "photos");
    return list.toOwnedSlice(allocator);
}

/// Parse escaped photo JSON objects from Unsplash SSR HTML.
fn parsePhotosFromHtml(allocator: Allocator, html: []const u8, limit: u32) ![]Asset {
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

    const marker = "{\\\"id\\\":\\\"";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, marker) orelse break;
        pos = found + 1;

        // Extract balanced braces on unescaped form
        const slice = html[found..];
        // Unescape \" → " for a window
        const window_len = @min(slice.len, 12000);
        var unesc: std.ArrayList(u8) = .empty;
        defer unesc.deinit(allocator);

        var i: usize = 0;
        while (i < window_len) {
            if (i + 1 < window_len and slice[i] == '\\' and slice[i + 1] == '"') {
                try unesc.append(allocator, '"');
                i += 2;
            } else if (i + 1 < window_len and slice[i] == '\\' and slice[i + 1] == '\\') {
                try unesc.append(allocator, '\\');
                i += 2;
            } else {
                try unesc.append(allocator, slice[i]);
                i += 1;
            }
        }

        // Find matching brace
        if (unesc.items.len == 0 or unesc.items[0] != '{') continue;
        var depth: i32 = 0;
        var end: ?usize = null;
        for (unesc.items, 0..) |c, idx| {
            if (c == '{') depth += 1;
            if (c == '}') {
                depth -= 1;
                if (depth == 0) {
                    end = idx + 1;
                    break;
                }
            }
        }
        const end_i = end orelse continue;
        const obj_str = unesc.items[0..end_i];

        // Must look like a photo: has urls
        if (std.mem.indexOf(u8, obj_str, "\"urls\"") == null) continue;
        if (std.mem.indexOf(u8, obj_str, "\"regular\"") == null) continue;

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, obj_str, .{}) catch continue;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) continue;
        const obj = root.object;

        const pid_val = obj.get("id") orelse continue;
        if (pid_val != .string) continue;
        const pid = pid_val.string;
        if (pid.len < 6 or pid.len > 20) continue;

        // Skip duplicates
        if (seen.contains(pid)) continue;

        // Skip premium/plus
        if (obj.get("premium")) |p| {
            if (p == .bool and p.bool) continue;
        }
        if (obj.get("plus")) |p| {
            if (p == .bool and p.bool) continue;
        }

        const urls_v = obj.get("urls") orelse continue;
        if (urls_v != .object) continue;
        const urls = urls_v.object;

        const regular = blk: {
            if (urls.get("regular")) |r| {
                if (r == .string) break :blk r.string;
            }
            if (urls.get("small")) |r| {
                if (r == .string) break :blk r.string;
            }
            if (urls.get("full")) |r| {
                if (r == .string) break :blk r.string;
            }
            continue;
        };

        // Skip plus CDN for free downloads
        if (std.mem.indexOf(u8, regular, "plus.unsplash.com") != null) continue;

        const thumb = blk: {
            if (urls.get("small")) |r| {
                if (r == .string) break :blk r.string;
            }
            if (urls.get("thumb")) |r| {
                if (r == .string) break :blk r.string;
            }
            break :blk regular;
        };

        var desc: []const u8 = pid;
        if (obj.get("alt_description")) |a| {
            if (a == .string and a.string.len > 0) desc = a.string;
        } else if (obj.get("description")) |d| {
            if (d == .string and d.string.len > 0) desc = d.string;
        }

        var author: ?[]const u8 = null;
        if (obj.get("user")) |u| {
            if (u == .object) {
                if (u.object.get("name")) |n| {
                    if (n == .string) author = n.string;
                }
            }
        }

        var width: ?u32 = null;
        var height: ?u32 = null;
        if (obj.get("width")) |w| {
            if (w == .integer) width = @intCast(w.integer);
        }
        if (obj.get("height")) |h| {
            if (h == .integer) height = @intCast(h.integer);
        }

        const id_owned = try allocator.dupe(u8, pid);
        errdefer allocator.free(id_owned);
        try seen.put(allocator, try allocator.dupe(u8, pid), {});

        const desc_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt_owned);
        const image_owned = try allocator.dupe(u8, regular);
        errdefer allocator.free(image_owned);
        const thumb_owned = try allocator.dupe(u8, thumb);
        errdefer allocator.free(thumb_owned);
        const provider_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(provider_owned);
        const author_owned: ?[]const u8 = if (author) |a| try allocator.dupe(u8, a) else null;
        errdefer if (author_owned) |a| allocator.free(a);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.writeAll("{\"source\":\"unsplash\"");
        if (obj.get("slug")) |s| {
            if (s == .string) try meta_aw.writer.print(",\"slug\":\"{s}\"", .{s.string});
        }
        try meta_aw.writer.writeAll("}");
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = id_owned,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = image_owned,
            .thumbnail_url = thumb_owned,
            .provider = provider_owned,
            .author = author_owned,
            .width = width,
            .height = height,
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

    const slug = try slugify(allocator, trimmed);
    defer allocator.free(slug);

    const search_url = try std.fmt.allocPrint(allocator, "https://unsplash.com/s/photos/{s}", .{slug});
    defer allocator.free(search_url);

    const j = jar(allocator);
    anubis.ensureAccess(client, allocator, j, search_url) catch |err| {
        return switch (err) {
            error.Network => error.Network,
            error.OutOfMemory => error.OutOfMemory,
            else => error.HttpStatus,
        };
    };

    const cookie_hdr = try j.headerValue(allocator);
    defer if (cookie_hdr) |c| allocator.free(c);

    var resp = try http_client.get(client, allocator, search_url, .{
        .cookie = cookie_hdr,
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://unsplash.com/",
        .max_redirects = 3,
    });
    defer resp.deinit();
    j.absorbResponse(&resp);

    if (resp.status != 200) return error.HttpStatus;
    if (std.mem.indexOf(u8, resp.body, "anubis_challenge") != null) return error.HttpStatus;

    const lim = @min(@max(limit, 1), 50);
    const assets = try parsePhotosFromHtml(allocator, resp.body, lim);

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
    // Right-click style: GET display CDN URL (image_url = urls.regular)
    const url = a.image_url orelse return error.NoUrl;

    // Use http_client with referer for CDN
    const body = http_client.getBody(client, allocator, url, .{
        .referer = "https://unsplash.com/",
        .accept = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        .max_redirects = 5,
    }) catch |err| switch (err) {
        error.RateLimited => return error.RateLimited,
        error.HttpStatus => return error.HttpStatus,
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Network,
    };
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
