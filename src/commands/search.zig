const std = @import("std");
const config = @import("../config.zig");
const args_mod = @import("../args.zig");
const asset_mod = @import("../asset.zig");
const registry = @import("../providers/registry.zig");
const aura = @import("../providers/aura.zig");
const unsplash = @import("../providers/unsplash.zig");
const isorepublic = @import("../providers/isorepublic.zig");
const picjumbo = @import("../providers/picjumbo.zig");
const foodiesfeed = @import("../providers/foodiesfeed.zig");
const picography = @import("../providers/picography.zig");
const gratisography = @import("../providers/gratisography.zig");
const startupstockphotos = @import("../providers/startupstockphotos.zig");
const burst = @import("../providers/burst.zig");
const jaymantri = @import("../providers/jaymantri.zig");
const publicdomainarchive = @import("../providers/publicdomainarchive.zig");
const magdeleine = @import("../providers/magdeleine.zig");
const splitshire = @import("../providers/splitshire.zig");
const deviantart = @import("../providers/deviantart.zig");
const negativespace = @import("../providers/negativespace.zig");
const skitterphoto = @import("../providers/skitterphoto.zig");
const libreshot = @import("../providers/libreshot.zig");
const moveast = @import("../providers/moveast.zig");
const cupcake = @import("../providers/cupcake.zig");
const freenaturestock = @import("../providers/freenaturestock.zig");
const goodfreephotos = @import("../providers/goodfreephotos.zig");
const stdio = @import("../stdio.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Asset = asset_mod.Asset;
const SearchResult = asset_mod.SearchResult;

pub const ExitCode = enum(u8) {
    success = 0,
    usage = 1,
    network = 2,
    not_found = 3,
    rate_limited = 4,
};

fn doSearch(
    client: *std.http.Client,
    allocator: Allocator,
    provider_id: []const u8,
    query: []const u8,
    limit: u32,
) !SearchResult {
    if (std.ascii.eqlIgnoreCase(provider_id, "aura")) {
        return aura.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "unsplash")) {
        return unsplash.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "isorepublic")) {
        return isorepublic.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "picjumbo")) {
        return picjumbo.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "foodiesfeed")) {
        return foodiesfeed.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "picography")) {
        return picography.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "gratisography")) {
        return gratisography.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "startupstockphotos")) {
        return startupstockphotos.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "burst")) {
        return burst.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "jaymantri")) {
        return jaymantri.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "publicdomainarchive")) {
        return publicdomainarchive.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "magdeleine")) {
        return magdeleine.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "splitshire")) {
        return splitshire.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "deviantart")) {
        return deviantart.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "negativespace")) {
        return negativespace.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "skitterphoto")) {
        return skitterphoto.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "libreshot")) {
        return libreshot.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "moveast")) {
        return moveast.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "cupcake")) {
        return cupcake.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "freenaturestock")) {
        return freenaturestock.search(client, allocator, query, limit);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "goodfreephotos")) {
        return goodfreephotos.search(client, allocator, query, limit);
    }
    return error.UnknownProvider;
}

fn doDownload(
    client: *std.http.Client,
    allocator: Allocator,
    io: Io,
    provider_id: []const u8,
    a: Asset,
    output_dir: []const u8,
) !@import("../download.zig").Saved {
    if (std.ascii.eqlIgnoreCase(provider_id, "aura")) {
        return aura.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "unsplash")) {
        return unsplash.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "isorepublic")) {
        return isorepublic.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "picjumbo")) {
        return picjumbo.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "foodiesfeed")) {
        return foodiesfeed.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "picography")) {
        return picography.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "gratisography")) {
        return gratisography.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "startupstockphotos")) {
        return startupstockphotos.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "burst")) {
        return burst.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "jaymantri")) {
        return jaymantri.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "publicdomainarchive")) {
        return publicdomainarchive.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "magdeleine")) {
        return magdeleine.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "splitshire")) {
        return splitshire.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "deviantart")) {
        return deviantart.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "negativespace")) {
        return negativespace.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "skitterphoto")) {
        return skitterphoto.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "libreshot")) {
        return libreshot.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "moveast")) {
        return moveast.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "cupcake")) {
        return cupcake.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "freenaturestock")) {
        return freenaturestock.download(client, allocator, io, a, output_dir);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "goodfreephotos")) {
        return goodfreephotos.download(client, allocator, io, a, output_dir);
    }
    return error.UnknownProvider;
}

fn doPrompt(provider_id: []const u8, a: Asset) ?[]const u8 {
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
    if (std.ascii.eqlIgnoreCase(provider_id, "deviantart")) return deviantart.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "negativespace")) return negativespace.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "skitterphoto")) return skitterphoto.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "libreshot")) return libreshot.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "moveast")) return moveast.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "cupcake")) return cupcake.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "freenaturestock")) return freenaturestock.getPrompt(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "goodfreephotos")) return goodfreephotos.getPrompt(a);
    return a.prompt orelse a.description;
}

fn doUrl(provider_id: []const u8, a: Asset) ?[]const u8 {
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
    if (std.ascii.eqlIgnoreCase(provider_id, "deviantart")) return deviantart.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "negativespace")) return negativespace.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "skitterphoto")) return skitterphoto.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "libreshot")) return libreshot.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "moveast")) return moveast.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "cupcake")) return cupcake.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "freenaturestock")) return freenaturestock.getUrl(a);
    if (std.ascii.eqlIgnoreCase(provider_id, "goodfreephotos")) return goodfreephotos.getUrl(a);
    return a.image_url;
}

