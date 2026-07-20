//! Normalized asset model shared across providers.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Asset = struct {
    id: []const u8,
    description: []const u8,
    prompt: ?[]const u8 = null,
    image_url: ?[]const u8 = null,
    thumbnail_url: ?[]const u8 = null,
    provider: []const u8,
    author: ?[]const u8 = null,
    width: ?u32 = null,
    height: ?u32 = null,
    /// Opaque provider-specific extras (JSON object string, optional).
    metadata_json: ?[]const u8 = null,

    pub fn deinit(self: *Asset, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.description);
        if (self.prompt) |p| allocator.free(p);
        if (self.image_url) |u| allocator.free(u);
        if (self.thumbnail_url) |u| allocator.free(u);
        allocator.free(self.provider);
        if (self.author) |a| allocator.free(a);
        if (self.metadata_json) |m| allocator.free(m);
        self.* = undefined;
    }
};

pub const SearchResult = struct {
    assets: []Asset,
    total: ?u64 = null,
    provider: []const u8,
    query: []const u8,
    allocator: Allocator,

    pub fn deinit(self: *SearchResult) void {
        for (self.assets) |*a| a.deinit(self.allocator);
        self.allocator.free(self.assets);
        self.allocator.free(self.provider);
        self.allocator.free(self.query);
        self.* = undefined;
    }
};

pub fn writeJson(asset: Asset, w: *std.Io.Writer) !void {
    try w.writeAll("{\n");
    try w.print("  \"id\": \"{s}\",\n", .{asset.id});
    try w.print("  \"description\": ", .{});
    try writeJsonString(w, asset.description);
    try w.writeAll(",\n  \"prompt\": ");
    if (asset.prompt) |p| {
        try writeJsonString(w, p);
    } else {
        try w.writeAll("null");
    }
    try w.writeAll(",\n  \"imageUrl\": ");
    if (asset.image_url) |u| {
        try writeJsonString(w, u);
    } else {
        try w.writeAll("null");
    }
    try w.writeAll(",\n  \"thumbnailUrl\": ");
    if (asset.thumbnail_url) |u| {
        try writeJsonString(w, u);
    } else {
        try w.writeAll("null");
    }
    try w.print(",\n  \"provider\": \"{s}\"", .{asset.provider});
    try w.writeAll(",\n  \"author\": ");
    if (asset.author) |a| {
        try writeJsonString(w, a);
    } else {
        try w.writeAll("null");
    }
    if (asset.width) |wd| {
        try w.print(",\n  \"width\": {d}", .{wd});
    } else {
        try w.writeAll(",\n  \"width\": null");
    }
    if (asset.height) |ht| {
        try w.print(",\n  \"height\": {d}", .{ht});
    } else {
        try w.writeAll(",\n  \"height\": null");
    }
    try w.writeAll(",\n  \"metadata\": ");
    if (asset.metadata_json) |m| {
        try w.writeAll(m);
    } else {
        try w.writeAll("{}");
    }
    try w.writeAll("\n}");
}

fn writeJsonString(w: *std.Io.Writer, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try w.print("\\u{x:0>4}", .{c});
                } else {
                    try w.writeByte(c);
                }
            },
        }
    }
    try w.writeByte('"');
}
