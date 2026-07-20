//! Thin HTTP helpers around std.http.Client.

const std = @import("std");
const config = @import("config.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const HttpError = error{
    Network,
    HttpStatus,
    RateLimited,
    OutOfMemory,
    InvalidUri,
    Tls,
    Unexpected,
};

pub fn get(
    client: *std.http.Client,
    allocator: Allocator,
    url: []const u8,
    extra_headers: []const std.http.Header,
) HttpError![]u8 {
    var aw: Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &aw.writer,
        .extra_headers = extra_headers,
        .headers = .{
            .user_agent = .{ .override = config.user_agent },
        },
    }) catch return error.Network;

    const code = @intFromEnum(result.status);
    if (code == 429) return error.RateLimited;
    if (code < 200 or code >= 300) return error.HttpStatus;

    return aw.toOwnedSlice() catch return error.OutOfMemory;
}

pub fn getBytes(
    client: *std.http.Client,
    allocator: Allocator,
    url: []const u8,
) HttpError![]u8 {
    return get(client, allocator, url, &.{});
}

/// Percent-encode a string for use in a query component (conservative).
pub fn queryEscape(allocator: Allocator, raw: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (raw) |c| {
        const unreserved = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_' or c == '.' or c == '~';
        if (unreserved) {
            try list.append(allocator, c);
        } else if (c == ' ') {
            try list.append(allocator, '%');
            try list.append(allocator, '2');
            try list.append(allocator, '0');
        } else {
            try list.append(allocator, '%');
            const hex = "0123456789ABCDEF";
            try list.append(allocator, hex[c >> 4]);
            try list.append(allocator, hex[c & 0xf]);
        }
    }
    return list.toOwnedSlice(allocator);
}
