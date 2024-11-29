const std = @import("std");

pub const vec2 = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) vec2 {
        return vec2{
            .x = x,
            .y = y,
        };
    }

    pub fn get_arr(self: vec2) [2]f32 {
        return [2]f32{
            self.x, self.y,
        };
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const red = (Color){
        .r = 255,
        .g = 0,
        .b = 0,
        .a = 255,
    };

    pub const green = (Color){
        .r = 0,
        .g = 255,
        .b = 0,
        .a = 255,
    };

    pub const blue = (Color){
        .r = 0,
        .g = 0,
        .b = 255,
        .a = 255,
    };

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }
};
