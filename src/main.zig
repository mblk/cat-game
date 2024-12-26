const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zgui = @import("zgui");
const zstbi = @import("zstbi");
const zearcut = @import("zearcut");

const engine = @import("engine/engine.zig");
const Window = engine.Window;
const InputState = engine.InputState;
const SceneManager = engine.SceneManager;

const MenuScene = @import("scenes/menu_scene.zig");
const EmptyScene = @import("scenes/empty_scene.zig");

const TestScene = @import("scenes/test_scene.zig");
const Renderer2DTestScene = @import("scenes/renderer_2d_test_scene.zig");

const GameScene = @import("scenes/game_scene.zig");

pub const TrackingAllocatorStats = struct {
    total_allocs: usize,
    total_resizes: usize,
    total_frees: usize,

    total_allocations: usize,
    total_memory_used: usize,
    max_memory_used: usize,
};

pub const TrackingAllocator = struct {
    const Self = TrackingAllocator;

    inner: std.mem.Allocator,

    total_allocs: usize = 0,
    total_resizes: usize = 0,
    total_frees: usize = 0,

    total_allocations: usize = 0,
    total_memory_used: usize = 0,
    max_memory_used: usize = 0,

    fn getAllocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    pub fn getStats(allocator: std.mem.Allocator) TrackingAllocatorStats {
        const self: *Self = @ptrCast(@alignCast(allocator.ptr));

        return TrackingAllocatorStats{
            .total_allocs = self.total_allocs,
            .total_resizes = self.total_resizes,
            .total_frees = self.total_frees,
            .total_allocations = self.total_allocations,
            .total_memory_used = self.total_memory_used,
            .max_memory_used = self.max_memory_used,
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        // self.mutex.lock();
        // defer self.mutex.unlock();

        //std.debug.print("alloc {d}\n", .{len});
        //std.debug.dumpCurrentStackTrace(@returnAddress());

        self.total_allocs += 1;
        self.total_allocations += 1;
        self.total_memory_used += len;
        self.max_memory_used = @max(self.max_memory_used, self.total_memory_used);

        return self.inner.vtable.alloc(self.inner.ptr, len, ptr_align, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        //std.debug.print("resize {d} -> {d}\n", .{ buf.len, new_len });

        self.total_resizes += 1;
        self.total_memory_used -= buf.len;
        self.total_memory_used += new_len;

        return self.inner.vtable.resize(self.inner.ptr, buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        //std.debug.print("free {d}\n", .{buf.len});

        self.total_frees += 1;
        self.total_allocations -= 1;
        self.total_memory_used -= buf.len;

        self.inner.vtable.free(self.inner.ptr, buf, buf_align, ret_addr);
    }
};

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
        .inner = gpa_alloc,
    };
    const tracking_gpa = tracking_gpa_state.getAllocator();

    // -----------------------------------

    var tracking_arena_state = TrackingAllocator{
        //.inner = arena_alloc,
        .inner = gpa_alloc2,
    };
    const tracking_arena = tracking_arena_state.getAllocator();

    // -----------------------------------
    const long_term_alloc = tracking_gpa;
    const per_frame_alloc = tracking_arena;
    // -----------------------------------

    var content_manager = try engine.ContentManager.create(long_term_alloc);
    defer content_manager.destroy();

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

    // -----------------------------------
    var scene_manager = try SceneManager.create(long_term_alloc, per_frame_alloc, window, &content_manager, &save_manager);
    defer scene_manager.destroy();

    try scene_manager.registerScene(MenuScene.getScene());
    try scene_manager.registerScene(EmptyScene.getScene());
    try scene_manager.registerScene(TestScene.getScene());
    try scene_manager.registerScene(Renderer2DTestScene.getScene());
    try scene_manager.registerScene(GameScene.getScene());

    //scene_manager.switchScene("menu");
    scene_manager.switchScene("game");

    scene_manager.runMainLoop();
}
