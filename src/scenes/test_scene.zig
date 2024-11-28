const std = @import("std");
const zgui = @import("zgui");

const SceneManager = @import("../engine/scene_manager.zig");
const Scene = SceneManager.Scene;

pub fn getScene() Scene {
    return Scene{
        .name = "test",
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

fn load(context: *const SceneManager.LoadContext) *void {
    // ...
    //_ = context;

    var data = context.allocator.create(Data) catch unreachable;

    data.a = 1;
    data.b = 2;
    data.c = 3;

    return @ptrCast(data);
}

fn unload(context: *const SceneManager.UnloadContext) void {
    // ...
    const data: *Data = @alignCast(@ptrCast(context.scene_data));

    context.allocator.destroy(data);
}

fn update(context: *const SceneManager.UpdateContext) void {
    //_ = context;

    if (context.input_state.consumeKeyDownEvent(.escape)) {
        context.scene_commands.change_scene = true;
        context.scene_commands.new_scene_name = "menu";
    }

    if (context.input_state.consumeKeyDownEvent(.space)) {
        std.log.info("test scene got space", .{});
    }
}

fn render(context: *const SceneManager.RenderContext) void {
    _ = context;
}

fn drawUi(context: *const SceneManager.DrawUiContext) void {
    //_ = context;

    zgui.setNextWindowPos(.{ .x = 300.0, .y = 300.0, .cond = .appearing });
    zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

    if (zgui.begin("test scene", .{})) {
        zgui.text("dt {d:.3}", .{context.dt});
        zgui.text("hello", .{});
        zgui.end();
    }
}
