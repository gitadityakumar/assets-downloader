//! Provider registry — resolve by id.

const std = @import("std");
const aura = @import("aura.zig");
const unsplash = @import("unsplash.zig");
const isorepublic = @import("isorepublic.zig");
const picjumbo = @import("picjumbo.zig");
const foodiesfeed = @import("foodiesfeed.zig");
const picography = @import("picography.zig");
const gratisography = @import("gratisography.zig");
const startupstockphotos = @import("startupstockphotos.zig");
const burst = @import("burst.zig");
const jaymantri = @import("jaymantri.zig");
const publicdomainarchive = @import("publicdomainarchive.zig");
const magdeleine = @import("magdeleine.zig");
const splitshire = @import("splitshire.zig");
const deviantart = @import("deviantart.zig");
const negativespace = @import("negativespace.zig");
const skitterphoto = @import("skitterphoto.zig");
const libreshot = @import("libreshot.zig");
const moveast = @import("moveast.zig");
const cupcake = @import("cupcake.zig");
const freenaturestock = @import("freenaturestock.zig");
const goodfreephotos = @import("goodfreephotos.zig");
const wikimedia = @import("wikimedia.zig");
const vecteezy = @import("vecteezy.zig");

pub const ProviderInfo = struct {
    id: []const u8,
    name: []const u8,
};

pub fn list() []const ProviderInfo {
    return &[_]ProviderInfo{
        .{ .id = aura.id, .name = aura.name },
        .{ .id = unsplash.id, .name = unsplash.name },
        .{ .id = isorepublic.id, .name = isorepublic.name },
        .{ .id = picjumbo.id, .name = picjumbo.name },
        .{ .id = foodiesfeed.id, .name = foodiesfeed.name },
        .{ .id = picography.id, .name = picography.name },
        .{ .id = gratisography.id, .name = gratisography.name },
        .{ .id = startupstockphotos.id, .name = startupstockphotos.name },
        .{ .id = burst.id, .name = burst.name },
        .{ .id = jaymantri.id, .name = jaymantri.name },
        .{ .id = publicdomainarchive.id, .name = publicdomainarchive.name },
        .{ .id = magdeleine.id, .name = magdeleine.name },
        .{ .id = splitshire.id, .name = splitshire.name },
        .{ .id = deviantart.id, .name = deviantart.name },
        .{ .id = negativespace.id, .name = negativespace.name },
        .{ .id = skitterphoto.id, .name = skitterphoto.name },
        .{ .id = libreshot.id, .name = libreshot.name },
        .{ .id = moveast.id, .name = moveast.name },
        .{ .id = cupcake.id, .name = cupcake.name },
        .{ .id = freenaturestock.id, .name = freenaturestock.name },
        .{ .id = goodfreephotos.id, .name = goodfreephotos.name },
        .{ .id = wikimedia.id, .name = wikimedia.name },
        .{ .id = vecteezy.id, .name = vecteezy.name },
    };
}

pub fn known(id: []const u8) bool {
    for (list()) |p| {
        if (std.ascii.eqlIgnoreCase(p.id, id)) return true;
    }
    return false;
}

pub fn displayName(id: []const u8) ?[]const u8 {
    for (list()) |p| {
        if (std.ascii.eqlIgnoreCase(p.id, id)) return p.name;
    }
    return null;
}

pub fn availableIds() []const u8 {
    return "aura, unsplash, isorepublic, picjumbo, foodiesfeed, picography, gratisography, startupstockphotos, burst, jaymantri, publicdomainarchive, magdeleine, splitshire, deviantart, negativespace, skitterphoto, libreshot, moveast, cupcake, freenaturestock, goodfreephotos, wikimedia, vecteezy";
}
