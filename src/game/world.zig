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

const Vehicle = @import("vehicle.zig").Vehicle;
const Block = @import("vehicle.zig").Block;
const BlockDef = @import("vehicle.zig").BlockDef;
const BlockRef = @import("vehicle.zig").BlockRef;

pub const VehicleRef = struct {
    vehicle_index: usize,
    //vehicle_version

    pub fn format(self: VehicleRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Vehicle(idx={d})", .{self.vehicle_index});
    }
};

pub const VehicleAndBlockRef = struct {
    vehicle: VehicleRef,
    block: BlockRef,

    pub fn format(self: VehicleAndBlockRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}+{s}", .{ self.vehicle, self.block });
    }
};

pub const World = struct {
    allocator: std.mem.Allocator,
    size: vec2,
    world_id: b2.b2WorldId,
    ground_segments: std.ArrayList(GroundSegment),
    vehicles: std.ArrayList(Vehicle),

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
            .vehicles = std.ArrayList(Vehicle).init(allocator),

            .world_id = world_id,
        };
    }

    pub fn free(self: *World) void {
        self.clear();

        self.ground_segments.deinit();

        for (self.vehicles.items) |*vehicle| {
            if (!vehicle.alive) continue;
            vehicle.destroy();
        }

        self.vehicles.deinit();
    }

    pub fn clear(self: *World) void {
        for (self.ground_segments.items) |*ground_segment| {
            ground_segment.free();
        }
        self.ground_segments.clearAndFree();
    }

    pub fn update(self: *World, dt: f32, temp_allocator: std.mem.Allocator) void {
        //
        _ = dt;

        for (self.ground_segments.items) |*ground_segment| {
            // TODO: add dirty flag?
            // XXX could use a temporary per-frame arena allocator here
            ground_segment.update(temp_allocator);
        }

        for (self.vehicles.items) |*vehicle| {
            if (!vehicle.alive) continue;
            if (!vehicle.edit_flag) continue;
            vehicle.edit_flag = false;

            // delete vehicle?
            {
                var num_alive_blocks: usize = 0;
                for (vehicle.blocks.items) |block| {
                    if (block.alive) {
                        num_alive_blocks += 1;
                    }
                }
                if (num_alive_blocks == 0) {
                    std.log.info("destroy vehicle", .{});
                    vehicle.destroy();
                    continue;
                }
            }

            // split vehicle?
            {
                //
                var split_result = vehicle.getSplitParts(temp_allocator); // XXX should use temp arena
                defer split_result.deinit();

                std.log.info("split:", .{});
                const parts = split_result.parts;
                for (parts) |part| {
                    std.log.info("  part:", .{});
                    for (part) |block_ref| {
                        std.log.info("    block: {s}", .{block_ref});
                    }
                }

                if (parts.len > 1) {
                    // keep parts[0] as it is
                    // split parts[1..] into new vehicle(s)
                    for (parts[1..]) |part_to_remove| {
                        const new_vehicle_pos_world = vehicle.transformLocalToWorld(vehicle.getBlock(part_to_remove[0]).?.local_position);
                        const new_vehicle_ref = self.createVehicle(new_vehicle_pos_world);
                        const new_vehicle = self.getVehicle(new_vehicle_ref).?;

                        const vehicle_transform = b2.b2Body_GetTransform(vehicle.body_id);
                        b2.b2Body_SetTransform(new_vehicle.body_id, vehicle_transform.p, vehicle_transform.q);
                        b2.b2Body_SetLinearVelocity(new_vehicle.body_id, b2.b2Body_GetLinearVelocity(vehicle.body_id));
                        b2.b2Body_SetAngularVelocity(new_vehicle.body_id, b2.b2Body_GetAngularVelocity(vehicle.body_id));

                        for (part_to_remove) |block_ref| {
                            const block = vehicle.getBlock(block_ref).?.*; // make a copy
                            const block_pos_world = vehicle.transformLocalToWorld(block.local_position);

                            vehicle.destroyBlock(block_ref);

                            const block_pos_new_local = new_vehicle.transformWorldToLocal(block_pos_world);
                            _ = new_vehicle.createBlock(block.def, block_pos_new_local);
                        }
                    }
                }
            }

            // TODO: maybe fix center after vehicle has been changed?
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

        //body_def.fixedRotation = true;

        const body_id = b2.b2CreateBody(self.world_id, &body_def);

        const box = b2.b2MakeBox(2.0, 1.0); // 4x2
        var shape_def = b2.b2DefaultShapeDef();
        shape_def.density = 1.0;
        shape_def.friction = 0.3;
        //shape_def.restitution = 0.5;
        _ = b2.b2CreatePolygonShape(body_id, &shape_def, &box);

        //var entity = self.createEntity();
        //entity.body_id = body_id;
        //self.entities.append(entity) catch unreachable;
    }

    //
    // vehicles
    //

    pub fn getVehicle(self: *World, vehicle_ref: VehicleRef) ?*Vehicle {
        const vehicle = &self.vehicles.items[vehicle_ref.vehicle_index];

        if (vehicle.alive) {
            return vehicle;
        }

        return null;
    }

    pub fn createVehicle(self: *World, position: vec2) VehicleRef {
        const vehicle = Vehicle.create(self.allocator, self.world_id, position);

        const index = self.vehicles.items.len;

        self.vehicles.append(vehicle) catch unreachable;

        return VehicleRef{
            .vehicle_index = index,
        };
    }

    pub const VehicleAndBlockResult = struct {
        vehicle: *Vehicle,
        block: *Block,
    };

    pub fn getVehicleAndBlock(self: *World, ref: VehicleAndBlockRef) ?VehicleAndBlockResult {
        if (self.getVehicle(ref.vehicle)) |vehicle| {
            if (vehicle.getBlock(ref.block)) |block| {
                return VehicleAndBlockResult{
                    .vehicle = vehicle,
                    .block = block,
                };
            }
        }
        return null;
    }

    pub const ClosestVehicleResult = struct {
        vehicle_and_block_ref: VehicleAndBlockRef,
        block_def: BlockDef,
        block_local: vec2,
        block_world: vec2,
    };

    pub fn getClosestVehicle(self: *World, position_world: vec2, max_distance: f32) ?ClosestVehicleResult {
        var closest_dist: f32 = std.math.floatMax(f32);
        var closest_vehicle: ?ClosestVehicleResult = null;

        for (self.vehicles.items, 0..) |*vehicle, vehicle_index| {
            if (!vehicle.alive) continue;

            for (vehicle.blocks.items, 0..) |*block, block_index| {
                if (!block.alive) continue;

                const block_position_world = vehicle.transformLocalToWorld(block.local_position);
                const dist = vec2.dist(block_position_world, position_world);

                if (dist < max_distance and dist < closest_dist) {
                    closest_dist = dist;
                    closest_vehicle = ClosestVehicleResult{
                        .vehicle_and_block_ref = VehicleAndBlockRef{
                            .vehicle = VehicleRef{
                                .vehicle_index = vehicle_index,
                            },
                            .block = BlockRef{
                                .block_index = block_index,
                            },
                        },
                        .block_def = block.def,
                        .block_local = block.local_position,
                        .block_world = block_position_world,
                    };
                }
            }
        }

        return closest_vehicle;
    }

    pub const ClosestBlockAttachResult = struct {
        vehicle_ref: VehicleRef,
        block_def: BlockDef,
        block_local: vec2,
        block_world: vec2,
        attach_local: vec2,
        attach_world: vec2,
        normal_local: vec2,
        normal_world: vec2,
    };

    pub fn getClosestBlockAttachPoint(self: *World, position_world: vec2, max_distance: f32, max_overhang_local: vec2) ?ClosestBlockAttachResult {
        var closest_dist: f32 = std.math.floatMax(f32);
        var closest_vehicle: ?ClosestBlockAttachResult = null;

        for (self.vehicles.items, 0..) |*vehicle, vehicle_index| {
            if (!vehicle.alive) continue;

            const position_local = vehicle.transformWorldToLocal(position_world);

            for (vehicle.blocks.items) |*block| {
                if (!block.alive) continue;

                const hw = block.def.size.x * 0.5;
                const hh = block.def.size.y * 0.5;

                // target position in block space
                const p = position_local.sub(block.local_position);

                if (-max_overhang_local.x - hw < p.x and p.x < hw + max_overhang_local.x) {
                    // top edge
                    {
                        const dist = @abs(hh - p.y);
                        const attach_local = block.local_position.add(vec2.init(p.x, hh));
                        const normal_local = vec2.init(0, 1);

                        if (dist < max_distance and dist < closest_dist) {
                            closest_dist = dist;
                            closest_vehicle = ClosestBlockAttachResult{
                                .vehicle_ref = VehicleRef{
                                    .vehicle_index = vehicle_index,
                                },

                                .block_def = block.def,
                                .block_local = block.local_position,
                                .block_world = vehicle.transformLocalToWorld(block.local_position),

                                .attach_local = attach_local,
                                .attach_world = vehicle.transformLocalToWorld(attach_local),

                                .normal_local = normal_local,
                                .normal_world = vehicle.rotateLocalToWorld(normal_local),
                            };
                        }
                    }

                    // bottom edge
                    {
                        const dist = @abs(-hh - p.y);
                        const attach_local = block.local_position.add(vec2.init(p.x, -hh));
                        const normal_local = vec2.init(0, -1);

                        if (dist < max_distance and dist < closest_dist) {
                            closest_dist = dist;
                            closest_vehicle = ClosestBlockAttachResult{
                                .vehicle_ref = VehicleRef{
                                    .vehicle_index = vehicle_index,
                                },

                                .block_def = block.def,
                                .block_local = block.local_position,
                                .block_world = vehicle.transformLocalToWorld(block.local_position),

                                .attach_local = attach_local,
                                .attach_world = vehicle.transformLocalToWorld(attach_local),

                                .normal_local = normal_local,
                                .normal_world = vehicle.rotateLocalToWorld(normal_local),
                            };
                        }
                    }
                }

                if (-max_overhang_local.y - hh < p.y and p.y < hh + max_overhang_local.y) {
                    // right edge
                    {
                        const dist = @abs(hw - p.x);
                        const attach_local = block.local_position.add(vec2.init(hw, p.y));
                        const normal_local = vec2.init(1, 0);

                        if (dist < max_distance and dist < closest_dist) {
                            closest_dist = dist;
                            closest_vehicle = ClosestBlockAttachResult{
                                .vehicle_ref = VehicleRef{
                                    .vehicle_index = vehicle_index,
                                },

                                .block_def = block.def,
                                .block_local = block.local_position,
                                .block_world = vehicle.transformLocalToWorld(block.local_position),

                                .attach_local = attach_local,
                                .attach_world = vehicle.transformLocalToWorld(attach_local),

                                .normal_local = normal_local,
                                .normal_world = vehicle.rotateLocalToWorld(normal_local),
                            };
                        }
                    }

                    // left edge
                    {
                        const dist = @abs(-hw - p.x);
                        const attach_local = block.local_position.add(vec2.init(-hw, p.y));
                        const normal_local = vec2.init(-1, 0);

                        if (dist < max_distance and dist < closest_dist) {
                            closest_dist = dist;
                            closest_vehicle = ClosestBlockAttachResult{
                                .vehicle_ref = VehicleRef{
                                    .vehicle_index = vehicle_index,
                                },

                                .block_def = block.def,
                                .block_local = block.local_position,
                                .block_world = vehicle.transformLocalToWorld(block.local_position),

                                .attach_local = attach_local,
                                .attach_world = vehicle.transformLocalToWorld(attach_local),

                                .normal_local = normal_local,
                                .normal_world = vehicle.rotateLocalToWorld(normal_local),
                            };
                        }
                    }
                }
            }
        }

        return closest_vehicle;
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
