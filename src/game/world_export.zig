const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Transform2 = engine.Transform2;

const World = @import("world.zig").World;
const GroundPointIndex = @import("world.zig").GroundPointIndex;

const VehicleDefs = @import("vehicle.zig").VehicleDefs;

const ItemDef = @import("item.zig").ItemDef;

const WorldData = struct {
    settings: SettingsData,
    ground_segments: []GroundSegmentData,
    vehicles: []VehicleData,
    items: []ItemData,
};

const SettingsData = struct {
    size: vec2,
    gravity: vec2,
    start_position: vec2,
    finish_position: vec2,
};

const GroundSegmentData = struct {
    position: vec2,
    points: []vec2,
};

const VehicleExporter = @import("vehicle_export.zig").VehicleExporter;
const VehicleImporter = @import("vehicle_export.zig").VehicleImporter;
const VehicleData = @import("vehicle_export.zig").VehicleData;

const ItemData = struct {
    def_id: []const u8,
    transform: Transform2,
};

pub const WorldExporter = struct {
    pub fn exportWorld(world: *const World, allocator: std.mem.Allocator) ![]const u8 {

        // convert World to WorldData

        // ground segments
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

        // vehicles
        var vehicles_data = std.ArrayList(VehicleData).init(allocator);
        defer vehicles_data.deinit();

        for (world.vehicles.items) |*vehicle| {
            if (!vehicle.alive) continue;

            const vehicle_data = try VehicleExporter.getVehicleData(vehicle, allocator);
            try vehicles_data.append(vehicle_data);
        }

        defer for (vehicles_data.items) |d| {
            allocator.free(d.blocks);
            allocator.free(d.devices);
        };

        // items
        var items_data = std.ArrayList(ItemData).init(allocator);
        defer items_data.deinit();

        for (world.items.items) |*item| {
            if (!item.alive) continue;

            try items_data.append(.{
                .def_id = item.def.id,
                .transform = item.getTransform(),
            });
        }

        // world
        const data = WorldData{
            .settings = .{
                .size = world.settings.size,
                .gravity = world.settings.gravity,
                .start_position = world.settings.start_position,
                .finish_position = world.settings.finish_position,
            },
            .ground_segments = ground_segments_data,
            .vehicles = vehicles_data.items,
            .items = items_data.items,
        };

        // convert to json
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try std.json.stringify(data, .{
            .whitespace = .indent_4,
        }, string.writer());

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
        world.reset();

        // populate world

        // settings
        world.settings.size = world_data.settings.size;
        world.settings.gravity = world_data.settings.gravity;
        world.settings.start_position = world_data.settings.start_position;
        world.settings.finish_position = world_data.settings.finish_position;

        // ground segments
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

        // vehicles
        for (world_data.vehicles) |vehicle_data| {
            _ = VehicleImporter.createVehicleFromData(world, vehicle_data);
        }

        // items
        for (world_data.items) |item_data| {
            if (world.defs.getItemDef(item_data.def_id)) |item_def| {
                _ = world.createItem(item_def, item_data.transform) catch unreachable;
            }
        }

        // xxx
        world.createPlayer(vec2.init(0, 0));
        world.movePlayersToStart();
        // xxx
    }
};
