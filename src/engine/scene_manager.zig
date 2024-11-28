const std = @import("std");

const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zgui = @import("zgui");

const Window = @import("window.zig");
const InputState = @import("input_state.zig");

const SceneManager = @This();
//{
allocator: std.mem.Allocator,
window: *Window,
all_scenes: std.ArrayList(Scene),
current_scene: ?*Scene,
current_scene_data: *void, // TODO maybe move to scene struct?
//}

pub const Scene = struct {
    name: []const u8,
    load: *const fn (context: *const LoadContext) *void,
    unload: *const fn (context: *const UnloadContext) void,
    update: *const fn (context: *const UpdateContext) void,
    render: *const fn (context: *const RenderContext) void,
    draw_ui: *const fn (context: *const DrawUiContext) void,
};

pub const LoadContext = struct {
    allocator: std.mem.Allocator,
};

pub const UnloadContext = struct {
    allocator: std.mem.Allocator,
    scene_data: *void,
};

pub const UpdateContext = struct {
    dt: f32,
    input_state: *InputState,
    scene_commands: *SceneCommandBuffer,
    scene_data: *void,
};

pub const RenderContext = struct {
    dt: f32,
    //renderer
    scene_data: *void,
};

pub const DrawUiContext = struct {
    dt: f32,
    scene_commands: *SceneCommandBuffer,
    scene_data: *void,
};

pub const SceneCommandBuffer = struct {
    exit: bool,
    change_scene: bool,
    new_scene_name: []const u8,
};

pub fn create(
    allocator: std.mem.Allocator,
    window: *Window,
) !*SceneManager {
    var scene_manager = try allocator.create(SceneManager);

    scene_manager.allocator = allocator;
    scene_manager.window = window;
    scene_manager.all_scenes = std.ArrayList(Scene).init(allocator);
    scene_manager.current_scene = null;
    scene_manager.current_scene_data = undefined;

    return scene_manager;
}

pub fn destroy(self: *SceneManager) void {
    self.unloadCurrentScene();

    self.all_scenes.deinit();

    // TODO not sure if this is allowed
    self.allocator.destroy(self);
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
        self.loadNewScene(new_scene);
    }
}

fn unloadCurrentScene(self: *SceneManager) void {
    if (self.current_scene) |scene| {
        const unload_context = UnloadContext{
            .allocator = self.allocator,
            .scene_data = self.current_scene_data,
        };

        std.log.info("unloading scene: {s}", .{scene.name});
        scene.unload(&unload_context);
    }

    self.current_scene = null;
    self.current_scene_data = undefined;
}

fn loadNewScene(self: *SceneManager, new_scene: *Scene) void {
    self.current_scene = new_scene;

    const load_context = LoadContext{
        .allocator = self.allocator,
    };

    std.log.info("loading scene: {s}", .{new_scene.name});
    self.current_scene_data = new_scene.load(&load_context);
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

    if (input_state.getKeyState(.left_control) and input_state.consumeKeyDownEvent(.escape)) {
        self.window.setShouldClose(true);
    }

    if (self.current_scene) |scene| {
        const update_context = UpdateContext{
            .dt = dt,
            .input_state = &input_state,
            .scene_commands = command_buffer,
            .scene_data = self.current_scene_data,
        };

        scene.update(&update_context);
    }

    //
    // clear
    //
    gl.clearColor(0.1, 0.1, 0.1, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT);

    if (self.current_scene) |scene| {
        const render_context = RenderContext{
            .dt = dt,
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

    zgui.setNextWindowPos(.{ .x = 10.0, .y = 10.0, .cond = .appearing });
    //zgui.setNextWindowSize(.{ .w = 200, .h = 600 });
    if (zgui.begin("Debug", .{})) {
        zgui.text("dt {d:.3}", .{dt});

        if (self.current_scene) |scene| {
            zgui.text("scene: {s}", .{scene.name});
        } else {
            zgui.text("scene: ---", .{});
        }

        zgui.end();
    }

    if (self.current_scene) |scene| {
        const draw_ui_context = DrawUiContext{
            .dt = dt,
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

fn getSceneByName(self: SceneManager, name: []const u8) ?*Scene {
    for (self.all_scenes.items) |*scene| {
        if (std.mem.eql(u8, name, scene.name)) {
            return scene;
        }
    }

    std.log.err("scene not found: {s}", .{name});
    return null;
}
