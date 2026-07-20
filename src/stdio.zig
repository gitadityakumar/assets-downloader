//! Simple stdout/stderr printing + line input for Zig 0.16.

const std = @import("std");
const builtin = @import("builtin");

fn writeFd(fd: i32, bytes: []const u8) void {
    if (bytes.len == 0) return;
    switch (builtin.os.tag) {
        .linux => {
            var offset: usize = 0;
            while (offset < bytes.len) {
                const n = std.os.linux.write(@intCast(fd), bytes.ptr + offset, bytes.len - offset);
                const signed: isize = @bitCast(n);
                if (signed < 0) return;
                offset += @intCast(signed);
            }
        },
        else => {
            var offset: usize = 0;
            while (offset < bytes.len) {
                const n = std.c.write(fd, bytes.ptr + offset, bytes.len - offset);
                if (n < 0) return;
                offset += @intCast(n);
            }
        },
    }
}

fn readFd(fd: i32, buffer: []u8) !usize {
    switch (builtin.os.tag) {
        .linux => {
            const n = std.os.linux.read(@intCast(fd), buffer.ptr, buffer.len);
            const signed: isize = @bitCast(n);
            if (signed < 0) return error.ReadFailed;
            return @intCast(signed);
        },
        else => {
            const n = std.c.read(fd, buffer.ptr, buffer.len);
            if (n < 0) return error.ReadFailed;
            return @intCast(n);
        },
    }
}

pub fn printOut(comptime fmt: []const u8, args: anytype) void {
    var buf: [16384]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => buf[0..],
    };
    writeFd(1, msg);
}

pub fn printErr(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => buf[0..],
    };
    writeFd(2, msg);
}

pub fn writeOut(bytes: []const u8) void {
    writeFd(1, bytes);
}

pub fn writeErr(bytes: []const u8) void {
    writeFd(2, bytes);
}

/// Leftover stdin bytes from a previous read (so multi-line pipe input works).
var stdin_pending: [4096]u8 = undefined;
var stdin_pending_len: usize = 0;
var stdin_pending_off: usize = 0;
var stdin_eof: bool = false;

fn pendingAvailable() usize {
    return stdin_pending_len - stdin_pending_off;
}

fn pushPending(bytes: []const u8) void {
    // If too large, keep what fits after compacting
    if (stdin_pending_off > 0) {
        const avail = pendingAvailable();
        if (avail > 0) {
            std.mem.copyForwards(u8, stdin_pending[0..avail], stdin_pending[stdin_pending_off..][0..avail]);
        }
        stdin_pending_len = avail;
        stdin_pending_off = 0;
    }
    const space = stdin_pending.len - stdin_pending_len;
    const n = @min(space, bytes.len);
    @memcpy(stdin_pending[stdin_pending_len..][0..n], bytes[0..n]);
    stdin_pending_len += n;
}

fn popPendingByte() ?u8 {
    if (stdin_pending_off >= stdin_pending_len) return null;
    const b = stdin_pending[stdin_pending_off];
    stdin_pending_off += 1;
    if (stdin_pending_off == stdin_pending_len) {
        stdin_pending_off = 0;
        stdin_pending_len = 0;
    }
    return b;
}

/// Read one line from stdin. Returns:
/// - allocated line (without trailing `\n`) on success
/// - `null` on EOF
///
/// Preserves leftover bytes when a single OS read returns multiple lines
/// (important for piped interactive tests: `printf '2\ndog\n' | ast`).
pub fn readLine(allocator: std.mem.Allocator, prompt: []const u8) !?[]u8 {
    writeOut(prompt);
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    while (true) {
        // Drain pending first
        while (popPendingByte()) |b| {
            if (b == '\n') return try list.toOwnedSlice(allocator);
            if (b == '\r') continue;
            try list.append(allocator, b);
        }

        if (stdin_eof) {
            if (list.items.len == 0) {
                list.deinit(allocator);
                return null;
            }
            return try list.toOwnedSlice(allocator);
        }

        var buf: [512]u8 = undefined;
        const n = try readFd(0, &buf);
        if (n == 0) {
            stdin_eof = true;
            if (list.items.len == 0) {
                list.deinit(allocator);
                return null;
            }
            return try list.toOwnedSlice(allocator);
        }

        // Process this chunk; any remainder after first newline goes to pending
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (buf[i] == '\n') {
                // save rest of buffer for next readLine
                if (i + 1 < n) pushPending(buf[i + 1 .. n]);
                return try list.toOwnedSlice(allocator);
            }
            if (buf[i] == '\r') continue;
            try list.append(allocator, buf[i]);
        }
    }
}
