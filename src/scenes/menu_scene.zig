const std = @import("std");
const zgui = @import("zgui");

const SceneManager = @import("../engine/scene_manager.zig");
const Scene = SceneManager.Scene;
const LoadContext = SceneManager.LoadContext;
const UnloadContext = SceneManager.UnloadContext;
const UpdateContext = SceneManager.UpdateContext;
const RenderContext = SceneManager.RenderContext;
const DrawUiContext = SceneManager.DrawUiContext;

pub fn getScene() Scene {
    return Scene{
        .name = "menu",
        .load = load,
        .unload = unload,
        .update = update,
        .render = render,
        .draw_ui = drawUi,
    };
}

const Data = struct {
    // per scene data
    a: i32,
    b: i32,
    c: i32,
};

fn load(context: *const LoadContext) *void {
    var data = context.allocator.create(Data) catch unreachable;

    data.a = 111;
    data.b = 222;
    data.c = 333;

    return @ptrCast(data);
}

fn unload(context: *const UnloadContext) void {
    const data: *Data = @alignCast(@ptrCast(context.scene_data));

    context.allocator.destroy(data);
}

fn update(context: *const UpdateContext) void {
    if (context.input_state.consumeKeyDownEvent(.escape)) {
        context.scene_commands.exit = true;
    }

    if (context.input_state.consumeKeyDownEvent(.space)) {
        std.log.info("test scene got space", .{});
    }
}

fn render(context: *const RenderContext) void {
    _ = context;
}

fn drawUi(context: *const DrawUiContext) void {
    var data: *Data = @alignCast(@ptrCast(context.scene_data));

    zgui.setNextWindowPos(.{ .x = 300.0, .y = 300.0, .cond = .appearing });
    zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

    if (zgui.begin("Main menu", .{})) {
        zgui.text("data {d} {d} {d}", .{ data.a, data.b, data.c });

        if (zgui.button("aaa", .{})) {
            data.a += 1;
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
