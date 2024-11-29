const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

pub fn getScene() engine.Scene {
    return engine.Scene{
        .name = "renderer_2d_test",
        .load = load,
        .unload = unload,
        .update = update,
        .render = render,
    };
}

const Data = struct {
    camera: engine.Camera,
    renderer: engine.Renderer2D,
};

fn load(context: *const engine.LoadContext) !*void {
    const data = try context.allocator.create(Data);

    data.camera = engine.Camera.create();
    data.renderer = try engine.Renderer2D.create(context.allocator, context.content_manager);

    return @ptrCast(data);
}

fn unload(context: *const engine.UnloadContext) void {
    const data: *Data = @alignCast(@ptrCast(context.scene_data));

    data.renderer.free();

    context.allocator.destroy(data);
}

fn update(context: *const engine.UpdateContext) void {
    const data: *Data = @alignCast(@ptrCast(context.scene_data));

    data.camera.setViewportSize(context.viewport_size);

    if (context.input_state.consumeMouseScroll()) |scroll| {
        data.camera.changeZoom(-scroll);
    }

    if (context.input_state.consumeKeyDownEvent(.backspace)) {
        data.camera.reset();
    }

    if (context.input_state.consumeKeyState(.left)) {
        data.camera.changePosition([2]f32{ -100.0 * context.dt, 0.0 });
    }

    if (context.input_state.consumeKeyState(.right)) {
        data.camera.changePosition([2]f32{ 100.0 * context.dt, 0.0 });
    }

    if (context.input_state.consumeKeyState(.up)) {
        data.camera.changePosition([2]f32{ 0.0, 100.0 * context.dt });
    }

    if (context.input_state.consumeKeyState(.down)) {
        data.camera.changePosition([2]f32{ 0.0, -100.0 * context.dt });
    }
}

fn render(context: *const engine.RenderContext) void {
    const data: *Data = @alignCast(@ptrCast(context.scene_data));

    const p1 = vec2.init(0.0, 0.0);
    const p2 = vec2.init(10.0, 0.0);
    const p3 = vec2.init(10.0, 10.0);
    const p4 = vec2{ .x = 0.0, .y = 10.0 };
    const p5 = vec2{ .x = 30.0, .y = 10.0 };

    const c1 = Color.red;
    const c2 = Color.green;
    const c3 = Color.blue;
    const c4 = Color.init(255, 255, 0, 255);

    data.renderer.addPoint(p1, 1.0, c1);
    data.renderer.addPoint(p2, 2.5, c2);
    data.renderer.addPoint(p3, 2.5, c3);
    data.renderer.addPoint(p4, 5.0, c4);
    data.renderer.addPointWithPixelSize(p5, 50.0, c1);

    data.renderer.addLine(p1, p2, c1);
    data.renderer.addLine(p2, p3, c2);
    data.renderer.addLine(p3, p4, c3);
    data.renderer.addLine(p4, p1, c4);

    // cw
    data.renderer.addTriangle(
        vec2.init(-30.0, 0.0),
        vec2.init(-30.0, 30.0),
        vec2.init(0.0, 30.0),
        Color.blue,
    );

    // ccw
    data.renderer.addTriangle(
        vec2.init(-30.0, 0.0),
        vec2.init(-30.0, -30.0),
        vec2.init(0.0, -30.0),
        Color.red,
    );

    data.renderer.render(&data.camera);
}
