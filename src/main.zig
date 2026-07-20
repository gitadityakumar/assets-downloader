//! ast — Asset Downloader CLI (Zig rewrite)

const std = @import("std");
const config = @import("config.zig");
const args_mod = @import("args.zig");
const help_cmd = @import("commands/help.zig");
const search_cmd = @import("commands/search.zig");
const interactive = @import("interactive.zig");
const unsplash = @import("providers/unsplash.zig");
const stdio = @import("stdio.zig");

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;

    // Always free Unsplash cookie jar before process exit (DebugAllocator).
    defer unsplash.deinitGlobals();

    var arg_list: std.ArrayList([]const u8) = .empty;
    defer arg_list.deinit(gpa);

    var it = std.process.Args.Iterator.init(init.minimal.args);
    _ = it.next(); // program name
    while (it.next()) |a| {
        try arg_list.append(gpa, a);
    }

    var client: std.http.Client = .{
        .allocator = gpa,
        .io = io,
    };
    defer client.deinit();

    if (arg_list.items.len == 0) {
        try interactive.run(&client, gpa, io);
        return 0;
    }

    var parsed = args_mod.parse(gpa, arg_list.items) catch |err| {
        const msg = switch (err) {
            error.UnknownOption => "unknown option",
            error.MissingValue => "option requires a value",
            error.InvalidNumber => "invalid number",
            error.ConflictingCommand => "cannot combine -s with another command",
            error.OutOfMemory => "out of memory",
        };
        stdio.printErr("error: {s}\nTry '{s} --help' for usage.\n", .{ msg, config.app_name });
        return 1;
    };
    defer parsed.deinit();

    if (parsed.flags.help or (parsed.command != null and std.mem.eql(u8, parsed.command.?, "help"))) {
        help_cmd.printHelp(io);
        return 0;
    }
    if (parsed.flags.version or (parsed.command != null and std.mem.eql(u8, parsed.command.?, "version"))) {
        help_cmd.printVersion(io);
        return 0;
    }

    const command = parsed.command;
    if (command == null) {
        if (parsed.flags.provider != null) {
            stdio.printErr("error: missing search. Did you mean: {s} -s -P <provider> \"<query>\"?\n", .{config.app_name});
            return 1;
        }
        try interactive.run(&client, gpa, io);
        return 0;
    }

    if (std.mem.eql(u8, command.?, "s")) {
        const code = try search_cmd.run(&client, gpa, io, &parsed);
        return @intFromEnum(code);
    }

    stdio.printErr("error: unknown command \"{s}\". Try: {s} s | {s} help\n", .{ command.?, config.app_name, config.app_name });
    return 1;
}

test {
    _ = @import("args.zig");
}
