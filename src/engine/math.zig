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

    pub fn normalize(self: vec2) vec2 {
        const my_len = self.len();
        std.debug.assert(my_len > 0.001);

        return self.scale(1.0 / my_len);
    }

    pub fn dot(self: vec2, other: vec2) f32 {
        return self.x * other.x + self.y * other.y;
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

    pub fn turn90cw(self: vec2) vec2 {
        return vec2{
            .x = self.y,
            .y = -self.x,
        };
    }

    pub fn turn90ccw(self: vec2) vec2 {
        return vec2{
            .x = -self.y,
            .y = self.x,
        };
    }

    pub fn rotate(self: vec2, a: f32) vec2 {
        const sin = std.math.sin(a);
        const cos = std.math.cos(a);

        return vec2{
            .x = cos * self.x - sin * self.y,
            .y = sin * self.x + cos * self.y,
        };
    }

    // -pi .. 0 .. pi
    // 0 = right
    // pi/2 = up
    // -pi/2 = down
    pub fn angle(self: vec2) f32 {
        return std.math.atan2(self.y, self.x);
    }

    pub fn angleBetween(a: vec2, b: vec2) f32 {
        const an = a.normalize();
        const bn = b.normalize();
        const dotProduct = an.dot(bn);
        return std.math.acos(std.math.clamp(dotProduct, -1, 1));
    }

    pub fn lerp(a: vec2, b: vec2, t: f32) vec2 {
        return vec2{
            .x = std.math.lerp(a.x, b.x, t),
            .y = std.math.lerp(a.y, b.y, t),
        };
    }

    pub fn format(self: vec2, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        //_ = options;

        // pub const FormatOptions = struct {
        //     precision: ?usize = null,
        //     width: ?usize = null,
        //     alignment: Alignment = default_alignment,
        //     fill: u21 = default_fill_char,
        // };

        //try writer.print("({d},{d},{s},{any})", .{ self.x, self.y, fmt, options });
        //try writer.print("{d:_>[1].[2]}\n", .{ self.x, width, precision });
        //try writer.print("{d:[1].[2]}\n", .{ self.x, width, precision });

        if (options.precision != null) {
            try writer.print("({d:.[2]},{d:.[2]})", .{ self.x, self.y, options.precision.? });
        } else {
            try writer.print("({d},{d})", .{ self.x, self.y });
        }
    }
};

pub const rot2 = struct {
    const identity = rot2{
        .sin = 0,
        .cos = 1,
    };

    sin: f32,
    cos: f32,

    pub fn from_up_vector(up: vec2) rot2 {
        const length_sq = up.x * up.x + up.y * up.y;
        if (length_sq == 0) {
            return rot2.identity;
        }
        const inv_length = 1.0 / std.math.sqrt(length_sq);
        return rot2{
            .sin = -up.x * inv_length,
            .cos = up.y * inv_length,
        };
    }

    pub fn from_angle(angle: f32) rot2 {
        return rot2{
            .sin = std.math.sin(angle),
            .cos = std.math.cos(angle),
        };
    }

    pub fn from_b2(b2rot: b2.b2Rot) rot2 {
        return rot2{
            .sin = b2rot.s,
            .cos = b2rot.c,
        };
    }

    pub fn to_b2(self: rot2) b2.b2Rot {
        return b2.b2Rot{
            .s = self.sin,
            .c = self.cos,
        };
    }

    pub fn rotateLocalToWorld(self: rot2, local_vector: vec2) vec2 {
        const x = local_vector.x;
        const y = local_vector.y;

        return vec2{
            .x = self.cos * x - self.sin * y,
            .y = self.sin * x + self.cos * y,
        };
    }

    pub fn rotateWorldToLocal(self: rot2, world_vector: vec2) vec2 {
        const x = world_vector.x;
        const y = world_vector.y;

        return vec2{
            .x = self.cos * x + self.sin * y,
            .y = -self.sin * x + self.cos * y,
        };
    }
};

pub const Transform2 = struct {
    pos: vec2,
    rot: rot2,

    pub fn from_pos(pos: vec2) Transform2 {
        return Transform2{
            .pos = pos,
            .rot = rot2.identity,
        };
    }

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

        return self.rot.rotateWorldToLocal(v);

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

    pub fn initFloat(r: f32, g: f32, b: f32, a: f32) Color {
        return Color{
            .r = floatToByte(r),
            .g = floatToByte(g),
            .b = floatToByte(b),
            .a = floatToByte(a),
        };
    }

    fn floatToByte(v: f32) u8 {
        const a: f32 = std.math.clamp(v * 255.0, 0.0, 255.0);
        const b: u8 = @intFromFloat(a);
        return b;
    }
};
