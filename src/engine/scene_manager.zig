const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zgui = @import("zgui");

const Window = @import("window.zig");
const InputState = @import("input_state.zig");
const ContentManager = @import("content_manager.zig").ContentManager;

pub const Scene = struct {
    name: []const u8,
    load: *const fn (context: *const LoadContext) anyerror!*anyopaque = load_default, // TODO keep defaults or remove?
    unload: *const fn (context: *const UnloadContext) void = unload_default,
    update: *const fn (context: *const UpdateContext) void = update_default,
    render: *const fn (context: *const RenderContext) void = render_default,
    draw_ui: *const fn (context: *const DrawUiContext) void = draw_ui_default,

    const DummyData = struct {
        a: i32,
    };

    fn load_default(context: *const LoadContext) !*anyopaque {
        var data = try context.allocator.create(DummyData);
        data.a = 123;
        return @ptrCast(data);
    }

    fn unload_default(context: *const UnloadContext) void {
        const data: *DummyData = @ptrCast(@alignCast(context.scene_data));
        std.debug.assert(data.a == 123);
        context.allocator.destroy(data);
    }

    fn update_default(context: *const UpdateContext) void {
        _ = context;
    }

    fn render_default(context: *const RenderContext) void {
        _ = context;
    }

    fn draw_ui_default(context: *const DrawUiContext) void {
        _ = context;
    }
};

// ctx: *anyopaque,
// const self: *Self = @ptrCast(@alignCast(ctx));

pub const LoadContext = struct {
    allocator: std.mem.Allocator,
    content_manager: *ContentManager,
};

pub const UnloadContext = struct {
    allocator: std.mem.Allocator,
    content_manager: *ContentManager,
    scene_data: *anyopaque,
};

pub const UpdateContext = struct {
    dt: f32,
    input_state: *InputState,
    viewport_size: [2]i32,
    scene_commands: *SceneCommandBuffer,
    scene_data: *anyopaque,
};

pub const RenderContext = struct {
    dt: f32,
    //renderer?
    viewport_size: [2]i32,
    scene_data: *anyopaque,
};

pub const DrawUiContext = struct {
    dt: f32,
    viewport_size: [2]i32,
    scene_commands: *SceneCommandBuffer,
    scene_data: *anyopaque,
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
    window: *Window,
    content_manager: *ContentManager,

    // scenes
    all_scenes: std.ArrayList(Scene),
    current_scene: ?*Scene,
    current_scene_data: *anyopaque, // TODO maybe move to scene struct?

    pub fn create(
        allocator: std.mem.Allocator,
        window: *Window,
        content_manager: *ContentManager,
    ) !SceneManager {
        return SceneManager{
            .allocator = allocator,
            .window = window,
            .content_manager = content_manager,

            .all_scenes = std.ArrayList(Scene).init(allocator),
            .current_scene = null,
            .current_scene_data = undefined,
        };
    }

    pub fn destroy(self: *SceneManager) void {
        self.unloadCurrentScene();

        self.all_scenes.deinit();
    }

    pub fn registerScene(self: *SceneManager, scene: Scene) !void {
        std.log.info("register new scene: {s}", .{scene.name});
        try self.all_scenes.append(scene);
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

                self.current_scene = null;
                self.current_scene_data = undefined;
            };
        }
    }

    fn unloadCurrentScene(self: *SceneManager) void {
        if (self.current_scene) |scene| {
            const unload_context = UnloadContext{
                .allocator = self.allocator,
                .content_manager = self.content_manager,
                .scene_data = self.current_scene_data,
            };

            std.log.info("unloading scene: {s}", .{scene.name});
            scene.unload(&unload_context);
        }
    }

    fn loadNewScene(self: *SceneManager, new_scene: *Scene) !void {
        const load_context = LoadContext{
            .allocator = self.allocator,
            .content_manager = self.content_manager,
        };

        std.log.info("loading scene: {s}", .{new_scene.name});
        self.current_scene_data = try new_scene.load(&load_context);
        self.current_scene = new_scene; // only assign on success
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

        //
        // update
        //
        var input_state: InputState = undefined;
        self.window.processEvents(&input_state);

        const viewport_size = self.window.viewport_size; // get after events are processed

        if (input_state.getKeyState(.left_control) and input_state.consumeKeyDownEvent(.escape)) {
            self.window.setShouldClose(true);
        }

        if (self.current_scene) |scene| {
            const update_context = UpdateContext{
                .dt = dt,
                .input_state = &input_state,
                .viewport_size = viewport_size,
                .scene_commands = command_buffer,
                .scene_data = self.current_scene_data,
            };

            scene.update(&update_context);
        }

        //
        // clear and render
        //
        gl.clearColor(0.1, 0.1, 0.1, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        if (self.current_scene) |scene| {
            const render_context = RenderContext{
                .dt = dt,
                .viewport_size = viewport_size,
                .scene_data = self.current_scene_data,
            };

            scene.render(&render_context);
        }

        //
        // render ui
        //
        zgui.backend.newFrame(
            @intCast(self.window.viewport_size[0]),
            @intCast(self.window.viewport_size[1]),
        );

        self.drawDebugUi(dt, command_buffer);

        if (self.current_scene) |scene| {
            const draw_ui_context = DrawUiContext{
                .dt = dt,
                .viewport_size = viewport_size,
                .scene_commands = command_buffer,
                .scene_data = self.current_scene_data,
            };

            scene.draw_ui(&draw_ui_context);
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

            if (self.current_scene) |scene| {
                zgui.text("scene: {s}", .{scene.name});
            } else {
                zgui.text("scene: ---", .{});
            }

            for (self.all_scenes.items) |scene| {
                const s: [:0]u8 = std.fmt.allocPrintZ(self.allocator, "switch to {s}", .{scene.name}) catch unreachable;

                defer self.allocator.free(s);

                if (zgui.button(s, .{})) {
                    command_buffer.change_scene = true;
                    command_buffer.new_scene_name = scene.name;
                }
            }

            zgui.end();
        }
    }

    fn getSceneByName(self: SceneManager, name: []const u8) ?*Scene {
        for (self.all_scenes.items) |*scene| {
            if (std.mem.eql(u8, name, scene.name)) {
                return scene;
            }
        }

        std.log.err("scene not found: {s}", .{name});
        return null;
    }
};
