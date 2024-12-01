const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;

const zbox = @import("zbox");
const b2 = zbox.API;

pub const GroundSegment = struct {
    world_id: b2.b2WorldId,
    position: vec2,
    points: std.ArrayList(vec2),
    dirty: bool,
    body_id: b2.b2BodyId,

    pub fn create(world_id: b2.b2WorldId, position: vec2, allocator: std.mem.Allocator) GroundSegment {
        return GroundSegment{
            .world_id = world_id,
            .position = position,
            .points = std.ArrayList(vec2).init(allocator),
            .dirty = true,
            .body_id = b2.b2_nullBodyId,
        };
    }

    pub fn free(self: *GroundSegment) void {
        self.destroyBody();
        self.points.deinit();
    }

    pub fn update(self: *GroundSegment, temp_allocator: std.mem.Allocator) void {
        if (!self.dirty) {
            return;
        }
        self.dirty = false;

        self.destroyBody();

        if (self.points.items.len >= 4) {
            self.createBody(temp_allocator);
        }
    }

    pub fn move(self: *GroundSegment, new_position: vec2) void {
        self.position = new_position;
        self.dirty = true;
    }

    pub fn createPoint(self: *GroundSegment, index: usize, position: vec2, is_global: bool) void {
        var p = position;

        if (is_global) {
            p = p.sub(self.position);
        }

        self.points.insert(index, p) catch unreachable;
        self.dirty = true;
    }

    pub fn destroyPoint(self: *GroundSegment, index: usize) void {
        _ = self.points.orderedRemove(index);
        self.dirty = true;
    }

    pub fn movePoint(self: *GroundSegment, index: usize, new_position: vec2, is_global: bool) void {
        var p = new_position;

        if (is_global) {
            p = p.sub(self.position);
        }

        self.points.items[index] = p;
        self.dirty = true;
    }

    fn createBody(self: *GroundSegment, temp_allocator: std.mem.Allocator) void {
        std.debug.assert(b2.B2_IS_NULL(self.body_id));
        std.debug.assert(self.points.items.len >= 4);

        var body_def = b2.b2DefaultBodyDef();
        self.body_id = b2.b2CreateBody(self.world_id, &body_def);

        const num_points = self.points.items.len;
        var points: []b2.b2Vec2 = temp_allocator.alloc(b2.b2Vec2, num_points) catch unreachable;
        defer temp_allocator.free(points);

        for (0.., self.points.items) |i, ground_point| {
            const p = self.position.add(ground_point);

            points[i] = b2.b2Vec2{
                .x = p.x,
                .y = p.y,
            };
        }

        var chain_def = b2.b2DefaultChainDef();
        chain_def.isLoop = true;
        chain_def.points = points.ptr;
        chain_def.count = @intCast(num_points);

        _ = b2.b2CreateChain(self.body_id, &chain_def);
    }

    fn destroyBody(self: *GroundSegment) void {
        if (b2.B2_IS_NON_NULL(self.body_id)) {
            b2.b2DestroyBody(self.body_id);
            self.body_id = b2.b2_nullBodyId;
        }
    }
};
