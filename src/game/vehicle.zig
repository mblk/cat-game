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

const AttachGraphNode = struct {
    block1: BlockRef,
    block2: BlockRef,
};

pub const Vehicle = struct {
    //
    alive: bool,
    //
    body_id: b2.b2BodyId,
    blocks: std.ArrayList(Block),

    attach_graph: std.ArrayList(AttachGraphNode),

    pub fn create(allocator: std.mem.Allocator, world_id: b2.b2WorldId, position: vec2) Vehicle {
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position.x = position.x;
        body_def.position.y = position.y;
        const body_id = b2.b2CreateBody(world_id, &body_def);

        const vehicle = Vehicle{
            .alive = true,
            .body_id = body_id,
            .blocks = std.ArrayList(Block).init(allocator),
            .attach_graph = std.ArrayList(AttachGraphNode).init(allocator),
        };

        //vehicle.createBlock(vec2.init(0, 0));
        //vehicle.createBlock(vec2.init(1, 0));

        return vehicle;
    }

    pub fn destroy(self: *Vehicle) void {
        std.debug.assert(self.alive);

        for (self.blocks.items) |*block| {
            if (!block.alive) continue;
            block.destroy();
        }

        self.attach_graph.deinit();
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

    pub fn createBlock(self: *Vehicle, def: BlockDef, local_position: vec2) void {
        std.debug.assert(self.alive);

        const block = Block.create(self.body_id, def, local_position);
        self.blocks.append(block) catch unreachable;

        b2.b2Body_SetAwake(self.body_id, true);
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

        // wake up physics
        b2.b2Body_SetAwake(self.body_id, true);

        // check if no more blocks left
        {
            var num_alive_blocks: usize = 0;
            for (self.blocks.items) |b| {
                if (b.alive) {
                    num_alive_blocks += 1;
                }
            }

            if (num_alive_blocks == 0) {
                std.log.info("no more blocks, destroy self", .{});
                self.destroy();
            }
        }
    }
};
