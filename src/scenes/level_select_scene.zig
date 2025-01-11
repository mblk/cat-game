const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");

pub fn getScene() engine.SceneDescriptor {
    return engine.SceneDescriptor{
        .id = .LevelSelect,
        .name = "level_select",
        .load = LevelSelectScene.load,
        .unload = LevelSelectScene.unload,
        .update = LevelSelectScene.update,
        .render = LevelSelectScene.render,
        .draw_ui = LevelSelectScene.drawUi,
    };
}

const LevelSelectScene = struct {
    const Self = @This();

    level_infos: engine.SaveManager.SaveInfos,

    fn load(context: *const engine.LoadContext) !*anyopaque {
        const self = try context.allocator.create(Self);

        const save_infos = try context.save_manager.getSaveInfos(.WorldExport, context.allocator);

        self.* = Self{
            .level_infos = save_infos,
        };

        return self;
    }

    fn unload(self_ptr: *anyopaque, context: *const engine.UnloadContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.level_infos.deinit();

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

        var buffer: [128]u8 = undefined;

        zgui.setNextWindowPos(.{ .x = 300.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

        if (zgui.begin("Select level", .{})) {
            if (zgui.button("Return to menu", .{ .w = button_w, .h = button_h })) {
                context.scene_commands.new_scene = .Menu;
            }

            zgui.separator();

            if (zgui.button("Empty (play)", .{ .w = button_w, .h = button_h })) {
                context.scene_commands.new_scene = .{
                    .Game = .{
                        .edit_mode = false,
                        .level_name = null,
                        .level_name_alloc = null,
                    },
                };
            }
            zgui.sameLine(.{});
            if (zgui.button("Empty (edit)", .{ .w = button_w, .h = button_h })) {
                context.scene_commands.new_scene = .{
                    .Game = .{
                        .edit_mode = true,
                        .level_name = null,
                        .level_name_alloc = null,
                    },
                };
            }

            zgui.separator();

            for (self.level_infos.entries) |level_info| {
                const s1 = std.fmt.bufPrintZ(&buffer, "{s} (play)", .{level_info.name}) catch unreachable;

                if (zgui.button(s1, .{ .w = button_w, .h = button_h })) {
                    context.scene_commands.new_scene = .{
                        .Game = .{
                            .edit_mode = false,
                            .level_name = context.allocator.dupe(u8, level_info.name) catch unreachable, // Must be freed by target scene
                            .level_name_alloc = context.allocator,
                        },
                    };
                }

                zgui.sameLine(.{});

                const s2 = std.fmt.bufPrintZ(&buffer, "{s} (edit)", .{level_info.name}) catch unreachable;

                if (zgui.button(s2, .{ .w = button_w, .h = button_h })) {
                    context.scene_commands.new_scene = .{
                        .Game = .{
                            .edit_mode = true,
                            .level_name = context.allocator.dupe(u8, level_info.name) catch unreachable, // Must be freed by target scene
                            .level_name_alloc = context.allocator,
                        },
                    };
                }
            }

            zgui.end();
        }
    }
};
