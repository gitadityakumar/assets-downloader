//! Picography provider — free CC0 stock photography.
//! Search: GET https://picography.co/?s={query}
//! Download: full-size wp-content URL (strip -WxH suffix).

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "picography";
pub const name = "Picography";

fn fullSizeUrl(allocator: Allocator, thumb: []const u8) ![]u8 {
    // .../picography-image-600x400.jpg → .../picography-image.jpg
    const q = std.mem.indexOfScalar(u8, thumb, '?') orelse thumb.len;
    const path = thumb[0..q];
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return allocator.dupe(u8, thumb);
    const file = path[slash + 1 ..];
    const dot = std.mem.lastIndexOfScalar(u8, file, '.') orelse return allocator.dupe(u8, thumb);
    const stem = file[0..dot];
    const ext = file[dot..];

    var cut = stem.len;
    if (std.mem.lastIndexOfScalar(u8, stem, '-')) |dash| {
        const maybe = stem[dash + 1 ..];
        if (std.mem.indexOfScalar(u8, maybe, 'x')) |x| {
            const w = maybe[0..x];
            const h = maybe[x + 1 ..];
            const w_ok = w.len > 0 and for (w) |c| {
                if (c < '0' or c > '9') break false;
            } else true;
            const h_ok = h.len > 0 and for (h) |c| {
                if (c < '0' or c > '9') break false;
            } else true;
            if (w_ok and h_ok) cut = dash;
        }
    }
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ path[0 .. slash + 1], stem[0..cut], ext });
}

fn idFromUrl(allocator: Allocator, page_url: []const u8) ![]u8 {
    // https://picography.co/mountains-nature-landscape/ → mountains-nature-landscape
    var u = page_url;
    if (std.mem.endsWith(u8, u, "/")) u = u[0 .. u.len - 1];
    const slash = std.mem.lastIndexOfScalar(u8, u, '/') orelse return allocator.dupe(u8, "photo");
    return allocator.dupe(u8, u[slash + 1 ..]);
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

    const marker = "class=\"single-photo";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, marker) orelse break;
        pos = found + marker.len;
        const a_start = std.mem.lastIndexOfScalar(u8, html[0..found], '<') orelse found;
        const window_end = @min(html.len, found + 3000);
        const win = html[a_start..window_end];

        const href_key = "href=\"";
        const href_i = std.mem.indexOf(u8, win, href_key) orelse continue;
        const href_start = href_i + href_key.len;
        const href_end = std.mem.indexOfScalarPos(u8, win, href_start, '"') orelse continue;
        const href = win[href_start..href_end];
        if (std.mem.indexOf(u8, href, "picography.co/") == null) continue;
        if (std.mem.indexOf(u8, href, "shutterstock") != null) continue;

        const src_key: []const u8 = if (std.mem.indexOf(u8, win, "data-src=\"") != null) "data-src=\"" else "src=\"";
        const src_i = std.mem.indexOf(u8, win, src_key) orelse continue;
        const src_start = src_i + src_key.len;
        const src_end = std.mem.indexOfScalarPos(u8, win, src_start, '"') orelse continue;
        const thumb_raw = win[src_start..src_end];
        if (std.mem.indexOf(u8, thumb_raw, "wp-content/uploads/") == null) continue;
        if (std.mem.indexOf(u8, thumb_raw, "sstk") != null) continue;

        const thumb_unesc = try htmlUnescapeBasic(allocator, thumb_raw);
        defer allocator.free(thumb_unesc);

        const name_key = "<span class=\"hidden\" itemprop=\"name\">";
        const title: []const u8 = blk: {
            if (std.mem.indexOf(u8, win, name_key)) |ni| {
                const ts = ni + name_key.len;
                const te = std.mem.indexOfScalarPos(u8, win, ts, '<') orelse break :blk "";
                break :blk std.mem.trim(u8, win[ts..te], " \t\r\n");
            }
            const title_key = "title=\"";
            if (std.mem.indexOf(u8, win, title_key)) |ti| {
                const ts = ti + title_key.len;
                const te = std.mem.indexOfScalarPos(u8, win, ts, '"') orelse break :blk "";
                break :blk win[ts..te];
            }
            break :blk "";
        };

        const author_key = "rel=\"author\">";
        const author: ?[]u8 = blk: {
            if (std.mem.indexOf(u8, win, author_key)) |ai| {
                const as = ai + author_key.len;
                const ae = std.mem.indexOfScalarPos(u8, win, as, '<') orelse break :blk null;
                const aname = std.mem.trim(u8, win[as..ae], " \t\r\n");
                if (aname.len > 0) {
                    break :blk try allocator.dupe(u8, aname);
                }
            }
            break :blk null;
        };
        errdefer if (author) |a| allocator.free(a);

        const pid = try idFromUrl(allocator, href);
        errdefer allocator.free(pid);
        if (seen.contains(pid)) {
            allocator.free(pid);
            if (author) |a| allocator.free(a);
            continue;
        }
        try seen.put(allocator, try allocator.dupe(u8, pid), {});

        const full = try fullSizeUrl(allocator, thumb_unesc);
        errdefer allocator.free(full);
        const desc = if (title.len > 0) title else pid;
        const desc_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt_owned);
        const thumb_owned = try allocator.dupe(u8, thumb_unesc);
        errdefer allocator.free(thumb_owned);
        const provider_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(provider_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"picography\",\"page\":\"{s}\"}}", .{href});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = full,
            .thumbnail_url = thumb_owned,
            .provider = provider_owned,
            .author = author,
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
    const search_url = try std.fmt.allocPrint(allocator, "https://picography.co/?s={s}", .{enc});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://picography.co/",
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
        .referer = "https://picography.co/",
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
