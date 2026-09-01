//! Moveast provider — free CC0 travel and journey stock photography by João Pacheco.
//! Search: GET https://moveast.me/api/read/json?num=50&type=photo
//! Download: Direct high-resolution JPEG from Tumblr CDN.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "moveast";
pub const name = "Moveast";

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

fn stripHtmlTags(allocator: Allocator, html: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    var in_tag = false;
    for (html) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            if (c == '\n' or c == '\r' or c == '\t') {
                if (list.items.len > 0 and list.items[list.items.len - 1] != ' ') {
                    try list.append(allocator, ' ');
                }
            } else {
                try list.append(allocator, c);
            }
        }
    }
    const trimmed = std.mem.trim(u8, list.items, " \t\r\n");
    return try allocator.dupe(u8, trimmed);
}

fn parseSearch(allocator: Allocator, json_text: []const u8, query: []const u8, limit: u32) ![]Asset {
    var raw = json_text;
    const prefix = "var tumblr_api_read = ";
    if (std.mem.startsWith(u8, raw, prefix)) {
        raw = raw[prefix.len..];
    }
    raw = std.mem.trimEnd(u8, raw, "; \n\r\t");

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return &[_]Asset{};

    const posts_val = root.object.get("posts") orelse return &[_]Asset{};
    if (posts_val != .array) return &[_]Asset{};

    var assets: std.ArrayList(Asset) = .empty;
    errdefer {
        for (assets.items) |*a| a.deinit(allocator);
        assets.deinit(allocator);
    }

    const trimmed_query = std.mem.trim(u8, query, " \t\r\n");
    const match_all = std.mem.eql(u8, trimmed_query, "*") or
        std.ascii.eqlIgnoreCase(trimmed_query, "all") or
        std.ascii.eqlIgnoreCase(trimmed_query, "moveast") or
        std.ascii.eqlIgnoreCase(trimmed_query, "photos") or
        trimmed_query.len == 0;

    for (posts_val.array.items) |p| {
        if (assets.items.len >= limit) break;
        if (p != .object) continue;

        const post_id_val = p.object.get("id") orelse continue;
        const post_id = switch (post_id_val) {
            .string => |s| s,
            .integer => |i| blk: {
                var buf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{i}) catch continue;
                break :blk s;
            },
            else => continue,
        };

        const raw_caption = if (p.object.get("photo-caption")) |c| (if (c == .string) c.string else "") else "";
        const slug = if (p.object.get("slug")) |s| (if (s == .string) s.string else "") else "";
        const photo_1280 = if (p.object.get("photo-url-1280")) |u| (if (u == .string) u.string else null) else null;
        const photo_500 = if (p.object.get("photo-url-500")) |u| (if (u == .string) u.string else null) else null;

        var tags_buf: std.ArrayList(u8) = .empty;
        defer tags_buf.deinit(allocator);
        if (p.object.get("tags")) |tags_val| {
            if (tags_val == .array) {
                for (tags_val.array.items) |tag_item| {
                    if (tag_item == .string) {
                        if (tags_buf.items.len > 0) try tags_buf.appendSlice(allocator, ", ");
                        try tags_buf.appendSlice(allocator, tag_item.string);
                    }
                }
            }
        }

        const clean_caption = try stripHtmlTags(allocator, raw_caption);
        defer allocator.free(clean_caption);

        // Check if query matches
        var matched = match_all;
        if (!matched) {
            if (containsIgnoreCase(tags_buf.items, trimmed_query) or
                containsIgnoreCase(clean_caption, trimmed_query) or
                containsIgnoreCase(slug, trimmed_query))
            {
                matched = true;
            }
        }
        if (!matched) continue;

        const best_img = photo_1280 orelse photo_500 orelse continue;
        const thumb_img = photo_500 orelse photo_1280 orelse best_img;

        // Description / prompt
        const desc = if (clean_caption.len > 0)
            clean_caption
        else if (slug.len > 0 and !std.mem.eql(u8, slug, "download"))
            slug
        else if (tags_buf.items.len > 0)
            tags_buf.items
        else
            "Moveast Stock Photo";

        const pid_owned = try allocator.dupe(u8, post_id);
        errdefer allocator.free(pid_owned);
        const desc_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(desc_owned);
        const prompt_owned = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt_owned);
        const img_owned = try allocator.dupe(u8, best_img);
        errdefer allocator.free(img_owned);
        const thumb_owned = try allocator.dupe(u8, thumb_img);
        errdefer allocator.free(thumb_owned);
        const provider_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(provider_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"moveast\",\"page\":\"https://moveast.me/post/{s}\"}}", .{post_id});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid_owned,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = img_owned,
            .thumbnail_url = thumb_owned,
            .provider = provider_owned,
            .author = try allocator.dupe(u8, "João Pacheco"),
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

    // Try searching by tag first
    const tagged_url = try std.fmt.allocPrint(allocator, "https://moveast.me/api/read/json?tagged={s}&num=50&type=photo", .{enc});
    defer allocator.free(tagged_url);

    var resp = try http_client.get(client, allocator, tagged_url, .{
        .accept = "application/json,text/javascript,*/*;q=0.8",
        .referer = "https://moveast.me/",
        .max_redirects = 5,
    });
    defer resp.deinit();

    var assets: []Asset = if (resp.status == 200)
        try parseSearch(allocator, resp.body, trimmed, lim)
    else
        try allocator.alloc(Asset, 0);

    // Fallback: if tag returned 0 results, fetch global feed and match client-side
    if (assets.len == 0) {
        allocator.free(assets);
        const global_url = "https://moveast.me/api/read/json?num=50&type=photo";
        var global_resp = try http_client.get(client, allocator, global_url, .{
            .accept = "application/json,text/javascript,*/*;q=0.8",
            .referer = "https://moveast.me/",
            .max_redirects = 5,
        });
        defer global_resp.deinit();
        if (global_resp.status != 200) return error.HttpStatus;
        assets = try parseSearch(allocator, global_resp.body, trimmed, lim);
    }

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
        .referer = "https://moveast.me/",
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
