const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zgui = @import("zgui");

const Window = @import("window.zig");
const InputState = @import("input_state.zig");
const ContentManager = @import("content_manager.zig").ContentManager;
const SaveManager = @import("save_manager.zig").SaveManager;

const TrackingAllocator = @import("../main.zig").TrackingAllocator;
const TrackingAllocatorStats = @import("../main.zig").TrackingAllocatorStats;

pub const SceneDescriptor = struct {
    // desc
    name: []const u8,
    // vtable
    load: *const fn (context: *const LoadContext) anyerror!*anyopaque,
    unload: *const fn (self_ptr: *anyopaque, context: *const UnloadContext) void,
    update: *const fn (self_ptr: *anyopaque, context: *const UpdateContext) void,
    render: *const fn (self_ptr: *anyopaque, context: *const RenderContext) void,
    draw_ui: *const fn (self_ptr: *anyopaque, context: *const DrawUiContext) void,
};

pub const Scene = struct {
    descriptor: SceneDescriptor,
    self_ptr: *anyopaque,
};

// TODO
// - think about different allocators (eg. arena allocator for per-frame-data)
//   - per frame (eg. arena)
//   - per scene
//   - per world
//   - per game (ie. global)

pub const LoadContext = struct {
    allocator: std.mem.Allocator,
    content_manager: *ContentManager,
};

pub const UnloadContext = struct {
    allocator: std.mem.Allocator,
    content_manager: *ContentManager,
};

pub const UpdateContext = struct {
    allocator: std.mem.Allocator,
    per_frame_allocator: std.mem.Allocator,
    dt: f32,
    input_state: *InputState,
    viewport_size: [2]i32,
    scene_commands: *SceneCommandBuffer,
};

pub const RenderContext = struct {
    allocator: std.mem.Allocator,
    per_frame_allocator: std.mem.Allocator,
    dt: f32,
    //renderer?
    viewport_size: [2]i32,
};

pub const DrawUiContext = struct {
    allocator: std.mem.Allocator,
    per_frame_allocator: std.mem.Allocator,
    dt: f32,
    input_state: *InputState, // XXX
    viewport_size: [2]i32,
    scene_commands: *SceneCommandBuffer,

    save_manager: *SaveManager,
};

pub const SceneCommandBuffer = struct {
    exit: bool,
    change_scene: bool,
    new_scene_name: []const u8,
    // TODO new scene args?
};

