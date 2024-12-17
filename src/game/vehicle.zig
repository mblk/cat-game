const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;

const zbox = @import("zbox");
const b2 = zbox.API;

// TODO b2 user data
// body -> Vehicle
// shape -> Block ?

pub const BlockDef = struct {
    id: []const u8,
    size: vec2,

    pub fn getAll(allocator: std.mem.Allocator) ![]BlockDef {
        var list = std.ArrayList(BlockDef).init(allocator);
        defer list.deinit();

        try list.append(BlockDef{
            .id = "block_1x1",
            .size = vec2.init(1, 1),
        });
        try list.append(BlockDef{
            .id = "block_2x1",
            .size = vec2.init(2, 1),
        });
        try list.append(BlockDef{
            .id = "block_4x1",
            .size = vec2.init(4, 1),
        });
        try list.append(BlockDef{
            .id = "block_2x2",
            .size = vec2.init(2, 2),
        });

        return list.toOwnedSlice();
    }
};

pub const BlockRef = struct {
    block_index: usize,
    //block_version

    pub fn format(self: BlockRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Block(idx={d})", .{self.block_index});
    }

    pub fn equals(self: BlockRef, other: BlockRef) bool {
        return self.block_index == other.block_index;
    }
};

pub const Block = struct {
    //
    alive: bool,
    //
    def: BlockDef, // copy for now, maybe change later
    local_position: vec2,
    shape_id: b2.b2ShapeId,

    pub fn create(body_id: b2.b2BodyId, def: BlockDef, local_position: vec2) Block {
        //
        const hw = def.size.x * 0.5;
        const hh = def.size.y * 0.5;
        const box = b2.b2MakeOffsetBox(hw, hh, local_position.to_b2(), b2.b2Rot_identity);

        var shape_def = b2.b2DefaultShapeDef();
        shape_def.density = 1.0;
        shape_def.friction = 0.3;

        const shape_id = b2.b2CreatePolygonShape(body_id, &shape_def, &box);

        const block = Block{
            .alive = true,
            .def = def,
            .local_position = local_position,
            .shape_id = shape_id,
        };

        return block;
    }

    pub fn destroy(self: *Block) void {
        std.debug.assert(self.alive);

        //
        b2.b2DestroyShape(self.shape_id, true);

        self.alive = false;
    }
};

pub const BlockConnectionEdge = struct {
    // id
    block1: BlockRef,
    block2: BlockRef,

    // extra data
    center_local: vec2,
    normal_local: vec2,

    pub fn format(self: BlockConnectionEdge, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Edge {s} {s}", .{ self.block1, self.block2 });
    }

    pub fn equals(self: BlockConnectionEdge, other: BlockConnectionEdge) bool {
        return self.block1.equals(other.block1) and self.block2.equals(other.block2) or
            self.block1.equals(other.block2) and self.block2.equals(other.block1);
    }

    pub fn tryGetOther(self: BlockConnectionEdge, ref: BlockRef) ?BlockRef {
        if (self.block1.equals(ref)) {
            return self.block2;
        } else if (self.block2.equals(ref)) {
            return self.block1;
        } else {
            return null;
        }
    }
};

