const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zgui = @import("zgui");
const zstbi = @import("zstbi");
const zearcut = @import("zearcut");

const TrackingAllocator = @import("utils/tracking_allocator.zig").TrackingAllocator;

const engine = @import("engine/engine.zig");
const Window = engine.Window;
const InputState = engine.InputState;
const SceneManager = engine.SceneManager;

const MenuScene = @import("scenes/menu_scene.zig");
const EmptyScene = @import("scenes/empty_scene.zig");
const TestScene = @import("scenes/test_scene.zig");
const Renderer2DTestScene = @import("scenes/renderer_2d_test_scene.zig");
const GameScene = @import("scenes/game_scene.zig");
const LevelSelectScene = @import("scenes/level_select_scene.zig");
const ShaderToyScene = @import("scenes/shader_toy_scene.zig");

pub fn main() !void {
    std.log.info("hello!", .{});
    defer std.log.info("bye!", .{});

    try glfw.init();
    defer glfw.terminate();

    // -----------------------------------

    var gpa_state = std.heap.GeneralPurposeAllocator(.{
        .verbose_log = false,
    }){};
    defer _ = gpa_state.deinit();
    const gpa_alloc = gpa_state.allocator();

    // -----------------------------------

    // TODO maybe use arena in release mode and gpa in debug mode?

    // var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena_state.deinit();
    // const arena_alloc = arena_state.allocator();

    var gpa_state2 = std.heap.GeneralPurposeAllocator(.{
        .verbose_log = false,
    }){};
    defer _ = gpa_state2.deinit();
    const gpa_alloc2 = gpa_state2.allocator();

    // -----------------------------------

    var tracking_gpa_state = TrackingAllocator{
        .verbose = false,
        .name = "long_term",
        .inner = gpa_alloc,
    };
    const tracking_gpa = tracking_gpa_state.getAllocator();

    // -----------------------------------

    var tracking_arena_state = TrackingAllocator{
        .verbose = false,
        .name = "per_frame",
        //.inner = arena_alloc,
        .inner = gpa_alloc2,
    };
    const tracking_arena = tracking_arena_state.getAllocator();

    // -----------------------------------
    const long_term_alloc = tracking_gpa;
    const per_frame_alloc = tracking_arena;
    // -----------------------------------

    var content_manager: engine.ContentManager = undefined;
    try content_manager.init(long_term_alloc, true);
    defer content_manager.deinit();

    var save_manager = try engine.SaveManager.create(long_term_alloc);
    defer save_manager.free();

    // -----------------------------------

    var window: *Window = try long_term_alloc.create(Window);
    defer long_term_alloc.destroy(window);

    try window.init();
    defer window.destroy();

    // -----------------------------------

    zstbi.init(long_term_alloc);
    zstbi.setFlipVerticallyOnLoad(true);
    defer zstbi.deinit();

    // -----------------------------------

    //zearcut.init(long_term_alloc); // TODO which allocator?
    zearcut.init(per_frame_alloc); // TODO which allocator?
    defer zearcut.deinit();

    // -----------------------------------

    zgui.init(long_term_alloc);
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

    zgui.plot.init();
    defer zgui.plot.deinit();

    // -----------------------------------
    var scene_manager = try SceneManager.create(long_term_alloc, per_frame_alloc, window, &content_manager, &save_manager);
    defer scene_manager.destroy();

    try scene_manager.registerScene(MenuScene.getScene());
    try scene_manager.registerScene(EmptyScene.getScene());
    try scene_manager.registerScene(TestScene.getScene());
    try scene_manager.registerScene(Renderer2DTestScene.getScene());
    try scene_manager.registerScene(GameScene.getScene());
    try scene_manager.registerScene(LevelSelectScene.getScene());
    try scene_manager.registerScene(ShaderToyScene.getScene());

    //scene_manager.switchScene(.Menu);

    //scene_manager.switchScene(.Renderer2DTest);

    //scene_manager.switchScene(.ShaderToy);

    scene_manager.switchScene(.{
        .Game = .{
            .edit_mode = false,
            .level_name = "world_1",
            .level_name_alloc = null,
        },
    });

    scene_manager.runMainLoop();
}
