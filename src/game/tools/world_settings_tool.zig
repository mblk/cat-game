const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const World = @import("../world.zig").World;
const WorldSettings = @import("../world.zig").WorldSettings;

const tools = @import("tools.zig");
const ToolVTable = tools.ToolVTable;
const ToolDeps = tools.ToolDeps;
const ToolUpdateContext = tools.ToolUpdateContext;
const ToolRenderContext = tools.ToolRenderContext;
const ToolDrawUiContext = tools.ToolDrawUiContext;

const Mode = union(enum) {
    Idle: void,
    SetStart: void,
    SetFinish: void,
};

pub const WorldSettingsTool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    world: *World,
    renderer2D: *engine.Renderer2D,

    mode: Mode = .Idle,

    pub fn getVTable() ToolVTable {
        return ToolVTable{
            .name = "World settings",
            .shortcut = .F1,
            .create = Self.create,
            .destroy = Self.destroy,
            .update = Self.update,
            .render = Self.render,
            .drawUi = Self.drawUi,
        };
    }

    fn create(allocator: std.mem.Allocator, deps: ToolDeps) !*anyopaque {
        const self = try allocator.create(Self);

        self.* = Self{
            .allocator = allocator,
            .world = deps.world,
            .renderer2D = deps.renderer2D,
        };

        return self;
    }

    fn destroy(self_ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.allocator.destroy(self);
    }

    fn update(self_ptr: *anyopaque, context: ToolUpdateContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        const input = context.input;
        const mouse_position = context.mouse_position;

        switch (self.mode) {
            .Idle => {
                //
            },
            .SetStart => {
                if (input.consumeMouseButtonDownEvent(.left)) {
                    self.world.settings.start_position = mouse_position;
                    self.mode = .Idle;
                }
            },
            .SetFinish => {
                if (input.consumeMouseButtonDownEvent(.left)) {
                    self.world.settings.finish_position = mouse_position;
                    self.mode = .Idle;
                }
            },
        }

        // cancel?
        if (self.mode != .Idle and input.consumeMouseButtonDownEvent(.right)) {
            self.mode = .Idle;
        }
    }

    fn render(self_ptr: *anyopaque, context: ToolRenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = self;
        _ = context;

        // const settings: *const WorldSettings = &self.world.settings;

        // self.renderer2D.addCircle(settings.start_position, 1.0, Color.white);
        // self.renderer2D.addCircle(settings.finish_position, 1.0, Color.white);

        // self.renderer2D.addText(settings.start_position, Color.white, "start", .{});
        // self.renderer2D.addText(settings.finish_position, Color.white, "finish", .{});
    }

    fn drawUi(self_ptr: *anyopaque, context: ToolDrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = context;

        zgui.setNextWindowPos(.{ .x = 10.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 300, .h = 600 });

        if (zgui.begin("World settings", .{})) {
            self.drawWindowContent();
        }
        zgui.end();
    }

    fn drawWindowContent(self: *Self) void {
        //var buffer: [128]u8 = undefined;

        zgui.text("Mode: {any}", .{self.mode});

        var settings: *WorldSettings = &self.world.settings;

        var size_array = [2]f32{
            settings.size.x,
            settings.size.y,
        };
        var gravity_array = [2]f32{
            settings.gravity.x,
            settings.gravity.y,
        };

        if (zgui.dragFloat2("Size", .{
            .v = &size_array,

            .speed = 10,
            .min = 10,
            .max = 5000,
            .cfmt = "%.1f m",
        })) {
            settings.size.x = size_array[0];
            settings.size.y = size_array[1];
            settings.size_changed = true;
        }

        if (zgui.dragFloat2("Gravity", .{
            .v = &gravity_array,

            .speed = 0.1,
            .min = -100,
            .max = 100,
            .cfmt = "%.2f m/s²",
        })) {
            settings.gravity.x = gravity_array[0];
            settings.gravity.y = gravity_array[1];
            settings.gravity_changed = true;
        }

        zgui.text("Start: {d:.1} {d:.1}", .{ settings.start_position.x, settings.start_position.y });
        zgui.text("Finish: {d:.1} {d:.1}", .{ settings.finish_position.x, settings.finish_position.y });

        if (zgui.button("Set start", .{})) {
            self.mode = .SetStart;
        }
        if (zgui.button("Set finish", .{})) {
            self.mode = .SetFinish;
        }

        if (self.mode == .SetStart) {
            zgui.text("Click in world so set start", .{});
        }
        if (self.mode == .SetFinish) {
            zgui.text("Click in world to set finish", .{});
        }
    }
};
