//! POSIX-style argument parser with combined short flags.
//! Supports: -s, -sjl 5, -fdo ./out, etc.

const std = @import("std");
const config = @import("config.zig");
const Allocator = std.mem.Allocator;

pub const Flags = struct {
    search: bool = false,
    limit: u32 = config.default_limit,
    json: bool = false,
    first: bool = false,
    download: bool = false,
    prompt: bool = false,
    url: bool = false,
    quiet: bool = false,
    help: bool = false,
    version: bool = false,
    output: []const u8 = config.default_output_dir,
    provider: ?[]const u8 = null,
};

pub const Parsed = struct {
    command: ?[]const u8 = null,
    positionals: []const []const u8 = &.{},
    flags: Flags = .{},
    /// Owned slices that must be freed (output path if allocated, etc.)
    owned_output: ?[]u8 = null,
    owned_provider: ?[]u8 = null,
    owned_positionals: ?[][]const u8 = null,
    allocator: Allocator,

    pub fn deinit(self: *Parsed) void {
        if (self.owned_output) |o| self.allocator.free(o);
        if (self.owned_provider) |p| self.allocator.free(p);
        if (self.owned_positionals) |ps| {
            for (ps) |p| self.allocator.free(p);
            self.allocator.free(ps);
        }
        self.* = undefined;
    }
};

pub const ParseError = error{
    UnknownOption,
    MissingValue,
    InvalidNumber,
    ConflictingCommand,
    OutOfMemory,
};

pub fn parse(allocator: Allocator, argv: []const []const u8) ParseError!Parsed {
    var flags: Flags = .{};
    var command: ?[]const u8 = null;
    var positionals: std.ArrayList([]const u8) = .empty;
    defer positionals.deinit(allocator);

    var owned_output: ?[]u8 = null;
    errdefer if (owned_output) |o| allocator.free(o);
    var owned_provider: ?[]u8 = null;
    errdefer if (owned_provider) |p| allocator.free(p);

    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const token = argv[i];

        if (std.mem.eql(u8, token, "--")) {
            i += 1;
            while (i < argv.len) : (i += 1) {
                try positionals.append(allocator, argv[i]);
            }
            break;
        }

        if (std.mem.startsWith(u8, token, "--")) {
            const body = token[2..];
            var name: []const u8 = body;
            var inline_value: ?[]const u8 = null;
            if (std.mem.indexOfScalar(u8, body, '=')) |eq| {
                name = body[0..eq];
                inline_value = body[eq + 1 ..];
            }
            try applyLong(allocator, &flags, &owned_output, &owned_provider, name, inline_value, argv, &i);
            continue;
        }

        if (token.len > 1 and token[0] == '-' and !isNumericToken(token)) {
            const cluster = token[1..];
            var c: usize = 0;
            while (c < cluster.len) {
                const ch = cluster[c];
                const long = shortToLong(ch) orelse return error.UnknownOption;
                if (isBooleanFlag(long)) {
                    try setBool(&flags, long, true);
                    c += 1;
                    continue;
                }
                // value-taking: rest of cluster or next argv
                const rest = cluster[c + 1 ..];
                var value: []const u8 = undefined;
                if (rest.len > 0) {
                    value = rest;
                    c = cluster.len;
                } else {
                    i += 1;
                    if (i >= argv.len or (std.mem.startsWith(u8, argv[i], "-") and !isNumericToken(argv[i]))) {
                        return error.MissingValue;
                    }
                    value = argv[i];
                    c = cluster.len;
                }
                try setValue(allocator, &flags, &owned_output, &owned_provider, long, value);
            }
            continue;
        }

        // positional
        if (command == null and positionals.items.len == 0) {
            if (flags.search) {
                try positionals.append(allocator, token);
            } else {
                command = token;
            }
            continue;
        }
        try positionals.append(allocator, token);
    }

    if (flags.search) {
        if (command) |cmd| {
            if (!std.mem.eql(u8, cmd, "s") and !std.mem.eql(u8, cmd, "search")) {
                return error.ConflictingCommand;
            }
        }
        command = "s";
    }
    if (command) |cmd| {
        if (std.mem.eql(u8, cmd, "search")) command = "s";
    }

    if (flags.limit < 1) return error.InvalidNumber;

    // Own positionals so Parsed outlives argv iterator buffers if needed
    var owned_pos: ?[][]const u8 = null;
    if (positionals.items.len > 0) {
        var arr = try allocator.alloc([]const u8, positionals.items.len);
        errdefer allocator.free(arr);
        for (positionals.items, 0..) |p, idx| {
            arr[idx] = try allocator.dupe(u8, p);
        }
        owned_pos = arr;
    }

    return .{
        .command = command,
        .positionals = if (owned_pos) |op| op else &.{},
        .flags = flags,
        .owned_output = owned_output,
        .owned_provider = owned_provider,
        .owned_positionals = owned_pos,
        .allocator = allocator,
    };
}

