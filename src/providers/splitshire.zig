//! SplitShire provider — free stock photos and artwork by Daniel Nanescu & community.
//! Search: GET https://www.splitshire.com/ (extracts __NEXT_DATA__ image collections)
//! Download: direct high-resolution assets hosted on DigitalOcean Spaces / SplitShire CDN.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "splitshire";
pub const name = "SplitShire";

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn matchesQuery(query: []const u8, title: []const u8, prompt: []const u8, slug: []const u8) bool {
    const trimmed = std.mem.trim(u8, query, " \t\r\n");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "*")) return true;

    var it = std.mem.tokenizeAny(u8, trimmed, " \t\r\n,");
    while (it.next()) |token| {
        if (containsIgnoreCase(title, token) or
            containsIgnoreCase(prompt, token) or
            containsIgnoreCase(slug, token))
        {
            return true;
        }
    }
    return false;
}

fn parseNextData(allocator: Allocator, html: []const u8, query: []const u8, limit: u32) ![]Asset {
    const script_marker = "<script id=\"__NEXT_DATA__\" type=\"application/json\">";
    const start_pos = std.mem.indexOf(u8, html, script_marker) orelse return error.NotFound;
    const json_start = start_pos + script_marker.len;
    const json_end = std.mem.indexOfPos(u8, html, json_start, "</script>") orelse return error.NotFound;
    const json_str = html[json_start..json_end];

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.NotFound;

    const props = root.object.get("props") orelse return error.NotFound;
    if (props != .object) return error.NotFound;
    const page_props = props.object.get("pageProps") orelse return error.NotFound;
    if (page_props != .object) return error.NotFound;

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

    const collection_keys = [_][]const u8{
        "nanoBananaImages",
        "nanoBananaLiteImages",
        "gptImage2Images",
        "architectImages",
    };

    // First pass: look for matching items
    for (collection_keys) |ckey| {
        const coll = page_props.object.get(ckey) orelse continue;
        if (coll != .array) continue;

        for (coll.array.items) |item| {
            if (assets.items.len >= limit) break;
            if (item != .object) continue;

            const item_obj = item.object;
            const item_id_val = item_obj.get("id") orelse continue;
            var id_str: []u8 = undefined;
            switch (item_id_val) {
                .integer => |iv| id_str = try std.fmt.allocPrint(allocator, "{d}", .{iv}),
                .string => |sv| id_str = try allocator.dupe(u8, sv),
                else => continue,
            }
            errdefer allocator.free(id_str);

            if (seen.contains(id_str)) {
                allocator.free(id_str);
                continue;
            }

            const slug = if (item_obj.get("slug")) |v| (if (v == .string) v.string else "") else "";
            const title = if (item_obj.get("title")) |v| (if (v == .string) v.string else "") else "";
            const prompt = if (item_obj.get("prompt")) |v| (if (v == .string) v.string else "") else "";

            const img_val = item_obj.get("image_url") orelse item_obj.get("imageSrc") orelse continue;
            const img_url = if (img_val == .string) img_val.string else continue;
            if (img_url.len == 0) {
                allocator.free(id_str);
                continue;
            }

            if (!matchesQuery(query, title, prompt, slug)) {
                allocator.free(id_str);
                continue;
            }

            try seen.put(allocator, try allocator.dupe(u8, id_str), {});

            var author_name: []const u8 = "Daniel Nanescu";
            if (item_obj.get("user")) |u_val| {
                if (u_val == .object) {
                    if (u_val.object.get("name")) |name_val| {
                        if (name_val == .string and name_val.string.len > 0) {
                            author_name = name_val.string;
                        }
                    }
                }
            }

            const desc = if (title.len > 0) title else (if (slug.len > 0) slug else id_str);
            const desc_owned = try allocator.dupe(u8, desc);
            errdefer allocator.free(desc_owned);
            const prompt_owned = try allocator.dupe(u8, if (prompt.len > 0) prompt else desc);
            errdefer allocator.free(prompt_owned);
            const img_owned = try allocator.dupe(u8, img_url);
            errdefer allocator.free(img_owned);
            const thumb_owned = try allocator.dupe(u8, img_url);
            errdefer allocator.free(thumb_owned);
            const prov_owned = try allocator.dupe(u8, id);
            errdefer allocator.free(prov_owned);
            const auth_owned = try allocator.dupe(u8, author_name);
            errdefer allocator.free(auth_owned);

            var meta_aw: Io.Writer.Allocating = .init(allocator);
            defer meta_aw.deinit();
            if (slug.len > 0) {
                try meta_aw.writer.print("{{\"source\":\"splitshire\",\"slug\":\"{s}\",\"page\":\"https://www.splitshire.com/photos/{s}\"}}", .{ slug, slug });
            } else {
                try meta_aw.writer.print("{{\"source\":\"splitshire\",\"page\":\"https://www.splitshire.com/\"}}", .{});
            }
            const meta = try meta_aw.toOwnedSlice();

            try assets.append(allocator, .{
                .id = id_str,
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
    }

    // Second pass: if query matched nothing, return top items
    if (assets.items.len == 0) {
        for (collection_keys) |ckey| {
            const coll = page_props.object.get(ckey) orelse continue;
            if (coll != .array) continue;

            for (coll.array.items) |item| {
                if (assets.items.len >= limit) break;
                if (item != .object) continue;

                const item_obj = item.object;
                const item_id_val = item_obj.get("id") orelse continue;
                var id_str: []u8 = undefined;
                switch (item_id_val) {
                    .integer => |iv| id_str = try std.fmt.allocPrint(allocator, "{d}", .{iv}),
                    .string => |sv| id_str = try allocator.dupe(u8, sv),
                    else => continue,
                }
                errdefer allocator.free(id_str);

                if (seen.contains(id_str)) {
                    allocator.free(id_str);
                    continue;
                }

                const slug = if (item_obj.get("slug")) |v| (if (v == .string) v.string else "") else "";
                const title = if (item_obj.get("title")) |v| (if (v == .string) v.string else "") else "";
                const prompt = if (item_obj.get("prompt")) |v| (if (v == .string) v.string else "") else "";

                const img_val = item_obj.get("image_url") orelse item_obj.get("imageSrc") orelse continue;
                const img_url = if (img_val == .string) img_val.string else continue;
                if (img_url.len == 0) {
                    allocator.free(id_str);
                    continue;
                }

                try seen.put(allocator, try allocator.dupe(u8, id_str), {});

                var author_name: []const u8 = "Daniel Nanescu";
                if (item_obj.get("user")) |u_val| {
                    if (u_val == .object) {
                        if (u_val.object.get("name")) |name_val| {
                            if (name_val == .string and name_val.string.len > 0) {
                                author_name = name_val.string;
                            }
                        }
                    }
                }

                const desc = if (title.len > 0) title else (if (slug.len > 0) slug else id_str);
                const desc_owned = try allocator.dupe(u8, desc);
                errdefer allocator.free(desc_owned);
                const prompt_owned = try allocator.dupe(u8, if (prompt.len > 0) prompt else desc);
                errdefer allocator.free(prompt_owned);
                const img_owned = try allocator.dupe(u8, img_url);
                errdefer allocator.free(img_owned);
                const thumb_owned = try allocator.dupe(u8, img_url);
                errdefer allocator.free(thumb_owned);
                const prov_owned = try allocator.dupe(u8, id);
                errdefer allocator.free(prov_owned);
                const auth_owned = try allocator.dupe(u8, author_name);
                errdefer allocator.free(auth_owned);

                var meta_aw: Io.Writer.Allocating = .init(allocator);
                defer meta_aw.deinit();
                if (slug.len > 0) {
                    try meta_aw.writer.print("{{\"source\":\"splitshire\",\"slug\":\"{s}\",\"page\":\"https://www.splitshire.com/photos/{s}\"}}", .{ slug, slug });
                } else {
                    try meta_aw.writer.print("{{\"source\":\"splitshire\",\"page\":\"https://www.splitshire.com/\"}}", .{});
                }
                const meta = try meta_aw.toOwnedSlice();

                try assets.append(allocator, .{
                    .id = id_str,
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
        }
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
    const search_url = try std.fmt.allocPrint(allocator, "https://www.splitshire.com/?s={s}", .{enc});
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        .referer = "https://www.splitshire.com/",
        .max_redirects = 5,
    });
    defer resp.deinit();
    if (resp.status != 200) return error.HttpStatus;

    const lim = @min(@max(limit, 1), 50);
    const assets = try parseNextData(allocator, resp.body, trimmed, lim);

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
        .referer = "https://www.splitshire.com/",
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
