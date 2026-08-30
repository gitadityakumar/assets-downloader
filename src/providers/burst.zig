//! Burst by Shopify provider — free high-resolution stock photography for websites and commercial use.
//! Search: GET https://burst.shopify.com/photos/search?q={query}
//! Download: full-size CDN URL on burst.shopifycdn.com (strip query parameters).

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "burst";
pub const name = "Burst by Shopify";

fn fullSizeUrl(allocator: Allocator, src_url: []const u8) ![]u8 {
    // https://burst.shopifycdn.com/photos/image.jpg?width=1000&... → https://burst.shopifycdn.com/photos/image.jpg
    const q = std.mem.indexOfScalar(u8, src_url, '?') orelse src_url.len;
    return allocator.dupe(u8, src_url[0..q]);
}

fn idFromUrl(allocator: Allocator, page_url: []const u8) ![]u8 {
    // /stock-photos/photos/coffee-on-rustic-table?q=coffee → coffee-on-rustic-table
    const q = std.mem.indexOfScalar(u8, page_url, '?') orelse page_url.len;
    var u = page_url[0..q];
    if (std.mem.endsWith(u8, u, "/")) u = u[0 .. u.len - 1];
    const slash = std.mem.lastIndexOfScalar(u8, u, '/') orelse return allocator.dupe(u8, "photo");
    var base = u[slash + 1 ..];
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
        base = base[0..dot];
    }
    return allocator.dupe(u8, base);
}

fn htmlUnescapeBasic(allocator: Allocator, s: []const u8) ![]u8 {
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
            if (std.mem.startsWith(u8, s[i..], "&#038;")) {
                try list.append(allocator, '&');
                i += 6;
                continue;
            }
        }
        try list.append(allocator, s[i]);
        i += 1;
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

    const marker = "burst.shopifycdn.com/photos/";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, marker) orelse break;
        pos = found + marker.len;

        // Search backward for start of <img or container
        const tag_start = std.mem.lastIndexOfScalar(u8, html[0..found], '<') orelse found;
        const window_end = @min(html.len, found + 1500);
        const win = html[tag_start..window_end];

        // Extract full src
        const src_key = "src=\"";
        const src_i = std.mem.indexOf(u8, win, src_key) orelse continue;
        const src_start = src_i + src_key.len;
        const src_end = std.mem.indexOfScalarPos(u8, win, src_start, '"') orelse continue;
        const src_raw = win[src_start..src_end];
        if (std.mem.indexOf(u8, src_raw, "burst.shopifycdn.com/photos/") == null) continue;

        const src_unesc = try htmlUnescapeBasic(allocator, src_raw);
        defer allocator.free(src_unesc);

        // Extract Title
        const title: []const u8 = blk: {
            const title_key = "data-photo-title=\"";
            if (std.mem.indexOf(u8, win, title_key)) |ti| {
                const ts = ti + title_key.len;
                const te = std.mem.indexOfScalarPos(u8, win, ts, '"') orelse break :blk "";
                break :blk win[ts..te];
            }
            const alt_key = "alt=\"";
            if (std.mem.indexOf(u8, win, alt_key)) |ai| {
                const ts = ai + alt_key.len;
                const te = std.mem.indexOfScalarPos(u8, win, ts, '"') orelse break :blk "";
                break :blk win[ts..te];
            }
            break :blk "";
        };

        const pid = try idFromUrl(allocator, src_unesc);
        errdefer allocator.free(pid);
        if (seen.contains(pid)) {
            allocator.free(pid);
            continue;
        }
        try seen.put(allocator, try allocator.dupe(u8, pid), {});

        const full = try fullSizeUrl(allocator, src_unesc);
        errdefer allocator.free(full);

        const desc = if (title.len > 0) title else pid;
        const desc_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt_owned);
        const thumb_owned = try allocator.dupe(u8, src_unesc);
        errdefer allocator.free(thumb_owned);
        const provider_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(provider_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"burst\",\"page\":\"https://burst.shopify.com/photos/{s}\"}}", .{pid});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = full,
            .thumbnail_url = thumb_owned,
            .provider = provider_owned,
            .author = try allocator.dupe(u8, "Burst by Shopify"),
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
    const search_url = try std.fmt.allocPrint(allocator, "https://burst.shopify.com/photos/search?q={s}", .{enc});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://burst.shopify.com/",
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
        .referer = "https://burst.shopify.com/",
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