/// Caller owns `query` and must free it with `allocator`.
pub fn resolveSearchAlloc(allocator: Allocator, parsed: *const Parsed) !struct {
    provider_id: []const u8,
    query: []u8,
    flags: Flags,
} {
    const flags = parsed.flags;
    var provider_id: ?[]const u8 = flags.provider;
    const start: usize = if (provider_id != null) 0 else blk: {
        if (parsed.positionals.len < 1) return error.MissingProvider;
        provider_id = parsed.positionals[0];
        break :blk 1;
    };
    if (parsed.positionals.len <= start) return error.MissingQuery;

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    for (parsed.positionals[start..], 0..) |part, idx| {
        if (idx > 0) try list.append(allocator, ' ');
        try list.appendSlice(allocator, part);
    }
    const query = try list.toOwnedSlice(allocator);
    return .{
        .provider_id = provider_id.?,
        .query = query,
        .flags = flags,
    };
}

fn shortToLong(ch: u8) ?[]const u8 {
    return switch (ch) {
        's' => "search",
        'l' => "limit",
        'j' => "json",
        'f' => "first",
        'd' => "download",
        'p' => "prompt",
        'u' => "url",
        'o' => "output",
        'q' => "quiet",
        'P' => "provider",
        'h' => "help",
        'v' => "version",
        else => null,
    };
}

fn isBooleanFlag(name: []const u8) bool {
    return std.mem.eql(u8, name, "search") or
        std.mem.eql(u8, name, "json") or
        std.mem.eql(u8, name, "first") or
        std.mem.eql(u8, name, "download") or
        std.mem.eql(u8, name, "prompt") or
        std.mem.eql(u8, name, "url") or
        std.mem.eql(u8, name, "quiet") or
        std.mem.eql(u8, name, "help") or
        std.mem.eql(u8, name, "version");
}

fn setBool(flags: *Flags, name: []const u8, value: bool) !void {
    if (std.mem.eql(u8, name, "search")) flags.search = value
    else if (std.mem.eql(u8, name, "json")) flags.json = value
    else if (std.mem.eql(u8, name, "first")) flags.first = value
    else if (std.mem.eql(u8, name, "download")) flags.download = value
    else if (std.mem.eql(u8, name, "prompt")) flags.prompt = value
    else if (std.mem.eql(u8, name, "url")) flags.url = value
    else if (std.mem.eql(u8, name, "quiet")) flags.quiet = value
    else if (std.mem.eql(u8, name, "help")) flags.help = value
    else if (std.mem.eql(u8, name, "version")) flags.version = value
    else return error.UnknownOption;
}

fn setValue(
    allocator: Allocator,
    flags: *Flags,
    owned_output: *?[]u8,
    owned_provider: *?[]u8,
    name: []const u8,
    value: []const u8,
) !void {
    if (std.mem.eql(u8, name, "limit")) {
        flags.limit = std.fmt.parseInt(u32, value, 10) catch return error.InvalidNumber;
    } else if (std.mem.eql(u8, name, "output")) {
        if (owned_output.*) |old| allocator.free(old);
        owned_output.* = try allocator.dupe(u8, value);
        flags.output = owned_output.*.?;
    } else if (std.mem.eql(u8, name, "provider")) {
        if (owned_provider.*) |old| allocator.free(old);
        owned_provider.* = try allocator.dupe(u8, value);
        flags.provider = owned_provider.*.?;
    } else return error.UnknownOption;
}

fn applyLong(
    allocator: Allocator,
    flags: *Flags,
    owned_output: *?[]u8,
    owned_provider: *?[]u8,
    name: []const u8,
    inline_value: ?[]const u8,
    argv: []const []const u8,
    i: *usize,
) !void {
    if (isBooleanFlag(name)) {
        if (inline_value) |v| {
            const b = parseBool(v) orelse return error.InvalidNumber;
            try setBool(flags, name, b);
        } else {
            try setBool(flags, name, true);
        }
        return;
    }
    const value = inline_value orelse blk: {
        i.* += 1;
        if (i.* >= argv.len or std.mem.startsWith(u8, argv[i.*], "-")) return error.MissingValue;
        break :blk argv[i.*];
    };
    try setValue(allocator, flags, owned_output, owned_provider, name, value);
}

fn parseBool(v: []const u8) ?bool {
    if (std.mem.eql(u8, v, "1") or std.mem.eql(u8, v, "true") or std.mem.eql(u8, v, "yes") or std.mem.eql(u8, v, "on")) return true;
    if (std.mem.eql(u8, v, "0") or std.mem.eql(u8, v, "false") or std.mem.eql(u8, v, "no") or std.mem.eql(u8, v, "off")) return false;
    return null;
}

fn isNumericToken(token: []const u8) bool {
    if (token.len == 0) return false;
    var start: usize = 0;
    if (token[0] == '-') start = 1;
    if (start >= token.len) return false;
    for (token[start..]) |c| {
        if (c < '0' or c > '9') return false;
    }
    return true;
}

test "parse -sjl 3" {
    const a = std.testing.allocator;
    const argv = [_][]const u8{ "-sjl", "3", "aura", "fox" };
    var p = try parse(a, &argv);
    defer p.deinit();
    try std.testing.expect(p.flags.search);
    try std.testing.expect(p.flags.json);
    try std.testing.expectEqual(@as(u32, 3), p.flags.limit);
    try std.testing.expectEqualStrings("s", p.command.?);
    try std.testing.expectEqualStrings("aura", p.positionals[0]);
}
