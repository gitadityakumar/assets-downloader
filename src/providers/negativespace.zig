//! NegativeSpace provider — high-resolution CC0 stock photos for personal and commercial use.
//! Search: GET https://negativespace.co/?s={query}
//! Download: Direct master-resolution JPEG/PNG from Flywheel / WordPress media storage.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "negativespace";
pub const name = "NegativeSpace";

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

fn stripGeometrySuffix(allocator: Allocator, url: []const u8) ![]u8 {
    const last_dot = std.mem.lastIndexOfScalar(u8, url, '.') orelse return try allocator.dupe(u8, url);
    const ext = url[last_dot..];
    const before_ext = url[0..last_dot];

    const last_dash = std.mem.lastIndexOfScalar(u8, before_ext, '-') orelse return try allocator.dupe(u8, url);
    const dim_part = before_ext[last_dash + 1 ..];

    if (std.mem.indexOfScalar(u8, dim_part, 'x')) |x_pos| {
        const w_str = dim_part[0..x_pos];
        const h_str = dim_part[x_pos + 1 ..];
        if (w_str.len > 0 and h_str.len > 0) {
            var all_digits = true;
            for (w_str) |c| {
                if (!std.ascii.isDigit(c)) {
                    all_digits = false;
                    break;
                }
            }
            for (h_str) |c| {
                if (!std.ascii.isDigit(c)) {
                    all_digits = false;
                    break;
                }
            }
            if (all_digits) {
                return try std.fmt.allocPrint(allocator, "{s}{s}", .{ before_ext[0..last_dash], ext });
            }
        }
    }

    return try allocator.dupe(u8, url);
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

    const img_marker = "wp-content/uploads/";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, img_marker) orelse break;
        pos = found + img_marker.len;

        // Find enclosing <img ...>
        const img_start = std.mem.lastIndexOfScalar(u8, html[0..found], '<') orelse continue;
        if (!std.mem.startsWith(u8, html[img_start..], "<img")) continue;
        const img_end = std.mem.indexOfScalarPos(u8, html, found, '>') orelse continue;
        const img_tag = html[img_start .. img_end + 1];

        // Extract src
        const src_key = "src=\"";
        const src_i = std.mem.indexOf(u8, img_tag, src_key) orelse continue;
        const src_start = src_i + src_key.len;
        const src_end = std.mem.indexOfScalarPos(u8, img_tag, src_start, '"') orelse continue;
        const src_val = img_tag[src_start..src_end];
        if (std.mem.indexOf(u8, src_val, "wp-content/uploads/") == null) continue;
        if (std.mem.indexOf(u8, src_val, "logo") != null) continue;

        // Extract alt
        const alt_key = "alt=\"";
        const alt_val: []const u8 = blk: {
            if (std.mem.indexOf(u8, img_tag, alt_key)) |ai| {
                const as = ai + alt_key.len;
                const ae = std.mem.indexOfScalarPos(u8, img_tag, as, '"') orelse break :blk "";
                break :blk img_tag[as..ae];
            }
            break :blk "";
        };

        // Find enclosing <a href="...">
        const a_search_start = if (img_start > 500) img_start - 500 else 0;
        const a_chunk = html[a_search_start..img_start];
        const href_val: []const u8 = blk: {
            if (std.mem.lastIndexOf(u8, a_chunk, "<a ")) |ai| {
                const href_i = std.mem.indexOfPos(u8, a_chunk, ai, "href=\"") orelse break :blk "";
                const hs = href_i + "href=\"".len;
                const he = std.mem.indexOfScalarPos(u8, a_chunk, hs, '"') orelse break :blk "";
                break :blk a_chunk[hs..he];
            }
            break :blk "";
        };

        // Determine ID from page URL or filename
        var slug_id: []const u8 = "";
        if (href_val.len > 0 and std.mem.startsWith(u8, href_val, "https://negativespace.co/")) {
            var trimmed = href_val["https://negativespace.co/".len..];
            trimmed = std.mem.trim(u8, trimmed, "/");
            if (trimmed.len > 0) slug_id = trimmed;
        }
        if (slug_id.len == 0) {
            const last_slash = std.mem.lastIndexOfScalar(u8, src_val, '/') orelse continue;
            slug_id = src_val[last_slash + 1 ..];
        }

        const pid = try allocator.dupe(u8, slug_id);
        errdefer allocator.free(pid);

        if (seen.contains(pid)) {
            allocator.free(pid);
            continue;
        }
        try seen.put(allocator, try allocator.dupe(u8, pid), {});

        const title_unesc = try htmlUnescape(allocator, if (alt_val.len > 0) alt_val else slug_id);
        defer allocator.free(title_unesc);

        const desc = if (title_unesc.len > 0) title_unesc else pid;
        const desc_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt_owned);

        const master_url = try stripGeometrySuffix(allocator, src_val);
        errdefer allocator.free(master_url);

        const thumb_owned = try allocator.dupe(u8, src_val);
        errdefer allocator.free(thumb_owned);
        const prov_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(prov_owned);
        const auth_owned = try allocator.dupe(u8, "NegativeSpace");
        errdefer allocator.free(auth_owned);

        const page_url = if (href_val.len > 0) href_val else master_url;
        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"negativespace\",\"page\":\"{s}\"}}", .{page_url});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc_owned,
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

    const encoded_query = try http_client.queryEscape(allocator, trimmed);
    defer allocator.free(encoded_query);

    const search_url = try std.fmt.allocPrint(allocator, "https://negativespace.co/?s={s}", .{encoded_query});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://negativespace.co/",
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
        .referer = "https://negativespace.co/",
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
