//! Skitterphoto provider — 100% free CC0 public domain photos.
//! Search: GET https://skitterphoto.com/photos/tags/{tag}
//! Download: Direct high-resolution JPEG from Skitterphoto CDN.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "skitterphoto";
pub const name = "Skitterphoto";

fn formatTag(allocator: Allocator, query: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, query, " \t\r\n");
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    for (trimmed) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try list.append(allocator, std.ascii.toLower(c));
        } else if (c == ' ' or c == '-' or c == '_') {
            if (list.items.len > 0 and list.items[list.items.len - 1] != '-') {
                try list.append(allocator, '-');
            }
        }
    }
    if (list.items.len == 0) {
        try list.appendSlice(allocator, "nature");
    }
    return list.toOwnedSlice(allocator);
}

fn formatTitleFromSlug(allocator: Allocator, slug: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    var cap_next = true;
    for (slug) |c| {
        if (c == '-' or c == '_' or c == '/') {
            if (list.items.len > 0 and list.items[list.items.len - 1] != ' ') {
                try list.append(allocator, ' ');
            }
            cap_next = true;
        } else if (cap_next and std.ascii.isAlphabetic(c)) {
            try list.append(allocator, std.ascii.toUpper(c));
            cap_next = false;
        } else {
            try list.append(allocator, c);
            cap_next = false;
        }
    }
    return list.toOwnedSlice(allocator);
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

    const marker = "https://skitterphoto.com/photos/";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, marker) orelse break;
        pos = found + marker.len;

        const rest = html[pos..];
        var id_len: usize = 0;
        while (id_len < rest.len and std.ascii.isDigit(rest[id_len])) : (id_len += 1) {}
        if (id_len == 0) continue;

        const photo_id = rest[0..id_len];
        if (seen.contains(photo_id)) continue;

        var slug: []const u8 = "";
        if (id_len < rest.len and rest[id_len] == '/') {
            const slug_start = id_len + 1;
            var slug_end = slug_start;
            while (slug_end < rest.len and rest[slug_end] != '"' and rest[slug_end] != '\'' and rest[slug_end] != ' ' and rest[slug_end] != '>') : (slug_end += 1) {}
            if (slug_end > slug_start) {
                slug = rest[slug_start..slug_end];
            }
        }

        try seen.put(allocator, try allocator.dupe(u8, photo_id), {});

        const pid = try allocator.dupe(u8, photo_id);
        errdefer allocator.free(pid);

        const desc = if (slug.len > 0)
            try formatTitleFromSlug(allocator, slug)
        else
            try std.fmt.allocPrint(allocator, "Skitterphoto Photo {s}", .{photo_id});
        errdefer allocator.free(desc);

        const prompt_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt_owned);

        const img_url = try std.fmt.allocPrint(allocator, "https://skitterphoto.com/photos/skitterphoto-{s}-default.jpg", .{photo_id});
        errdefer allocator.free(img_url);

        const thumb_url = try std.fmt.allocPrint(allocator, "https://skitterphoto.com/photos/skitterphoto-{s}-thumbnail.jpg", .{photo_id});
        errdefer allocator.free(thumb_url);

        const prov_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(prov_owned);

        const auth_owned = try allocator.dupe(u8, "Skitterphoto");
        errdefer allocator.free(auth_owned);

        const page_url = if (slug.len > 0)
            try std.fmt.allocPrint(allocator, "https://skitterphoto.com/photos/{s}/{s}", .{ photo_id, slug })
        else
            try std.fmt.allocPrint(allocator, "https://skitterphoto.com/photos/{s}", .{photo_id});
        defer allocator.free(page_url);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"skitterphoto\",\"page\":\"{s}\"}}", .{page_url});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc,
            .prompt = prompt_owned,
            .image_url = img_url,
            .thumbnail_url = thumb_url,
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
    const tag = try formatTag(allocator, query);
    defer allocator.free(tag);

    const search_url = try std.fmt.allocPrint(allocator, "https://skitterphoto.com/photos/tags/{s}", .{tag});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://skitterphoto.com/",
        .max_redirects = 5,
    });
    defer resp.deinit();
    if (resp.status != 200) {
        // Fallback to latest photos feed if tag not found
        var fallback_resp = try http_client.get(client, allocator, "https://skitterphoto.com/photos", .{
            .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            .referer = "https://skitterphoto.com/",
            .max_redirects = 5,
        });
        defer fallback_resp.deinit();
        if (fallback_resp.status != 200) return error.HttpStatus;

        const lim = @min(@max(limit, 1), 50);
        const assets = try parseSearch(allocator, fallback_resp.body, lim);
        return .{
            .assets = assets,
            .total = null,
            .provider = try allocator.dupe(u8, id),
            .query = try allocator.dupe(u8, query),
            .allocator = allocator,
        };
    }

    const lim = @min(@max(limit, 1), 50);
    const assets = try parseSearch(allocator, resp.body, lim);

    return .{
        .assets = assets,
        .total = null,
        .provider = try allocator.dupe(u8, id),
        .query = try allocator.dupe(u8, query),
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
        .referer = "https://skitterphoto.com/",
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
