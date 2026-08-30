//! Public Domain Archive provider — 100% free public domain and vintage stock photos.
//! Search: GET https://publicdomainarchive.com/?s={query}
//! Download: Direct high-resolution image URL from wp-content/uploads/

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "publicdomainarchive";
pub const name = "Public Domain Archive";

fn idFromUrl(allocator: Allocator, href: []const u8) ![]u8 {
    // /wooden-wood-boat-dock.html -> wooden-wood-boat-dock
    var u = href;
    if (std.mem.startsWith(u8, u, "https://publicdomainarchive.com")) {
        u = u["https://publicdomainarchive.com".len..];
    } else if (std.mem.startsWith(u8, u, "https://www.publicdomainarchive.com")) {
        u = u["https://www.publicdomainarchive.com".len..];
    }
    if (std.mem.startsWith(u8, u, "/")) u = u[1..];
    if (std.mem.endsWith(u8, u, ".html")) u = u[0 .. u.len - 5];
    if (std.mem.endsWith(u8, u, "/")) u = u[0 .. u.len - 1];
    return allocator.dupe(u8, u);
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

    const marker = "wp-content/uploads/";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, marker) orelse break;
        pos = found + marker.len;

        // Search backward for the enclosing <a or <img
        const tag_start = std.mem.lastIndexOfScalar(u8, html[0..found], '<') orelse found;
        const window_end = @min(html.len, found + 1200);
        const win = html[tag_start..window_end];

        // Extract image src
        const src_key = "src=\"";
        const src_i = std.mem.indexOf(u8, win, src_key) orelse continue;
        const src_start = src_i + src_key.len;
        const src_end = std.mem.indexOfScalarPos(u8, win, src_start, '"') orelse continue;
        const src_raw = win[src_start..src_end];

        // Skip non-photo icons / banners
        if (std.mem.indexOf(u8, src_raw, "modern.jpg") != null or
            std.mem.indexOf(u8, src_raw, "vintage.jpg") != null or
            std.mem.indexOf(u8, src_raw, "weekly.jpg") != null)
        {
            continue;
        }

        var full_img_url: []u8 = undefined;
        if (std.mem.startsWith(u8, src_raw, "http")) {
            full_img_url = try allocator.dupe(u8, src_raw);
        } else {
            if (std.mem.startsWith(u8, src_raw, "/")) {
                full_img_url = try std.fmt.allocPrint(allocator, "https://publicdomainarchive.com{s}", .{src_raw});
            } else {
                full_img_url = try std.fmt.allocPrint(allocator, "https://publicdomainarchive.com/{s}", .{src_raw});
            }
        }
        errdefer allocator.free(full_img_url);

        // Extract Alt / Title
        const alt_key = "alt=\"";
        const title: []const u8 = blk: {
            if (std.mem.indexOf(u8, win, alt_key)) |ai| {
                const as = ai + alt_key.len;
                const ae = std.mem.indexOfScalarPos(u8, win, as, '"') orelse break :blk "";
                break :blk win[as..ae];
            }
            break :blk "";
        };

        const title_unesc = try htmlUnescapeBasic(allocator, title);
        defer allocator.free(title_unesc);

        // Extract link href to determine ID
        const href_key = "href=\"";
        const href: []const u8 = blk: {
            if (std.mem.indexOf(u8, win, href_key)) |hi| {
                const hs = hi + href_key.len;
                const he = std.mem.indexOfScalarPos(u8, win, hs, '"') orelse break :blk "";
                break :blk win[hs..he];
            }
            break :blk "";
        };

        const pid = if (href.len > 0 and !std.mem.startsWith(u8, href, "http") and std.mem.endsWith(u8, href, ".html"))
            try idFromUrl(allocator, href)
        else
            try idFromUrl(allocator, full_img_url);
        errdefer allocator.free(pid);

        if (seen.contains(pid) or pid.len == 0 or std.mem.eql(u8, pid, "category") or std.mem.eql(u8, pid, "public-domain-images")) {
            allocator.free(pid);
            allocator.free(full_img_url);
            continue;
        }
        try seen.put(allocator, try allocator.dupe(u8, pid), {});

        const desc = if (title_unesc.len > 0) title_unesc else pid;
        const desc_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt_owned);
        const thumb_owned = try allocator.dupe(u8, full_img_url);
        errdefer allocator.free(thumb_owned);
        const provider_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(provider_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"publicdomainarchive\",\"page\":\"https://publicdomainarchive.com/{s}.html\"}}", .{pid});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = full_img_url,
            .thumbnail_url = thumb_owned,
            .provider = provider_owned,
            .author = try allocator.dupe(u8, "Public Domain Archive"),
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
    const search_url = try std.fmt.allocPrint(allocator, "https://publicdomainarchive.com/?s={s}", .{enc});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://publicdomainarchive.com/",
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
        .referer = "https://publicdomainarchive.com/",
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
