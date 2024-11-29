const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");

pub fn getScene() engine.Scene {
    return engine.Scene{
        .name = "empty",
        // uses defaults
    };
}
