const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zgui = @import("zgui");

const InputState = @import("input_state.zig");
const Window = @This();

glfw_window: *glfw.Window,
viewport_size: [2]i32,
input_state: InputState = InputState{},

pub fn init(self: *Window) !void {
    std.log.info("sizeof inputstate: {d}", .{@sizeOf(InputState)});
    std.log.info("sizeof window: {d}", .{@sizeOf(Window)});

    if (glfw.Monitor.getAll()) |all_monitors| {
        for (all_monitors) |monitor| {
            const name = try monitor.getName();
            const pos = monitor.getPos();

            std.log.info("monitor {s} pos {d} {d}", .{ name, pos[0], pos[1] });

            const mode = try monitor.getVideoMode();

            std.log.info("  mode {d}x{d} @ {d} Hz bits {d} {d} {d}", .{
                mode.width,
                mode.height,
                mode.refresh_rate,
                mode.red_bits,
                mode.green_bits,
                mode.blue_bits,
            });

            const modes = try monitor.getVideoModes();

            for (modes) |m| {
                std.log.info("  other mode {d}x{d} @ {d} Hz", .{
                    m.width,
                    m.height,
                    m.refresh_rate,
                });
            }
        }
    }

    // 2256x1504
    //const size = [2]i32{ 2256 / 2, 1504 / 2 };
    const size = [2]i32{ 1920, 1080 };

    const gl_major = 4;
    const gl_minor = 0;

    glfw.windowHintTyped(.context_version_major, gl_major);
    glfw.windowHintTyped(.context_version_minor, gl_minor);
    glfw.windowHintTyped(.opengl_profile, .opengl_core_profile);
    glfw.windowHintTyped(.opengl_forward_compat, true);
    glfw.windowHintTyped(.client_api, .opengl_api);
    glfw.windowHintTyped(.doublebuffer, true);

    const glfw_window = try glfw.Window.create(size[0], size[1], "mycatgame999", null);

    const content_scale = glfw_window.getContentScale();
    std.log.info("content_scale {d} {d}", .{ content_scale[0], content_scale[1] });

    glfw.makeContextCurrent(glfw_window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    glfw_window.setUserPointer(self);

    _ = glfw_window.setFramebufferSizeCallback(framebufferSizeCallback);
    _ = glfw_window.setCursorPosCallback(cursorPosCallback);
    _ = glfw_window.setMouseButtonCallback(mouseButtonCallback);
    _ = glfw_window.setKeyCallback(keyCallback);
    _ = glfw_window.setScrollCallback(scrollCallback);

    self.glfw_window = glfw_window;
    self.viewport_size = glfw_window.getFramebufferSize();
}

pub fn destroy(self: *Window) void {
    self.glfw_window.destroy();
}

pub fn getShouldClose(self: Window) bool {
    return self.glfw_window.shouldClose();
}

pub fn setShouldClose(self: *Window, should_close: bool) void {
    self.glfw_window.setShouldClose(should_close);
}

pub fn processEvents(self: *Window, input_state_copy: *InputState) void {
    self.input_state.clear();

    // this will call the callbacks
    glfw.pollEvents();

    if (zgui.io.getWantCaptureMouse()) {
        self.input_state.removeMouseInput();
    }
    if (zgui.io.getWantCaptureKeyboard()) {
        self.input_state.removeKeyboardInput();
    }

    self.input_state.detectEvents();

    self.input_state.copyTo(input_state_copy);
}

pub fn swapBuffers(self: *Window) void {
    self.glfw_window.swapBuffers();
}

fn framebufferSizeCallback(glfw_window: *glfw.Window, width: i32, height: i32) callconv(.C) void {
    //std.log.debug("resize {} {}", .{ width, height });

    if (glfw_window.getUserPointer(Window)) |window| {
        window.viewport_size = [2]i32{ width, height };
    }

    gl.viewport(0, 0, width, height);
}

fn cursorPosCallback(glfw_window: *glfw.Window, xpos: f64, ypos: f64) callconv(.c) void {
    //std.log.debug("cursor pos {d} {d}", .{ xpos, ypos });

    if (glfw_window.getUserPointer(Window)) |window| {
        window.input_state.mouse_position_screen = [2]f32{
            @floatCast(xpos),
            @floatCast(ypos),
        };
    }
}

fn mouseButtonCallback(glfw_window: *glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = mods;

    //std.log.debug("mouse button {?} {?} {?}", .{ button, action, mods });

    if (glfw_window.getUserPointer(Window)) |window| {
        if (InputState.getIndexFromMouseButton(button)) |index| {
            window.input_state.mouse_button_states[index] = action != .release;
        }
    }
}

fn keyCallback(glfw_window: *glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) callconv(.c) void {
    _ = scancode;
    _ = mods;

    //std.log.debug("key {?} {d} {?} {?}", .{ key, scancode, action, mods });

    if (glfw_window.getUserPointer(Window)) |window| {
        if (InputState.getIndexFromKey(key)) |index| {
            window.input_state.key_states[index] = action != .release;
        }
    }
}

fn scrollCallback(glfw_window: *glfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    _ = xoffset;

    //std.log.debug("scroll {d} {d}", .{ xoffset, yoffset });

    if (glfw_window.getUserPointer(Window)) |window| {
        window.input_state.mouse_scroll = @floatCast(yoffset);
    }
}
