const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zgui = @import("zgui");

const engine = @import("engine/engine.zig");
const Window = engine.Window;
const InputState = engine.InputState;
const SceneManager = engine.SceneManager;

const MenuScene = @import("scenes/menu_scene.zig");
const EmptyScene = @import("scenes/empty_scene.zig");

const TestScene = @import("scenes/test_scene.zig");
const Renderer2DTestScene = @import("scenes/renderer_2d_test_scene.zig");

pub fn main() !void {
    std.log.info("hello!", .{});
    defer std.log.info("bye!", .{});

    try glfw.init();
    defer glfw.terminate();

    var gpa_state = std.heap.GeneralPurposeAllocator(.{
        .verbose_log = false,
    }){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // -----------------------------------

    var content_manager = try engine.ContentManager.create(gpa);
    defer content_manager.destroy();

    // -----------------------------------

    var window: *Window = try gpa.create(Window);
    defer gpa.destroy(window);

    try window.init();
    defer window.destroy();

    // -----------------------------------

    zgui.init(gpa);
    defer zgui.deinit();

    var scale_factor: f32 = scale_factor: {
        const scale = window.glfw_window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    std.log.info("scale_factor {d}", .{scale_factor});

    _ = &scale_factor;
    //scale_factor = 2.0;

    _ = zgui.io.addFontFromFile(
        //content_dir ++ "Roboto-Medium.ttf",
        "content/fonts/Roboto-Medium.ttf",
        std.math.floor(16.0 * scale_factor),
    );

    zgui.getStyle().scaleAllSizes(scale_factor);

    zgui.backend.init(window.glfw_window);
    defer zgui.backend.deinit();

    // -----------------------------------
    var scene_manager = try SceneManager.create(gpa, window, content_manager);
    defer scene_manager.destroy();

    try scene_manager.registerScene(MenuScene.getScene());
    try scene_manager.registerScene(EmptyScene.getScene());

    try scene_manager.registerScene(TestScene.getScene());
    try scene_manager.registerScene(Renderer2DTestScene.getScene());

    scene_manager.switchScene("menu");

    scene_manager.runMainLoop();
}
