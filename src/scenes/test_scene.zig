const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");

pub fn getScene() engine.Scene {
    return engine.Scene{
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

fn load(context: *const engine.LoadContext) !*anyopaque {
    // ...
    //_ = context;

    const data = try context.allocator.create(Data);

    data.a = 1;
    data.b = 2;
    data.c = 3;

    return data;
}

fn unload(context: *const engine.UnloadContext) void {
    // ...
    const data: *Data = @alignCast(@ptrCast(context.scene_data));

    context.allocator.destroy(data);
}

fn update(context: *const engine.UpdateContext) void {
    //_ = context;

    if (context.input_state.consumeKeyDownEvent(.escape)) {
        context.scene_commands.change_scene = true;
        context.scene_commands.new_scene_name = "menu";
    }

    if (context.input_state.consumeKeyDownEvent(.space)) {
        std.log.info("test scene got space", .{});
    }
}

fn render(context: *const engine.RenderContext) void {
    _ = context;
}

fn drawUi(context: *const engine.DrawUiContext) void {
    //_ = context;

    zgui.setNextWindowPos(.{ .x = 300.0, .y = 300.0, .cond = .appearing });
    zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

    if (zgui.begin("test scene", .{})) {
        zgui.text("dt {d:.3}", .{context.dt});
        zgui.text("hello", .{});
        zgui.end();
    }
}
