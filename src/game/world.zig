const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Transform2 = engine.Transform2;

const zbox = @import("zbox");
const b2 = zbox.API;

const UserData = @import("user_data.zig").UserData;

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
const DeviceDef = @import("vehicle.zig").DeviceDef;
const DeviceTransferData = @import("vehicle.zig").DeviceTransferData;

const Player = @import("player.zig").Player;

const item_ns = @import("item.zig");
const Item = item_ns.Item;
const ItemDef = item_ns.ItemDef;

const refs = @import("refs.zig");
const VehicleRef = refs.VehicleRef;
const BlockRef = refs.BlockRef;
const DeviceRef = refs.DeviceRef;
const ItemRef = refs.ItemRef;

pub const VehicleAndBlockRef = struct {
    vehicle: VehicleRef,
    block: BlockRef,

    pub fn format(self: VehicleAndBlockRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}+{s}", .{ self.vehicle, self.block });
    }
};

pub const VehicleAndDeviceRef = struct {
    vehicle: VehicleRef,
    device: DeviceRef,

    pub fn format(self: VehicleAndDeviceRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}+{s}", .{ self.vehicle, self.device });
    }
};

pub const WorldDefs = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    block_defs: []const BlockDef,
    device_defs: []const DeviceDef,
    item_defs: []const ItemDef,

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
        std.log.info("WorldDefs init", .{});

        const block_defs = try BlockDef.getAll(allocator);
        const device_defs = try DeviceDef.getAll(allocator);
        const item_defs = try ItemDef.getAll(allocator);

        self.allocator = allocator;
        self.block_defs = block_defs;
        self.device_defs = device_defs;
        self.item_defs = item_defs;
    }

    pub fn deinit(self: *Self) void {
        std.log.info("WorldDefs deinit", .{});

        self.allocator.free(self.block_defs);
        self.allocator.free(self.device_defs);
        self.allocator.free(self.item_defs);
    }

    pub fn getBlockDef(self: *const Self, id: []const u8) ?BlockDef { // TODO return const pointer
        for (self.block_defs) |block_def| {
            if (std.mem.eql(u8, id, block_def.id)) {
                return block_def;
            }
        }

        std.log.err("block def not found: '{s}'", .{id});
        return null;
    }

    pub fn getDeviceDef(self: *const Self, id: []const u8) ?DeviceDef { // TODO return const pointer
        for (self.device_defs) |device_def| {
            if (std.mem.eql(u8, id, device_def.id)) {
                return device_def;
            }
        }

        std.log.err("device def not found: '{s}'", .{id});
        return null;
    }

    pub fn getItemDef(self: *const Self, id: []const u8) ?*const ItemDef {
        for (self.item_defs) |*item_def| {
            if (std.mem.eql(u8, id, item_def.id)) {
                return item_def;
            }
        }

        std.log.err("item def not found: '{s}'", .{id});
        return null;
    }
};