pub fn run(
    client: *std.http.Client,
    allocator: Allocator,
    io: Io,
    parsed: *const args_mod.Parsed,
) !ExitCode {
    const inv = args_mod.resolveSearchAlloc(allocator, parsed) catch |err| {
        switch (err) {
            error.MissingProvider => stdio.printErr("error: missing provider. Usage: {s} s <provider> \"<query>\"\n", .{config.app_name}),
            error.MissingQuery => stdio.printErr("error: missing search query\n", .{}),
            else => stdio.printErr("error: invalid search invocation\n", .{}),
        }
        return .usage;
    };
    defer allocator.free(inv.query);

    if (!registry.known(inv.provider_id)) {
        stdio.printErr("error: unknown provider \"{s}\". Available: {s}\n", .{ inv.provider_id, registry.availableIds() });
        return .usage;
    }

    const flags = inv.flags;
    const limit: u32 = if (flags.first) 1 else flags.limit;
    const display = registry.displayName(inv.provider_id) orelse inv.provider_id;

    if (!flags.quiet) {
        stdio.printErr("Searching {s} for \"{s}\"…\n", .{ display, inv.query });
    }

    var result = doSearch(client, allocator, inv.provider_id, inv.query, limit) catch |err| {
        switch (err) {
            error.RateLimited => {
                stdio.printErr("error: rate limited by provider\n", .{});
                return .rate_limited;
            },
            error.HttpStatus => {
                stdio.printErr("error: API returned an error status (or bot check failed)\n", .{});
                return .network;
            },
            error.Network => {
                stdio.printErr("error: network request failed\n", .{});
                return .network;
            },
            error.EmptyQuery => {
                stdio.printErr("error: empty query\n", .{});
                return .usage;
            },
            else => {
                stdio.printErr("error: search failed: {s}\n", .{@errorName(err)});
                return .network;
            },
        }
    };
    defer result.deinit();

    var assets = result.assets;
    if (flags.first and assets.len > 1) {
        assets = assets[0..1];
    }

    if (assets.len == 0) {
        if (flags.json) {
            if (flags.first) {
                stdio.writeOut("null\n");
            } else {
                stdio.printOut("{{\"query\":\"{s}\",\"provider\":\"{s}\",\"total\":0,\"count\":0,\"assets\":[]}}\n", .{ inv.query, inv.provider_id });
            }
            return .success;
        }
        if (flags.prompt or flags.url or flags.download or flags.first) {
            stdio.printErr("error: no results for \"{s}\"\n", .{inv.query});
            return .not_found;
        }
        stdio.writeOut("No results found.\n");
        return .success;
    }

    if (flags.download) {
        for (assets) |a| {
            if (!flags.quiet) stdio.printErr("Downloading {s}…\n", .{a.id});
            var saved = doDownload(client, allocator, io, inv.provider_id, a, flags.output) catch |err| {
                stdio.printErr("error: download failed: {s}\n", .{@errorName(err)});
                return .network;
            };
            defer saved.deinit();
            if (!flags.quiet) {
                stdio.printErr("✓ Saved {s} → {s}\n", .{ saved.filename, saved.path });
            }
            if (flags.first and !flags.json and !flags.prompt and !flags.url) {
                stdio.printOut("{s}\n", .{saved.path});
                return .success;
            }
        }
    }

    if (flags.json) {
        if (flags.first) {
            var aw: Io.Writer.Allocating = .init(allocator);
            defer aw.deinit();
            try asset_mod.writeJson(assets[0], &aw.writer);
            stdio.writeOut(aw.written());
            stdio.writeOut("\n");
        } else {
            var aw: Io.Writer.Allocating = .init(allocator);
            defer aw.deinit();
            try aw.writer.writeAll("{\n  \"query\": ");
            try writeStr(&aw.writer, inv.query);
            try aw.writer.print(",\n  \"provider\": \"{s}\",\n  \"total\": {d},\n  \"count\": {d},\n  \"assets\": [\n", .{
                inv.provider_id,
                result.total orelse assets.len,
                assets.len,
            });
            for (assets, 0..) |a, i| {
                if (i > 0) try aw.writer.writeAll(",\n");
                try asset_mod.writeJson(a, &aw.writer);
            }
            try aw.writer.writeAll("\n  ]\n}\n");
            stdio.writeOut(aw.written());
        }
        return .success;
    }

    if (flags.prompt) {
        for (assets) |a| {
            const p = doPrompt(inv.provider_id, a) orelse "";
            stdio.printOut("{s}\n", .{p});
        }
        return .success;
    }

    if (flags.url) {
        for (assets) |a| {
            if (doUrl(inv.provider_id, a)) |u| stdio.printOut("{s}\n", .{u});
        }
        return .success;
    }

    for (assets, 0..) |a, i| {
        stdio.printOut("{d: >2}. {s}\n", .{ i + 1, a.description });
    }
    if (!flags.quiet) {
        stdio.printErr("\n{d} shown\n", .{assets.len});
    }
    return .success;
}

fn writeStr(w: *Io.Writer, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            else => try w.writeByte(c),
        }
    }
    try w.writeByte('"');
}
