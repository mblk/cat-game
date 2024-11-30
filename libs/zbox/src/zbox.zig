const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

const options = @import("box2d_options");

pub const API = @cImport({
    @cInclude("box2d.h");
});

pub fn init() void {
    std.log.info("hello box2d", .{});

    // TODO overwrite allocator?

    const version = b2GetVersion();

    std.log.info("b2 version {d}.{d}.{d}", .{ version.major, version.minor, version.revision });

    const v2 = API.b2GetVersion();

    std.log.info("b2 version {d}.{d}.{d}", .{ v2.major, v2.minor, v2.revision });
}

extern fn b2GetVersion() b2Version;

pub const b2Version = extern struct {
    major: c_int,
    minor: c_int,
    revision: c_int,
};
