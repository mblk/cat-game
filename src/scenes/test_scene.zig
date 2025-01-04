const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");

pub fn getScene() engine.SceneDescriptor {
    return engine.SceneDescriptor{
        .id = .TestScene2,
        .name = "test",
        .load = TestScene.load,
        .unload = TestScene.unload,
        .update = TestScene.update,
        .render = TestScene.render,
        .draw_ui = TestScene.drawUi,
    };
}

const TestScene = struct {
    const Self = @This();

    // per scene data
    a: i32,
    b: i32,
    c: i32,

    fn load(context: *const engine.LoadContext) !*anyopaque {
        const self = try context.allocator.create(Self);
        self.* = Self{
            .a = 1,
            .b = 2,
            .c = 3,
        };
        return self;
    }

    fn unload(self_ptr: *anyopaque, context: *const engine.UnloadContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        context.allocator.destroy(self);
    }

    fn update(self_ptr: *anyopaque, context: *const engine.UpdateContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = self;

        if (context.input_state.consumeKeyDownEvent(.escape)) {
            // context.scene_commands.change_scene = true;
            // context.scene_commands.new_scene_name = "menu";
        }

        if (context.input_state.consumeKeyDownEvent(.space)) {
            std.log.info("test scene got space", .{});
        }
    }

    fn render(self_ptr: *anyopaque, context: *const engine.RenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = self;
        _ = context;
    }

    fn drawUi(self_ptr: *anyopaque, context: *const engine.DrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = self;

        zgui.setNextWindowPos(.{ .x = 300.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

        if (zgui.begin("test scene", .{})) {
            zgui.text("dt {d:.3}", .{context.dt});
            zgui.text("hello", .{});
            zgui.end();
        }
    }
};