pub const SceneManager = struct {
    // deps
    allocator: std.mem.Allocator,
    per_frame_allocator: std.mem.Allocator,
    window: *Window,
    content_manager: *ContentManager,
    save_manager: *SaveManager,

    // scenes
    all_scenes: std.ArrayList(SceneDescriptor),
    active_scene: ?Scene,

    pub fn create(
        allocator: std.mem.Allocator,
        per_frame_allocator: std.mem.Allocator,
        window: *Window,
        content_manager: *ContentManager,
        save_manager: *SaveManager,
    ) !SceneManager {
        return SceneManager{
            .allocator = allocator,
            .per_frame_allocator = per_frame_allocator,
            .window = window,
            .content_manager = content_manager,
            .save_manager = save_manager,

            .all_scenes = std.ArrayList(SceneDescriptor).init(allocator),
            .active_scene = null,
        };
    }

    pub fn destroy(self: *SceneManager) void {
        self.unloadCurrentScene();

        self.all_scenes.deinit();
    }

    pub fn registerScene(self: *SceneManager, scene_descriptor: SceneDescriptor) !void {
        std.log.info("register new scene: {s}", .{scene_descriptor.name});
        try self.all_scenes.append(scene_descriptor);
    }

    pub fn switchScene(self: *SceneManager, new_scene_name: []const u8) void {
        std.log.info("switch scene: {s}", .{new_scene_name});

        // unload current scene
        self.unloadCurrentScene();

        // load new scene
        const maybe_new_scene = self.getSceneByName(new_scene_name);
        if (maybe_new_scene) |new_scene| {
            self.loadNewScene(new_scene) catch |e| {
                std.log.err("failed to lead new scene: {any}", .{e});

                self.active_scene = null;
            };
        }
    }

    fn unloadCurrentScene(self: *SceneManager) void {
        if (self.active_scene) |scene| {
            const unload_context = UnloadContext{
                .allocator = self.allocator,
                .content_manager = self.content_manager,
            };

            std.log.info("unloading scene: {s}", .{scene.descriptor.name});
            scene.descriptor.unload(scene.self_ptr, &unload_context);
        }
    }

    fn loadNewScene(self: *SceneManager, scene_descriptor: SceneDescriptor) !void {
        std.log.info("loading scene: {s}", .{scene_descriptor.name});

        const load_context = LoadContext{
            .allocator = self.allocator,
            .content_manager = self.content_manager,
        };

        self.active_scene = Scene{
            .descriptor = scene_descriptor,
            .self_ptr = try scene_descriptor.load(&load_context),
        };
    }

    pub fn runMainLoop(self: *SceneManager) void {
        var t_prev = glfw.getTime();

        while (!self.window.getShouldClose()) {
            // update timing
            const t0: f64 = glfw.getTime();
            const dt64 = t0 - t_prev;
            const dt: f32 = @floatCast(dt64);
            t_prev = t0;

            var scene_command_buffer = SceneCommandBuffer{
                .exit = false,
                .change_scene = false,
                .new_scene_name = undefined,
            };

            // one frame
            self.frame(dt, &scene_command_buffer);

            // execute scene commands
            if (scene_command_buffer.exit) {
                self.window.setShouldClose(true);
            }
            if (scene_command_buffer.change_scene) {
                self.switchScene(scene_command_buffer.new_scene_name);
            }
        }
    }

    fn frame(self: *SceneManager, dt: f32, command_buffer: *SceneCommandBuffer) void {
        //std.debug.print("== new frame ==\n", .{});

        //
        // update
        //
        var input_state: InputState = undefined;
        self.window.processEvents(&input_state);

        const viewport_size = self.window.viewport_size; // get after events are processed

        if (input_state.getKeyState(.left_control) and input_state.consumeKeyDownEvent(.escape)) {
            self.window.setShouldClose(true);
        }

        if (self.active_scene) |scene| {
            const update_context = UpdateContext{
                .allocator = self.allocator,
                .per_frame_allocator = self.per_frame_allocator,
                .dt = dt,
                .input_state = &input_state,
                .viewport_size = viewport_size,
                .scene_commands = command_buffer,
            };

            scene.descriptor.update(scene.self_ptr, &update_context);
        }

        //
        // clear and render
        //
        gl.clearColor(0.1, 0.1, 0.1, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        if (self.active_scene) |scene| {
            const render_context = RenderContext{
                .allocator = self.allocator,
                .per_frame_allocator = self.per_frame_allocator,
                .dt = dt,
                .viewport_size = viewport_size,
            };

            scene.descriptor.render(scene.self_ptr, &render_context);
        }

        //
        // render ui
        //
        zgui.backend.newFrame(
            @intCast(self.window.viewport_size[0]),
            @intCast(self.window.viewport_size[1]),
        );

        self.drawDebugUi(dt, command_buffer);

        if (self.active_scene) |scene| {
            const draw_ui_context = DrawUiContext{
                .allocator = self.allocator,
                .per_frame_allocator = self.per_frame_allocator,
                .dt = dt,
                .input_state = &input_state,
                .viewport_size = viewport_size,
                .scene_commands = command_buffer,
                .save_manager = self.save_manager,
            };

            scene.descriptor.draw_ui(scene.self_ptr, &draw_ui_context);
        }

        zgui.backend.draw();

        //
        // swap
        //
        self.window.swapBuffers();
    }

    fn drawDebugUi(self: *SceneManager, dt: f32, command_buffer: *SceneCommandBuffer) void {
        zgui.setNextWindowPos(.{ .x = 10.0, .y = 10.0, .cond = .appearing });
        //zgui.setNextWindowSize(.{ .w = 200, .h = 600 });

        if (zgui.begin("Debug", .{})) {
            zgui.text("dt {d:.3}", .{dt});

            zgui.separator();

            if (self.active_scene) |scene| {
                zgui.text("scene: {s}", .{scene.descriptor.name});
            } else {
                zgui.text("scene: ---", .{});
            }

            var buffer: [128]u8 = undefined;

            for (self.all_scenes.items) |scene| {
                const s = std.fmt.bufPrintZ(&buffer, "switch to {s}", .{scene.name}) catch unreachable;

                if (zgui.button(s, .{})) {
                    command_buffer.change_scene = true;
                    command_buffer.new_scene_name = scene.name;
                }
            }

            zgui.separator();

            if (zgui.collapsingHeader("memory", .{})) {
                {
                    const stats = TrackingAllocator.getStats(self.allocator);
                    zgui.text("long term alloc:", .{});
                    zgui.text("allocations: {d}", .{stats.total_allocations});
                    zgui.text("cur memory used: {d}", .{stats.total_memory_used});
                    zgui.text("max memory used: {d}", .{stats.max_memory_used});
                }

                {
                    const stats = TrackingAllocator.getStats(self.per_frame_allocator);
                    zgui.text("per frame alloc:", .{});
                    zgui.text("allocations: {d}", .{stats.total_allocations});
                    zgui.text("cur memory used: {d}", .{stats.total_memory_used});
                    zgui.text("max memory used: {d}", .{stats.max_memory_used});
                }
            }

            zgui.end();
        }
    }

    fn getSceneByName(self: SceneManager, name: []const u8) ?SceneDescriptor {
        for (self.all_scenes.items) |scene| {
            if (std.mem.eql(u8, name, scene.name)) {
                return scene;
            }
        }

        std.log.err("scene not found: {s}", .{name});
        return null;
    }
};
