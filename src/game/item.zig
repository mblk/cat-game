const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Transform2 = engine.Transform2;

const b2 = @import("zbox").API;

pub const ItemType = enum {
    Food,
    Debris,
};

pub const ItemShape = union(enum) {
    Circle: f32, // radius
    Rect: vec2, // width, height
};

pub const ItemDef = struct {
    const Self = @This();

    id: []const u8,
    shape: ItemShape,
    //density: f32,
    //friction: f32,
    data: union(ItemType) {
        Food: struct {
            kcal: f32,
        },
        Debris: struct {
            foo: i32,
        },
    },

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("ItemDef(id={s})", .{self.id}); // TODO
    }

    pub fn getAll(allocator: std.mem.Allocator) ![]ItemDef {
        var result = std.ArrayList(ItemDef).init(allocator);
        defer result.deinit();

        try result.append(ItemDef{
            .id = "treat_small_1",
            .shape = .{
                .Circle = 0.2, // radius
            },
            .data = .{
                .Food = .{
                    .kcal = 100,
                },
            },
        });

        try result.append(ItemDef{
            .id = "treat_big_1",
            .shape = .{
                .Rect = vec2.init(0.5, 0.5),
            },
            .data = .{
                .Food = .{
                    .kcal = 1000,
                },
            },
        });

        try result.append(ItemDef{
            .id = "debris_1",
            .shape = .{
                .Rect = vec2.init(0.4, 0.2),
            },
            .data = .{
                .Debris = .{
                    .foo = 1,
                },
            },
        });

        return result.toOwnedSlice();
    }
};

pub const Item = struct {
    const Self = @This();

    alive: bool,
    def: *const ItemDef,
    body_id: b2.b2BodyId,

    pub fn init(self: *Self, world_id: b2.b2WorldId, def: *const ItemDef, transform: Transform2) void {
        std.log.info("Item init", .{});

        const body_id = createBody(world_id, def, transform);

        self.* = Item{
            .alive = true,
            .def = def,
            .body_id = body_id,
        };
    }

    fn createBody(world_id: b2.b2WorldId, def: *const ItemDef, transform: Transform2) b2.b2BodyId {
        switch (def.data) {
            .Food => |food_data| {
                //
                _ = food_data;
            },
            .Debris => |debris_data| {
                //
                _ = debris_data;
            },
        }

        // body
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position = transform.pos.to_b2();
        body_def.rotation = transform.rot.to_b2();
        const body_id = b2.b2CreateBody(world_id, &body_def);

        // shape
        var shape_def = b2.b2DefaultShapeDef();
        shape_def.density = 1.0;
        shape_def.friction = 0.3;

        switch (def.shape) {
            .Circle => |radius| {
                const b2_circle: b2.b2Circle = .{
                    .center = b2.b2Vec2_zero,
                    .radius = radius,
                };

                _ = b2.b2CreateCircleShape(body_id, &shape_def, &b2_circle);
            },
            .Rect => |size| {
                const b2_box = b2.b2MakeBox(size.x * 0.5, size.y * 0.5);

                _ = b2.b2CreatePolygonShape(body_id, &shape_def, &b2_box);
            },
        }

        return body_id;
    }

    pub fn deinit(self: *Self) void {
        std.log.info("Item deinit", .{});
        std.debug.assert(self.alive);

        b2.b2DestroyBody(self.body_id);
        self.alive = false;
    }

    pub fn getTransform(self: *const Self) Transform2 {
        std.debug.assert(self.alive);

        const t = b2.b2Body_GetTransform(self.body_id);
        return Transform2.from_b2(t);
    }

    pub fn setTransform(self: Self, transform: Transform2) void {
        std.debug.assert(self.alive);

        b2.b2Body_SetTransform(
            self.body_id,
            transform.pos.to_b2(),
            transform.rot.to_b2(),
        );

        b2.b2Body_SetAwake(self.body_id, true);
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Item(def={s}, alive={any})", .{ self.def.id, self.alive }); // TODO
    }
};
