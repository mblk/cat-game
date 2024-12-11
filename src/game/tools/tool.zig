const std = @import("std");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const World = @import("../world.zig").World;

pub const Tool = struct {
    vtable: ToolVTable,
    context: *anyopaque,
};

pub const ToolVTable = struct {
    name: []const u8,

    create: *const fn (allocator: std.mem.Allocator, world: *World, renderer2D: *engine.Renderer2D) anyerror!*anyopaque,
    destroy: *const fn (context: *anyopaque) void,
    update: *const fn (context: *anyopaque, input: *engine.InputState, mouse_position: vec2) void,
    render: *const fn (context: *anyopaque) void,
    drawUi: *const fn (context: *anyopaque) void,
};

// need deps:
//
