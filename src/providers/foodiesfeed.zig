//! Foodiesfeed provider — Next.js search page with embedded photo JSON.
//! Search: GET /s/{query}
//! Download: master_url on R2 CDN.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "foodiesfeed";
pub const name = "Foodiesfeed";

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
    if (list.items.len == 0) try list.appendSlice(allocator, "food");
    return list.toOwnedSlice(allocator);
}

fn unescapeJsonWindow(allocator: Allocator, slice: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    var i: usize = 0;
    while (i < slice.len) {
        if (i + 1 < slice.len and slice[i] == '\\' and slice[i + 1] == '"') {
            try list.append(allocator, '"');
            i += 2;
        } else if (i + 1 < slice.len and slice[i] == '\\' and slice[i + 1] == '\\') {
            try list.append(allocator, '\\');
            i += 2;
        } else if (i + 1 < slice.len and slice[i] == '\\' and slice[i + 1] == '/') {
            try list.append(allocator, '/');
            i += 2;
        } else if (i + 1 < slice.len and slice[i] == '\\' and slice[i + 1] == 'n') {
            try list.append(allocator, '\n');
            i += 2;
        } else if (i + 1 < slice.len and slice[i] == '\\' and slice[i + 1] == 'u') {
            // skip simple unicode escapes as '?'
            if (i + 5 < slice.len) {
                try list.append(allocator, '?');
                i += 6;
            } else {
                try list.append(allocator, slice[i]);
                i += 1;
            }
        } else {
            try list.append(allocator, slice[i]);
            i += 1;
        }
    }
    return list.toOwnedSlice(allocator);
}

fn extractField(obj: []const u8, key: []const u8) ?[]const u8 {
    // "key":"value"
    var buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&buf, "\"{s}\":\"", .{key}) catch return null;
    const idx = std.mem.indexOf(u8, obj, needle) orelse return null;
    const start = idx + needle.len;
    var i = start;
    while (i < obj.len) : (i += 1) {
        if (obj[i] == '\\' and i + 1 < obj.len) {
            i += 1;
            continue;
        }
        if (obj[i] == '"') return obj[start..i];
    }
    return null;
}

fn extractIntField(obj: []const u8, key: []const u8) ?u32 {
    var buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&buf, "\"{s}\":", .{key}) catch return null;
    const idx = std.mem.indexOf(u8, obj, needle) orelse return null;
    var i = idx + needle.len;
    while (i < obj.len and (obj[i] == ' ' or obj[i] == '\t')) : (i += 1) {}
    const start = i;
    while (i < obj.len and obj[i] >= '0' and obj[i] <= '9') : (i += 1) {}
    if (i == start) return null;
    return std.fmt.parseInt(u32, obj[start..i], 10) catch null;
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

    // Prefer escaped form in RSC payload: \"master_url\":\"https://...
    const markers = [_][]const u8{ "\\\"master_url\\\":\\\"", "\"master_url\":\"" };
    for (markers) |marker| {
        var pos: usize = 0;
        while (assets.items.len < limit) {
            const found = std.mem.indexOfPos(u8, html, pos, marker) orelse break;
            pos = found + 1;
            const win_start = if (found > 800) found - 800 else 0;
            const win_end = @min(html.len, found + 600);
            const window = html[win_start..win_end];

            const unesc = unescapeJsonWindow(allocator, window) catch continue;
            defer allocator.free(unesc);

            const master = extractField(unesc, "master_url") orelse continue;
            if (!std.mem.startsWith(u8, master, "http")) continue;
            const slug = extractField(unesc, "slug") orelse blk: {
                // filename without ext
                const slash = std.mem.lastIndexOfScalar(u8, master, '/') orelse break :blk "photo";
                const file = master[slash + 1 ..];
                const dot = std.mem.lastIndexOfScalar(u8, file, '.') orelse file.len;
                break :blk file[0..dot];
            };
            if (seen.contains(slug)) continue;

            const title = extractField(unesc, "title");
            const desc_field = extractField(unesc, "description");
            const thumb = extractField(unesc, "thumbnail_url") orelse extractField(unesc, "webp_url") orelse master;
            const width = extractIntField(unesc, "width");
            const height = extractIntField(unesc, "height");

            // Prefer English-looking title; fall back to slug
            const desc = blk: {
                if (title) |t| {
                    var ascii = true;
                    for (t) |c| {
                        if (c >= 0x80) {
                            ascii = false;
                            break;
                        }
                    }
                    if (ascii and t.len > 0) break :blk t;
                }
                if (desc_field) |d| {
                    var ascii = true;
                    for (d) |c| {
                        if (c >= 0x80) {
                            ascii = false;
                            break;
                        }
                    }
                    if (ascii and d.len > 0) break :blk d;
                }
                break :blk slug;
            };

            const id_owned = try allocator.dupe(u8, slug);
            errdefer allocator.free(id_owned);
            try seen.put(allocator, try allocator.dupe(u8, slug), {});

            const desc_owned = try allocator.dupe(u8, desc);
            errdefer allocator.free(desc_owned);
            const prompt_owned = try allocator.dupe(u8, desc);
            errdefer allocator.free(prompt_owned);
            const image_owned = try allocator.dupe(u8, master);
            errdefer allocator.free(image_owned);
            const thumb_owned = try allocator.dupe(u8, thumb);
            errdefer allocator.free(thumb_owned);
            const provider_owned = try allocator.dupe(u8, id);
            errdefer allocator.free(provider_owned);

            var meta_aw: Io.Writer.Allocating = .init(allocator);
            defer meta_aw.deinit();
            try meta_aw.writer.print("{{\"source\":\"foodiesfeed\",\"slug\":\"{s}\"}}", .{slug});
            const meta = try meta_aw.toOwnedSlice();

            try assets.append(allocator, .{
                .id = id_owned,
                .description = desc_owned,
                .prompt = prompt_owned,
                .image_url = image_owned,
                .thumbnail_url = thumb_owned,
                .provider = provider_owned,
                .author = null,
                .width = width,
                .height = height,
                .metadata_json = meta,
            });
        }
        if (assets.items.len > 0) break;
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
    const search_url = try std.fmt.allocPrint(allocator, "https://www.foodiesfeed.com/s/{s}", .{slug});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://www.foodiesfeed.com/",
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
        .referer = "https://www.foodiesfeed.com/",
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
