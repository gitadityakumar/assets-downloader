//! HTTP helpers with redirect control, cookies, and browser-like headers.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const browser_ua =
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36";

pub const HttpError = error{
    Network,
    HttpStatus,
    RateLimited,
    OutOfMemory,
    InvalidUri,
    Unexpected,
};

pub const Response = struct {
    status: u16,
    location: ?[]u8 = null,
    /// Concatenated Set-Cookie values separated by \n if multiple.
    set_cookies: []const []u8 = &.{},
    body: []u8,
    allocator: Allocator,
    owned_cookies: ?[][]u8 = null,

    pub fn deinit(self: *Response) void {
        if (self.location) |l| self.allocator.free(l);
        if (self.owned_cookies) |ocs| {
            for (ocs) |c| self.allocator.free(c);
            self.allocator.free(ocs);
        }
        self.allocator.free(self.body);
        self.* = undefined;
    }
};

pub const CookieJar = struct {
    map: std.StringHashMapUnmanaged([]const u8) = .empty,
    allocator: Allocator,

    pub fn init(allocator: Allocator) CookieJar {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CookieJar) void {
        var it = self.map.iterator();
        while (it.next()) |e| {
            self.allocator.free(e.key_ptr.*);
            self.allocator.free(e.value_ptr.*);
        }
        self.map.deinit(self.allocator);
    }

    pub fn putFromSetCookie(self: *CookieJar, set_cookie: []const u8) !void {
        const semi = std.mem.indexOfScalar(u8, set_cookie, ';') orelse set_cookie.len;
        const nv = std.mem.trim(u8, set_cookie[0..semi], " ");
        const eq = std.mem.indexOfScalar(u8, nv, '=') orelse return;
        const name = nv[0..eq];
        const value = nv[eq + 1 ..];
        if (value.len == 0) {
            if (self.map.fetchRemove(name)) |kv| {
                self.allocator.free(kv.key);
                self.allocator.free(kv.value);
            }
            return;
        }
        const name_owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_owned);
        const value_owned = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_owned);
        if (self.map.fetchRemove(name)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }
        try self.map.put(self.allocator, name_owned, value_owned);
    }

    pub fn absorbResponse(self: *CookieJar, resp: *const Response) void {
        for (resp.set_cookies) |sc| {
            self.putFromSetCookie(sc) catch {};
        }
    }

    pub fn headerValue(self: *CookieJar, allocator: Allocator) !?[]u8 {
        if (self.map.count() == 0) return null;
        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(allocator);
        var it = self.map.iterator();
        var first = true;
        while (it.next()) |e| {
            if (!first) try list.appendSlice(allocator, "; ");
            first = false;
            try list.appendSlice(allocator, e.key_ptr.*);
            try list.append(allocator, '=');
            try list.appendSlice(allocator, e.value_ptr.*);
        }
        return try list.toOwnedSlice(allocator);
    }
};

pub const GetOptions = struct {
    cookie: ?[]const u8 = null,
    referer: ?[]const u8 = null,
    accept: []const u8 = "*/*",
    max_redirects: u16 = 0,
    user_agent: []const u8 = browser_ua,
};

pub fn get(
    client: *std.http.Client,
    allocator: Allocator,
    url: []const u8,
    options: GetOptions,
) HttpError!Response {
    var current_url = try allocator.dupe(u8, url);
    defer allocator.free(current_url);

    var redirects_left = options.max_redirects;
    while (true) {
        var resp = try getOnce(client, allocator, current_url, options);
        const code = resp.status;
        if (code == 429) {
            resp.deinit();
            return error.RateLimited;
        }
        if ((code == 301 or code == 302 or code == 303 or code == 307 or code == 308) and redirects_left > 0) {
            const loc = resp.location orelse {
                resp.deinit();
                return error.HttpStatus;
            };
            const next = resolveUrl(allocator, current_url, loc) catch {
                resp.deinit();
                return error.InvalidUri;
            };
            resp.deinit();
            allocator.free(current_url);
            current_url = next;
            redirects_left -= 1;
            continue;
        }
        return resp;
    }
}

