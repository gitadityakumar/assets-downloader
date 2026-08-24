//! Kaboompics provider — gallery search HTML with base64 data-modal JSON.
//! Search: GET /?search_keywords={query}
//! Download: GET /download/{name}/original

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "kaboompics";
pub const name = "Kaboompics";

fn b64Decode(allocator: Allocator, input: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const maxlen = try decoder.calcSizeForSlice(input);
    const out = try allocator.alloc(u8, maxlen);
    errdefer allocator.free(out);
    try decoder.decode(out, input);
    return out;
}

fn jsonString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    if (v != .string or v.string.len == 0) return null;
    return v.string;
}

fn jsonInt(obj: std.json.ObjectMap, key: []const u8) ?u32 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .integer => |n| if (n >= 0) @intCast(n) else null,
        else => null,
    };
}

fn absUrl(allocator: Allocator, path: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, path, "http://") or std.mem.startsWith(u8, path, "https://")) {
        return allocator.dupe(u8, path);
    }
    if (std.mem.startsWith(u8, path, "/")) {
        return std.fmt.allocPrint(allocator, "https://kaboompics.com{s}", .{path});
    }
    return std.fmt.allocPrint(allocator, "https://kaboompics.com/{s}", .{path});
}

fn parseSearch(allocator: Allocator, html: []const u8, limit: u32) ![]Asset {
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

    const marker = "data-modal=\"";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, marker) orelse break;
        pos = found + marker.len;
        const end = std.mem.indexOfScalarPos(u8, html, pos, '"') orelse break;
        const b64 = html[pos..end];
        pos = end + 1;
        if (b64.len < 20) continue;

        const decoded = b64Decode(allocator, b64) catch continue;
        defer allocator.free(decoded);

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, decoded, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const photo_v = parsed.value.object.get("photo") orelse continue;
        if (photo_v != .object) continue;
        const photo = photo_v.object;

        const name_hash = jsonString(photo, "name") orelse continue;
        if (seen.contains(name_hash)) continue;

        const pid = if (jsonInt(photo, "id")) |n|
            try std.fmt.allocPrint(allocator, "{d}", .{n})
        else
            try allocator.dupe(u8, name_hash);
        errdefer allocator.free(pid);

        const alt = jsonString(photo, "alt") orelse jsonString(photo, "headerTitle") orelse jsonString(photo, "seoAlt") orelse pid;
        const image_src = jsonString(photo, "imageSrc");
        const href = jsonString(photo, "href");

        const download_url = try std.fmt.allocPrint(allocator, "https://kaboompics.com/download/{s}/original", .{name_hash});
        errdefer allocator.free(download_url);

        var thumb: ?[]u8 = null;
        if (image_src) |src| {
            thumb = try absUrl(allocator, src);
        }
        errdefer if (thumb) |t| allocator.free(t);

        var author: ?[]const u8 = null;
        if (parsed.value.object.get("photographer")) |ph| {
            if (ph == .object) {
                if (jsonString(ph.object, "username")) |u| {
                    author = try allocator.dupe(u8, u);
                }
            }
        }
        errdefer if (author) |a| allocator.free(a);

        try seen.put(allocator, try allocator.dupe(u8, name_hash), {});

        const desc_owned = try allocator.dupe(u8, alt);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, alt);
        errdefer allocator.free(prompt_owned);
        const provider_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(provider_owned);
        const thumb_owned = thumb orelse try allocator.dupe(u8, download_url);
        thumb = null;

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.writeAll("{\"source\":\"kaboompics\"");
        try meta_aw.writer.print(",\"name\":\"{s}\"", .{name_hash});
        if (href) |h| try meta_aw.writer.print(",\"href\":\"{s}\"", .{h});
        try meta_aw.writer.writeAll("}");
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = download_url,
            .thumbnail_url = thumb_owned,
            .provider = provider_owned,
            .author = author,
            .width = jsonInt(photo, "width"),
            .height = jsonInt(photo, "height"),
            .metadata_json = meta,
        });
        author = null;
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
    const search_url = try std.fmt.allocPrint(allocator, "https://kaboompics.com/?search_keywords={s}", .{enc});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://kaboompics.com/",
        .max_redirects = 5,
    });
    defer resp.deinit();
    if (resp.status != 200) return error.HttpStatus;

    const lim = @min(@max(limit, 1), 50);
    const assets = try parseSearch(allocator, resp.body, lim);

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
    const body = http_client.getBody(client, allocator, url, .{
        .referer = "https://kaboompics.com/",
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
    const path = try download_mod.uniquePath(allocator, io, output_dir, a.id, "jpg");
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
