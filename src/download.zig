//! Download helpers.

const std = @import("std");
const http_util = @import("http_util.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const DownloadError = error{
    NoUrl,
    Network,
    HttpStatus,
    RateLimited,
    Io,
    OutOfMemory,
};

pub const Saved = struct {
    path: []u8,
    filename: []const u8,
    bytes: usize,
    allocator: Allocator,

    pub fn deinit(self: *Saved) void {
        self.allocator.free(self.path);
        self.* = undefined;
    }
};

pub fn ensureDir(io: Io, dir_path: []const u8) !void {
    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, dir_path);
}

pub fn guessExtension(url: []const u8) []const u8 {
    const path = if (std.mem.indexOfScalar(u8, url, '?')) |q| url[0..q] else url;
    const pairs = [_]struct { []const u8, []const u8 }{
        .{ ".jpeg", "jpg" },
        .{ ".jpg", "jpg" },
        .{ ".png", "png" },
        .{ ".webp", "webp" },
        .{ ".gif", "gif" },
        .{ ".avif", "avif" },
        .{ ".svg", "svg" },
        .{ ".mp4", "mp4" },
        .{ ".webm", "webm" },
    };
    for (pairs) |pair| {
        if (std.ascii.endsWithIgnoreCase(path, pair[0])) return pair[1];
    }
    return "jpg";
}

pub fn sanitizeFilename(allocator: Allocator, name: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (name) |c| {
        const bad = c == '<' or c == '>' or c == ':' or c == '"' or c == '/' or
            c == '\\' or c == '|' or c == '?' or c == '*' or c < 0x20;
        if (bad) {
            try list.append(allocator, '_');
        } else if (c == ' ') {
            try list.append(allocator, '_');
        } else {
            try list.append(allocator, c);
        }
    }
    if (list.items.len == 0) try list.appendSlice(allocator, "asset");
    if (list.items.len > 120) list.shrinkRetainingCapacity(120);
    return list.toOwnedSlice(allocator);
}

fn pathExists(io: Io, path: []const u8) bool {
    const cwd = Io.Dir.cwd();
    cwd.access(io, path, .{}) catch return false;
    return true;
}

pub fn uniquePath(allocator: Allocator, io: Io, directory: []const u8, base: []const u8, ext: []const u8) ![]u8 {
    const safe = try sanitizeFilename(allocator, base);
    defer allocator.free(safe);

    var candidate = try std.fmt.allocPrint(allocator, "{s}/{s}.{s}", .{ directory, safe, ext });
    if (!pathExists(io, candidate)) return candidate;

    allocator.free(candidate);
    var n: u32 = 1;
    while (n < 10_000) : (n += 1) {
        candidate = try std.fmt.allocPrint(allocator, "{s}/{s}-{d}.{s}", .{ directory, safe, n, ext });
        if (!pathExists(io, candidate)) return candidate;
        allocator.free(candidate);
    }
    return error.Io;
}

pub fn downloadUrl(
    client: *std.http.Client,
    allocator: Allocator,
    io: Io,
    url: []const u8,
    output_dir: []const u8,
    preferred_base: []const u8,
) DownloadError!Saved {
    if (url.len == 0) return error.NoUrl;

    ensureDir(io, output_dir) catch return error.Io;

    const body = http_util.getBytes(client, allocator, url) catch |err| switch (err) {
        error.RateLimited => return error.RateLimited,
        error.HttpStatus => return error.HttpStatus,
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Network,
    };
    defer allocator.free(body);

    if (body.len == 0) return error.HttpStatus;

    const ext = guessExtension(url);
    const path = uniquePath(allocator, io, output_dir, preferred_base, ext) catch return error.Io;
    errdefer allocator.free(path);

    const cwd = Io.Dir.cwd();
    cwd.writeFile(io, .{ .sub_path = path, .data = body }) catch return error.Io;

    const filename = std.fs.path.basename(path);
    return .{
        .path = path,
        .filename = filename,
        .bytes = body.len,
        .allocator = allocator,
    };
}
