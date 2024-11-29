const std = @import("std");

pub const engine = @import("engine/engine.zig");
pub const world = @import("game/world.zig");

test {
    std.testing.refAllDecls(@This());
}
