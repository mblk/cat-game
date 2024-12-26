const std = @import("std");
const glfw = @import("zglfw");

const InputState = @This();
pub const Key = glfw.Key;
pub const MouseButton = glfw.MouseButton;

// keyboard
key_states: [512]bool = [_]bool{false} ** 512,
prev_key_states: [512]bool = [_]bool{false} ** 512, // TODO pack more effeciently?

key_down_events: [512]bool = [_]bool{false} ** 512,
key_up_events: [512]bool = [_]bool{false} ** 512,

// mouse
mouse_position_screen: [2]f32 = [2]f32{ 0.0, 0.0 },
mouse_scroll: f32 = 0.0,

mouse_button_states: [8]bool = [_]bool{false} ** 8,
prev_mouse_button_states: [8]bool = [_]bool{false} ** 8,

mouse_button_down_events: [8]bool = [_]bool{false} ** 8,
mouse_button_up_events: [8]bool = [_]bool{false} ** 8,

pub fn clear(self: *InputState) void {
    self.mouse_scroll = 0.0;
    self.prev_key_states = self.key_states;
    self.prev_mouse_button_states = self.mouse_button_states;

    // Alternative:
    // @memcpy(&self.prev_key_states, &self.key_states);
    // @memcpy(&self.prev_mouse_button_states, &self.mouse_button_states);
}

pub fn removeMouseInput(self: *InputState) void {
    self.mouse_scroll = 0.0;
    self.mouse_button_states = [_]bool{false} ** 8;
}

pub fn removeKeyboardInput(self: *InputState) void {
    self.key_states = [_]bool{false} ** 512;
}

pub fn detectEvents(self: *InputState) void { // TODO hardcoded values
    {
        var i: usize = 0;
        while (i < 512) : (i += 1) {
            self.key_down_events[i] = self.key_states[i] and !self.prev_key_states[i];
            self.key_up_events[i] = !self.key_states[i] and self.prev_key_states[i];
        }
    }
    {
        var i: usize = 0;
        while (i < 8) : (i += 1) {
            self.mouse_button_down_events[i] = self.mouse_button_states[i] and !self.prev_mouse_button_states[i];
            self.mouse_button_up_events[i] = !self.mouse_button_states[i] and self.prev_mouse_button_states[i];
        }
    }
}

pub fn copyTo(self: InputState, copy: *InputState) void {
    copy.* = self;

    // Alternative:
    //const dest: [*]u8 = @ptrCast(copy);
    //const src: [*]const u8 = @ptrCast(&self);
    //@memcpy(dest[0..@sizeOf(InputState)], src);
    // or
    //@memcpy(dest, src[0..@sizeOf(InputState)]);
}

pub fn consumeMouseScroll(self: *InputState) ?i32 {
    if (@abs(self.mouse_scroll) > 0.1) {
        const scroll = self.mouse_scroll;
        self.mouse_scroll = 0.0;

        if (scroll > 0) {
            return 1;
        } else {
            return -1;
        }
    }

    return null;
}

pub fn getKeyState(self: *InputState, key: Key) bool {
    if (getIndexFromKey(key)) |index| {
        return self.key_states[index];
    }
    return false;
}

// pub fn consumeKeyState(self: *InputState, key: Key) bool {
//     if (getIndexFromKey(key)) |index| {
//         const state = self.key_states[index];
//         self.key_states[index] = false;
//         return state;
//     }
//     return false;
// }

pub fn consumeKeyDownEvent(self: *InputState, key: Key) bool {
    if (getIndexFromKey(key)) |index| {
        const event = self.key_down_events[index];
        self.key_down_events[index] = false;
        return event;
    }
    return false;
}

pub fn consumeKeyUpEvent(self: *InputState, key: Key) bool {
    if (getIndexFromKey(key)) |index| {
        const event = self.key_up_events[index];
        self.key_up_events[index] = false;
        return event;
    }
    return false;
}

pub fn consumeSingleKeyDownEvent(self: *InputState) ?Key {
    var num_key_down_events: usize = 0;
    var key_index: usize = 0;

    for (0..512) |i| {
        if (self.key_down_events[i]) {
            num_key_down_events += 1;
            key_index = i;
        }
    }

    if (num_key_down_events != 1) {
        return null;
    }

    self.key_down_events[key_index] = false;

    return getKeyFromIndex(key_index);
}

pub fn getMouseButtonState(self: *InputState, button: MouseButton) bool {
    if (getIndexFromMouseButton(button)) |index| {
        return self.mouse_button_states[index];
    }
    return false;
}

// pub fn consumeMouseButtonState(self: *InputState, button: MouseButton) bool {
//     if (getIndexFromMouseButton(button)) |index| {
//         const state = self.mouse_button_states[index];
//         self.mouse_button_states[index] = false;
//         return state;
//     }
//     return false;
// }

pub fn consumeMouseButtonDownEvent(self: *InputState, button: MouseButton) bool {
    if (getIndexFromMouseButton(button)) |index| {
        const event = self.mouse_button_down_events[index];
        self.mouse_button_down_events[index] = false;
        return event;
    }
    return false;
}

pub fn consumeMouseButtonUpEvent(self: *InputState, button: MouseButton) bool {
    if (getIndexFromMouseButton(button)) |index| {
        const event = self.mouse_button_up_events[index];
        self.mouse_button_up_events[index] = false;
        return event;
    }
    return false;
}

pub fn getIndexFromKey(key: glfw.Key) ?usize {
    const index: i32 = @intFromEnum(key);

    if (index < 0 or index >= 512) // XXX
        return null;

    const idx: usize = @intCast(index);
    return idx;
}

pub fn getKeyFromIndex(index: usize) ?Key {
    if (index >= 512)
        return null;

    const value: Key = @enumFromInt(index);
    return value;
}

pub fn getIndexFromMouseButton(button: glfw.MouseButton) ?usize {
    const index: i32 = @intFromEnum(button);

    if (index < 0 or index >= 8) // XXX
        return null;

    const idx: usize = @intCast(index);
    return idx;
}
