const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

pub fn getScene() engine.SceneDescriptor {
    return engine.SceneDescriptor{
        .id = .Renderer2DTest,
        .name = "renderer_2d_test",
        .load = Renderer2DTestScene.load,
        .unload = Renderer2DTestScene.unload,
        .update = Renderer2DTestScene.update,
        .render = Renderer2DTestScene.render,
        .draw_ui = Renderer2DTestScene.drawUi,
    };
}

const Renderer2DTestScene = struct {
    const Self = @This();

    camera: engine.Camera,
    renderer: engine.Renderer2D,

    texture1: u32,
    texture2: u32,
    texture3: u32,

    fn load(context: *const engine.LoadContext) !*anyopaque {
        const self = try context.allocator.create(Self);
        // self.* = Self{
        //     .camera = engine.Camera.create(),
        // };

        self.camera = engine.Camera.create();

        try self.renderer.init(context.allocator, context.content_manager);

        self.texture1 = try self.renderer.loadTexture("cat1.png");
        self.texture2 = try self.renderer.loadTexture("cat2.png");
        self.texture3 = try self.renderer.loadTexture("cardboard1.png");

        return self;
    }

    fn unload(self_ptr: *anyopaque, context: *const engine.UnloadContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.renderer.deinit();

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

        if (context.input_state.getKeyState(.left)) self.camera.changeOffset(vec2.init(-100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.right)) self.camera.changeOffset(vec2.init(100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.up)) self.camera.changeOffset(vec2.init(0.0, 100.0 * context.dt));
        if (context.input_state.getKeyState(.down)) self.camera.changeOffset(vec2.init(0.0, -100.0 * context.dt));
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

        self.renderer.addCircle(vec2.init(0, -10), 1.0, Color.red);
        self.renderer.addCircle(vec2.init(5, -10), 2.0, Color.green);

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

        // ccw
        self.renderer.addTexturedTriangle(
            vec2.init(-60.0, 0.0), // top left
            vec2.init(-60.0, -30.0), // bottom left
            vec2.init(-30.0, -30.0), // bottom right
            Color.white,
            vec2.init(0, 1),
            vec2.init(0, 0),
            vec2.init(1, 0),
            self.texture1,
        );
        self.renderer.addTexturedTriangle(
            vec2.init(-90.0, 0.0), // top left
            vec2.init(-90.0, -30.0), // bottom left
            vec2.init(-60.0, -30.0), // bottom right
            Color.white,
            vec2.init(0, 1),
            vec2.init(0, 0),
            vec2.init(1, 0),
            self.texture2,
        );
        self.renderer.addTexturedTriangle(
            vec2.init(-120.0, 0.0), // top left
            vec2.init(-120.0, -30.0), // bottom left
            vec2.init(-90.0, -30.0), // bottom right
            Color.white,
            vec2.init(0, 1),
            vec2.init(0, 0),
            vec2.init(1, 0),
            self.texture3,
        );

        self.renderer.addTexturedQuad([_]vec2{
            vec2.init(-60, -60),
            vec2.init(-30, -60),
            vec2.init(-30, -30),
            vec2.init(-60, -30),
        }, Color.white, self.texture3);
        self.renderer.addTexturedQuad([_]vec2{
            vec2.init(-90, -60),
            vec2.init(-60, -60),
            vec2.init(-60, -30),
            vec2.init(-90, -30),
        }, Color.white, self.texture2);
        self.renderer.addTexturedQuad([_]vec2{
            vec2.init(-120, -60),
            vec2.init(-90, -60),
            vec2.init(-90, -30),
            vec2.init(-120, -30),
        }, Color.white, self.texture1);

        self.renderer.addText(vec2.init(0, 0), Color.red, "Hello !", .{});
        self.renderer.addText(vec2.init(0, -10), Color.green, "World !", .{});

        self.renderer.render(&self.camera);
    }

    fn drawUi(self_ptr: *anyopaque, context: *const engine.DrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = context;

        self.renderer.renderToZGui(&self.camera);
    }
};
