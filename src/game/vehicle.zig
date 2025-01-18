const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const rot2 = engine.rot2;
const Transform2 = engine.Transform2;

const zbox = @import("zbox");
const b2 = zbox.API;

const refs = @import("refs.zig");
const BlockRef = refs.BlockRef;
const DeviceRef = refs.DeviceRef;

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
                    .max_suspension = 0,
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
                    .max_suspension = 1.0,
                },
            },
        });

        try list.append(DeviceDef{
            .id = "thruster_1",
            .data = .{
                .Thruster = .{
                    .size = vec2.init(0.25, 0.5),
                    .max_thrust = 10.0,
                },
            },
        });

        try list.append(DeviceDef{
            .id = "thruster_2",
            .data = .{
                .Thruster = .{
                    .size = vec2.init(0.5, 1.0),
                    .max_thrust = 100.0,
                },
            },
        });

        return list.toOwnedSlice();
    }
};

pub const DeviceTransferData = struct {
    def: DeviceDef,
    local_position: vec2,
};

pub const Device = struct {
    alive: bool,
    def: DeviceDef,
    type: DeviceType,
    local_position: vec2,
    data_index: usize, // index into wheel/thruster/etc-arrays
    block_index: usize, // index into block-array
};

pub const WheelDeviceDef = struct {
    radius: f32,
    has_motor: bool,
    max_torque: f32,
    max_suspension: f32,
};

pub const WheelDevice = struct {
    const Self = @This();

    alive: bool,
    def: WheelDeviceDef,

    parent_body_id: b2.b2BodyId,
    body_id: b2.b2BodyId,
    joint_id: b2.b2JointId,

    control_left_key: engine.InputState.Key = .four,
    control_right_key: engine.InputState.Key = .five,

    fn create(def: WheelDeviceDef, world_id: b2.b2WorldId, parent_body_id: b2.b2BodyId, position_world: vec2) WheelDevice {
        std.log.info("wheel create", .{});

        // create wheel body
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position = position_world.to_b2();
        const body_id = b2.b2CreateBody(world_id, &body_def);

        const circle = b2.b2Circle{
            .center = b2.b2Vec2_zero,
            .radius = def.radius,
        };

        var shape = b2.b2DefaultShapeDef();
        shape.density = 0.1;
        shape.friction = 0.9;

        _ = b2.b2CreateCircleShape(body_id, &shape, &circle);

        // create wheel joint
        var wheel_joint_def = b2.b2DefaultWheelJointDef();
        wheel_joint_def.collideConnected = false;
        wheel_joint_def.bodyIdA = parent_body_id;
        wheel_joint_def.bodyIdB = body_id;
        wheel_joint_def.localAxisA = vec2.init(0, 1).to_b2();
        wheel_joint_def.localAnchorA = b2.b2Body_GetLocalPoint(wheel_joint_def.bodyIdA, position_world.to_b2());
        wheel_joint_def.localAnchorB = b2.b2Body_GetLocalPoint(wheel_joint_def.bodyIdB, position_world.to_b2());

        // std.log.info("local anchor a {any}", .{wheel_joint_def.localAnchorA});
        // std.log.info("local anchor b {any}", .{wheel_joint_def.localAnchorB});

        wheel_joint_def.enableLimit = true;
        wheel_joint_def.upperTranslation = def.max_suspension / 2;
        wheel_joint_def.lowerTranslation = -def.max_suspension / 2;

        wheel_joint_def.hertz = 1.0;
        wheel_joint_def.dampingRatio = 0.7;

        const joint_id = b2.b2CreateWheelJoint(world_id, &wheel_joint_def);

        return WheelDevice{
            .alive = true,
            .def = def,

            .parent_body_id = parent_body_id,
            .body_id = body_id,
            .joint_id = joint_id,
        };
    }

    fn destroy(self: *Self) void {
        std.log.info("wheel destroy", .{});

        std.debug.assert(self.alive);

        self.alive = false;

        b2.b2DestroyJoint(self.joint_id);
        b2.b2DestroyBody(self.body_id);

        self.joint_id = b2.b2_nullJointId;
        self.body_id = b2.b2_nullBodyId;
    }

    fn update(self: *Self, input: *engine.InputState) void {
        var target: f32 = 0;

        if (input.getKeyState(self.control_left_key)) {
            target += 1;
        }
        if (input.getKeyState(self.control_right_key)) {
            target -= 1;
        }

        if (@abs(target) > 0.1) {
            b2.b2Body_SetAwake(self.parent_body_id, true);
            b2.b2Body_SetAwake(self.body_id, true);

            b2.b2WheelJoint_SetMotorSpeed(self.joint_id, target * 10); // rad/s ?
            b2.b2WheelJoint_SetMaxMotorTorque(self.joint_id, 100.0); // Nm ?
            b2.b2WheelJoint_EnableMotor(self.joint_id, true);
        } else {
            b2.b2WheelJoint_EnableMotor(self.joint_id, false);
        }
    }

    pub fn getWheelTransform(self: *const Self) Transform2 {
        const b2transform = b2.b2Body_GetTransform(self.body_id); // TODO maybe do this once in update?
        return Transform2.from_b2(b2transform);
    }
};

