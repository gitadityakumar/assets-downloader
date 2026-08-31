//! Keyboard-driven interactive mode.

const std = @import("std");
const config = @import("config.zig");
const asset_mod = @import("asset.zig");
const aura = @import("providers/aura.zig");
const unsplash = @import("providers/unsplash.zig");
const isorepublic = @import("providers/isorepublic.zig");
const picjumbo = @import("providers/picjumbo.zig");
const foodiesfeed = @import("providers/foodiesfeed.zig");
const picography = @import("providers/picography.zig");
const gratisography = @import("providers/gratisography.zig");
const startupstockphotos = @import("providers/startupstockphotos.zig");
const burst = @import("providers/burst.zig");
const jaymantri = @import("providers/jaymantri.zig");
const publicdomainarchive = @import("providers/publicdomainarchive.zig");
const magdeleine = @import("providers/magdeleine.zig");
const splitshire = @import("providers/splitshire.zig");
const registry = @import("providers/registry.zig");
const stdio = @import("stdio.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

fn waitEnter(allocator: Allocator) void {
    const line = stdio.readLine(allocator, "Press Enter to continue…") catch return;
    if (line) |l| allocator.free(l);
}

fn searchProvider(
    client: *std.http.Client,
    allocator: Allocator,
    provider_id: []const u8,
    query: []const u8,
) !SearchResult {
    if (std.ascii.eqlIgnoreCase(provider_id, "aura")) {
        return aura.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "unsplash")) {
        return unsplash.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "isorepublic")) {
        return isorepublic.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "picjumbo")) {
        return picjumbo.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "foodiesfeed")) {
        return foodiesfeed.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "picography")) {
        return picography.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "gratisography")) {
        return gratisography.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "startupstockphotos")) {
        return startupstockphotos.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "burst")) {
        return burst.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "jaymantri")) {
        return jaymantri.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "publicdomainarchive")) {
        return publicdomainarchive.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "magdeleine")) {
        return magdeleine.search(client, allocator, query, config.default_limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "splitshire")) {
        return splitshire.search(client, allocator, query, config.default_limit);
    }
    return error.UnknownProvider;
}

fn downloadAsset(
    client: *std.http.Client,
    allocator: Allocator,
    io: Io,
    provider_id: []const u8,
    a: Asset,
) !@import("download.zig").Saved {
    if (std.ascii.eqlIgnoreCase(provider_id, "aura")) {
        return aura.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "unsplash")) {
        return unsplash.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "isorepublic")) {
        return isorepublic.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "picjumbo")) {
        return picjumbo.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "foodiesfeed")) {
        return foodiesfeed.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "picography")) {
        return picography.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "gratisography")) {
        return gratisography.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "startupstockphotos")) {
        return startupstockphotos.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "burst")) {
        return burst.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "jaymantri")) {
        return jaymantri.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "publicdomainarchive")) {
        return publicdomainarchive.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "magdeleine")) {
        return magdeleine.download(client, allocator, io, a, config.default_output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "splitshire")) {
        return splitshire.download(client, allocator, io, a, config.default_output_dir);
    }
    return error.UnknownProvider;
}

fn promptOf(provider_id: []const u8, a: Asset) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(provider_id, "aura")) return aura.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "unsplash")) return unsplash.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "isorepublic")) return isorepublic.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "picjumbo")) return picjumbo.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "foodiesfeed")) return foodiesfeed.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "picography")) return picography.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "gratisography")) return gratisography.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "startupstockphotos")) return startupstockphotos.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "burst")) return burst.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "jaymantri")) return jaymantri.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "publicdomainarchive")) return publicdomainarchive.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "magdeleine")) return magdeleine.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "splitshire")) return splitshire.getPrompt(a);
    return a.prompt;
}

fn urlOf(provider_id: []const u8, a: Asset) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(provider_id, "aura")) return aura.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "unsplash")) return unsplash.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "isorepublic")) return isorepublic.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "picjumbo")) return picjumbo.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "foodiesfeed")) return foodiesfeed.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "picography")) return picography.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "gratisography")) return gratisography.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "startupstockphotos")) return startupstockphotos.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "burst")) return burst.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "jaymantri")) return jaymantri.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "publicdomainarchive")) return publicdomainarchive.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "magdeleine")) return magdeleine.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "splitshire")) return splitshire.getUrl(a);
    return a.image_url;
}

