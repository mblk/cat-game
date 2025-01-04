const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");

pub fn getScene() engine.SceneDescriptor {
    return engine.SceneDescriptor{
        .id = .Menu,
        .name = "menu",
        .load = MenuScene.load,
        .unload = MenuScene.unload,
        .update = MenuScene.update,
        .render = MenuScene.render,
        .draw_ui = MenuScene.drawUi,
    };
}

const MenuScene = struct {
    const Self = @This();

    a: i32,

    fn load(context: *const engine.LoadContext) !*anyopaque {
        const self = try context.allocator.create(Self);
        self.* = Self{
            .a = 111,
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
            context.scene_commands.exit = true;
        }
    }

    fn render(self_ptr: *anyopaque, context: *const engine.RenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = self;
        _ = context;
    }

    fn drawUi(self_ptr: *anyopaque, context: *const engine.DrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        const button_w = 200;
        const button_h = 40;

        _ = self;

        zgui.setNextWindowPos(.{ .x = 300.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

        if (zgui.begin("Main menu", .{})) {
            if (zgui.button("Start new game", .{ .w = button_w, .h = button_h })) {
                context.scene_commands.new_scene = .LevelSelect;
            }

            if (zgui.button("Load test scene 1", .{ .w = button_w, .h = button_h })) {
                context.scene_commands.new_scene = .Renderer2DTest;
            }

            if (zgui.button("Load test scene 2", .{ .w = button_w, .h = button_h })) {
                context.scene_commands.new_scene = .TestScene1;
            }

            if (zgui.button("Load test scene 3", .{ .w = button_w, .h = button_h })) {
                context.scene_commands.new_scene = .TestScene2;
            }

            if (zgui.button("Exit game", .{ .w = button_w, .h = button_h })) {
                context.scene_commands.exit = true;
            }

            zgui.end();
        }
    }
};
