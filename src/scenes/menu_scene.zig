const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");

pub fn getScene() engine.SceneDescriptor {
    return engine.SceneDescriptor{
        .name = "menu",
        .load = MenuScene.load,
        .unload = MenuScene.unload,
        .update = MenuScene.update,
        .render = MenuScene.render,
        .draw_ui = MenuScene.drawUi,
    };
}

const MenuScene = struct {
    const Self = MenuScene;

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

        _ = self;

        zgui.setNextWindowPos(.{ .x = 300.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

        if (zgui.begin("Main menu", .{})) {
            if (zgui.button("Start new game", .{})) {
                context.scene_commands.change_scene = true;
                context.scene_commands.new_scene_name = "game";
            }

            if (zgui.button("Load test scene 1", .{})) {
                context.scene_commands.change_scene = true;
                context.scene_commands.new_scene_name = "test";
            }

            if (zgui.button("Load test scene 2", .{})) {
                context.scene_commands.change_scene = true;
                context.scene_commands.new_scene_name = "test2";
            }

            if (zgui.button("Load test scene 3", .{})) {
                context.scene_commands.change_scene = true;
                context.scene_commands.new_scene_name = "test3";
            }

            if (zgui.button("Exit game", .{})) {
                context.scene_commands.exit = true;
            }

            zgui.end();
        }
    }
};
