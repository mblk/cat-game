const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;

const World = @import("world.zig").World;
const GroundPointIndex = @import("world.zig").GroundPointIndex;

const WorldData = struct {
    ground_segments: []GroundSegmentData,
};

const GroundSegmentData = struct {
    position: vec2,
    points: []vec2,
};

pub const WorldExporter = struct {
    pub fn exportWorld(world: *World, allocator: std.mem.Allocator) ![]const u8 {

        // convert World to WorldData
        const ground_segments_data = try allocator.alloc(GroundSegmentData, world.ground_segments.items.len);
        defer allocator.free(ground_segments_data);

        for (0.., world.ground_segments.items) |ground_segment_index, ground_segment| {
            const ground_points_data = try allocator.alloc(vec2, ground_segment.points.items.len);

            for (0.., ground_segment.points.items) |ground_point_index, ground_point| {
                ground_points_data[ground_point_index] = ground_point;
            }

            ground_segments_data[ground_segment_index] = GroundSegmentData{
                .position = ground_segment.position,
                .points = ground_points_data,
            };
        }

        defer for (ground_segments_data) |d| {
            allocator.free(d.points);
        };

        const data = WorldData{
            .ground_segments = ground_segments_data,
        };

        // convert to json
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try std.json.stringify(data, .{
            .whitespace = .indent_4,
        }, string.writer());

        //return string.allocatedSlice();
        return allocator.dupe(u8, string.items);
    }
};

pub const WorldImporter = struct {
    pub fn importWorld(world: *World, data: []const u8, allocator: std.mem.Allocator) !void {

        // parse json
        const parsed = try std.json.parseFromSlice(
            WorldData,
            allocator,
            data,
            .{},
        );
        defer parsed.deinit();

        const world_data = parsed.value;

        // clear world
        world.clear();

        // populate world
        for (world_data.ground_segments) |segment_data| {
            const ground_segment_index = world.createGroundSegment(segment_data.position);

            for (0.., segment_data.points) |point_index, point_data| {
                const ground_point_index = GroundPointIndex{
                    .ground_segment_index = ground_segment_index.index,
                    .ground_point_index = point_index,
                };

                _ = world.createGroundPoint(ground_point_index, point_data, false);
            }
        }
    }
};
