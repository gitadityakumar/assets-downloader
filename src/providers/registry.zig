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
    return "aura, unsplash, isorepublic, picjumbo, foodiesfeed, picography, gratisography, startupstockphotos, burst";
}
