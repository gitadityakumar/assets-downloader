const std = @import("std");
const config = @import("../config.zig");
const registry = @import("../providers/registry.zig");
const stdio = @import("../stdio.zig");
const Io = std.Io;

pub fn printVersion(io: Io) void {
    _ = io;
    stdio.printOut("{s} {s}\n", .{ config.app_name, config.version });
}

pub fn printHelp(io: Io) void {
    _ = io;
    const providers = registry.list();

    stdio.printOut(
        \\{s} — multi-provider asset search & download CLI
        \\          (Asset Downloader; command is spelled "ast")
        \\
        \\USAGE
        \\  {s}                              Interactive mode
        \\  {s} s <provider> <query>         Search assets (scriptable)
        \\  {s} -s <provider> <query>        Same via -s / --search flag
        \\  {s} help                         Show this help
        \\  {s} version                      Show version
        \\
        \\EXAMPLES
        \\  {s} s aura "cyberpunk fox"
        \\  {s} -s aura "cyberpunk fox"
        \\  {s} s aura "cyberpunk fox" --limit 5
        \\  {s} s aura "cyberpunk fox" --json
        \\  {s} s aura "cyberpunk fox" --first --url
        \\  {s} s aura "cyberpunk fox" --first --download
        \\  {s} -sjl 3 aura "cat"
        \\  {s} -sfu aura "golden retriever"
        \\
        \\OPTIONS
        \\  -s, --search          Run search (alternative to subcommand s)
        \\  -l, --limit <n>       Number of results (default: {d})
        \\  -j, --json            Machine-readable JSON output
        \\  -f, --first           Only the highest-ranked result
        \\  -d, --download        Download result(s) to the output directory
        \\  -p, --prompt          Print generation prompt only
        \\  -u, --url             Print image URL only
        \\  -o, --output <dir>    Download directory (default: {s})
        \\  -q, --quiet           Suppress non-essential messages
        \\  -P, --provider <id>   Provider id
        \\  -h, --help            Show help
        \\  -v, --version         Show version
        \\
        \\PROVIDERS
        \\
    , .{
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.app_name,
        config.default_limit,
        config.default_output_dir,
    });

    for (providers) |p| {
        stdio.printOut("  {s: <12} {s}\n", .{ p.id, p.name });
    }

    stdio.writeOut(
        \\
        \\INTERACTIVE MODE
        \\  Launch with no arguments. Keyboard-driven menus.
        \\  From the result list: number + Enter · S search again · Q quit
        \\
        \\EXIT CODES
        \\  0  success
        \\  1  usage / validation error
        \\  2  network error
        \\  3  not found
        \\  4  rate limited
        \\
    );
}
