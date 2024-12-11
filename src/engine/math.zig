const std = @import("std");

const zbox = @import("zbox");
const b2 = zbox.API;

pub const vec2 = struct {
    x: f32,
    y: f32,

    pub const zero = init(0, 0);

    pub fn init(x: f32, y: f32) vec2 {
        return vec2{
            .x = x,
            .y = y,
        };
    }

    pub fn get_array(self: vec2) [2]f32 {
        return [2]f32{
            self.x, self.y,
        };
    }

    pub fn to_b2(self: vec2) b2.b2Vec2 {
        return b2.b2Vec2{
            .x = self.x,
            .y = self.y,
        };
    }

    pub fn from_b2(other: b2.b2Vec2) vec2 {
        return vec2{
            .x = other.x,
            .y = other.y,
        };
    }

    pub fn add(self: vec2, other: vec2) vec2 {
        return vec2{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn sub(self: vec2, other: vec2) vec2 {
        return vec2{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    pub fn neg(self: vec2) vec2 {
        return vec2{
            .x = -self.x,
            .y = -self.y,
        };
    }

    pub fn dist(a: vec2, b: vec2) f32 {
        return std.math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const red = (Color){ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = (Color){ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = (Color){ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const white = (Color){ .r = 255, .g = 255, .b = 255, .a = 255 };

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }
};
