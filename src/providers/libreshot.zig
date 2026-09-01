//! LibreShot provider — Martin Vorel's free CC0 stock photography.
//! Search: GET https://libreshot.com/?s={query}
//! Download: Direct master-resolution JPEG from LibreShot / WordPress media storage.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "libreshot";
pub const name = "LibreShot";

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

    const img_marker = "<img";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, img_marker) orelse break;
        pos = found + img_marker.len;

        const img_end = std.mem.indexOfScalarPos(u8, html, found, '>') orelse continue;
        const img_tag = html[found .. img_end + 1];

        // Extract real image URL: check data-src first, then src
        var src_val: []const u8 = "";
        if (std.mem.indexOf(u8, img_tag, "data-src=")) |dsi| {
            var ds_start = dsi + "data-src=".len;
            var is_quoted = false;
            var quote_char: u8 = 0;
            if (ds_start < img_tag.len and (img_tag[ds_start] == '"' or img_tag[ds_start] == '\'')) {
                is_quoted = true;
                quote_char = img_tag[ds_start];
                ds_start += 1;
            }
            var ds_end = ds_start;
            while (ds_end < img_tag.len) : (ds_end += 1) {
                if (is_quoted) {
                    if (img_tag[ds_end] == quote_char) break;
                } else {
                    if (img_tag[ds_end] == ' ' or img_tag[ds_end] == '>' or img_tag[ds_end] == '\t' or img_tag[ds_end] == '\n') break;
                }
            }
            if (ds_end > ds_start) {
                src_val = img_tag[ds_start..ds_end];
            }
        } else if (std.mem.indexOf(u8, img_tag, "src=")) |si| {
            var s_start = si + "src=".len;
            var is_quoted = false;
            var quote_char: u8 = 0;
            if (s_start < img_tag.len and (img_tag[s_start] == '"' or img_tag[s_start] == '\'')) {
                is_quoted = true;
                quote_char = img_tag[s_start];
                s_start += 1;
            }
            var s_end = s_start;
            while (s_end < img_tag.len) : (s_end += 1) {
                if (is_quoted) {
                    if (img_tag[s_end] == quote_char) break;
                } else {
                    if (img_tag[s_end] == ' ' or img_tag[s_end] == '>' or img_tag[s_end] == '\t' or img_tag[s_end] == '\n') break;
                }
            }
            if (s_end > s_start) {
                src_val = img_tag[s_start..s_end];
            }
        }

        if (src_val.len == 0 or std.mem.indexOf(u8, src_val, "wp-content/uploads/") == null) continue;
        if (std.mem.indexOf(u8, src_val, "logo") != null or std.mem.indexOf(u8, src_val, "Banner") != null) continue;

        // Extract alt attribute
        var alt_val: []const u8 = "";
        if (std.mem.indexOf(u8, img_tag, "alt=")) |ai| {
            var as = ai + "alt=".len;
            var is_quoted = false;
            var quote_char: u8 = 0;
            if (as < img_tag.len and (img_tag[as] == '"' or img_tag[as] == '\'')) {
                is_quoted = true;
                quote_char = img_tag[as];
                as += 1;
            }
            var ae = as;
            while (ae < img_tag.len) : (ae += 1) {
                if (is_quoted) {
                    if (img_tag[ae] == quote_char) break;
                } else {
                    if (img_tag[ae] == ' ' or img_tag[ae] == '>' or img_tag[ae] == '\t' or img_tag[ae] == '\n') break;
                }
            }
            if (ae > as) {
                alt_val = img_tag[as..ae];
            }
        }

        // Find enclosing <a href="...">
        const a_search_start = if (found > 500) found - 500 else 0;
        const a_chunk = html[a_search_start..found];
        const href_val: []const u8 = blk: {
            if (std.mem.lastIndexOf(u8, a_chunk, "<a ")) |ai| {
                const href_i = std.mem.indexOfPos(u8, a_chunk, ai, "href=") orelse break :blk "";
                var hs = href_i + "href=".len;
                var is_quoted = false;
                var quote_char: u8 = 0;
                if (hs < a_chunk.len and (a_chunk[hs] == '"' or a_chunk[hs] == '\'')) {
                    is_quoted = true;
                    quote_char = a_chunk[hs];
                    hs += 1;
                }
                var he = hs;
                while (he < a_chunk.len) : (he += 1) {
                    if (is_quoted) {
                        if (a_chunk[he] == quote_char) break;
                    } else {
                        if (a_chunk[he] == ' ' or a_chunk[he] == '>' or a_chunk[he] == '\t' or a_chunk[he] == '\n') break;
                    }
                }
                if (he > hs) break :blk a_chunk[hs..he];
            }
            break :blk "";
        };

        // Determine ID from page URL or filename
        var raw_slug: []const u8 = "";
        if (href_val.len > 0 and std.mem.startsWith(u8, href_val, "https://libreshot.com/")) {
            var trimmed = href_val["https://libreshot.com/".len..];
            trimmed = std.mem.trim(u8, trimmed, "/");
            if (trimmed.len > 0) raw_slug = trimmed;
        }
        if (raw_slug.len == 0) {
            const last_slash = std.mem.lastIndexOfScalar(u8, src_val, '/') orelse continue;
            raw_slug = src_val[last_slash + 1 ..];
        }

        // Strip file extension and dimension suffixes from ID
        var clean_id = raw_slug;
        if (std.mem.lastIndexOfScalar(u8, clean_id, '.')) |dot_idx| {
            clean_id = clean_id[0..dot_idx];
        }
        if (std.mem.lastIndexOfScalar(u8, clean_id, '-')) |dash_idx| {
            const dim_part = clean_id[dash_idx + 1 ..];
            if (std.mem.indexOfScalar(u8, dim_part, 'x')) |x_pos| {
                const w_str = dim_part[0..x_pos];
                const h_str = dim_part[x_pos + 1 ..];
                var all_digits = (w_str.len > 0 and h_str.len > 0);
                for (w_str) |c| if (!std.ascii.isDigit(c)) {
                    all_digits = false;
                    break;
                };
                for (h_str) |c| if (!std.ascii.isDigit(c)) {
                    all_digits = false;
                    break;
                };
                if (all_digits) {
                    clean_id = clean_id[0..dash_idx];
                }
            }
        }

        const pid = try allocator.dupe(u8, clean_id);
        errdefer allocator.free(pid);

        if (seen.contains(pid)) {
            allocator.free(pid);
            continue;
        }
        try seen.put(allocator, try allocator.dupe(u8, pid), {});

        const title_unesc = try htmlUnescape(allocator, if (alt_val.len > 0) alt_val else clean_id);
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
        const auth_owned = try allocator.dupe(u8, "Martin Vorel");
        errdefer allocator.free(auth_owned);

        const page_url = if (href_val.len > 0) href_val else master_url;
        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"libreshot\",\"page\":\"{s}\"}}", .{page_url});
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

    const search_url = try std.fmt.allocPrint(allocator, "https://libreshot.com/?s={s}", .{encoded_query});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://libreshot.com/",
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
        .referer = "https://libreshot.com/",
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
