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
    // per scene data
    a: i32,
    b: i32,
    c: i32,

    some_text: []const u8,

    // camera: engine.Camera,

    // renderer: engine.Renderer2D,
};

fn load(context: *const engine.LoadContext) !*void {
    const data = try context.allocator.create(Data);

    data.a = 111;
    data.b = 222;
    data.c = 333;

    data.some_text = try context.content_manager.loadDataFile(context.allocator, "text", "test.txt");

    // data.camera = engine.Camera.create();

    // data.renderer = try engine.Renderer2D.create(context.allocator, context.content_manager);

    // TODO must free any data in case of error

    return @ptrCast(data);
}

fn unload(context: *const engine.UnloadContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    //data.renderer.free();

    context.allocator.free(data.some_text);

    context.allocator.destroy(data);
}

fn update(context: *const engine.UpdateContext) void {
    if (context.input_state.consumeKeyDownEvent(.escape)) {
        context.scene_commands.exit = true;
    }
}

fn render(context: *const engine.RenderContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    _ = data;

    // data.renderer.addLine(
    //     [3]f32{ 0.0, 0.0, 0.0 },
    //     [3]f32{ 10.0, 0.0, 0.0 },
    //     [4]u8{ 255, 255, 255, 255 },
    // );

    // data.renderer.render(&data.camera);
}

fn drawUi(context: *const engine.DrawUiContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    zgui.setNextWindowPos(.{ .x = 300.0, .y = 300.0, .cond = .appearing });
    zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

    if (zgui.begin("Main menu", .{})) {
        zgui.text("data {d} {d} {d}", .{ data.a, data.b, data.c });
        zgui.text("text: {s}", .{data.some_text});

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
