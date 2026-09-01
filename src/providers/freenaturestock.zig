//! Free Nature Stock provider — Adrian Pelletier's free CC0 nature & wildlife stock photography.
//! Search: GET https://freenaturestock.com/?s={query}
//! Download: Direct master full-resolution JPEG from Cloudflare CDN (up to 20+ MB).

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "freenaturestock";
pub const name = "Free Nature Stock";

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
    const match_all = std.mem.eql(u8, trimmed_query, "*") or
        std.ascii.eqlIgnoreCase(trimmed_query, "all") or
        std.ascii.eqlIgnoreCase(trimmed_query, "nature") or
        std.ascii.eqlIgnoreCase(trimmed_query, "photos") or
        trimmed_query.len == 0;

    const img_marker = "<img";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, img_marker) orelse break;
        pos = found + img_marker.len;

        const img_end = std.mem.indexOfScalarPos(u8, html, found, '>') orelse continue;
        const img_tag = html[found .. img_end + 1];

        // Must be a photo thumbnail: /photos/thumb/freenaturestock-{id}.jpg
        const src_key = "src=\"";
        const src_idx = std.mem.indexOf(u8, img_tag, src_key) orelse continue;
        const src_start = src_idx + src_key.len;
        const src_end = std.mem.indexOfScalarPos(u8, img_tag, src_start, '"') orelse continue;
        const src_val = img_tag[src_start..src_end];

        if (std.mem.indexOf(u8, src_val, "/photos/thumb/") == null) continue;

        // Extract alt title
        var alt_val: []const u8 = "";
        const alt_key = "alt=\"";
        if (std.mem.indexOf(u8, img_tag, alt_key)) |ai| {
            const as = ai + alt_key.len;
            if (std.mem.indexOfScalarPos(u8, img_tag, as, '"')) |ae| {
                alt_val = img_tag[as..ae];
            }
        }

        const alt_clean = try htmlUnescape(allocator, alt_val);
        defer allocator.free(alt_clean);

        // Check query match
        var matched = match_all;
        if (!matched) {
            if (containsIgnoreCase(alt_clean, trimmed_query) or
                containsIgnoreCase(src_val, trimmed_query))
            {
                matched = true;
            }
        }
        if (!matched) continue;

        // Extract filename / ID e.g. freenaturestock-2340 from /photos/thumb/freenaturestock-2340.jpg
        const last_slash = std.mem.lastIndexOfScalar(u8, src_val, '/') orelse continue;
        var filename = src_val[last_slash + 1 ..];
        if (std.mem.lastIndexOfScalar(u8, filename, '.')) |dot| {
            filename = filename[0..dot];
        }

        if (seen.contains(filename)) continue;
        try seen.put(allocator, try allocator.dupe(u8, filename), {});

        // Build master URL: https://cdn.freenaturestock.com/photos/{filename}.jpg
        const master_url = try std.fmt.allocPrint(allocator, "https://cdn.freenaturestock.com/photos/{s}.jpg", .{filename});
        errdefer allocator.free(master_url);

        const thumb_url = if (std.mem.startsWith(u8, src_val, "http"))
            try allocator.dupe(u8, src_val)
        else
            try std.fmt.allocPrint(allocator, "https://cdn.freenaturestock.com{s}", .{src_val});
        errdefer allocator.free(thumb_url);

        const pid = try allocator.dupe(u8, filename);
        errdefer allocator.free(pid);

        const desc = if (alt_clean.len > 0) alt_clean else filename;
        const desc_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt_owned);

        const prov_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(prov_owned);
        const auth_owned = try allocator.dupe(u8, "Adrian Pelletier");
        errdefer allocator.free(auth_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"freenaturestock\",\"page\":\"https://freenaturestock.com/\"}}", .{});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = master_url,
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
    const trimmed = std.mem.trim(u8, query, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyQuery;

    const enc = try http_client.queryEscape(allocator, trimmed);
    defer allocator.free(enc);

    const lim = @min(@max(limit, 1), 50);

    const search_url = try std.fmt.allocPrint(allocator, "https://freenaturestock.com/?s={s}", .{enc});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://freenaturestock.com/",
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
    const body = http_client.getBody(client, allocator, url, .{
        .referer = "https://freenaturestock.com/",
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
