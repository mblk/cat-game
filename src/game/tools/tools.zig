const std = @import("std");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const World = @import("../world.zig").World;

pub const Tool = struct {
    vtable: ToolVTable,
    self_ptr: *anyopaque,
};

pub const ToolVTable = struct {
    name: []const u8, // XXX doesnt make sense

    create: *const fn (allocator: std.mem.Allocator, deps: ToolDeps) anyerror!*anyopaque,
    destroy: *const fn (self_ptr: *anyopaque) void,
    update: *const fn (self_ptr: *anyopaque, context: ToolUpdateContext) void,
    render: *const fn (self_ptr: *anyopaque, context: ToolRenderContext) void,
    drawUi: *const fn (self_ptr: *anyopaque, context: ToolDrawUiContext) void,
};

// need deps:
// ...

pub const ToolDeps = struct {
    //allocator: std.mem.Allocator,
    world: *World,
    renderer2D: *engine.Renderer2D,
};

pub const ToolUpdateContext = struct {
    input: *engine.InputState,
    mouse_position: vec2,
};

pub const ToolRenderContext = struct {
    //
};

pub const ToolDrawUiContext = struct {
    //
};

pub const ToolManager = struct {
    const Self = ToolManager;

    allocator: std.mem.Allocator,
    deps: ToolDeps,
    all_tools: std.ArrayList(ToolVTable),
    active_tool: ?Tool,

    pub fn create(allocator: std.mem.Allocator, deps: ToolDeps) Self {
        return Self{
            .allocator = allocator,
            .deps = deps,
            .all_tools = std.ArrayList(ToolVTable).init(allocator),
            .active_tool = null,
        };
    }

    pub fn destroy(self: *Self) void {
        if (self.active_tool) |tool| {
            tool.vtable.destroy(tool.self_ptr);
        }
        self.all_tools.deinit();
    }

    pub fn register(self: *Self, tool_vtable: ToolVTable) !void {
        try self.all_tools.append(tool_vtable);
    }

    pub fn select(self: *Self, tool_to_select: ToolVTable) void {
        if (self.active_tool) |tool| {
            tool.vtable.destroy(tool.self_ptr);
        }
        self.active_tool = Tool{
            .vtable = tool_to_select,
            .self_ptr = tool_to_select.create(self.allocator, self.deps) catch unreachable,
        };
    }

    pub fn deselect(self: *Self) void {
        if (self.active_tool) |tool| {
            tool.vtable.destroy(tool.self_ptr);
            self.active_tool = null;
        }
    }

    pub fn update(self: *Self, context: ToolUpdateContext) void {
        if (self.active_tool) |tool| {
            tool.vtable.update(tool.self_ptr, context);
        }
    }

    pub fn render(self: *Self, context: ToolRenderContext) void {
        if (self.active_tool) |tool| {
            tool.vtable.render(tool.self_ptr, context);
        }
    }

    pub fn drawUi(self: *Self, context: ToolDrawUiContext) void {
        if (self.active_tool) |tool| {
            tool.vtable.drawUi(tool.self_ptr, context);
        }
    }
};