pub fn run(client: *std.http.Client, allocator: Allocator, io: Io) !void {
    stdio.printOut("{s} {s}\n", .{ config.app_name, config.version });
    stdio.writeOut("Interactive asset downloader. Keyboard only.\n");
    stdio.writeOut("Tip: Ctrl+C to abort.\n\n");

    const providers = registry.list();
    if (providers.len == 0) {
        stdio.writeErr("No providers registered.\n");
        return;
    }

    // Provider menu
    stdio.writeOut("Select a provider:\n\n");
    for (providers, 0..) |p, i| {
        stdio.printOut("{d: >2}. {s} ({s})\n", .{ i + 1, p.name, p.id });
    }
    stdio.writeOut("\n");

    // readLine does not format — build the prompt first
    const pick_prompt = try std.fmt.allocPrint(allocator, "Select [1-{d}]: ", .{providers.len});
    defer allocator.free(pick_prompt);
    const pick = try stdio.readLine(allocator, pick_prompt);
    defer if (pick) |p| allocator.free(p);
    if (pick == null) {
        stdio.writeOut("Goodbye.\n");
        return;
    }
    const pick_s = std.mem.trim(u8, pick.?, " \t");
    const pi = std.fmt.parseInt(usize, pick_s, 10) catch {
        stdio.writeOut("Invalid choice.\n");
        return;
    };
    if (pi < 1 or pi > providers.len) {
        stdio.writeOut("Invalid choice.\n");
        return;
    }
    const provider = providers[pi - 1];
    stdio.printOut("Provider: {s} ({s})\n", .{ provider.name, provider.id });

    while (true) {
        stdio.printOut("\n── {s} search ──────────────────────────────\n", .{provider.name});
        const query_owned = try stdio.readLine(allocator, "Search query: ");
        defer if (query_owned) |q| allocator.free(q);
        if (query_owned == null) {
            stdio.writeOut("Goodbye.\n");
            return;
        }
        const query = std.mem.trim(u8, query_owned.?, " \t");

        if (query.len == 0) {
            stdio.writeOut("Empty query. Try again or type q to quit.\n");
            continue;
        }
        if (std.ascii.eqlIgnoreCase(query, "q") or std.ascii.eqlIgnoreCase(query, "quit")) {
            stdio.writeOut("Goodbye.\n");
            return;
        }

        stdio.printOut("\nSearching {s} for \"{s}\"…\n", .{ provider.name, query });

        var result = searchProvider(client, allocator, provider.id, query) catch |e| {
            stdio.printErr("Search failed: {s}\n", .{@errorName(e)});
            continue;
        };
        defer result.deinit();

        if (result.assets.len == 0) {
            stdio.writeOut("No results found.\n");
            continue;
        }

        stdio.printOut("Found {d} result(s).\n", .{result.assets.len});

        const flow = try resultsLoop(client, allocator, io, provider.id, result.assets, query);
        if (flow == .exit) {
            stdio.writeOut("Goodbye.\n");
            return;
        }
    }
}

const Flow = enum { search, exit };

fn resultsLoop(
    client: *std.http.Client,
    allocator: Allocator,
    io: Io,
    provider_id: []const u8,
    assets: []Asset,
    query: []const u8,
) !Flow {
    while (true) {
        stdio.printOut("\n── Results for \"{s}\" ──────────────────────\n\n", .{query});
        stdio.writeOut("Select an asset:\n\n");
        for (assets, 0..) |a, i| {
            stdio.printOut("{d: >2}. {s}\n", .{ i + 1, a.description });
        }
        stdio.writeOut("\nS  search again    Q  quit\n");

        const prompt = try std.fmt.allocPrint(allocator, "Select [1-{d}] or S/Q: ", .{assets.len});
        defer allocator.free(prompt);
        const raw = try stdio.readLine(allocator, prompt);
        defer if (raw) |r| allocator.free(r);
        const choice = std.mem.trim(u8, raw orelse "", " \t");
        if (choice.len == 0) continue;

        if (std.ascii.eqlIgnoreCase(choice, "q") or std.ascii.eqlIgnoreCase(choice, "quit")) return .exit;
        if (std.ascii.eqlIgnoreCase(choice, "s")) return .search;

        const n = std.fmt.parseInt(usize, choice, 10) catch {
            stdio.writeOut("Invalid choice.\n");
            continue;
        };
        if (n < 1 or n > assets.len) {
            stdio.writeOut("Invalid choice.\n");
            continue;
        }

        const action = try assetMenu(client, allocator, io, provider_id, assets[n - 1]);
        switch (action) {
            .back => {},
            .search => return .search,
            .exit => return .exit,
        }
    }
}

const Action = enum { back, search, exit };

fn assetMenu(
    client: *std.http.Client,
    allocator: Allocator,
    io: Io,
    provider_id: []const u8,
    a: Asset,
) !Action {
    while (true) {
        stdio.printOut("\n── {s} ──\n\n", .{a.description});
        stdio.writeOut("Actions:\n\n");
        stdio.writeOut(" 1. Download Image\n");
        stdio.writeOut(" 2. View Prompt\n");
        stdio.writeOut(" 3. View Image URL\n");
        stdio.writeOut(" 4. Back\n");
        stdio.writeOut(" 5. Search Again\n");
        stdio.writeOut(" 6. Exit\n\n");
        stdio.writeOut("B  back    S  search again    Q  quit\n");

        const raw = try stdio.readLine(allocator, "Select [1-6] or B/S/Q: ");
        defer if (raw) |r| allocator.free(r);
        const choice = std.mem.trim(u8, raw orelse "", " \t");
        if (choice.len == 0) continue;

        if (std.ascii.eqlIgnoreCase(choice, "q")) return .exit;
        if (std.ascii.eqlIgnoreCase(choice, "s")) return .search;
        if (std.ascii.eqlIgnoreCase(choice, "b")) return .back;

        const n = std.fmt.parseInt(usize, choice, 10) catch {
            stdio.writeOut("Invalid choice.\n");
            continue;
        };

        switch (n) {
            1 => {
                stdio.writeOut("Downloading…\n");
                var saved = downloadAsset(client, allocator, io, provider_id, a) catch |e| {
                    stdio.printErr("Download failed: {s}\n", .{@errorName(e)});
                    waitEnter(allocator);
                    return .back;
                };
                defer saved.deinit();
                stdio.printOut("\n✓ Saved as {s}\n  {s}\n\n", .{ saved.filename, saved.path });
                waitEnter(allocator);
                return .back;
            },
            2 => {
                stdio.printOut("\n{s}\n\n", .{promptOf(provider_id, a) orelse "(No prompt available)"});
                waitEnter(allocator);
                return .back;
            },
            3 => {
                stdio.printOut("\n{s}\n\n", .{urlOf(provider_id, a) orelse "(No image URL available)"});
                waitEnter(allocator);
                return .back;
            },
            4 => return .back,
            5 => return .search,
            6 => return .exit,
            else => stdio.writeOut("Invalid choice.\n"),
        }
    }
}
