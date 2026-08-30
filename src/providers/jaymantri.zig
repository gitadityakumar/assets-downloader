//! Jay Mantri provider — free CC0 stock photography (nature, architecture, coastal, urban).
//! Search: GET https://jaymantri.com/api/read/json?num=50&type=photo
//! Download: Direct master image from R2 / Tumblr CDN.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "jaymantri";
pub const name = "Jay Mantri";

fn extractR2Url(caption: []const u8) ?[]const u8 {
    const key = "href=\"";
    const start_idx = std.mem.indexOf(u8, caption, key) orelse return null;
    const url_start = start_idx + key.len;
    const url_end = std.mem.indexOfScalarPos(u8, caption, url_start, '"') orelse return null;
    const u = caption[url_start..url_end];
    if (std.mem.startsWith(u8, u, "http")) return u;
    return null;
}

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
        std.ascii.eqlIgnoreCase(trimmed_query, "jaymantri") or
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

        const caption = if (p.object.get("photo-caption")) |c| (if (c == .string) c.string else "") else "";
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

        // Check if query matches
        var matched = match_all;
        if (!matched) {
            if (containsIgnoreCase(tags_buf.items, trimmed_query) or
                containsIgnoreCase(caption, trimmed_query) or
                containsIgnoreCase(slug, trimmed_query))
            {
                matched = true;
            }
        }
        if (!matched) continue;

        // Image URL: Prefer R2 master URL, then 1280px, then 500px
        const r2_url = extractR2Url(caption);
        const best_img = r2_url orelse photo_1280 orelse photo_500 orelse continue;
        const thumb_img = photo_500 orelse photo_1280 orelse best_img;

        // Description / prompt
        const desc = if (tags_buf.items.len > 0)
            tags_buf.items
        else if (slug.len > 0 and !std.mem.eql(u8, slug, "download"))
            slug
        else
            "Jay Mantri Stock Photo";

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
        try meta_aw.writer.print("{{\"source\":\"jaymantri\",\"page\":\"https://jaymantri.com/post/{s}\"}}", .{post_id});
        const meta = try meta_aw.toOwnedSlice();

        try assets.append(allocator, .{
            .id = pid_owned,
            .description = desc_owned,
            .prompt = prompt_owned,
            .image_url = img_owned,
            .thumbnail_url = thumb_owned,
            .provider = provider_owned,
            .author = try allocator.dupe(u8, "Jay Mantri"),
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

    // Fetch up to 50 photo posts from Jay Mantri public JSON endpoint
    const url = "https://jaymantri.com/api/read/json?num=50&type=photo";
    var resp = try http_client.get(client, allocator, url, .{
        .accept = "application/json,text/javascript,*/*;q=0.8",
        .referer = "https://jaymantri.com/",
        .max_redirects = 5,
    });
    defer resp.deinit();
    if (resp.status != 200) return error.HttpStatus;

    const lim = @min(@max(limit, 1), 50);
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
        .referer = "https://jaymantri.com/",
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
