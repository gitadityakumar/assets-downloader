//! DeviantArt provider — creative reference photos, stock imagery, and digital art.
//! Search: GET https://www.deviantart.com/tag/{tag}
//! Download: Direct high-resolution image assets from Wixmp CDN.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "deviantart";
pub const name = "DeviantArt";

fn formatTag(allocator: Allocator, query: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, query, " \t\r\n");
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    for (trimmed) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try list.append(allocator, std.ascii.toLower(c));
        }
    }
    if (list.items.len == 0) {
        try list.appendSlice(allocator, "stock");
    }
    return list.toOwnedSlice(allocator);
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

    const art_marker = "/art/";
    var pos: usize = 0;
    while (assets.items.len < limit) {
        const found = std.mem.indexOfPos(u8, html, pos, art_marker) orelse break;
        pos = found + art_marker.len;

        // Search backward for the enclosing tag
        const tag_start = std.mem.lastIndexOfScalar(u8, html[0..found], '<') orelse found;
        const window_end = @min(html.len, found + 1500);
        const win = html[tag_start..window_end];

        // Extract href
        const href_key = "href=\"";
        const href_i = std.mem.indexOf(u8, win, href_key) orelse continue;
        const href_start = href_i + href_key.len;
        const href_end = std.mem.indexOfScalarPos(u8, win, href_start, '"') orelse continue;
        const href_val = win[href_start..href_end];
        if (std.mem.indexOf(u8, href_val, "/art/") == null) continue;

        // Extract img src
        const src_key = "src=\"";
        const src_i = std.mem.indexOf(u8, win, src_key) orelse continue;
        const src_start = src_i + src_key.len;
        const src_end = std.mem.indexOfScalarPos(u8, win, src_start, '"') orelse continue;
        const src_val = win[src_start..src_end];
        if (std.mem.indexOf(u8, src_val, "wixmp.com") == null) continue;

        // Extract img alt
        const alt_key = "alt=\"";
        const alt_val: []const u8 = blk: {
            if (std.mem.indexOf(u8, win, alt_key)) |ai| {
                const as = ai + alt_key.len;
                const ae = std.mem.indexOfScalarPos(u8, win, as, '"') orelse break :blk "";
                break :blk win[as..ae];
            }
            break :blk "";
        };

        // Parse author and slug from href: https://www.deviantart.com/{author}/art/{slug}-{id}
        var u = href_val;
        if (std.mem.startsWith(u8, u, "https://www.deviantart.com/")) {
            u = u["https://www.deviantart.com/".len..];
        } else if (std.mem.startsWith(u8, u, "https://deviantart.com/")) {
            u = u["https://deviantart.com/".len..];
        } else if (std.mem.startsWith(u8, u, "/")) {
            u = u[1..];
        }

        const slash_idx = std.mem.indexOfScalar(u8, u, '/') orelse continue;
        const author_str = u[0..slash_idx];
        const rest = u[slash_idx + 1 ..];
        const art_prefix = "art/";
        if (!std.mem.startsWith(u8, rest, art_prefix)) continue;
        const slug_id = rest[art_prefix.len..];
        if (slug_id.len == 0) continue;

        const pid = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ author_str, slug_id });
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
        const img_owned = try allocator.dupe(u8, src_val);
        errdefer allocator.free(img_owned);
        const thumb_owned = try allocator.dupe(u8, src_val);
        errdefer allocator.free(thumb_owned);
        const prov_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(prov_owned);
        const auth_owned = try allocator.dupe(u8, author_str);
        errdefer allocator.free(auth_owned);

        var full_page_url: []u8 = undefined;
        if (std.mem.startsWith(u8, href_val, "http")) {
            full_page_url = try allocator.dupe(u8, href_val);
        } else {
            full_page_url = try std.fmt.allocPrint(allocator, "https://www.deviantart.com/{s}", .{u});
        }
        defer allocator.free(full_page_url);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"deviantart\",\"page\":\"{s}\"}}", .{full_page_url});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = img_owned,
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
    const tag = try formatTag(allocator, query);
    defer allocator.free(tag);

    const search_url = try std.fmt.allocPrint(allocator, "https://www.deviantart.com/tag/{s}", .{tag});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://www.deviantart.com/",
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
        .referer = "https://www.deviantart.com/",
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
