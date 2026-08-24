//! Picjumbo provider — WordPress masonry search HTML.
//! Search: GET /search/{query}/
//! Download: direct wp-content original JPEG/PNG URL.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "picjumbo";
pub const name = "Picjumbo";

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

fn normalizeImgUrl(allocator: Allocator, raw: []const u8) ![]u8 {
    const u = raw;
    if (std.mem.startsWith(u8, u, "//")) {
        return std.fmt.allocPrint(allocator, "https:{s}", .{u});
    }
    if (std.mem.startsWith(u8, u, "http://") or std.mem.startsWith(u8, u, "https://")) {
        return allocator.dupe(u8, u);
    }
    if (std.mem.startsWith(u8, u, "/")) {
        return std.fmt.allocPrint(allocator, "https://picjumbo.com{s}", .{u});
    }
    return allocator.dupe(u8, u);
}

fn originalFromThumb(allocator: Allocator, thumb: []const u8) ![]u8 {
    // https://i0.wp.com/picjumbo.com/wp-content/uploads/foo.jpeg?w=600&quality=80
    // → https://picjumbo.com/wp-content/uploads/foo.jpeg
    var u = thumb;
    if (std.mem.indexOf(u8, u, "picjumbo.com/wp-content/uploads/")) |idx| {
        const start = idx;
        const path_start = std.mem.indexOfPos(u8, u, start, "/wp-content/") orelse return normalizeImgUrl(allocator, thumb);
        var path = u[path_start..];
        if (std.mem.indexOfScalar(u8, path, '?')) |q| path = path[0..q];
        return std.fmt.allocPrint(allocator, "https://picjumbo.com{s}", .{path});
    }
    var path = u;
    if (std.mem.indexOfScalar(u8, path, '?')) |q| path = path[0..q];
    return normalizeImgUrl(allocator, path);
}

fn idFromPage(allocator: Allocator, page: []const u8) ![]u8 {
    var p = page;
    if (std.mem.endsWith(u8, p, "/")) p = p[0 .. p.len - 1];
    const slash = std.mem.lastIndexOfScalar(u8, p, '/') orelse return allocator.dupe(u8, "photo");
    return allocator.dupe(u8, p[slash + 1 ..]);
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

    const marker = "masonry_item photo_item";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, marker) orelse break;
        pos = found + marker.len;
        const window_end = @min(html.len, found + 3000);
        const win = html[found..window_end];

        // href page
        const href_key = "href=\"";
        const href_i = std.mem.indexOf(u8, win, href_key) orelse continue;
        const hs = href_i + href_key.len;
        const he = std.mem.indexOfScalarPos(u8, win, hs, '"') orelse continue;
        const page = win[hs..he];
        if (std.mem.indexOf(u8, page, "picjumbo.com/") == null) continue;
        if (std.mem.indexOf(u8, page, "/free-images/") != null) continue;
        if (std.mem.indexOf(u8, page, "premium") != null) continue;

        const aria_key = "aria-label=\"";
        const title: []const u8 = blk: {
            if (std.mem.indexOf(u8, win, aria_key)) |ai| {
                const ts = ai + aria_key.len;
                const te = std.mem.indexOfScalarPos(u8, win, ts, '"') orelse break :blk "";
                break :blk win[ts..te];
            }
            break :blk "";
        };

        const src_key = "src=\"";
        const src_i = std.mem.indexOf(u8, win, src_key) orelse continue;
        const ss = src_i + src_key.len;
        const se = std.mem.indexOfScalarPos(u8, win, ss, '"') orelse continue;
        const thumb_raw = win[ss..se];
        if (std.mem.indexOf(u8, thumb_raw, "wp-content/uploads/") == null) continue;
        if (std.mem.indexOf(u8, thumb_raw, "istock") != null) continue;

        const thumb_unesc = try htmlUnescapeBasic(allocator, thumb_raw);
        defer allocator.free(thumb_unesc);

        const pid = try idFromPage(allocator, page);
        errdefer allocator.free(pid);
        if (seen.contains(pid)) {
            allocator.free(pid);
            continue;
        }
        try seen.put(allocator, try allocator.dupe(u8, pid), {});

        const full = try originalFromThumb(allocator, thumb_unesc);
        errdefer allocator.free(full);
        const thumb = try normalizeImgUrl(allocator, thumb_unesc);
        errdefer allocator.free(thumb);

        const desc_src = if (title.len > 0) title else pid;
        const desc_owned = try allocator.dupe(u8, desc_src);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, desc_src);
        errdefer allocator.free(prompt_owned);
        const provider_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(provider_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"picjumbo\",\"page\":\"{s}\"}}", .{page});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = full,
            .thumbnail_url = thumb,
            .provider = provider_owned,
            .author = try allocator.dupe(u8, "Viktor Hanacek"),
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

    const slug = try slugify(allocator, trimmed);
    defer allocator.free(slug);
    const search_url = try std.fmt.allocPrint(allocator, "https://picjumbo.com/?s={s}", .{slug});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://picjumbo.com/",
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
        .referer = "https://picjumbo.com/",
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
