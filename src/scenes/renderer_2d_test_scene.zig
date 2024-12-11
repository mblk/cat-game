const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

pub fn getScene() engine.SceneDescriptor {
    return engine.SceneDescriptor{
        .name = "renderer_2d_test",
        .load = Renderer2DTestScene.load,
        .unload = Renderer2DTestScene.unload,
        .update = Renderer2DTestScene.update,
        .render = Renderer2DTestScene.render,
        .draw_ui = Renderer2DTestScene.drawUi,
    };
}

const Renderer2DTestScene = struct {
    const Self = Renderer2DTestScene;

    camera: engine.Camera,
    renderer: *engine.Renderer2D,

    fn load(context: *const engine.LoadContext) !*anyopaque {
        const self = try context.allocator.create(Self);
        self.* = Self{
            .camera = engine.Camera.create(),
            .renderer = try engine.Renderer2D.create(context.allocator, context.content_manager),
        };
        return self;
    }

    fn unload(self_ptr: *anyopaque, context: *const engine.UnloadContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.renderer.free();

        context.allocator.destroy(self);
    }

    fn update(self_ptr: *anyopaque, context: *const engine.UpdateContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.camera.setViewportSize(context.viewport_size);

        if (context.input_state.consumeMouseScroll()) |scroll| {
            self.camera.changeZoom(-scroll);
        }

        if (context.input_state.consumeKeyDownEvent(.backspace)) {
            self.camera.reset();
        }

        if (context.input_state.getKeyState(.left)) self.camera.changePosition(vec2.init(-100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.right)) self.camera.changePosition(vec2.init(100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.up)) self.camera.changePosition(vec2.init(0.0, 100.0 * context.dt));
        if (context.input_state.getKeyState(.down)) self.camera.changePosition(vec2.init(0.0, -100.0 * context.dt));
    }

    fn render(self_ptr: *anyopaque, context: *const engine.RenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = context;

        const p1 = vec2.init(0.0, 0.0);
        const p2 = vec2.init(10.0, 0.0);
        const p3 = vec2.init(10.0, 10.0);
        const p4 = vec2{ .x = 0.0, .y = 10.0 };
        const p5 = vec2{ .x = 30.0, .y = 10.0 };

        const c1 = Color.red;
        const c2 = Color.green;
        const c3 = Color.blue;
        const c4 = Color.init(255, 255, 0, 255);

        self.renderer.addPoint(p1, 1.0, c1);
        self.renderer.addPoint(p2, 2.5, c2);
        self.renderer.addPoint(p3, 2.5, c3);
        self.renderer.addPoint(p4, 5.0, c4);
        self.renderer.addPointWithPixelSize(p5, 50.0, c1);

        self.renderer.addLine(p1, p2, c1);
        self.renderer.addLine(p2, p3, c2);
        self.renderer.addLine(p3, p4, c3);
        self.renderer.addLine(p4, p1, c4);

        // cw
        self.renderer.addTriangle(
            vec2.init(-30.0, 0.0),
            vec2.init(-30.0, 30.0),
            vec2.init(0.0, 30.0),
            Color.blue,
        );

        // ccw
        self.renderer.addTriangle(
            vec2.init(-30.0, 0.0),
            vec2.init(-30.0, -30.0),
            vec2.init(0.0, -30.0),
            Color.red,
        );

        self.renderer.render(&self.camera);
    }

    fn drawUi(self_ptr: *anyopaque, context: *const engine.DrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = self;
        _ = context;
    }
};
