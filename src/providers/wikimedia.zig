//! Wikimedia Commons provider — free CC0, public domain, and freely-licensed educational/stock media.
//! Search: GET https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrnamespace=6&gsrsearch={query}&gsrlimit={limit}&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=500&format=json
//! Download: Direct master full-resolution media from upload.wikimedia.org.

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "wikimedia";
pub const name = "Wikimedia Commons";

const RankedAsset = struct {
    index: i64,
    asset: Asset,
};

fn sortRanked(_: void, a: RankedAsset, b: RankedAsset) bool {
    return a.index < b.index;
}

fn stripQueryParam(url: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, url, '?')) |q| {
        return url[0..q];
    }
    return url;
}

fn cleanTitle(allocator: Allocator, raw_title: []const u8) ![]u8 {
    var title = raw_title;
    if (std.mem.startsWith(u8, title, "File:")) {
        title = title["File:".len..];
    }
    if (std.mem.lastIndexOfScalar(u8, title, '.')) |dot| {
        title = title[0..dot];
    }
    const res = try allocator.dupe(u8, title);
    for (res) |*c| {
        if (c.* == '_') c.* = ' ';
    }
    return res;
}

fn parseSearch(allocator: Allocator, json_bytes: []const u8, limit: u32) ![]Asset {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return &[_]Asset{};
    const query_val = root.object.get("query") orelse return &[_]Asset{};
    if (query_val != .object) return &[_]Asset{};
    const pages_val = query_val.object.get("pages") orelse return &[_]Asset{};
    if (pages_val != .object) return &[_]Asset{};

    var ranked_list: std.ArrayList(RankedAsset) = .empty;
    errdefer {
        for (ranked_list.items) |*r| r.asset.deinit(allocator);
        ranked_list.deinit(allocator);
    }

    var it = pages_val.object.iterator();
    while (it.next()) |entry| {
        const page = entry.value_ptr.*;
        if (page != .object) continue;

        const pageid_val = page.object.get("pageid");
        const page_id_int: i64 = if (pageid_val) |pid| switch (pid) {
            .integer => |i| i,
            else => 0,
        } else 0;

        const index_val = page.object.get("index");
        const rank_index: i64 = if (index_val) |idx| switch (idx) {
            .integer => |i| i,
            else => 999999,
        } else 999999;

        const title_val = page.object.get("title");
        const title_str = if (title_val) |t| switch (t) {
            .string => |s| s,
            else => "",
        } else "";

        const imageinfo_val = page.object.get("imageinfo");
        if (imageinfo_val == null or imageinfo_val.? != .array or imageinfo_val.?.array.items.len == 0) {
            continue;
        }

        const info = imageinfo_val.?.array.items[0];
        if (info != .object) continue;

        const url_val = info.object.get("url") orelse continue;
        if (url_val != .string) continue;
        const raw_img_url = url_val.string;
        const img_url_clean = stripQueryParam(raw_img_url);

        const thumb_val = info.object.get("thumburl");
        const raw_thumb_url = if (thumb_val) |tv| switch (tv) {
            .string => |s| s,
            else => raw_img_url,
        } else raw_img_url;
        const thumb_url_clean = stripQueryParam(raw_thumb_url);

        const width_val = info.object.get("width");
        const width: ?u32 = if (width_val) |w| switch (w) {
            .integer => |i| if (i > 0) @intCast(i) else null,
            else => null,
        } else null;

        const height_val = info.object.get("height");
        const height: ?u32 = if (height_val) |h| switch (h) {
            .integer => |i| if (i > 0) @intCast(i) else null,
            else => null,
        } else null;

        const pid_str = try std.fmt.allocPrint(allocator, "wikimedia-{d}", .{page_id_int});
        errdefer allocator.free(pid_str);

        const cleaned_title = try cleanTitle(allocator, title_str);
        errdefer allocator.free(cleaned_title);

        const prompt_str = try allocator.dupe(u8, cleaned_title);
        errdefer allocator.free(prompt_str);

        const master_url = try allocator.dupe(u8, img_url_clean);
        errdefer allocator.free(master_url);

        const thumb_url = try allocator.dupe(u8, thumb_url_clean);
        errdefer allocator.free(thumb_url);

        const prov_owned = try allocator.dupe(u8, id);
        errdefer allocator.free(prov_owned);

        const auth_owned = try allocator.dupe(u8, "Wikimedia Commons Contributors");
        errdefer allocator.free(auth_owned);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"wikimedia\",\"pageid\":{d},\"page\":\"https://commons.wikimedia.org/?curid={d}\"}}", .{ page_id_int, page_id_int });
        const meta = try meta_aw.toOwnedSlice();

        try ranked_list.append(allocator, .{
            .index = rank_index,
            .asset = .{
                .id = pid_str,
                .description = cleaned_title,
                .prompt = prompt_str,
                .image_url = master_url,
                .thumbnail_url = thumb_url,
                .provider = prov_owned,
                .author = auth_owned,
                .width = width,
                .height = height,
                .metadata_json = meta,
            },
        });
    }

    std.mem.sort(RankedAsset, ranked_list.items, {}, sortRanked);

    const take_count = @min(ranked_list.items.len, @as(usize, limit));
    const result = try allocator.alloc(Asset, take_count);
    for (0..take_count) |i| {
        result[i] = ranked_list.items[i].asset;
    }
    for (take_count..ranked_list.items.len) |i| {
        ranked_list.items[i].asset.deinit(allocator);
    }
    ranked_list.deinit(allocator);

    return result;
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

    const search_url = try std.fmt.allocPrint(
        allocator,
        "https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrnamespace=6&gsrsearch={s}&gsrlimit={d}&prop=imageinfo&iiprop=url|size|mime&iiurlwidth=500&format=json",
        .{ enc, lim },
    );
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "application/json",
        .max_redirects = 5,
    });
    defer resp.deinit();
    if (resp.status != 200) return error.HttpStatus;

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
