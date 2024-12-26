const std = @import("std");

const zbox = @import("zbox");
const b2 = zbox.API;

pub const vec2 = packed struct {
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

    pub fn scale(self: vec2, factor: f32) vec2 {
        return vec2{
            .x = self.x * factor,
            .y = self.y * factor,
        };
    }

    pub fn mulPairwise(self: vec2, other: vec2) vec2 {
        return vec2{
            .x = self.x * other.x,
            .y = self.y * other.y,
        };
    }

    pub fn len(self: vec2) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn dist(a: vec2, b: vec2) f32 {
        return std.math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
    }
};

pub const rot2 = struct {
    angle: f32,
    sin: f32,
    cos: f32,

    pub fn from_angle(angle: f32) rot2 {
        return rot2{
            .angle = angle,
            .sin = std.math.sin(angle),
            .cos = std.math.cos(angle),
        };
    }

    pub fn from_b2(b2rot: b2.b2Rot) rot2 {
        return rot2{
            .angle = 0, // TODO
            .sin = b2rot.s,
            .cos = b2rot.c,
        };
    }

    pub fn rotateLocalToWorld(self: rot2, local_vector: vec2) vec2 {
        const x = local_vector.x;
        const y = local_vector.y;

        return vec2{
            .x = self.cos * x - self.sin * y,
            .y = self.sin * x + self.cos * y,
        };

        //return B2_LITERAL( b2Vec2 ){ q.c * v.x - q.s * v.y, q.s * v.x + q.c * v.y };
    }

    pub fn rotateWorldToLocal(self: rot2, world_vector: vec2) vec2 {
        const x = world_vector.x;
        const y = world_vector.y;

        return vec2{
            .x = self.cos * x + self.sin * y,
            .y = -self.sin * x + self.cos * y,
        };

        //return B2_LITERAL( b2Vec2 ){ q.c * v.x + q.s * v.y, -q.s * v.x + q.c * v.y };
    }
};

pub const Transform2 = struct {
    pos: vec2,
    rot: rot2,

    pub fn from_b2(b2transform: b2.b2Transform) Transform2 {
        const p = vec2.from_b2(b2transform.p);
        const q = rot2.from_b2(b2transform.q);

        return Transform2{
            .pos = p,
            .rot = q,
        };
    }

    pub fn rotateLocalToWorld(self: Transform2, local_vector: vec2) vec2 {
        return self.rot.rotateLocalToWorld(local_vector);
    }

    pub fn rotateWorldToLocal(self: Transform2, world_vector: vec2) vec2 {
        return self.rot.rotateWorldToLocal(world_vector);
    }

    pub fn transformLocalToWorld(self: Transform2, local_position: vec2) vec2 {
        //
        return self.rot.rotateLocalToWorld(local_position).add(self.pos);

        // float x = ( t.q.c * p.x - t.q.s * p.y ) + t.p.x;
        // float y = ( t.q.s * p.x + t.q.c * p.y ) + t.p.y;
    }

    pub fn transformWorldToLocal(self: Transform2, world_position: vec2) vec2 {
        //
        const v = world_position.sub(self.pos);

        self.rot.rotateWorldToLocal(v);

        // float vx = p.x - t.p.x;
        // float vy = p.y - t.p.y;
        // return B2_LITERAL( b2Vec2 ){ t.q.c * vx + t.q.s * vy, -t.q.s * vx + t.q.c * vy };
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
    pub const black = (Color){ .r = 0, .g = 0, .b = 0, .a = 255 };

    pub const gray1 = (Color){ .r = 16, .g = 16, .b = 16, .a = 255 };
    pub const gray2 = (Color){ .r = 32, .g = 32, .b = 32, .a = 255 };
    pub const gray3 = (Color){ .r = 64, .g = 64, .b = 64, .a = 255 };
    pub const gray4 = (Color){ .r = 96, .g = 96, .b = 96, .a = 255 };

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }
};