pub fn Graph(comptime T: type) type {
    return struct {
        const Self = @This();

        edges: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) Graph(T) {
            return Self{
                .edges = std.ArrayList(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.edges.deinit();
        }

        pub fn hasEdge(self: *Self, edge: T) bool {
            for (self.edges.items) |x| {
                if (x.equals(edge)) {
                    return true;
                }
            }

            return false;
        }

        pub fn addEdge(self: *Self, edge: T) void {
            std.log.info("addEdge {s}", .{edge});
            self.edges.append(edge) catch unreachable;
        }
    };
}

pub const DeviceType = enum {
    Wheel,
    Thruster,
};

pub const DeviceDef = struct {
    id: []const u8,
    data: union(DeviceType) {
        Wheel: WheelDeviceDef,
        Thruster: ThrusterDeviceDef,
    },

    pub fn getAll(allocator: std.mem.Allocator) ![]DeviceDef {
        var list = std.ArrayList(DeviceDef).init(allocator);
        defer list.deinit();

        try list.append(DeviceDef{
            .id = "wheel_1",
            .data = .{
                .Wheel = .{
                    .radius = 1.0,
                    .has_motor = false,
                    .max_torque = 0,
                },
            },
        });
        try list.append(DeviceDef{
            .id = "wheel_2",
            .data = .{
                .Wheel = .{
                    .radius = 2.0,
                    .has_motor = true,
                    .max_torque = 10.0,
                },
            },
        });

        try list.append(DeviceDef{
            .id = "thruster_1",
            .data = .{
                .Thruster = .{
                    .max_thrust = 100.0,
                },
            },
        });

        return list.toOwnedSlice();
    }
};

pub const DeviceRef = struct {
    device_index: usize,
    // version
};

pub const Device = struct {
    alive: bool,
    type: DeviceType,
    local_position: vec2,
    data_index: usize, // index into wheel/thruster/etc-arrays
    block_index: usize, // index into block-array
};

pub const WheelDeviceDef = struct {
    radius: f32,
    has_motor: bool,
    max_torque: f32,
};

pub const WheelDevice = struct {
    alive: bool,
    def: WheelDeviceDef,

    body_id: b2.b2BodyId,
    joint_id: b2.b2JointId,

    fn create(def: WheelDeviceDef, world_id: b2.b2WorldId, parent_body_id: b2.b2BodyId, position_world: vec2) WheelDevice {
        std.log.info("wheel create", .{});

        // create wheel body
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position.x = 0;
        body_def.position.y = 0;
        const body_id = b2.b2CreateBody(world_id, &body_def);

        const circle = b2.b2Circle{
            .center = position_world.to_b2(),
            .radius = 2.0,
        };

        const shape = b2.b2DefaultShapeDef();

        _ = b2.b2CreateCircleShape(body_id, &shape, &circle);

        // create wheel joint
        var wheel_joint_def = b2.b2DefaultWheelJointDef();
        wheel_joint_def.collideConnected = false;
        wheel_joint_def.bodyIdA = parent_body_id;
        wheel_joint_def.bodyIdB = body_id;
        wheel_joint_def.localAxisA = vec2.init(0, 1).to_b2();
        wheel_joint_def.localAnchorA = b2.b2Body_GetLocalPoint(wheel_joint_def.bodyIdA, position_world.to_b2());
        wheel_joint_def.localAnchorB = b2.b2Body_GetLocalPoint(wheel_joint_def.bodyIdB, position_world.to_b2());

        std.log.info("local anchor a {any}", .{wheel_joint_def.localAnchorA});
        std.log.info("local anchor b {any}", .{wheel_joint_def.localAnchorB});

        wheel_joint_def.enableLimit = true;
        wheel_joint_def.upperTranslation = -2;
        wheel_joint_def.lowerTranslation = -3;

        wheel_joint_def.hertz = 1.0;
        wheel_joint_def.dampingRatio = 0.7;

        const joint_id = b2.b2CreateWheelJoint(world_id, &wheel_joint_def);

        //2Vec2 pivot = { 0.0f, 10.0f };
        // b2Vec2 axis = b2Normalize( { 1.0f, 1.0f } );
        // b2WheelJointDef jointDef = b2DefaultWheelJointDef();
        // jointDef.bodyIdA = groundId;
        // jointDef.bodyIdB = bodyId;
        // jointDef.localAxisA = b2Body_GetLocalVector( jointDef.bodyIdA, axis );
        // jointDef.localAnchorA = b2Body_GetLocalPoint( jointDef.bodyIdA, pivot );
        // jointDef.localAnchorB = b2Body_GetLocalPoint( jointDef.bodyIdB, pivot );
        // jointDef.motorSpeed = m_motorSpeed;
        // jointDef.maxMotorTorque = m_motorTorque;
        // jointDef.enableMotor = m_enableMotor;
        // jointDef.lowerTranslation = -3.0f;
        // jointDef.upperTranslation = 3.0f;
        // jointDef.enableLimit = m_enableLimit;
        // jointDef.hertz = m_hertz;
        // jointDef.dampingRatio = m_dampingRatio;

        // m_jointId = b2CreateWheelJoint( m_worldId, &jointDef );

        return WheelDevice{
            .alive = true,
            .def = def,

            .body_id = body_id,
            .joint_id = joint_id,
        };
    }
};

pub const ThrusterDeviceDef = struct {
    max_thrust: f32,
};

pub const ThrusterDevice = struct {
    alive: bool,
    def: ThrusterDeviceDef,

    fn create(def: ThrusterDeviceDef) ThrusterDevice {
        std.log.info("thruster create", .{});

        return ThrusterDevice{
            .alive = true,
            .def = def,
        };
    }
};

pub const Vehicle = struct {
    //
    alive: bool,
    //
    world_id: b2.b2WorldId,
    body_id: b2.b2BodyId,
    blocks: std.ArrayList(Block),

    devices: std.ArrayList(Device),
    wheels: std.ArrayList(WheelDevice),
    thrusters: std.ArrayList(ThrusterDevice),

    block_connection_graph: Graph(BlockConnectionEdge),

    edit_flag: bool,

    pub fn create(allocator: std.mem.Allocator, world_id: b2.b2WorldId, position: vec2) Vehicle {
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position.x = position.x;
        body_def.position.y = position.y;
        const body_id = b2.b2CreateBody(world_id, &body_def);

        const vehicle = Vehicle{
            .alive = true,
            .world_id = world_id,
            .body_id = body_id,
            .blocks = .init(allocator),
            .devices = .init(allocator),
            .wheels = .init(allocator),
            .thrusters = .init(allocator),
            .block_connection_graph = .init(allocator),
            .edit_flag = false,
        };

        //vehicle.createBlock(vec2.init(0, 0));
        //vehicle.createBlock(vec2.init(1, 0));

        return vehicle;
    }

    pub fn destroy(self: *Vehicle) void {
        std.debug.assert(self.alive);

        // TODO destroy devices etc

        for (self.blocks.items) |*block| {
            if (!block.alive) continue;
            block.destroy();
        }

        self.block_connection_graph.deinit();
        self.thrusters.deinit();
        self.wheels.deinit();
        self.devices.deinit();
        self.blocks.deinit();

        b2.b2DestroyBody(self.body_id);

        self.alive = false;
    }

    pub fn transformWorldToLocal(self: *Vehicle, world_position: vec2) vec2 {
        std.debug.assert(self.alive);

        const transform = b2.b2Body_GetTransform(self.body_id);
        return vec2.from_b2(b2.b2InvTransformPoint(transform, world_position.to_b2()));
    }

    pub fn transformLocalToWorld(self: *Vehicle, local_position: vec2) vec2 {
        std.debug.assert(self.alive);

        const transform = b2.b2Body_GetTransform(self.body_id);
        return vec2.from_b2(b2.b2TransformPoint(transform, local_position.to_b2()));
    }

    pub fn rotateLocalToWorld(self: *Vehicle, local_vector: vec2) vec2 {
        std.debug.assert(self.alive);

        const transform = b2.b2Body_GetTransform(self.body_id);
        return vec2.from_b2(b2.b2RotateVector(transform.q, local_vector.to_b2()));
    }

    pub fn rotateWorldToLocal(self: *Vehicle, world_vector: vec2) vec2 {
        std.debug.assert(self.alive);

        const transform = b2.b2Body_GetTransform(self.body_id);
        return vec2.from_b2(b2.b2InvRotateVector(transform.q, world_vector.to_b2()));
    }

    pub fn getBlock(self: *Vehicle, ref: BlockRef) ?*Block {
        std.debug.assert(self.alive);

        const block: *Block = &self.blocks.items[ref.block_index];
        if (block.alive) {
            return block;
        }

        return null;
    }

    pub fn createBlock(self: *Vehicle, def: BlockDef, local_position: vec2) BlockRef {
        std.debug.assert(self.alive);

        const index = self.blocks.items.len;

        const block = Block.create(self.body_id, def, local_position);
        self.blocks.append(block) catch unreachable;

        b2.b2Body_SetAwake(self.body_id, true);

        const ref = BlockRef{
            .block_index = index,
        };

        self.updateBlockConnectionGraphAfterBlockAdded(ref);

        self.edit_flag = true;

        return ref;
    }

    // pub fn _getClosestBlock(self: *Vehicle, world_position: vec2) ?*Block {
    //     std.debug.assert(self.alive);

    //     var closest_dist: f32 = std.math.floatMax(f32);
    //     var closest_block: ?*Block = null;

    //     const vehicle_transform = b2.b2Body_GetTransform(self.body_id);

    //     for (self.blocks.items) |*block| {
    //         if (!block.alive) continue;

    //         const block_position = vec2.from_b2(b2.b2TransformPoint(vehicle_transform, block.local_position.to_b2()));
    //         const dist = vec2.dist(world_position, block_position);

    //         if (dist < closest_dist) {
    //             closest_dist = dist;
    //             closest_block = block;
    //         }
    //     }

    //     return closest_block;
    // }

    pub fn destroyBlock(self: *Vehicle, block_ref: BlockRef) void {
        std.debug.assert(self.alive);

        // destroy block
        {
            const block = &self.blocks.items[block_ref.block_index];
            block.destroy();
        }

        // ...
        self.updateBlockConnectionGraphAfterBlockRemoved(block_ref);

        // wake up physics
        b2.b2Body_SetAwake(self.body_id, true);

        self.edit_flag = true;
    }

    fn updateBlockConnectionGraphAfterBlockAdded(self: *Vehicle, added_block_ref: BlockRef) void {
        const new_block: *Block = self.getBlock(added_block_ref).?;

        std.log.info("== updateBlockConnectionGraphAfterBlockAdded ==", .{});

        // compare new block to all other blocks
        for (self.blocks.items, 0..) |*other_block, other_block_index| {
            if (!other_block.alive) continue;
            if (other_block_index == added_block_ref.block_index) continue;

            if (blocksAreTouching(new_block, other_block)) {
                //
                const center_local = other_block.local_position.add(new_block.local_position).scale(0.5);
                const normal_local = getContactNormal(new_block, other_block).?;

                const edge = BlockConnectionEdge{
                    .block1 = added_block_ref,
                    .block2 = BlockRef{
                        .block_index = other_block_index,
                    },
                    .center_local = center_local,
                    .normal_local = normal_local,
                };

                if (!self.block_connection_graph.hasEdge(edge)) {
                    self.block_connection_graph.addEdge(edge);
                }
            }
        }
    }

    fn updateBlockConnectionGraphAfterBlockRemoved(self: *Vehicle, removed_block_ref: BlockRef) void {
        std.log.info("== updateBlockConnectionGraphAfterBlockRemoved ==", .{});

        // remove all matching connections
        var i: usize = 0;
        while (i < self.block_connection_graph.edges.items.len) {
            const edge = self.block_connection_graph.edges.items[i];

            if (edge.block1.equals(removed_block_ref) or edge.block2.equals(removed_block_ref)) {
                _ = self.block_connection_graph.edges.swapRemove(i);
            } else {
                i += 1;
            }
        }

        //
    }

    fn blocksAreTouching(block1: *Block, block2: *Block) bool {
        const p1 = block1.local_position;
        const p2 = block2.local_position;

        const hs1 = block1.def.size.scale(0.5);
        const hs2 = block2.def.size.scale(0.5);

        const tolerance = 0.1;

        const min1 = p1.sub(hs1);
        const max1 = p1.add(hs1);
        const min2 = p2.sub(hs2);
        const max2 = p2.add(hs2);

        const overlapX = min1.x <= max2.x + tolerance and max1.x >= min2.x - tolerance;
        const overlapY = min1.y <= max2.y + tolerance and max1.y >= min2.y - tolerance;

        return overlapX and overlapY;
    }

    fn getContactNormal(block1: *Block, block2: *Block) ?vec2 {
        const p1 = block1.local_position;
        const p2 = block2.local_position;

        const hs1 = block1.def.size.scale(0.5);
        const hs2 = block2.def.size.scale(0.5);

        const tolerance = 0.1;

        const min1 = p1.sub(hs1);
        const max1 = p1.add(hs1);
        const min2 = p2.sub(hs2);
        const max2 = p2.add(hs2);

        // Berechne die Penetration (oder den Abstand mit Toleranz) auf jeder Achse
        const penetrationX = if (min1.x <= max2.x + tolerance and max1.x >= min2.x - tolerance)
            @min(max1.x - min2.x, max2.x - min1.x)
        else
            -1.0; // Kein Kontakt auf dieser Achse

        const penetrationY = if (min1.y <= max2.y + tolerance and max1.y >= min2.y - tolerance)
            @min(max1.y - min2.y, max2.y - min1.y)
        else
            -1.0;

        // Identifiziere die Achse mit der kleinsten positiven Penetration
        var minPenetration = std.math.floatMax(f32);
        var normal = vec2{ .x = 0, .y = 0 };

        if (penetrationX >= 0 and penetrationX < minPenetration) {
            minPenetration = penetrationX;
            normal = vec2{ .x = if (p1.x > p2.x) 1 else -1, .y = 0 };
        }
        if (penetrationY >= 0 and penetrationY < minPenetration) {
            minPenetration = penetrationY;
            normal = vec2{ .x = 0, .y = if (p1.y > p2.y) 1 else -1 };
        }

        // Falls keine Penetration gefunden wurde, gibt es keinen Kontakt
        if (minPenetration == std.math.floatMax(f32)) {
            //return null;
            std.log.warn("getContactNormal failed", .{});
            return vec2.init(1, 0);
        }

        return normal;
    }

    pub const SplitPartsResult = struct {
        allocator: std.mem.Allocator,
        parts: [][]BlockRef,

        pub fn deinit(self: *SplitPartsResult) void {
            for (self.parts) |part| {
                self.allocator.free(part);
            }
            self.allocator.free(self.parts);
        }
    };

    pub fn getSplitParts(self: *Vehicle, temp_allocator: std.mem.Allocator) SplitPartsResult {
        // state
        var remaining = std.AutoHashMap(BlockRef, void).init(temp_allocator);
        defer remaining.deinit();
        var visited = std.AutoHashMap(BlockRef, void).init(temp_allocator);
        defer visited.deinit();

        for (self.blocks.items, 0..) |block, block_index| {
            if (!block.alive) continue;

            const block_ref = BlockRef{
                .block_index = block_index,
            };

            remaining.put(block_ref, {}) catch unreachable;
        }

        // result builder
        var parts = std.ArrayList([]BlockRef).init(temp_allocator);
        defer parts.deinit();
        var current_part = std.ArrayList(BlockRef).init(temp_allocator);
        defer current_part.deinit();

        // remaining work
        var next = std.ArrayList(BlockRef).init(temp_allocator);
        defer next.deinit();

        while (true) {
            var key_iter = remaining.keyIterator();
            const maybe_first = key_iter.next();
            if (maybe_first == null) break;
            const first = maybe_first.?.*;
            std.log.info("first: {s}", .{first});

            next.clearRetainingCapacity();
            next.append(first) catch unreachable;

            std.debug.assert(current_part.items.len == 0);
            current_part.clearRetainingCapacity(); // just in case

            while (next.items.len > 0) {
                const current = next.swapRemove(0); // pop first

                if (visited.contains(current)) {
                    std.log.info("current already visited {s}", .{current});
                    continue;
                }

                std.log.info("current: {s}", .{current});

                visited.put(current, {}) catch unreachable;
                current_part.append(current) catch unreachable;

                const was_removed = remaining.remove(current);
                std.debug.assert(was_removed);

                // add all connected blocks to the 'next' queue
                for (self.block_connection_graph.edges.items) |edge| {
                    if (edge.tryGetOther(current)) |other| {
                        if (visited.contains(other)) continue;

                        std.debug.assert(!other.equals(current));
                        next.append(other) catch unreachable;
                    }
                }
            }

            std.debug.assert(current_part.items.len > 0);
            parts.append(current_part.toOwnedSlice() catch unreachable) catch unreachable;
            std.debug.assert(current_part.items.len == 0);
        }

        {
            std.debug.assert(parts.items.len > 0);
            const parts_slice: [][]BlockRef = parts.toOwnedSlice() catch unreachable;

            std.mem.sort([]BlockRef, parts_slice, {}, struct {
                pub fn inner(ctx: void, lhs: []BlockRef, rhs: []BlockRef) bool {
                    _ = ctx;
                    return lhs.len > rhs.len;
                }
            }.inner);

            return SplitPartsResult{
                .allocator = temp_allocator,
                .parts = parts_slice,
            };
        }
    }

    //
    // devices
    //

    pub fn createDevice(self: *Vehicle, def: DeviceDef, local_position: vec2) DeviceRef {
        var data_index: usize = 0;

        const world_position = self.transformLocalToWorld(local_position);

        switch (def.data) {
            .Wheel => |wheel_def| {
                //
                const wheel_index = self.wheels.items.len;
                const wheel = WheelDevice.create(wheel_def, self.world_id, self.body_id, world_position);
                self.wheels.append(wheel) catch unreachable;

                data_index = wheel_index;
            },

            .Thruster => |thruster_def| {
                //
                const thruster_index = self.thrusters.items.len;
                const thruster = ThrusterDevice.create(thruster_def);
                self.thrusters.append(thruster) catch unreachable;

                data_index = thruster_index;
            },
        }

        const device_index = self.devices.items.len;

        self.devices.append(Device{
            .alive = true,
            .type = def.data,
            .local_position = local_position,
            .block_index = 0,
            .data_index = data_index,
        }) catch unreachable;

        return DeviceRef{
            .device_index = device_index,
        };
    }
};
