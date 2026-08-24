//! Provider registry — resolve by id.

const std = @import("std");
const aura = @import("aura.zig");
const unsplash = @import("unsplash.zig");
const pexels = @import("pexels.zig");
const isorepublic = @import("isorepublic.zig");
const kaboompics = @import("kaboompics.zig");
const picjumbo = @import("picjumbo.zig");
const foodiesfeed = @import("foodiesfeed.zig");

pub const ProviderInfo = struct {
    id: []const u8,
    name: []const u8,
};

pub fn list() []const ProviderInfo {
    return &[_]ProviderInfo{
        .{ .id = aura.id, .name = aura.name },
        .{ .id = unsplash.id, .name = unsplash.name },
        .{ .id = pexels.id, .name = pexels.name },
        .{ .id = isorepublic.id, .name = isorepublic.name },
        .{ .id = kaboompics.id, .name = kaboompics.name },
        .{ .id = picjumbo.id, .name = picjumbo.name },
        .{ .id = foodiesfeed.id, .name = foodiesfeed.name },
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
    return "aura, unsplash, pexels, isorepublic, kaboompics, picjumbo, foodiesfeed";
}
