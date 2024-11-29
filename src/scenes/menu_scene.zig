const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");

pub fn getScene() engine.Scene {
    return engine.Scene{
        .name = "menu",
        .load = load,
        .unload = unload,
        .update = update,
        .render = render,
        .draw_ui = drawUi,
    };
}

const Data = struct {
    a: i32,
};

fn load(context: *const engine.LoadContext) !*anyopaque {
    const data = try context.allocator.create(Data);

    data.a = 111;

    // TODO must free any data in case of error

    return data;
}

fn unload(context: *const engine.UnloadContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    context.allocator.destroy(data);
}

fn update(context: *const engine.UpdateContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    _ = data;

    if (context.input_state.consumeKeyDownEvent(.escape)) {
        context.scene_commands.exit = true;
    }
}

fn render(context: *const engine.RenderContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    _ = data;
}

fn drawUi(context: *const engine.DrawUiContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    _ = data;

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
