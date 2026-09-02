//! NASA Image and Video Library provider — public domain space and aeronautics imagery.
//! Search: GET https://images-api.nasa.gov/search?q={query}&media_type=image
//! Download: Direct high-resolution assets from images-assets.nasa.gov

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_client = @import("../http_client.zig");
const download_mod = @import("../download.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "nasa";
pub const name = "NASA Image Library";

fn escapeUrl(allocator: Allocator, raw_url: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (raw_url) |c| {
        if (c == ' ') {
            try list.appendSlice(allocator, "%20");
        } else {
            try list.append(allocator, c);
        }
    }
    return list.toOwnedSlice(allocator);
}

fn sanitizeId(allocator: Allocator, raw_id: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, "nasa-");
    for (raw_id) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_') {
            try list.append(allocator, c);
        } else if (c == ' ') {
            try list.append(allocator, '-');
        }
    }
    if (list.items.len == 5) {
        try list.appendSlice(allocator, "image");
    }
    return list.toOwnedSlice(allocator);
}

fn parseJsonSearch(allocator: Allocator, json_bytes: []const u8, query: []const u8, limit: u32) ![]Asset {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return &[_]Asset{};

    const coll_val = root.object.get("collection") orelse return &[_]Asset{};
    if (coll_val != .object) return &[_]Asset{};

    const items_val = coll_val.object.get("items") orelse return &[_]Asset{};
    if (items_val != .array) return &[_]Asset{};

    var assets: std.ArrayList(Asset) = .empty;
    errdefer {
        for (assets.items) |*a| a.deinit(allocator);
        assets.deinit(allocator);
    }

    const items = items_val.array.items;
    for (items) |item| {
        if (assets.items.len >= limit) break;
        if (item != .object) continue;

        const data_val = item.object.get("data") orelse continue;
        if (data_val != .array or data_val.array.items.len == 0) continue;
        const d = data_val.array.items[0];
        if (d != .object) continue;

        const nasa_id_val = d.object.get("nasa_id");
        const raw_nasa_id = if (nasa_id_val) |v| switch (v) {
            .string => |s| s,
            else => "",
        } else "";
        if (raw_nasa_id.len == 0) continue;

        const title_val = d.object.get("title");
        const title = if (title_val) |v| switch (v) {
            .string => |s| s,
            else => "",
        } else "";

        const center_val = d.object.get("center");
        const center = if (center_val) |v| switch (v) {
            .string => |s| s,
            else => "",
        } else "";

        const photog_val = d.object.get("photographer");
        const photog = if (photog_val) |v| switch (v) {
            .string => |s| s,
            else => "",
        } else "";

        // Extract links: thumb, large, orig
        var thumb_raw: ?[]const u8 = null;
        var large_raw: ?[]const u8 = null;
        var orig_raw: ?[]const u8 = null;
        var medium_raw: ?[]const u8 = null;

        if (item.object.get("links")) |lv| {
            if (lv == .array) {
                for (lv.array.items) |l| {
                    if (l != .object) continue;
                    const href_val = l.object.get("href") orelse continue;
                    const href = switch (href_val) {
                        .string => |s| s,
                        else => continue,
                    };
                    const rel_val = l.object.get("rel");
                    const rel = if (rel_val) |rv| switch (rv) {
                        .string => |s| s,
                        else => "",
                    } else "";

                    if (std.mem.endsWith(u8, href, "~thumb.jpg") or std.mem.eql(u8, rel, "preview")) {
                        thumb_raw = href;
                    } else if (std.mem.endsWith(u8, href, "~large.jpg")) {
                        large_raw = href;
                    } else if (std.mem.endsWith(u8, href, "~medium.jpg")) {
                        medium_raw = href;
                    } else if (std.mem.eql(u8, rel, "canonical") or std.mem.indexOf(u8, href, "~orig.") != null) {
                        orig_raw = href;
                    }
                }
            }
        }

        // Determine best image_url
        // If orig is a jpeg/png, use orig.
        // If orig is a .tif (TIFF), prefer large or medium jpeg so standard viewers work directly.
        var best_url_raw: ?[]const u8 = null;
        if (orig_raw) |ourl| {
            if (std.mem.endsWith(u8, ourl, ".tif") or std.mem.endsWith(u8, ourl, ".tiff")) {
                best_url_raw = large_raw orelse medium_raw orelse ourl;
            } else {
                best_url_raw = ourl;
            }
        } else {
            best_url_raw = large_raw orelse medium_raw orelse thumb_raw;
        }

        const active_url = best_url_raw orelse continue;
        const esc_img_url = try escapeUrl(allocator, active_url);
        errdefer allocator.free(esc_img_url);

        const esc_thumb_url = if (thumb_raw) |t|
            try escapeUrl(allocator, t)
        else
            try allocator.dupe(u8, esc_img_url);
        errdefer allocator.free(esc_thumb_url);

        const safe_id = try sanitizeId(allocator, raw_nasa_id);
        errdefer allocator.free(safe_id);

        const desc = try allocator.dupe(u8, if (title.len > 0) title else safe_id);
        errdefer allocator.free(desc);

        const prompt = try allocator.dupe(u8, desc);
        errdefer allocator.free(prompt);

        const prov = try allocator.dupe(u8, id);
        errdefer allocator.free(prov);

        const author_str = if (photog.len > 0)
            try allocator.dupe(u8, photog)
        else if (center.len > 0)
            try std.fmt.allocPrint(allocator, "NASA / {s}", .{center})
        else
            try allocator.dupe(u8, "NASA");
        errdefer allocator.free(author_str);

        var meta_aw: Io.Writer.Allocating = .init(allocator);
        defer meta_aw.deinit();
        try meta_aw.writer.print("{{\"source\":\"nasa\",\"nasa_id\":\"{s}\",\"center\":\"{s}\"}}", .{ raw_nasa_id, center });
        const meta = try meta_aw.toOwnedSlice();

        _ = query;

        try assets.append(allocator, .{
            .id = safe_id,
            .description = desc,
            .prompt = prompt,
            .image_url = esc_img_url,
            .thumbnail_url = esc_thumb_url,
            .provider = prov,
            .author = author_str,
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

    const lim = @min(@max(limit, 1), 100);

    const search_url = try std.fmt.allocPrint(
        allocator,
        "https://images-api.nasa.gov/search?q={s}&media_type=image",
        .{enc},
    );
    defer allocator.free(search_url);

    var resp = try http_client.get(client, allocator, search_url, .{
        .accept = "application/json",
        .max_redirects = 5,
    });
    defer resp.deinit();
    if (resp.status != 200) return error.HttpStatus;

    const assets = try parseJsonSearch(allocator, resp.body, trimmed, lim);

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
    }) catch |err| {
        // Fallback to thumbnail if primary URL fails
        if (a.thumbnail_url) |turl| {
            const fb_body = try http_client.getBody(client, allocator, turl, .{
                .accept = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
                .max_redirects = 5,
            });
            defer allocator.free(fb_body);
            try download_mod.ensureDir(io, output_dir);
            const ext = download_mod.guessExtension(turl);
            const path = try download_mod.uniquePath(allocator, io, output_dir, a.id, ext);
            errdefer allocator.free(path);
            const cwd = Io.Dir.cwd();
            cwd.writeFile(io, .{ .sub_path = path, .data = fb_body }) catch return error.Io;
            return .{
                .path = path,
                .filename = std.fs.path.basename(path),
                .bytes = fb_body.len,
                .allocator = allocator,
            };
        }
        return err;
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