pub const WorldSettings = struct {
    size: vec2,
    size_changed: bool,

    gravity: vec2,
    gravity_changed: bool,

    start_position: vec2,
    finish_position: vec2,
};

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    settings: WorldSettings,
    defs: *const WorldDefs, // owned by caller

    world_id: b2.b2WorldId,
    outer_bounds_body_id: b2.b2BodyId,

    ground_segments: std.ArrayList(GroundSegment),
    vehicles: std.ArrayList(Vehicle),
    players: std.ArrayList(Player),
    items: std.ArrayList(Item),

    pub fn init(
        self: *Self,
        allocator: std.mem.Allocator,
        defs: *const WorldDefs,
    ) void {
        const world_id = createPhysicsWorld();

        self.* = World{
            .allocator = allocator,
            .settings = .{
                .size = vec2.init(200, 100),
                .size_changed = false,
                .gravity = vec2.init(0, -9.8),
                .gravity_changed = false,
                .start_position = vec2.init(-50, 25),
                .finish_position = vec2.init(50, 25),
            },
            .defs = defs,

            .world_id = world_id,
            .outer_bounds_body_id = b2.b2_nullBodyId,

            .ground_segments = .init(allocator),
            .vehicles = .init(allocator),
            .players = .init(allocator),
            .items = .init(allocator),
        };

        self.updateOuterBounds();
        self.updateGravity();
    }

    fn createPhysicsWorld() b2.b2WorldId {
        const world_def = b2.b2DefaultWorldDef();
        const world_id = b2.b2CreateWorld(&world_def);
        return world_id;
    }

    fn createOuterBounds(world_id: b2.b2WorldId, world_size: vec2) b2.b2BodyId {
        const half_world_size = world_size.scale(0.5);

        var body_def = b2.b2DefaultBodyDef();
        const body_id = b2.b2CreateBody(world_id, &body_def);

        var points = [4]b2.b2Vec2{
            b2.b2Vec2{ .x = -half_world_size.x, .y = -half_world_size.y }, // bottom left
            b2.b2Vec2{ .x = -half_world_size.x, .y = half_world_size.y }, // top left
            b2.b2Vec2{ .x = half_world_size.x, .y = half_world_size.y }, // top right
            b2.b2Vec2{ .x = half_world_size.x, .y = -half_world_size.y }, // bottom right
        };

        var chain_def = b2.b2DefaultChainDef();
        chain_def.isLoop = true;
        chain_def.points = &points;
        chain_def.count = 4;

        _ = b2.b2CreateChain(body_id, &chain_def);

        return body_id;
    }

    fn updateOuterBounds(self: *Self) void {
        std.log.info("world: update outer bounds: {d:.1}", .{self.settings.size});
        //
        if (b2.B2_IS_NON_NULL(self.outer_bounds_body_id)) {
            b2.b2DestroyBody(self.outer_bounds_body_id);
        }
        self.outer_bounds_body_id = createOuterBounds(self.world_id, self.settings.size);
    }

    fn updateGravity(self: *Self) void {
        std.log.info("world: update gravity {d:.2}", .{self.settings.gravity});
        //
        b2.b2World_SetGravity(self.world_id, self.settings.gravity.to_b2());
    }

    pub fn deinit(self: *Self) void {
        for (self.players.items) |*player| {
            player.destroy();
        }

        for (self.items.items) |*item| {
            if (!item.alive) continue;
            item.deinit();
        }

        for (self.vehicles.items) |*vehicle| {
            if (!vehicle.alive) continue;
            vehicle.destroy();
        }

        for (self.ground_segments.items) |*ground_segment| {
            ground_segment.free();
        }

        self.items.deinit();
        self.players.deinit();
        self.vehicles.deinit();
        self.ground_segments.deinit();

        b2.b2DestroyWorld(self.world_id);
    }

    pub fn reset(self: *World) void {
        const alloc = self.allocator;
        const defs = self.defs;

        self.deinit();
        self.init(alloc, defs);

        // TODO clear vs deinit+init ?

        // for (self.players.items) |*player| {
        //     player.destroy(); // player weg oder behalten ??
        // }

        // self.players.clearRetainingCapacity(); // ???

        // for (self.items.items) |*item| {
        //     if (!item.alive) continue;
        //     item.deinit();
        // }

        // for (self.vehicles.items) |*vehicle| {
        //     if (!vehicle.alive) continue;
        //     vehicle.destroy();
        // }

        // for (self.ground_segments.items) |*ground_segment| {
        //     ground_segment.free();
        // }

        // self.items.clearRetainingCapacity();
        // self.vehicles.clearRetainingCapacity();
        // self.ground_segments.clearRetainingCapacity();
    }

    pub fn update(
        self: *World,
        dt: f32,
        temp_allocator: std.mem.Allocator,
        input: *engine.InputState,
        renderer: *engine.Renderer2D, // TODO remove, only used for debugging
    ) void {
        //
        // TODO whats the best order ?
        //
        _ = dt;

        //
        // settings changed?
        //
        if (self.settings.size_changed) {
            self.settings.size_changed = false;
            self.updateOuterBounds();
        }

        if (self.settings.gravity_changed) {
            self.settings.gravity_changed = false;
            self.updateGravity();
        }

        // TODO what to do about start & finish ?

        //
        // ground segments changed?
        //
        for (self.ground_segments.items) |*ground_segment| {
            // TODO: use dirty flag
            ground_segment.update(temp_allocator);
        }

        //
        // vehicles changed?
        //
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
                    std.log.info("no alive blocks left, destroying vehicle", .{});
                    vehicle.destroy();
                    continue;
                }
            }

            // split vehicle?
            {
                //
                var split_result = vehicle.getSplitParts(temp_allocator);
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

                        // Note: using the same body-position for the new vehicle to make it easier to transfer stuff. Must be fixed afterwards.

                        const new_vehicle_pos_world = vec2.from_b2(b2.b2Body_GetPosition(vehicle.body_id));
                        const new_vehicle_ref = self.createVehicle(Transform2.from_pos(new_vehicle_pos_world));
                        const new_vehicle = self.getVehicle(new_vehicle_ref).?;

                        // copy physics state
                        const vehicle_transform = b2.b2Body_GetTransform(vehicle.body_id);
                        b2.b2Body_SetTransform(new_vehicle.body_id, vehicle_transform.p, vehicle_transform.q);
                        b2.b2Body_SetLinearVelocity(new_vehicle.body_id, b2.b2Body_GetLinearVelocity(vehicle.body_id));
                        b2.b2Body_SetAngularVelocity(new_vehicle.body_id, b2.b2Body_GetAngularVelocity(vehicle.body_id));

                        for (part_to_remove) |block_ref| {
                            const block = vehicle.getBlock(block_ref).?.*; // make a copy

                            // get affected device data
                            const device_refs = vehicle.getAllDevicesOnBlock(block_ref, temp_allocator);
                            defer temp_allocator.free(device_refs);
                            var transfer_datas = std.ArrayList(DeviceTransferData).init(temp_allocator);
                            defer transfer_datas.deinit();

                            std.log.info("devices to transfer: {s}", .{device_refs});

                            for (device_refs) |device_ref| {
                                if (vehicle.getDeviceTransferData(device_ref)) |transfer_data| {
                                    transfer_datas.append(transfer_data) catch unreachable;
                                }
                            }

                            // destroy and recreate block
                            vehicle.destroyBlock(block_ref);
                            _ = new_vehicle.createBlock(block.def, block.local_position);

                            // recreate devices
                            for (transfer_datas.items) |transfer_data| {
                                _ = new_vehicle.createDevice(transfer_data.def, transfer_data.local_position);
                            }
                        }
                    }
                }
            }

            // TODO: fix center after vehicle has been changed
            // - but this might cause accumulating floating point errors?
        }

        //
        // Step vehicles
        //
        for (self.vehicles.items) |*vehicle| {
            if (!vehicle.alive) continue;

            vehicle.update(input, renderer);
        }

        //
        // Step world
        //
        const physics_time_step: f32 = 1.0 / 60.0; // TODO run multiple steps depending on frame dt
        const physics_sub_step_count: i32 = 4;

        b2.b2World_Step(self.world_id, physics_time_step, physics_sub_step_count);
    }

    pub fn checkWinCondition(self: *Self) bool {
        for (self.players.items) |*player| {
            const t = player.getTransform();
            const dist_to_finish = vec2.dist(t.pos, self.settings.finish_position);

            //std.log.info("dist {d}", .{dist_to_finish});

            if (dist_to_finish < 2.5) { // xxx
                return true;
            }
        }

        return false;
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
    // vehicles
    //

    pub fn getVehicle(self: *World, vehicle_ref: VehicleRef) ?*Vehicle {
        const vehicle = &self.vehicles.items[vehicle_ref.vehicle_index];

        if (vehicle.alive) {
            return vehicle;
        }

        return null;
    }

    pub fn createVehicle(self: *World, transform: Transform2) VehicleRef {
        const vehicle = Vehicle.create(self.allocator, self.world_id, transform);

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

    pub const ClosestVehicleAndBlockResult = struct {
        ref: VehicleAndBlockRef,
        block_world: vec2,
    };

    pub fn getClosestVehicleAndBlock(self: *World, position_world: vec2, max_distance: f32) ?ClosestVehicleAndBlockResult {
        var closest_dist: f32 = std.math.floatMax(f32);
        var closest_vehicle_ref: ?ClosestVehicleAndBlockResult = null;

        for (self.vehicles.items, 0..) |*vehicle, vehicle_index| {
            if (!vehicle.alive) continue;

            for (vehicle.blocks.items, 0..) |*block, block_index| {
                if (!block.alive) continue;

                const block_position_world = vehicle.transformLocalToWorld(block.local_position);
                const dist = vec2.dist(block_position_world, position_world);

                if (dist < max_distance and dist < closest_dist) {
                    closest_dist = dist;
                    closest_vehicle_ref = ClosestVehicleAndBlockResult{
                        .ref = VehicleAndBlockRef{
                            .vehicle = VehicleRef{
                                .vehicle_index = vehicle_index,
                            },
                            .block = BlockRef{
                                .block_index = block_index,
                            },
                        },
                        .block_world = block_position_world,
                    };
                }
            }
        }

        return closest_vehicle_ref;
    }

    pub const ClosestVehicleAndBlockOrDeviceResult = union(enum) {
        VehicleAndBlock: struct {
            ref: VehicleAndBlockRef,
            //block_def: BlockDef,
            //block_local: vec2,
            block_world: vec2,
        },
        VehicleAndDevice: struct {
            ref: VehicleAndDeviceRef,
            device_world: vec2,
        },
    };

    pub fn getClosestVehicleAndBlockOrDevice(self: *World, position_world: vec2, max_distance: f32) ?ClosestVehicleAndBlockOrDeviceResult {
        var closest_dist: f32 = std.math.floatMax(f32);
        var closest_vehicle: ?ClosestVehicleAndBlockOrDeviceResult = null;

        for (self.vehicles.items, 0..) |*vehicle, vehicle_index| {
            if (!vehicle.alive) continue;

            for (vehicle.blocks.items, 0..) |*block, block_index| {
                if (!block.alive) continue;

                const block_position_world = vehicle.transformLocalToWorld(block.local_position);
                const dist = vec2.dist(block_position_world, position_world);

                if (dist < max_distance and dist < closest_dist) {
                    closest_dist = dist;
                    closest_vehicle = ClosestVehicleAndBlockOrDeviceResult{
                        .VehicleAndBlock = .{
                            .ref = VehicleAndBlockRef{
                                .vehicle = VehicleRef{
                                    .vehicle_index = vehicle_index,
                                },
                                .block = BlockRef{
                                    .block_index = block_index,
                                },
                            },
                            //.block_def = block.def,
                            //.block_local = block.local_position,
                            .block_world = block_position_world,
                        },
                    };
                }
            }

            for (vehicle.devices.items, 0..) |*device, device_index| {
                if (!device.alive) continue;

                const device_position_world = vehicle.transformLocalToWorld(device.local_position);
                const dist = vec2.dist(device_position_world, position_world);

                if (dist < max_distance and dist < closest_dist) {
                    closest_dist = dist;
                    closest_vehicle = ClosestVehicleAndBlockOrDeviceResult{
                        .VehicleAndDevice = .{
                            .ref = VehicleAndDeviceRef{
                                .vehicle = VehicleRef{
                                    .vehicle_index = vehicle_index,
                                },
                                .device = DeviceRef{
                                    .device_index = device_index,
                                },
                            },
                            .device_world = device_position_world,
                        },
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

    //
    // items
    //

    pub fn createItem(self: *Self, def: *const ItemDef, transform: Transform2) !ItemRef {
        const index = self.items.items.len;

        // TODO ArrayList vielleicht nicht das richtige? Lieber selbst verwalten mit alloc?
        // aktuell: struct-init + init() das ist nicht so gut
        try self.items.append(Item{
            .alive = undefined,
            .def = undefined,
            .body_id = undefined,
        });

        const item: *Item = &self.items.items[index];
        item.init(self.world_id, def, transform);

        const user_data = UserData{
            .type = .Item,
            .index = @intCast(index),
            // TODO item_version
        };
        user_data.setToBody(item.body_id);

        const item_ref = ItemRef{
            .item_index = index,
        };
        return item_ref;
    }

    pub fn getItem(self: *Self, ref: ItemRef) ?*Item {
        const item: *Item = &self.items.items[ref.item_index];
        if (item.alive) {
            return item;
        }

        return null;
    }

    pub fn destroyItem(self: *Self, ref: ItemRef) bool {
        if (self.getItem(ref)) |item| {
            item.deinit();
            return true;
        } else {
            std.log.warn("destroyItem: item not found: {s}", .{ref});
            return false;
        }
    }

    //
    // players
    //

    pub fn createPlayer(self: *World, position: vec2) void {
        const player = Player.create(self, position);

        self.players.append(player) catch unreachable;
    }

    pub fn movePlayersToStart(self: *Self) void {
        for (self.players.items) |*player| {
            player.teleportTo(self.settings.start_position);
        }
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
