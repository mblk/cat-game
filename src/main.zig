const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zgui = @import("zgui");

const Window = @import("engine/window.zig");
const InputState = @import("engine/input_state.zig");
const SceneManager = @import("engine/scene_manager.zig");

const TestScene = @import("scenes/test_scene.zig");
const MenuScene = @import("scenes/menu_scene.zig");

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

    scale_factor = 2.0;

    _ = zgui.io.addFontFromFile(
        //content_dir ++ "Roboto-Medium.ttf",
        "content/fonts/Roboto-Medium.ttf",
        std.math.floor(16.0 * scale_factor),
    );

    zgui.getStyle().scaleAllSizes(scale_factor);

    zgui.backend.init(window.glfw_window);
    defer zgui.backend.deinit();

    // -----------------------------------
    const test_scene = TestScene.getScene();
    const menu_scene = MenuScene.getScene();

    var scene_manager = try SceneManager.create(gpa, window);
    defer scene_manager.destroy();

    try scene_manager.registerScene(menu_scene);
    try scene_manager.registerScene(test_scene);

    scene_manager.switchScene("menu");

    scene_manager.runMainLoop();
}
