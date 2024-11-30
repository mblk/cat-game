const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;

const zbox = @import("zbox");
const b2 = zbox.API;

pub const WorldSave = struct {
    pub const GroundSegment = struct {
        position: vec2,
        points: []vec2,
    };

    ground_segments: []GroundSegment,
};

pub const World = struct {
    pub const GroundPointIndex = struct {
        ground_segment_index: usize,
        ground_point_index: usize,
    };

    pub const GroundSegmentIndex = struct {
        index: usize,
    };

    pub const GroundSegment = struct {
        position: vec2,
        points: std.ArrayList(vec2),
        dirty: bool,
        body_id: b2.b2BodyId,
    };

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
        //
        for (self.ground_segments.items) |ground_segment| {
            ground_segment.points.deinit();
        }

        self.ground_segments.deinit();
    }

    pub fn load(self: *World) !void {
        //

        //_ = try self.createGroundSegment(vec2.init(0, 0));
        //_ = try self.createGroundSegment(vec2.init(30, 10));

        const file = try std.fs.cwd().openFile("save.json", .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const buffer = try file.readToEndAlloc(self.allocator, file_size);
        defer self.allocator.free(buffer);

        std.log.info("load: {s}", .{buffer});

        // -------------------------------
        const parsed = try std.json.parseFromSlice(
            WorldSave,
            self.allocator,
            buffer,
            .{},
        );
        defer parsed.deinit();

        const world_data = parsed.value;

        for (world_data.ground_segments) |segment_data| {
            const ground_segment_index = try self.createEmptyGroundSegment(segment_data.position);

            for (0.., segment_data.points) |point_index, point_data| {
                const ground_point_index = World.GroundPointIndex{
                    .ground_segment_index = ground_segment_index.index,
                    .ground_point_index = point_index,
                };

                _ = try self.createGroundPointLocal(ground_point_index, point_data);
            }
        }
    }

    pub fn save(self: *World) !void {
        // TODO: use special allocator?

        const ground_segments_data = try self.allocator.alloc(WorldSave.GroundSegment, self.ground_segments.items.len);
        defer self.allocator.free(ground_segments_data);

        for (0.., self.ground_segments.items) |ground_segment_index, ground_segment| {
            const ground_points_data = try self.allocator.alloc(vec2, ground_segment.points.items.len);

            for (0.., ground_segment.points.items) |ground_point_index, ground_point| {
                ground_points_data[ground_point_index] = ground_point;
            }

            ground_segments_data[ground_segment_index] = WorldSave.GroundSegment{
                .position = ground_segment.position,
                .points = ground_points_data,
            };
        }

        defer for (ground_segments_data) |d| {
            self.allocator.free(d.points);
        };

        const data = WorldSave{
            .ground_segments = ground_segments_data,
        };

        var string = std.ArrayList(u8).init(self.allocator);
        defer string.deinit();

        try std.json.stringify(data, .{
            .whitespace = .indent_4,
        }, string.writer());

        const s = string.items;

        std.log.info("save {s}", .{s});

        // ----

        var file = try std.fs.cwd().createFile("save.json", .{});
        defer file.close();
        try file.writeAll(s);
    }

    pub fn update(self: *World, dt: f32) void {
        //
        _ = dt;

        for (self.ground_segments.items) |*ground_segment| {
            if (!ground_segment.dirty) continue;
            ground_segment.dirty = false;

            // destroy old body and chain
            if (b2.B2_IS_NON_NULL(ground_segment.body_id)) {
                b2.b2DestroyBody(ground_segment.body_id);
            }

            // create new body
            var body_def = b2.b2DefaultBodyDef();
            ground_segment.body_id = b2.b2CreateBody(self.world_id, &body_def);

            const num_points = ground_segment.points.items.len;

            // XXX could use a temporary per-frame arena allocator here
            var points: []b2.b2Vec2 = self.allocator.alloc(b2.b2Vec2, num_points) catch unreachable;
            defer self.allocator.free(points);

            for (0.., ground_segment.points.items) |i, ground_point| {
                const p = ground_segment.position.add(ground_point);

                points[i] = b2.b2Vec2{
                    .x = p.x,
                    .y = p.y,
                };
            }

            var chain_def = b2.b2DefaultChainDef();
            chain_def.isLoop = true;
            chain_def.points = points.ptr;
            chain_def.count = @intCast(num_points);

            _ = b2.b2CreateChain(ground_segment.body_id, &chain_def);
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

    pub fn createGroundSegment(self: *World, position: vec2) !GroundSegmentIndex {
        var segment = GroundSegment{
            .position = position,
            .points = std.ArrayList(vec2).init(self.allocator),
            .dirty = true,
            .body_id = b2.b2_nullBodyId,
        };

        // box2d uses ccw order.

        try segment.points.append(vec2.init(-10, -10)); // local
        try segment.points.append(vec2.init(10, -10));
        try segment.points.append(vec2.init(10, 10));
        try segment.points.append(vec2.init(-10, 10));

        const index = self.ground_segments.items.len;

        try self.ground_segments.append(segment);

        return GroundSegmentIndex{
            .index = index,
        };
    }

    pub fn createEmptyGroundSegment(self: *World, position: vec2) !GroundSegmentIndex {
        const segment = GroundSegment{
            .position = position,
            .points = std.ArrayList(vec2).init(self.allocator),
            .dirty = true,
            .body_id = b2.b2_nullBodyId,
        };

        const index = self.ground_segments.items.len;

        try self.ground_segments.append(segment);

        return GroundSegmentIndex{
            .index = index,
        };
    }

    pub fn deleteGroundSegment(self: *World, index: GroundSegmentIndex) void {
        var ground_segment = self.ground_segments.orderedRemove(index.index);

        ground_segment.points.deinit();
    }

    pub fn moveGroundSegment(self: *World, index: GroundSegmentIndex, new_position: vec2) void {
        const ground_segment = &self.ground_segments.items[index.index];
        ground_segment.position = new_position;
        ground_segment.dirty = true;
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

    pub fn createGroundPoint(self: *World, index: GroundPointIndex, global_position: vec2) !GroundPointIndex {
        const ground_segment = &self.ground_segments.items[index.ground_segment_index];

        const local_position = global_position.sub(ground_segment.position);
        const insert_position = index.ground_point_index; // + 1;

        try ground_segment.points.insert(insert_position, local_position);

        ground_segment.dirty = true;

        return GroundPointIndex{
            .ground_segment_index = index.ground_segment_index,
            .ground_point_index = insert_position,
        };
    }

    pub fn createGroundPointLocal(self: *World, index: GroundPointIndex, local_position: vec2) !GroundPointIndex {
        const ground_segment = &self.ground_segments.items[index.ground_segment_index];

        const insert_position = index.ground_point_index; // + 1;

        try ground_segment.points.insert(insert_position, local_position);

        ground_segment.dirty = true;

        return GroundPointIndex{
            .ground_segment_index = index.ground_segment_index,
            .ground_point_index = insert_position,
        };
    }

    pub fn deleteGroundPoint(self: *World, index: GroundPointIndex) void {
        const ground_segment = &self.ground_segments.items[index.ground_segment_index];

        if (ground_segment.points.items.len <= 3) {
            std.log.err("can't delete ground point, only 3 points left", .{});
            return;
        }

        ground_segment.dirty = true;

        _ = ground_segment.points.orderedRemove(index.ground_point_index);
    }

    pub fn moveGroundPoint(self: *World, index: GroundPointIndex, global_position: vec2) void {
        const ground_segment = &self.ground_segments.items[index.ground_segment_index];

        const local_position = global_position.sub(ground_segment.position);

        ground_segment.points.items[index.ground_point_index] = local_position;
        ground_segment.dirty = true;
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