fn getOnce(
    client: *std.http.Client,
    allocator: Allocator,
    url: []const u8,
    options: GetOptions,
) HttpError!Response {
    const uri = std.Uri.parse(url) catch return error.InvalidUri;

    var headers_buf: [8]std.http.Header = undefined;
    var n: usize = 0;
    headers_buf[n] = .{ .name = "Accept", .value = options.accept };
    n += 1;
    headers_buf[n] = .{ .name = "Accept-Language", .value = "en-US,en;q=0.9" };
    n += 1;
    if (options.referer) |r| {
        headers_buf[n] = .{ .name = "Referer", .value = r };
        n += 1;
    }
    if (options.cookie) |c| {
        headers_buf[n] = .{ .name = "Cookie", .value = c };
        n += 1;
    }

    var req = client.request(.GET, uri, .{
        .redirect_behavior = .unhandled,
        .headers = .{
            .user_agent = .{ .override = options.user_agent },
        },
        .extra_headers = headers_buf[0..n],
    }) catch return error.Network;
    defer req.deinit();

    req.sendBodiless() catch return error.Network;

    var redirect_buf: [16 * 1024]u8 = undefined;
    var response = req.receiveHead(&redirect_buf) catch return error.Network;

    const status: u16 = @intFromEnum(response.head.status);

    var location: ?[]u8 = null;
    if (response.head.location) |loc| {
        location = allocator.dupe(u8, loc) catch return error.OutOfMemory;
    }
    errdefer if (location) |l| allocator.free(l);

    var cookie_list: std.ArrayList([]u8) = .empty;
    errdefer {
        for (cookie_list.items) |c| allocator.free(c);
        cookie_list.deinit(allocator);
    }

    var it = response.head.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "set-cookie")) {
            const dup = allocator.dupe(u8, h.value) catch return error.OutOfMemory;
            cookie_list.append(allocator, dup) catch {
                allocator.free(dup);
                return error.OutOfMemory;
            };
        }
    }

    var aw: Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();

    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => allocator.alloc(u8, std.compress.zstd.default_window_len) catch return error.OutOfMemory,
        .deflate, .gzip => allocator.alloc(u8, std.compress.flate.max_window_len) catch return error.OutOfMemory,
        .compress => return error.Unexpected,
    };
    defer if (decompress_buffer.len != 0) allocator.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);
    _ = reader.streamRemaining(&aw.writer) catch return error.Network;

    const body = aw.toOwnedSlice() catch return error.OutOfMemory;
    const owned_cookies = cookie_list.toOwnedSlice(allocator) catch return error.OutOfMemory;

    return .{
        .status = status,
        .location = location,
        .set_cookies = owned_cookies,
        .body = body,
        .allocator = allocator,
        .owned_cookies = owned_cookies,
    };
}

fn resolveUrl(allocator: Allocator, base: []const u8, loc: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, loc, "http://") or std.mem.startsWith(u8, loc, "https://")) {
        return try allocator.dupe(u8, loc);
    }
    if (std.mem.startsWith(u8, loc, "/")) {
        const scheme_end = std.mem.indexOf(u8, base, "://") orelse return error.InvalidUri;
        const after = base[scheme_end + 3 ..];
        const path_start = std.mem.indexOfScalar(u8, after, '/') orelse after.len;
        const origin = base[0 .. scheme_end + 3 + path_start];
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ origin, loc });
    }
    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, loc });
}

pub fn getBody(
    client: *std.http.Client,
    allocator: Allocator,
    url: []const u8,
    options: GetOptions,
) HttpError![]u8 {
    var opts = options;
    if (opts.max_redirects == 0) opts.max_redirects = 5;
    var resp = try get(client, allocator, url, opts);
    defer resp.deinit();
    if (resp.status == 429) return error.RateLimited;
    if (resp.status < 200 or resp.status >= 300) return error.HttpStatus;
    return try allocator.dupe(u8, resp.body);
}

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
        } else {
            try list.append(allocator, '%');
            const hex = "0123456789ABCDEF";
            try list.append(allocator, hex[c >> 4]);
            try list.append(allocator, hex[c & 0xf]);
        }
    }
    return list.toOwnedSlice(allocator);
}
