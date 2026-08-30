//! Magdeleine provider — hand-picked free high-resolution stock photography (nature, vintage, architecture).
//! Search: GET https://magdeleine.co/?s={query}
//! Download: master original resolution image from wp-content/uploads/

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "magdeleine";
pub const name = "Magdeleine";

fn fullSizeUrl(allocator: Allocator, src_url: []const u8) ![]u8 {
    // https://magdeleine.co/wp-content/uploads/2022/05/StockSnap_9BHTWNWCEB-500x375.jpg
    // → https://magdeleine.co/wp-content/uploads/2022/05/StockSnap_9BHTWNWCEB.jpg
    const dot = std.mem.lastIndexOfScalar(u8, src_url, '.') orelse return allocator.dupe(u8, src_url);
    const before_ext = src_url[0..dot];
    const ext = src_url[dot..];

    if (std.mem.lastIndexOfScalar(u8, before_ext, '-')) |dash| {
        const dim_candidate = before_ext[dash + 1 ..];
        if (std.mem.indexOfScalar(u8, dim_candidate, 'x')) |x_pos| {
            const w = dim_candidate[0..x_pos];
            const h = dim_candidate[x_pos + 1 ..];
            var all_digits = (w.len > 0 and h.len > 0);
            for (w) |c| {
                if (!std.ascii.isDigit(c)) {
                    all_digits = false;
                    break;
                }
            }
            for (h) |c| {
                if (!std.ascii.isDigit(c)) {
                    all_digits = false;
                    break;
                }
            }
            if (all_digits) {
                return try std.fmt.allocPrint(allocator, "{s}{s}", .{ before_ext[0..dash], ext });
            }
        }
    }
    return allocator.dupe(u8, src_url);
}

fn idFromUrl(allocator: Allocator, page_url: []const u8) ![]u8 {
    // https://magdeleine.co/photo-by-natures-beauty-n-1630/ -> photo-by-natures-beauty-n-1630
    var u = page_url;
    if (std.mem.endsWith(u8, u, "/")) u = u[0 .. u.len - 1];
    const slash = std.mem.lastIndexOfScalar(u8, u, '/') orelse return allocator.dupe(u8, "photo");
    var base = u[slash + 1 ..];
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
        base = base[0..dot];
    }
    return allocator.dupe(u8, base);
}

fn formatTitleFromSlug(allocator: Allocator, slug: []const u8) ![]u8 {
    // photo-by-natures-beauty-n-1630 -> Natures Beauty 1630
    var s = slug;
    if (std.mem.startsWith(u8, s, "photo-by-")) s = s["photo-by-".len..];
    if (std.mem.startsWith(u8, s, "photo-")) s = s["photo-".len..];

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    var cap_next = true;
    for (s) |c| {
        if (c == '-' or c == '_') {
            if (list.items.len > 0 and list.items[list.items.len - 1] != ' ') {
                try list.append(allocator, ' ');
            }
            cap_next = true;
        } else {
            if (cap_next and std.ascii.isAlphabetic(c)) {
                try list.append(allocator, std.ascii.toUpper(c));
                cap_next = false;
            } else {
                try list.append(allocator, c);
                cap_next = false;
            }
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

    const marker = "wp-content/uploads/";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, marker) orelse break;
        pos = found + marker.len;

        // Search backward for start of card / tag
        const tag_start = std.mem.lastIndexOfScalar(u8, html[0..found], '<') orelse found;
        const window_end = @min(html.len, found + 1500);
        const win = html[tag_start..window_end];

        // Extract image src
        const src_key = "src=\"";
        const src_i = std.mem.indexOf(u8, win, src_key) orelse continue;
        const src_start = src_i + src_key.len;
        const src_end = std.mem.indexOfScalarPos(u8, win, src_start, '"') orelse continue;
        const src_raw = win[src_start..src_end];

        // Skip avatar images
        if (std.mem.indexOf(u8, src_raw, "-96x96.") != null or
            std.mem.indexOf(u8, src_raw, "-400x400.") != null or
            std.mem.indexOf(u8, src_raw, "-150x150.") != null)
        {
            continue;
        }

        // Extract photo page link
        const photo_link_key = "href=\"";
        const photo_link: []const u8 = blk: {
            var search_idx: usize = 0;
            while (std.mem.indexOfPos(u8, win, search_idx, photo_link_key)) |hi| {
                const hs = hi + photo_link_key.len;
                const he = std.mem.indexOfScalarPos(u8, win, hs, '"') orelse break;
                const link = win[hs..he];
                if (std.mem.indexOf(u8, link, "/photo-") != null) {
                    break :blk link;
                }
                search_idx = he;
            }
            break :blk "";
        };

        const pid = if (photo_link.len > 0)
            try idFromUrl(allocator, photo_link)
        else
            try idFromUrl(allocator, src_raw);
        errdefer allocator.free(pid);

        if (seen.contains(pid) or pid.len == 0 or std.mem.eql(u8, pid, "author")) {
            allocator.free(pid);
            continue;
        }
        try seen.put(allocator, try allocator.dupe(u8, pid), {});

        // Extract author name
        const author_key = "/author/";
        const author: []const u8 = blk: {
            if (std.mem.indexOf(u8, win, author_key)) |ai| {
                const tag_close = std.mem.indexOfScalarPos(u8, win, ai, '>') orelse break :blk "Magdeleine";
                const tag_end = std.mem.indexOfScalarPos(u8, win, tag_close, '<') orelse break :blk "Magdeleine";
                const auth_text = std.mem.trim(u8, win[tag_close + 1 .. tag_end], " \t\r\n");
                if (auth_text.len > 0) break :blk auth_text;
            }
            break :blk "Magdeleine";
        };

        const full_url = try fullSizeUrl(allocator, src_raw);
        errdefer allocator.free(full_url);

        const desc = try formatTitleFromSlug(allocator, pid);
        errdefer allocator.free(desc);
        const prompt_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt_owned);
        const thumb_owned = try allocator.dupe(u8, src_raw);
        errdefer allocator.free(thumb_owned);
        const provider_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(provider_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        if (photo_link.len > 0) {
            try meta_aw.writer.print("{{\"source\":\"magdeleine\",\"page\":\"{s}\"}}", .{photo_link});
        } else {
            try meta_aw.writer.print("{{\"source\":\"magdeleine\",\"page\":\"https://magdeleine.co/{s}/\"}}", .{pid});
        }
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc,
            .prompt = prompt_owned,
            .image_url = full_url,
            .thumbnail_url = thumb_owned,
            .provider = provider_owned,
            .author = try allocator.dupe(u8, author),
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
    const search_url = try std.fmt.allocPrint(allocator, "https://magdeleine.co/?s={s}", .{enc});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://magdeleine.co/",
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
        .referer = "https://magdeleine.co/",
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
