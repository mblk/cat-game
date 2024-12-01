const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;

const zbox = @import("zbox");
const b2 = zbox.API;

pub const GroundSegmentIndex = struct {
    index: usize,
};

pub const GroundPointIndex = struct {
    ground_segment_index: usize,
    ground_point_index: usize,
};

pub const GroundSegment = @import("ground_segment.zig").GroundSegment;

pub const World = struct {
    allocator: std.mem.Allocator,
    size: vec2,
    ground_segments: std.ArrayList(GroundSegment),
    world_id: b2.b2WorldId,

    pub fn create(allocator: std.mem.Allocator) World {
        const world_width = 200.0;
        const world_height = 100.0;
        const half_world_width = world_width * 0.5;
        const half_world_height = world_height * 0.5;

        // b2 world
        const world_def = b2.b2DefaultWorldDef();
        const world_id = b2.b2CreateWorld(&world_def);

        // ground body
        {
            var ground_body_def = b2.b2DefaultBodyDef();
            ground_body_def.position.x = 0.0;
            ground_body_def.position.y = -25.0;

            const ground_id = b2.b2CreateBody(world_id, &ground_body_def);

            const ground_box = b2.b2MakeBox(40.0, 2.0);
            const ground_shape_def = b2.b2DefaultShapeDef();
            _ = b2.b2CreatePolygonShape(ground_id, &ground_shape_def, &ground_box);
        }

        // outer bounds chain segment
        {
            var body_def = b2.b2DefaultBodyDef();

            const body_id = b2.b2CreateBody(world_id, &body_def);

            var points = [4]b2.b2Vec2{
                b2.b2Vec2{ .x = -half_world_width, .y = -half_world_height }, // bottom left
                b2.b2Vec2{ .x = -half_world_width, .y = half_world_height }, // top left
                b2.b2Vec2{ .x = half_world_width, .y = half_world_height }, // top right
                b2.b2Vec2{ .x = half_world_width, .y = -half_world_height }, // bottom right
            };

            var chain_def = b2.b2DefaultChainDef();
            chain_def.isLoop = true;
            chain_def.points = &points;
            chain_def.count = 4;

            _ = b2.b2CreateChain(body_id, &chain_def);
        }

        //
        return World{
            .allocator = allocator,
            .size = vec2.init(100, 100),
            .ground_segments = std.ArrayList(GroundSegment).init(allocator),

            .world_id = world_id,
        };
    }

    pub fn free(self: *World) void {
        self.clear();

        self.ground_segments.deinit();
    }

    pub fn clear(self: *World) void {
        for (self.ground_segments.items) |*ground_segment| {
            ground_segment.free();
        }
        self.ground_segments.clearAndFree();
    }

    pub fn update(self: *World, dt: f32) void {
        //
        _ = dt;

        for (self.ground_segments.items) |*ground_segment| {
            // XXX could use a temporary per-frame arena allocator here
            ground_segment.update(self.allocator);
        }

        const physics_time_step: f32 = 1.0 / 60.0;
        const physics_sub_step_count: i32 = 4;

        b2.b2World_Step(self.world_id, physics_time_step, physics_sub_step_count);
    }

    //
    // ground segments
    //

    pub fn getGroundSegment(self: *World, position: vec2, max_distance: f32) ?GroundSegmentIndex {
        var closest_idx: ?GroundSegmentIndex = null;
        var closest_dist = std.math.floatMax(f32);

        for (0.., self.ground_segments.items) |ground_segment_index, ground_segment| {
            const dist = vec2.dist(ground_segment.position, position);
            if (dist < max_distance and dist < closest_dist) {
                closest_idx = GroundSegmentIndex{
                    .index = ground_segment_index,
                };
                closest_dist = dist;
            }
        }

        return closest_idx;
    }

    pub fn createGroundSegment(self: *World, position: vec2) GroundSegmentIndex {
        const segment = GroundSegment.create(self.world_id, position, self.allocator);
        const index = self.ground_segments.items.len;

        self.ground_segments.append(segment) catch unreachable;

        return GroundSegmentIndex{
            .index = index,
        };
    }

    pub fn deleteGroundSegment(self: *World, index: GroundSegmentIndex) void {
        var ground_segment = self.ground_segments.orderedRemove(index.index);

        ground_segment.free();
    }

    pub fn moveGroundSegment(self: *World, index: GroundSegmentIndex, new_position: vec2) void {
        const ground_segment = &self.ground_segments.items[index.index];
        ground_segment.move(new_position);
    }

    //
    // ground points
    //

    pub fn getGroundPoint(self: *World, position: vec2, max_distance: f32) ?GroundPointIndex {
        var closest: ?GroundPointIndex = null;
        var closest_dist: f32 = std.math.floatMax(f32);

        for (0.., self.ground_segments.items) |ground_segment_index, ground_segment| {
            for (0.., ground_segment.points.items) |ground_point_index, ground_point| {
                const p = ground_segment.position.add(ground_point);
                const dist = vec2.dist(p, position);

                if (dist < max_distance and dist < closest_dist) {
                    closest_dist = dist;
                    closest = GroundPointIndex{
                        .ground_segment_index = ground_segment_index,
                        .ground_point_index = ground_point_index,
                    };
                }
            }
        }

        return closest;
    }

    pub fn createGroundPoint(self: *World, index: GroundPointIndex, position: vec2, is_global: bool) GroundPointIndex {
        const ground_segment = &self.ground_segments.items[index.ground_segment_index];

        ground_segment.createPoint(index.ground_point_index, position, is_global);

        return GroundPointIndex{
            .ground_segment_index = index.ground_segment_index,
            .ground_point_index = index.ground_point_index,
        };
    }

    pub fn deleteGroundPoint(self: *World, index: GroundPointIndex) void {
        const ground_segment = &self.ground_segments.items[index.ground_segment_index];

        ground_segment.destroyPoint(index.ground_point_index);
    }

    pub fn moveGroundPoint(self: *World, index: GroundPointIndex, global_position: vec2) void {
        const ground_segment = &self.ground_segments.items[index.ground_segment_index];

        ground_segment.movePoint(index.ground_point_index, global_position, true);
    }

    //
    // entities
    //

    pub fn createDynamicBox(self: *World, position: vec2) void {
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position.x = position.x;
        body_def.position.y = position.y;
        const body_id = b2.b2CreateBody(self.world_id, &body_def);

        const box = b2.b2MakeBox(1.0, 1.0);
        var shape_def = b2.b2DefaultShapeDef();
        shape_def.density = 1.0;
        shape_def.friction = 0.3;
        shape_def.restitution = 0.5;
        _ = b2.b2CreatePolygonShape(body_id, &shape_def, &box);

        //var entity = self.createEntity();
        //entity.body_id = body_id;
        //self.entities.append(entity) catch unreachable;
    }
};

test "world: leaks test 1" {
    var world = World.create(std.testing.allocator);
    try world.load();
    world.free();
    // testing for memory leaks
}

test "world: create ground segment 1" {
    var world = World.create(std.testing.allocator);
    defer world.free();

    const index1 = try world.createGroundSegment(vec2.init(10.0, 0.0));
    const index2 = try world.createGroundSegment(vec2.init(20.0, 0.0));

    try std.testing.expect(index1.index == 0);
    try std.testing.expect(index2.index == 1);
}