pub const ThrusterDeviceDef = struct {
    size: vec2,
    max_thrust: f32,
};

pub const ThrusterDevice = struct {
    const Self = @This();

    alive: bool,
    def: ThrusterDeviceDef,

    position_local: vec2,

    parent_body_id: b2.b2BodyId,
    shape_id: b2.b2ShapeId,

    control_key: engine.InputState.Key = .one,

    fn create(def: ThrusterDeviceDef, parent_body_id: b2.b2BodyId, position_local: vec2) ThrusterDevice {
        std.log.info("thruster create", .{});

        const hw = def.size.x * 0.5;
        const hh = def.size.y * 0.5;
        const box = b2.b2MakeOffsetBox(hw, hh, position_local.to_b2(), b2.b2Rot_identity);

        var shape_def = b2.b2DefaultShapeDef();
        shape_def.density = 1.0;
        shape_def.friction = 0.3;

        const shape_id = b2.b2CreatePolygonShape(parent_body_id, &shape_def, &box);

        return ThrusterDevice{
            .alive = true,
            .def = def,

            .position_local = position_local,

            .parent_body_id = parent_body_id,
            .shape_id = shape_id,
        };
    }

    fn destroy(self: *Self) void {
        std.log.info("thruster destroy", .{});

        std.debug.assert(self.alive);

        b2.b2DestroyShape(self.shape_id, true);
        self.shape_id = b2.b2_nullShapeId;

        self.alive = false;
    }

    fn update(self: *Self, input: *engine.InputState, renderer: *engine.Renderer2D) void {
        //_ = self;
        //_ = input;
        //_ = renderer;

        if (input.getKeyState(self.control_key)) {
            const transform = b2.b2Body_GetTransform(self.parent_body_id);

            // apply force here
            const position_world = vec2.from_b2(b2.b2TransformPoint(transform, self.position_local.to_b2()));

            // in this direction
            const force_dir_local = vec2.init(0, 1);
            const force_dir_world = vec2.from_b2(b2.b2RotateVector(transform.q, force_dir_local.to_b2()));
            const force = force_dir_world.scale(self.def.max_thrust);

            b2.b2Body_ApplyForce(self.parent_body_id, force.to_b2(), position_world.to_b2(), true);

            renderer.addLine(
                position_world,
                position_world.add(force_dir_world.neg()),
                engine.Renderer2D.Layers.Debug,
                engine.Color.red,
            );
        }
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

    pub fn create(allocator: std.mem.Allocator, world_id: b2.b2WorldId, transform: Transform2) Vehicle {
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position = transform.pos.to_b2();
        body_def.rotation = transform.rot.to_b2();
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
            .edit_flag = false, // TODO maybe start with true so world.update can do stuff
        };

        //vehicle.createBlock(vec2.init(0, 0));
        //vehicle.createBlock(vec2.init(1, 0));

        return vehicle;
    }

    pub fn destroy(self: *Vehicle) void {
        std.debug.assert(self.alive);

        for (self.devices.items, 0..) |*device, device_index| {
            if (!device.alive) continue;

            self.destroyDevice(.{
                .device_index = device_index,
            });
        }

        for (self.blocks.items, 0..) |*block, block_index| {
            if (!block.alive) continue;

            self.destroyBlock(.{
                .block_index = block_index,
            });
        }

        self.block_connection_graph.deinit();
        self.thrusters.deinit();
        self.wheels.deinit();
        self.devices.deinit();
        self.blocks.deinit();

        b2.b2DestroyBody(self.body_id);

        self.alive = false;
    }

    pub fn update(self: *Vehicle, input: *engine.InputState, renderer: *engine.Renderer2D) void {
        for (self.devices.items) |*device| {
            if (!device.alive) continue;

            //
        }

        for (self.wheels.items) |*wheel| {
            if (!wheel.alive) continue;

            wheel.update(input);
        }

        for (self.thrusters.items) |*thruster| {
            if (!thruster.alive) continue;

            thruster.update(input, renderer);
        }
    }

    pub fn getTransform(self: *const Vehicle) Transform2 {
        std.debug.assert(self.alive);

        const t = b2.b2Body_GetTransform(self.body_id);
        return Transform2.from_b2(t);
    }

    pub fn transformWorldToLocal(self: *const Vehicle, world_position: vec2) vec2 {
        std.debug.assert(self.alive);

        const transform = b2.b2Body_GetTransform(self.body_id);
        return vec2.from_b2(b2.b2InvTransformPoint(transform, world_position.to_b2()));
    }

    pub fn transformLocalToWorld(self: *const Vehicle, local_position: vec2) vec2 {
        std.debug.assert(self.alive);

        const transform = b2.b2Body_GetTransform(self.body_id);
        return vec2.from_b2(b2.b2TransformPoint(transform, local_position.to_b2()));
    }

    pub fn rotateLocalToWorld(self: *const Vehicle, local_vector: vec2) vec2 {
        std.debug.assert(self.alive);

        const transform = b2.b2Body_GetTransform(self.body_id);
        return vec2.from_b2(b2.b2RotateVector(transform.q, local_vector.to_b2()));
    }

    pub fn rotateWorldToLocal(self: *const Vehicle, world_vector: vec2) vec2 {
        std.debug.assert(self.alive);

        const transform = b2.b2Body_GetTransform(self.body_id);
        return vec2.from_b2(b2.b2InvRotateVector(transform.q, world_vector.to_b2()));
    }

    pub fn getCenterOfMassWorld(self: *const Vehicle) vec2 {
        std.debug.assert(self.alive);

        return vec2.from_b2(b2.b2Body_GetWorldCenterOfMass(self.body_id));
    }

    pub fn getBlock(self: *const Vehicle, ref: BlockRef) ?*Block {
        std.debug.assert(self.alive);

        const block: *Block = &self.blocks.items[ref.block_index];
        if (block.alive) {
            return block;
        }

        return null;
    }

    pub fn getBlockAtPosition(self: *const Vehicle, local_position: vec2) ?BlockRef {
        std.debug.assert(self.alive);

        var closest_dist: f32 = std.math.floatMax(f32);
        var closest_block_ref: ?BlockRef = null;

        //const vehicle_transform = b2.b2Body_GetTransform(self.body_id);

        for (self.blocks.items, 0..) |*block, block_index| {
            if (!block.alive) continue;

            //  TODO continue if block does not contain position

            const dist = vec2.dist(block.local_position, local_position);

            if (dist < closest_dist) {
                closest_dist = dist;
                closest_block_ref = BlockRef{
                    .block_index = block_index,
                };
            }
        }

        return closest_block_ref;
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

    pub fn destroyBlock(self: *Vehicle, block_ref: BlockRef) void {
        std.debug.assert(self.alive);

        // destroy devices
        {
            for (self.devices.items, 0..) |*device, device_index| {
                if (device.block_index == block_ref.block_index) {
                    self.destroyDevice(.{
                        .device_index = device_index,
                    });
                }
            }
        }

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

    fn blocksAreTouching(block1: *const Block, block2: *const Block) bool {
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

    fn getContactNormal(block1: *const Block, block2: *const Block) ?vec2 {
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

    pub fn getSplitParts(self: *const Vehicle, temp_allocator: std.mem.Allocator) SplitPartsResult {

        // TODO make a generic graph-type with graph.findPartitions ?

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

    pub fn getDevice(self: *const Vehicle, ref: DeviceRef) ?*Device {
        std.debug.assert(self.alive);

        const device: *Device = &self.devices.items[ref.device_index];

        if (device.alive) {
            return device;
        }

        return null;
    }

    pub fn getClosestDevice(self: *const Vehicle, position_world: vec2, max_distance: f32) ?DeviceRef {
        std.debug.assert(self.alive);

        var closest_dist: f32 = std.math.floatMax(f32);
        var closest_device_ref: ?DeviceRef = null;

        const position_local = self.transformWorldToLocal(position_world);

        for (self.devices.items, 0..) |*device, device_index| {
            if (!device.alive) continue;

            const dist = vec2.dist(device.local_position, position_local);

            if (dist < max_distance and dist < closest_dist) {
                closest_dist = dist;
                closest_device_ref = DeviceRef{
                    .device_index = device_index,
                };
            }
        }

        return closest_device_ref;
    }

    pub fn getAllDevicesOnBlock(self: *const Vehicle, block_ref: BlockRef, allocator: std.mem.Allocator) []DeviceRef {
        std.debug.assert(self.alive);

        var result = std.ArrayList(DeviceRef).init(allocator);
        defer result.deinit();

        for (self.devices.items, 0..) |*device, device_index| {
            if (!device.alive) continue;

            if (device.block_index == block_ref.block_index) {
                result.append(.{
                    .device_index = device_index,
                }) catch unreachable;
            }
        }

        return result.toOwnedSlice() catch unreachable;
    }

    pub fn getDeviceTransferData(self: *const Vehicle, device_ref: DeviceRef) ?DeviceTransferData {
        std.debug.assert(self.alive);

        if (self.getDevice(device_ref)) |device| {
            std.debug.assert(device.alive);

            return DeviceTransferData{
                .def = device.def,
                .local_position = device.local_position,
            };
        }

        return null;
    }

    pub fn createDevice(self: *Vehicle, def: DeviceDef, local_position: vec2) ?DeviceRef {
        std.debug.assert(self.alive);

        var data_index: usize = 0;

        const maybe_block_ref = self.getBlockAtPosition(local_position);
        if (maybe_block_ref == null) {
            std.log.err("createDevice: no block at that position", .{});
            return null;
        }
        const block_ref = maybe_block_ref.?;

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
                const thruster = ThrusterDevice.create(thruster_def, self.body_id, local_position);
                self.thrusters.append(thruster) catch unreachable;

                data_index = thruster_index;
            },
        }

        const device_index = self.devices.items.len;

        self.devices.append(Device{
            .alive = true,
            .def = def,
            .type = def.data,
            .local_position = local_position,
            .block_index = block_ref.block_index,
            .data_index = data_index,
        }) catch unreachable;

        return DeviceRef{
            .device_index = device_index,
        };
    }

    pub fn destroyDevice(self: *Vehicle, ref: DeviceRef) void {
        std.debug.assert(self.alive);

        const maybe_device = self.getDevice(ref);
        if (maybe_device == null) {
            return;
        }
        const device = maybe_device.?;

        device.alive = false;

        switch (device.type) {
            .Wheel => {
                //
                const wheel: *WheelDevice = &self.wheels.items[device.data_index];
                wheel.destroy();
            },
            .Thruster => {
                //
                const thruster: *ThrusterDevice = &self.thrusters.items[device.data_index];
                thruster.destroy();
            },
        }
    }
};
