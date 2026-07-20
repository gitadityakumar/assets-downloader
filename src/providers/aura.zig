//! Aura.build Assets provider (Supabase PostgREST).
//! See docs/AURA_API.md

const std = @import("std");
const asset_mod = @import("../asset.zig");
const http_util = @import("../http_util.zig");
const download_mod = @import("../download.zig");
const config = @import("../config.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const id = "aura";
pub const name = "Aura.build";

const supabase_rest = "https://hoirqrkdgbmvpwutwuwj.supabase.co/rest/v1";
const anon_key =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhvaXJxcmtkZ2JtdnB3dXR3dXdqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM2Nzc2NTAsImV4cCI6MjA1OTI1MzY1MH0._UsCSHsTELn7m54tOhX3ySm67WEhcyHAPbuxEQZsl3c";

const select_cols =
    "id,title,description,keywords,resolution,colors," ++
    "image_original,image_320w,image_800w,image_1600w,image_3840w," ++
    "featured,active,created_at,updated_at,created_by,views,forks," ++
    "premium,private,slug,transparent,media_type,image_url," ++
    "video_url,video_poster_url,video_duration";

const AuraRow = struct {
    id: i64,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    keywords: ?[]const []const u8 = null,
    resolution: ?[]const u8 = null,
    image_original: ?[]const u8 = null,
    image_320w: ?[]const u8 = null,
    image_800w: ?[]const u8 = null,
    image_1600w: ?[]const u8 = null,
    image_3840w: ?[]const u8 = null,
    image_url: ?[]const u8 = null,
    slug: ?[]const u8 = null,
    views: ?i64 = null,
    forks: ?i64 = null,
    media_type: ?[]const u8 = null,
    premium: ?bool = null,
    created_at: ?[]const u8 = null,
    created_by: ?[]const u8 = null,
};

fn rewriteStorageUrl(url: []const u8, buf: []u8) []const u8 {
    // hoirqrkdgbmvpwutwuwj-all.supabase.co → hoirqrkdgbmvpwutwuwj.supabase.co
    const needle = "-all.supabase.co";
    if (std.mem.indexOf(u8, url, needle)) |idx| {
        const before = url[0..idx];
        const after = url[idx + needle.len ..];
        if (before.len + ".supabase.co".len + after.len > buf.len) return url;
        @memcpy(buf[0..before.len], before);
        @memcpy(buf[before.len .. before.len + ".supabase.co".len], ".supabase.co");
        @memcpy(buf[before.len + ".supabase.co".len ..][0..after.len], after);
        return buf[0 .. before.len + ".supabase.co".len + after.len];
    }
    return url;
}

fn pickImage(row: AuraRow, scratch: []u8) ?[]const u8 {
    const candidates = [_]?[]const u8{
        row.image_3840w,
        row.image_original,
        row.image_1600w,
        row.image_url,
        row.image_800w,
        row.image_320w,
    };
    for (candidates) |c| {
        if (c) |u| {
            if (std.mem.startsWith(u8, u, "http")) {
                return rewriteStorageUrl(u, scratch);
            }
        }
    }
    return null;
}

fn pickThumb(row: AuraRow, scratch: []u8) ?[]const u8 {
    const candidates = [_]?[]const u8{ row.image_800w, row.image_320w, row.image_1600w, row.image_url };
    for (candidates) |c| {
        if (c) |u| {
            if (std.mem.startsWith(u8, u, "http")) {
                return rewriteStorageUrl(u, scratch);
            }
        }
    }
    return pickImage(row, scratch);
}

fn dimsForResolution(res: ?[]const u8) struct { ?u32, ?u32 } {
    if (res == null) return .{ null, null };
    const r = res.?;
    if (std.mem.eql(u8, r, "16:9")) return .{ 3840, 2160 };
    if (std.mem.eql(u8, r, "4:3")) return .{ 1600, 1200 };
    if (std.mem.eql(u8, r, "1:1")) return .{ 1600, 1600 };
    if (std.mem.eql(u8, r, "3:4")) return .{ 1200, 1600 };
    if (std.mem.eql(u8, r, "9:16")) return .{ 1080, 1920 };
    return .{ null, null };
}

fn escapeIlike(allocator: Allocator, token: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (token) |c| {
        if (c == '%' or c == '_') {
            try list.append(allocator, '\\');
        }
        try list.append(allocator, c);
    }
    return list.toOwnedSlice(allocator);
}

fn appendTokenGroup(list: *std.ArrayList(u8), allocator: Allocator, token: []const u8) !void {
    const safe = try escapeIlike(allocator, token);
    defer allocator.free(safe);
    // or(title.ilike.%T%,description.ilike.%T%,keywords.cs.{T})
    try list.appendSlice(allocator, "or(title.ilike.%");
    try list.appendSlice(allocator, safe);
    try list.appendSlice(allocator, "%,description.ilike.%");
    try list.appendSlice(allocator, safe);
    try list.appendSlice(allocator, "%,keywords.cs.{");
    try list.appendSlice(allocator, safe);
    try list.appendSlice(allocator, "})");
}

fn encodeQueryValue(allocator: Allocator, raw: []const u8) ![]u8 {
    // Encode so Uri.parse accepts braces/commas/etc. in the query string.
    return http_util.queryEscape(allocator, raw);
}

fn buildSearchUrl(allocator: Allocator, query: []const u8, limit: u32, offset: u32) ![]u8 {
    var filter_list: std.ArrayList(u8) = .empty;
    defer filter_list.deinit(allocator);

    var tokens = std.mem.tokenizeAny(u8, query, " \t\n\r");
    var count: usize = 0;
    var first = true;
    while (tokens.next()) |tok| {
        if (tok.len == 0) continue;
        count += 1;
        if (!first) try filter_list.append(allocator, ',');
        first = false;
        try appendTokenGroup(&filter_list, allocator, tok);
    }

    var url: std.ArrayList(u8) = .empty;
    errdefer url.deinit(allocator);
    try url.appendSlice(allocator, supabase_rest);
    try url.appendSlice(allocator, "/assets?select=");
    // select list is safe unencoded (commas OK in query for most servers, but encode for Uri)
    const enc_select = try encodeQueryValue(allocator, select_cols);
    defer allocator.free(enc_select);
    try url.appendSlice(allocator, enc_select);
    try url.appendSlice(allocator, "&private=eq.false&order=views.desc");
    const page = try std.fmt.allocPrint(allocator, "&offset={d}&limit={d}", .{ offset, limit });
    defer allocator.free(page);
    try url.appendSlice(allocator, page);

    if (count == 1) {
        const groups = filter_list.items;
        if (groups.len > 4 and std.mem.startsWith(u8, groups, "or(") and groups[groups.len - 1] == ')') {
            const inner = groups[3 .. groups.len - 1];
            var raw_val: std.ArrayList(u8) = .empty;
            defer raw_val.deinit(allocator);
            try raw_val.append(allocator, '(');
            try raw_val.appendSlice(allocator, inner);
            try raw_val.append(allocator, ')');
            const enc = try encodeQueryValue(allocator, raw_val.items);
            defer allocator.free(enc);
            try url.appendSlice(allocator, "&or=");
            try url.appendSlice(allocator, enc);
        }
    } else if (count > 1) {
        var raw_val: std.ArrayList(u8) = .empty;
        defer raw_val.deinit(allocator);
        try raw_val.append(allocator, '(');
        try raw_val.appendSlice(allocator, filter_list.items);
        try raw_val.append(allocator, ')');
        const enc = try encodeQueryValue(allocator, raw_val.items);
        defer allocator.free(enc);
        try url.appendSlice(allocator, "&and=");
        try url.appendSlice(allocator, enc);
    }

    return url.toOwnedSlice(allocator);
}

fn normalizeRow(allocator: Allocator, row: AuraRow) !Asset {
    var scratch: [2048]u8 = undefined;
    const id_str = try std.fmt.allocPrint(allocator, "{d}", .{row.id});
    errdefer allocator.free(id_str);

    const desc = if (row.title) |t| (if (t.len > 0) t else null) else null;
    const description = try allocator.dupe(u8, desc orelse id_str);
    errdefer allocator.free(description);

    var prompt: ?[]const u8 = null;
    if (row.description) |d| {
        if (d.len > 0) prompt = try allocator.dupe(u8, d);
    } else if (row.title) |t| {
        prompt = try allocator.dupe(u8, t);
    }
    errdefer if (prompt) |p| allocator.free(p);

    var image_url: ?[]const u8 = null;
    if (pickImage(row, &scratch)) |u| {
        image_url = try allocator.dupe(u8, u);
    }
    errdefer if (image_url) |u| allocator.free(u);

    var thumb: ?[]const u8 = null;
    if (pickThumb(row, &scratch)) |u| {
        thumb = try allocator.dupe(u8, u);
    }
    errdefer if (thumb) |u| allocator.free(u);

    const provider = try allocator.dupe(u8, id);
    errdefer allocator.free(provider);

    const wh = dimsForResolution(row.resolution);

    // compact metadata JSON
    var meta_aw: Io.Writer.Allocating = .init(allocator);
    defer meta_aw.deinit();
    try meta_aw.writer.print("{{\"slug\":", .{});
    if (row.slug) |s| {
        try meta_aw.writer.print("\"{s}\"", .{s});
    } else try meta_aw.writer.writeAll("null");
    try meta_aw.writer.print(",\"views\":{d},\"mediaType\":", .{row.views orelse 0});
    if (row.media_type) |m| {
        try meta_aw.writer.print("\"{s}\"", .{m});
    } else try meta_aw.writer.writeAll("\"image\"");
    try meta_aw.writer.writeAll("}");
    const metadata_json = try meta_aw.toOwnedSlice();

    return .{
        .id = id_str,
        .description = description,
        .prompt = prompt,
        .image_url = image_url,
        .thumbnail_url = thumb,
        .provider = provider,
        .author = null,
        .width = wh[0],
        .height = wh[1],
        .metadata_json = metadata_json,
    };
}

pub fn search(
    client: *std.http.Client,
    allocator: Allocator,
    query: []const u8,
    limit: u32,
) !SearchResult {
    const trimmed = std.mem.trim(u8, query, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyQuery;

    const lim = @min(@max(limit, 1), 100);
    const url = try buildSearchUrl(allocator, trimmed, lim, 0);
    defer allocator.free(url);

    const headers = [_]std.http.Header{
        .{ .name = "apikey", .value = anon_key },
        .{ .name = "Authorization", .value = "Bearer " ++ anon_key },
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "Accept-Profile", .value = "public" },
        .{ .name = "Prefer", .value = "count=exact" },
    };

    const body = try http_util.get(client, allocator, url, &headers);
    defer allocator.free(body);

    const parsed = try std.json.parseFromSlice([]AuraRow, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    var assets = try allocator.alloc(Asset, parsed.value.len);
    errdefer {
        for (assets[0..]) |*a| a.deinit(allocator);
        allocator.free(assets);
    }

    for (parsed.value, 0..) |row, i| {
        assets[i] = try normalizeRow(allocator, row);
    }

    const provider_owned = try allocator.dupe(u8, id);
    const query_owned = try allocator.dupe(u8, trimmed);

    return .{
        .assets = assets,
        .total = null, // Content-Range not exposed by fetch()
        .provider = provider_owned,
        .query = query_owned,
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
    return download_mod.downloadUrl(client, allocator, io, url, output_dir, a.id);
}

pub fn getPrompt(a: Asset) ?[]const u8 {
    if (a.prompt) |p| {
        if (p.len > 0) return p;
    }
    if (a.description.len > 0) return a.description;
    return null;
}

pub fn getUrl(a: Asset) ?[]const u8 {
    return a.image_url;
}
