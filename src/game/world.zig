const std = @import("std");

const engine = @import("../engine/engine.zig");

const vec2 = engine.vec2;

pub const GroundSegment = struct {
    position: vec2,
    points: std.ArrayList(vec2),
};

pub const World = struct {
    allocator: std.mem.Allocator,

    size: vec2,

    ground_segments: std.ArrayList(GroundSegment),

    pub fn create(allocator: std.mem.Allocator) World {
        //
        return World{
            .allocator = allocator,
            .size = vec2.init(100, 100),
            .ground_segments = std.ArrayList(GroundSegment).init(allocator),
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

        _ = try self.createGroundSegment(vec2.init(0, 0));
        _ = try self.createGroundSegment(vec2.init(30, 10));
    }

    pub fn save() void {
        //
    }

    //
    // ground segments
    //

    pub const GroundSegmentIndex = struct {
        index: usize,
    };

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
        };

        try segment.points.append(vec2.init(-10, -10)); // local
        try segment.points.append(vec2.init(-10, 10));
        try segment.points.append(vec2.init(10, 10));
        try segment.points.append(vec2.init(10, -10));

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
    }

    //
    // ground points
    //

    pub const GroundPointIndex = struct {
        ground_segment_index: usize,
        ground_point_index: usize,
    };

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
        const insert_position = index.ground_point_index + 1;

        try ground_segment.points.insert(insert_position, local_position);

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

        _ = ground_segment.points.orderedRemove(index.ground_point_index);
    }

    pub fn moveGroundPoint(self: *World, index: GroundPointIndex, global_position: vec2) void {
        const ground_segment = &self.ground_segments.items[index.ground_segment_index];

        const local_position = global_position.sub(ground_segment.position);

        ground_segment.points.items[index.ground_point_index] = local_position;
    }
};

test "world test 1" {
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
