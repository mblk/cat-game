const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;

const zbox = @import("zbox");
const b2 = zbox.API;

const physics = @import("physics.zig");

pub const GroundSegmentShape = union(enum) {
    const Self = @This();

    Box: struct {
        width: f32,
        height: f32,
        angle: f32,
    },
    Circle: struct {
        radius: f32,
    },
    Polygon: struct {
        points: []vec2,
    },

    pub fn clone(self: Self, allocator: std.mem.Allocator) Self {
        switch (self) {
            .Box => return self,
            .Circle => return self,
            .Polygon => |d| {
                return .{
                    .Polygon = .{
                        .points = allocator.dupe(vec2, d.points) catch unreachable,
                    },
                };
            },
        }
    }
};

pub const GroundSegment = struct {
    const Self = @This();

    // deps
    world_allocator: std.mem.Allocator,
    world_id: b2.b2WorldId,

    // config
    position: vec2,
    shape: GroundSegmentShape,

    // state
    dirty: bool,
    body_id: b2.b2BodyId,

    pub fn init(
        world_allocator: std.mem.Allocator,
        world_id: b2.b2WorldId,
        position: vec2,
        shape: GroundSegmentShape,
    ) Self {
        return Self{
            .world_allocator = world_allocator,
            .world_id = world_id,

            .position = position,
            .shape = shape,

            .dirty = true,
            .body_id = b2.b2_nullBodyId,
        };
    }

    pub fn deinit(self: *GroundSegment) void {
        self.destroyBody();

        if (self.shape == .Polygon) {
            self.world_allocator.free(self.shape.Polygon.points);
        }
    }

    pub fn update(self: *GroundSegment, temp_allocator: std.mem.Allocator) void {
        if (!self.dirty) {
            return;
        }
        self.dirty = false;

        self.destroyBody();
        self.createBody(temp_allocator);
    }

    pub fn move(self: *GroundSegment, new_position: vec2) void {
        self.position = new_position;
        self.dirty = true;
    }

    pub fn findPoint(self: GroundSegment, position_world: vec2, max_distance: f32) ?usize {
        std.debug.assert(self.shape == .Polygon);

        const position_local = position_world.sub(self.position);

        var closest_dist: f32 = std.math.floatMax(f32);
        var closest_index: ?usize = null;

        for (self.shape.Polygon.points, 0..) |point, i| {
            const dist = vec2.dist(point, position_local);

            if (dist < max_distance and dist < closest_dist) {
                closest_dist = dist;
                closest_index = i;
            }
        }

        return closest_index;
    }

    pub fn createPoint(self: *GroundSegment, index: usize, position: vec2, is_global: bool) void {
        std.debug.assert(self.shape == .Polygon);

        var p = position;
        if (is_global) {
            p = p.sub(self.position);
        }

        // TODO try to resize first
        //self.world_allocator.resize(old_mem: anytype, new_n: usize)

        const old_points: []vec2 = self.shape.Polygon.points;
        const old_len = old_points.len;

        // Ensure the index is valid
        std.debug.assert(index <= old_len); // index == old_len allows inserting at the end

        // Allocate memory for the new array
        const new_points: []vec2 = self.world_allocator.alloc(vec2, old_len + 1) catch unreachable;

        // Copy points before the insertion index
        for (0..index) |i| {
            new_points[i] = old_points[i];
        }

        // Insert the new point
        new_points[index] = p;

        // Shift points after the insertion index
        for (index..old_len) |i| {
            new_points[i + 1] = old_points[i];
        }

        // Free the old memory
        self.world_allocator.free(old_points);

        // Update the polygon with the new points
        self.shape = .{
            .Polygon = .{
                .points = new_points,
            },
        };

        self.dirty = true;
    }

    pub fn destroyPoint(self: *GroundSegment, index: usize) void {
        std.debug.assert(self.shape == .Polygon);

        // TODO try to resize first
        //self.world_allocator.resize(old_mem: anytype, new_n: usize)

        const old_points: []vec2 = self.shape.Polygon.points;
        const old_len = old_points.len;

        // Ensure the index is valid and there are enough points to remove
        std.debug.assert(index < old_len);
        std.debug.assert(old_len > 1); // Prevent removing the last point (optional constraint)

        // Allocate memory for the new array with one less point
        const new_points: []vec2 = self.world_allocator.alloc(vec2, old_len - 1) catch unreachable;

        // Copy points before the index
        for (0..index) |i| {
            new_points[i] = old_points[i];
        }

        // Copy points after the index (shift left)
        for (index + 1..old_len) |i| {
            new_points[i - 1] = old_points[i];
        }

        // Free the old memory
        self.world_allocator.free(old_points);

        // Update the polygon with the new points
        self.shape = .{
            .Polygon = .{
                .points = new_points,
            },
        };

        self.dirty = true;
    }

    pub fn movePoint(self: *GroundSegment, index: usize, new_position: vec2, is_global: bool) void {
        std.debug.assert(self.shape == .Polygon);

        var p = new_position;

        if (is_global) {
            p = p.sub(self.position);
        }

        self.shape.Polygon.points[index] = p;
        self.dirty = true;
    }

    fn createBody(self: *GroundSegment, temp_allocator: std.mem.Allocator) void {
        //
        std.debug.assert(b2.B2_IS_NULL(self.body_id));

        switch (self.shape) {
            .Box => |box| {

                // body
                var body_def = b2.b2DefaultBodyDef();
                body_def.type = b2.b2_staticBody;
                body_def.position = self.position.to_b2();
                body_def.rotation = b2.b2MakeRot(box.angle);

                self.body_id = b2.b2CreateBody(self.world_id, &body_def);

                // shape
                var shape_def = b2.b2DefaultShapeDef();
                shape_def.density = 1.0;
                shape_def.friction = 0.3;
                shape_def.filter = physics.Filters.getGroundFilter();

                const b2_box = b2.b2MakeBox(box.width * 0.5, box.height * 0.5);

                _ = b2.b2CreatePolygonShape(self.body_id, &shape_def, &b2_box);
            },
            .Circle => |circle| {

                // body
                var body_def = b2.b2DefaultBodyDef();
                body_def.type = b2.b2_staticBody;
                body_def.position = self.position.to_b2();

                self.body_id = b2.b2CreateBody(self.world_id, &body_def);

                // shape
                var shape_def = b2.b2DefaultShapeDef();
                shape_def.density = 1.0;
                shape_def.friction = 0.3;
                shape_def.filter = physics.Filters.getGroundFilter();

                const b2_circle = b2.b2Circle{
                    .center = vec2.zero.to_b2(),
                    .radius = circle.radius,
                };

                _ = b2.b2CreateCircleShape(self.body_id, &shape_def, &b2_circle);
            },
            .Polygon => |polygon| {
                if (polygon.points.len >= 4) { // TODO 3 or 4 ?

                    // body
                    var body_def = b2.b2DefaultBodyDef();
                    body_def.type = b2.b2_staticBody;
                    body_def.position = self.position.to_b2();

                    self.body_id = b2.b2CreateBody(self.world_id, &body_def);

                    // shape
                    const num_points = polygon.points.len;
                    var points: []b2.b2Vec2 = temp_allocator.alloc(b2.b2Vec2, num_points) catch unreachable;
                    defer temp_allocator.free(points);

                    for (0.., polygon.points) |i, ground_point| {
                        points[i] = ground_point.to_b2();
                    }

                    var chain_def = b2.b2DefaultChainDef();
                    // TODO set friction, restitution, etc
                    chain_def.isLoop = true;
                    chain_def.points = points.ptr; // TODO maybe just cast existing data? memory layout should be the same?
                    chain_def.count = @intCast(num_points);
                    chain_def.filter = physics.Filters.getGroundFilter();

                    _ = b2.b2CreateChain(self.body_id, &chain_def);
                }
            },
        }
    }

    fn destroyBody(self: *GroundSegment) void {
        if (b2.B2_IS_NULL(self.body_id)) {
            return;
        }

        b2.b2DestroyBody(self.body_id);
        self.body_id = b2.b2_nullBodyId;
    }
};
