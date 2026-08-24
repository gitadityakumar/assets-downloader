//! Pexels provider — browser-style, no API key.
//! Search: HTML /search/{query}/ with __NEXT_DATA__ JSON.
//! Download: images.pexels.com CDN (image.download_link or large).

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "pexels";
pub const name = "Pexels";

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
    while (list.items.len > 0 and list.items[list.items.len - 1] == '-') {
        _ = list.pop();
    }
    if (list.items.len == 0) try list.appendSlice(allocator, "photos");
    return list.toOwnedSlice(allocator);
}

fn extractNextData(html: []const u8) ?[]const u8 {
    const marker = "id=\"__NEXT_DATA__\"";
    const start_tag = std.mem.indexOf(u8, html, marker) orelse return null;
    const gt = std.mem.indexOfPos(u8, html, start_tag, ">") orelse return null;
    const json_start = gt + 1;
    const json_end = std.mem.indexOfPos(u8, html, json_start, "</script>") orelse return null;
    return html[json_start..json_end];
}

fn jsonString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    if (v != .string) return null;
    if (v.string.len == 0) return null;
    return v.string;
}

fn jsonInt(obj: std.json.ObjectMap, key: []const u8) ?u32 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        .float => |f| if (f >= 0) @intFromFloat(f) else null,
        else => null,
    };
}

fn photoId(allocator: Allocator, item: std.json.ObjectMap, attrs: std.json.ObjectMap) !?[]u8 {
    if (jsonString(attrs, "id")) |s| return try allocator.dupe(u8, s);
    if (jsonString(item, "id")) |s| return try allocator.dupe(u8, s);
    if (jsonInt(attrs, "id")) |n| return try std.fmt.allocPrint(allocator, "{d}", .{n});
    if (item.get("id")) |v| {
        if (v == .integer and v.integer >= 0) return try std.fmt.allocPrint(allocator, "{d}", .{v.integer});
    }
    return null;
}

fn parsePhotos(allocator: Allocator, html: []const u8, limit: u32) ![]Asset {
    var assets: std.ArrayList(Asset) = .empty;
    errdefer {
        for (assets.items) |*a| a.deinit(allocator);
        assets.deinit(allocator);
    }

    const raw = extractNextData(html) orelse return error.HttpStatus;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch return error.HttpStatus;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.HttpStatus;
    const props = root.object.get("props") orelse return error.HttpStatus;
    if (props != .object) return error.HttpStatus;
    const page_props = props.object.get("pageProps") orelse return error.HttpStatus;
    if (page_props != .object) return error.HttpStatus;
    const initial = page_props.object.get("initialData") orelse return error.HttpStatus;
    if (initial != .object) return error.HttpStatus;
    const data = initial.object.get("data") orelse return error.HttpStatus;
    if (data != .array) return error.HttpStatus;

    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var it = seen.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        seen.deinit(allocator);
    }

    for (data.array.items) |item| {
        if (assets.items.len >= limit) break;
        if (item != .object) continue;
        const type_s = jsonString(item.object, "type") orelse "photo";
        if (!std.mem.eql(u8, type_s, "photo")) continue;

        const attrs_v = item.object.get("attributes") orelse continue;
        if (attrs_v != .object) continue;
        const attrs = attrs_v.object;

        const pid = (try photoId(allocator, item.object, attrs)) orelse continue;
        errdefer allocator.free(pid);
        if (seen.contains(pid)) {
            allocator.free(pid);
            continue;
        }

        const image_v = attrs.get("image") orelse {
            allocator.free(pid);
            continue;
        };
        if (image_v != .object) {
            allocator.free(pid);
            continue;
        }
        const image = image_v.object;

        const download_link = jsonString(image, "download_link");
        const large = jsonString(image, "large");
        const medium = jsonString(image, "medium");
        const small = jsonString(image, "small");
        const image_url = download_link orelse large orelse medium orelse {
            allocator.free(pid);
            continue;
        };
        const thumb = small orelse medium orelse large orelse image_url;

        const title = jsonString(attrs, "title");
        const alt = jsonString(attrs, "alt") orelse jsonString(attrs, "description");
        const desc = title orelse alt orelse pid;

        var author: ?[]const u8 = null;
        if (attrs.get("user")) |u| {
            if (u == .object) {
                const first = jsonString(u.object, "first_name") orelse "";
                const last = jsonString(u.object, "last_name") orelse "";
                if (first.len > 0 or last.len > 0) {
                    author = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
                        first,
                        if (first.len > 0 and last.len > 0) " " else "",
                        last,
                    });
                }
            }
        }
        errdefer if (author) |a| allocator.free(a);

        const width = jsonInt(attrs, "width");
        const height = jsonInt(attrs, "height");
        const slug = jsonString(attrs, "slug");

        try seen.put(allocator, try allocator.dupe(u8, pid), {});

        const desc_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, alt orelse desc);
        errdefer allocator.free(prompt_owned);
        const image_owned = try allocator.dupe(u8, image_url);
        errdefer allocator.free(image_owned);
        const thumb_owned = try allocator.dupe(u8, thumb);
        errdefer allocator.free(thumb_owned);
        const provider_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(provider_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.writeAll("{\"source\":\"pexels\"");
        if (slug) |s| try meta_aw.writer.print(",\"slug\":\"{s}\"", .{s});
        try meta_aw.writer.writeAll("}");
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = image_owned,
            .thumbnail_url = thumb_owned,
            .provider = provider_owned,
            .author = author,
            .width = width,
            .height = height,
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

    const slug = try slugify(allocator, trimmed);
    defer allocator.free(slug);

    const search_url = try std.fmt.allocPrint(allocator, "https://www.pexels.com/search/{s}/", .{slug});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://www.pexels.com/",
        .max_redirects = 5,
    });
    defer resp.deinit();
    if (resp.status != 200) return error.HttpStatus;

    const lim = @min(@max(limit, 1), 50);
    const assets = try parsePhotos(allocator, resp.body, lim);

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
        .referer = "https://www.pexels.com/",
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
