const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zgui = @import("zgui");

const Window = @import("window.zig");
const InputState = @import("input_state.zig");
const ContentManager = @import("content_manager.zig").ContentManager;
const SaveManager = @import("save_manager.zig").SaveManager;

const TrackingAllocator = @import("../utils/tracking_allocator.zig").TrackingAllocator;

pub const SceneDescriptor = struct {
    // desc
    id: SceneId,
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

// TODO so wie bei den Tools?
// pub const SceneDeps = struct {
//     //
// };

pub const LoadContext = struct {
    allocator: std.mem.Allocator,
    per_frame_allocator: std.mem.Allocator,
    content_manager: *ContentManager,
    save_manager: *SaveManager,
    scene_args: SceneArgs,
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
    new_scene: ?SceneArgs,
};

pub const SceneId = enum {
    Menu,
    LevelSelect,
    Game,

    Renderer2DTest,
    TestScene1,
    TestScene2,
};

pub const SceneArgs = union(SceneId) {
    Menu: void,
    LevelSelect: void,
    Game: struct {
        edit_mode: bool,
        level_name: ?[]const u8,
        level_name_alloc: ?std.mem.Allocator, // level_name must be freed by target-scene if this is set
    },

    Renderer2DTest: void,
    TestScene1: void,
    TestScene2: void,
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

    // temp state/settings
    render_wireframe: bool = false,
    render_clear_color: [3]f32 = [_]f32{ 0, 0, 0 },

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

        if (self.getSceneById(scene_descriptor.id) != null) {
            std.log.err("scene already registered: {any}", .{scene_descriptor.id});
            std.debug.assert(false);
            return;
        }

        try self.all_scenes.append(scene_descriptor);
    }

    pub fn switchScene(self: *SceneManager, new_scene_args: SceneArgs) void {
        std.log.info("switch scene: {any}", .{new_scene_args});

        // unload current scene
        self.unloadCurrentScene();

        // load new scene
        self.loadNewScene(new_scene_args);
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

    fn loadNewScene(self: *SceneManager, new_scene_args: SceneArgs) void {
        const new_scene_id: SceneId = std.meta.activeTag(new_scene_args);

        if (self.getSceneById(new_scene_id)) |new_scene_desc| {
            const load_context = LoadContext{
                .allocator = self.allocator,
                .per_frame_allocator = self.per_frame_allocator,
                .content_manager = self.content_manager,
                .save_manager = self.save_manager,
                .scene_args = new_scene_args,
            };

            const self_ptr = new_scene_desc.load(&load_context) catch |e| {
                std.log.err("failed to load scene: {any}", .{e});

                self.active_scene = null;
                return;
            };

            self.active_scene = Scene{
                .descriptor = new_scene_desc,
                .self_ptr = self_ptr,
            };
        } else {
            std.log.err("scene not found: {any}", .{new_scene_id});
        }
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
                .new_scene = null,
            };

            // one frame
            self.frame(dt, &scene_command_buffer);

            // execute scene commands
            if (scene_command_buffer.exit) {
                self.window.setShouldClose(true);
            }
            //if (scene_command_buffer.change_scene) {
            if (scene_command_buffer.new_scene) |new_scene| {
                self.switchScene(new_scene);
            }
        }
    }

    fn frame(self: *SceneManager, dt: f32, command_buffer: *SceneCommandBuffer) void {
        //std.debug.print("== new frame ==\n", .{});

        //
        // update
        //

        self.content_manager.update();

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
        gl.clearColor(self.render_clear_color[0], self.render_clear_color[1], self.render_clear_color[2], 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        if (self.render_wireframe) {
            gl.polygonMode(gl.FRONT_AND_BACK, gl.LINE);
        } else {
            gl.polygonMode(gl.FRONT_AND_BACK, gl.FILL);
        }

        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LESS);

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
        zgui.setNextWindowPos(.{ .x = 10.0, .y = 50.0, .cond = .appearing });
        //zgui.setNextWindowSize(.{ .w = 200, .h = 600 });

        _ = command_buffer;

        if (zgui.begin("Debug", .{})) {
            zgui.text("dt {d:.3} fps {d:.1}", .{ dt, 1.0 / dt });

            if (zgui.collapsingHeader("scenes", .{})) {
                if (self.active_scene) |scene| {
                    zgui.text("scene: {s}", .{scene.descriptor.name});
                } else {
                    zgui.text("scene: ---", .{});
                }

                var buffer: [128]u8 = undefined;

                for (self.all_scenes.items) |scene| {
                    const s = std.fmt.bufPrintZ(&buffer, "switch to {s}", .{scene.name}) catch unreachable;

                    if (zgui.button(s, .{})) {
                        // command_buffer.change_scene = true;
                        // command_buffer.new_scene_name = scene.name;
                    }
                }
            }

            if (zgui.collapsingHeader("render", .{})) {
                if (zgui.radioButton("Wireframe", .{ .active = self.render_wireframe })) {
                    self.render_wireframe = true;
                }
                if (zgui.radioButton("Fill", .{ .active = !self.render_wireframe })) {
                    self.render_wireframe = false;
                }

                _ = zgui.colorEdit3("Clear color", .{
                    .col = &self.render_clear_color,
                });
            }

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

            // if (zgui.collapsingHeader("shaders", .{})) {
            //     for (self.content_manager.shaders.items) |*shader| {
            //         zgui.text("ogl id={d} modified={any}", .{ shader.id, shader.modified });
            //     }
            // }
        }
        zgui.end();
    }

    // fn getSceneByName(self: SceneManager, name: []const u8) ?SceneDescriptor {
    //     for (self.all_scenes.items) |scene| {
    //         if (std.mem.eql(u8, name, scene.name)) {
    //             return scene;
    //         }
    //     }

    //     std.log.err("scene not found: {s}", .{name});
    //     return null;
    // }

    fn getSceneById(self: SceneManager, id: SceneId) ?SceneDescriptor {
        for (self.all_scenes.items) |scene| {
            if (scene.id == id) {
                return scene;
            }
        }

        //std.log.err("scene not found: {any}", .{id});
        return null;
    }
};
