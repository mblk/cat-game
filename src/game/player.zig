const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const rot2 = engine.rot2;
const Transform2 = engine.Transform2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const UserData = @import("user_data.zig").UserData;

const World = @import("world.zig").World;

const refs = @import("refs.zig");
const ItemRef = refs.ItemRef;

pub const Player = struct {
    const Self = @This();

    world: *World,

    body_id: b2.b2BodyId,

    show_hand: bool = false,
    hand_start: vec2 = undefined,
    hand_end: vec2 = undefined,

    show_hint: bool = false,
    hint_position: vec2 = undefined,
    hint_buffer: [128]u8 = undefined,
    hint_text: ?[]const u8 = null,

    has_mouse_joint: bool = false,
    mouse_joint: b2.b2JointId = b2.b2_nullJointId,

    total_kcal_eaten: f32 = 0,
    total_kcal_burned: f32 = 0,

    pub fn create(world: *World, position: vec2) Player {
        std.log.info("player create", .{});

        const body_id = createBody(world.world_id, position);

        return Player{
            .world = world,
            .body_id = body_id,
        };
    }

    fn createBody(world_id: b2.b2WorldId, position: vec2) b2.b2BodyId {
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position = position.to_b2();
        body_def.fixedRotation = true;

        const body_id = b2.b2CreateBody(world_id, &body_def);

        // head
        {
            var circle = b2.b2Circle{
                .center = b2.b2Vec2{ .x = 0, .y = 0.5 },
                .radius = 0.4,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 1.0;
            shape_def.friction = 0.1;

            _ = b2.b2CreateCircleShape(body_id, &shape_def, &circle);
        }

        // body front
        {
            var circle = b2.b2Circle{
                .center = b2.b2Vec2{ .x = 0, .y = 0.0 },
                .radius = 0.5,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 1.0;
            shape_def.friction = 0.1;

            _ = b2.b2CreateCircleShape(body_id, &shape_def, &circle);
        }

        // leg1
        {
            var circle = b2.b2Circle{
                .center = b2.b2Vec2{ .x = -0.1, .y = -0.5 },
                .radius = 0.1,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 1.0;
            shape_def.friction = 0.1;

            _ = b2.b2CreateCircleShape(body_id, &shape_def, &circle);
        }

        // leg2
        {
            var circle = b2.b2Circle{
                .center = b2.b2Vec2{ .x = 0.1, .y = -0.5 },
                .radius = 0.1,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 1.0;
            shape_def.friction = 0.1;

            _ = b2.b2CreateCircleShape(body_id, &shape_def, &circle);
        }

        return body_id;
    }

    pub fn destroy(self: *Player) void {
        std.log.info("player destroy", .{});

        b2.b2DestroyBody(self.body_id);
    }

    const QueryData = struct {
        point: vec2,
        hit: bool,
        body_id: b2.b2BodyId,
        player_body_id: b2.b2BodyId, // TODO use filters instead
        ignore_body_id: b2.b2BodyId = b2.b2_nullBodyId,
        exact_hit: bool = true,
    };

    // pub const b2OverlapResultFcn = fn (b2ShapeId, ?*anyopaque) callconv(.c) bool;
    fn my_query_func(shape_id: b2.b2ShapeId, context: ?*anyopaque) callconv(.c) bool {
        const query_data: *QueryData = @ptrCast(@alignCast(context));

        const body_id = b2.b2Shape_GetBody(shape_id);
        const body_type = b2.b2Body_GetType(body_id);

        if (body_type != b2.b2_dynamicBody) {
            return true; // continue
        }

        if (b2.B2_ID_EQUALS(body_id, query_data.player_body_id)) {
            return true; // continue
        }
        if (b2.B2_ID_EQUALS(body_id, query_data.ignore_body_id)) {
            return true; // continue
        }

        const b2point = b2.b2Vec2{
            .x = query_data.point.x,
            .y = query_data.point.y,
        };

        if (!query_data.exact_hit) {
            query_data.hit = true;
            query_data.body_id = body_id;
            return false;
        }

        if (b2.b2Shape_TestPoint(shape_id, b2point)) {
            query_data.hit = true;
            query_data.body_id = body_id;
            return false; // stop
        }

        return true; // continue
    }

    pub fn update(self: *Player, dt: f32, input: *engine.InputState, mouse_position: vec2, control_enabled: bool) void {
        //
        //_ = dt;

        // reset hand/hint
        self.show_hand = false;
        self.show_hint = false;
        self.hint_text = null;

        if (!control_enabled) {
            if (self.has_mouse_joint) {
                b2.b2DestroyJoint(self.mouse_joint);

                self.mouse_joint = b2.b2_nullJointId;
                self.has_mouse_joint = false;
            }

            return;
        }

        const player_position = b2.b2Body_GetPosition(self.body_id);
        const player_velocity = b2.b2Body_GetLinearVelocity(self.body_id);

        const player_mass = b2.b2Body_GetMass(self.body_id);
        //const world_gravity = b2.b2World_GetGravity(self.world_id);

        // move?
        var target_vx: f32 = 0;
        if (input.getKeyState(.a)) {
            target_vx -= 10;
        }
        if (input.getKeyState(.d)) {
            target_vx += 10;
        }

        const curr_vx = player_velocity.x;
        const err_vx = target_vx - curr_vx;
        const f_x = err_vx * 2.5;

        if (@abs(target_vx) > 0.1 and @abs(f_x) > 0.1) {
            b2.b2Body_ApplyForceToCenter(self.body_id, b2.b2Vec2{ .x = f_x, .y = 0 }, true);

            const kcal_cost: f32 = @abs(f_x) * dt * 1.0;

            self.total_kcal_burned += kcal_cost;
        }

        // jump?
        if (input.consumeKeyDownEvent(.space)) {
            const curr_vy = player_velocity.y;
            const target_vy = 10.0;
            const err_vy = target_vy - curr_vy;
            const i_y = player_mass * err_vy;

            b2.b2Body_ApplyLinearImpulseToCenter(self.body_id, b2.b2Vec2{ .x = 0, .y = i_y }, true);

            self.total_kcal_burned += 10.0;
        }

        // grab stuff?
        if (self.has_mouse_joint) {
            const target_body = b2.b2Joint_GetBodyB(self.mouse_joint);

            // stop grab?
            if (input.consumeMouseButtonUpEvent(.left)) {
                b2.b2DestroyJoint(self.mouse_joint);

                //b2.b2Body_SetFixedRotation(target_body, false); // XXX

                self.mouse_joint = b2.b2_nullJointId;
                self.has_mouse_joint = false;
            }
            // update grab
            else {
                b2.b2MouseJoint_SetTarget(self.mouse_joint, b2.b2Vec2{
                    .x = mouse_position.x,
                    .y = mouse_position.y,
                });
                b2.b2Body_SetAwake(target_body, true);
            }

            self.show_hand = true;
            self.hand_start = vec2.from_b2(player_position);
            self.hand_end = mouse_position;
        } else {
            const aabb = b2.b2AABB{
                .lowerBound = b2.b2Vec2{
                    .x = mouse_position.x - 0.001,
                    .y = mouse_position.y - 0.001,
                },
                .upperBound = b2.b2Vec2{
                    .x = mouse_position.x + 0.001,
                    .y = mouse_position.y + 0.001,
                },
            };

            var query_context = QueryData{
                .point = mouse_position,
                .hit = false,
                .body_id = b2.b2_nullBodyId,
                .player_body_id = self.body_id,
            };

            _ = b2.b2World_OverlapAABB(self.world.world_id, aabb, b2.b2DefaultQueryFilter(), my_query_func, &query_context);

            if (query_context.hit) {
                std.debug.assert(b2.B2_IS_NON_NULL(query_context.body_id));

                self.show_hand = true;
                self.hand_start = vec2.init(player_position.x, player_position.y);
                self.hand_end = mouse_position;

                if (UserData.getFromBody(query_context.body_id)) |user_data| {
                    if (user_data.getRef()) |ref| {
                        switch (ref) {
                            .Vehicle => |vehicle_ref| {
                                //
                                _ = vehicle_ref;
                            },
                            .Block => |block_ref| {
                                //
                                _ = block_ref;
                            },
                            .Device => |device_ref| {
                                //
                                _ = device_ref;
                            },
                            .Item => |item_ref| {
                                //
                                //_ = item_ref;

                                self.show_hint = true;
                                self.hint_position = vec2.from_b2(b2.b2Body_GetWorldCenterOfMass(query_context.body_id)).add(vec2.init(0, 1));
                                self.hint_text = std.fmt.bufPrint(&self.hint_buffer, "Press e to pick up", .{}) catch unreachable;

                                if (input.consumeKeyDownEvent(.e)) {
                                    if (self.world.getItem(item_ref)) |item| {
                                        std.log.info("consume item: {s}", .{item});

                                        const item_copy = item.*;

                                        if (self.world.destroyItem(item_ref)) {
                                            switch (item_copy.def.data) {
                                                .Food => |food_data| {
                                                    self.total_kcal_eaten += food_data.kcal;
                                                },
                                                else => {},
                                            }
                                        }
                                    }
                                }
                            },
                        }
                    }
                }

                // start grab?
                if (input.consumeMouseButtonDownEvent(.left)) {
                    var mouse_joint_def = b2.b2DefaultMouseJointDef();
                    mouse_joint_def.bodyIdA = self.body_id;
                    mouse_joint_def.bodyIdB = query_context.body_id;
                    mouse_joint_def.target = mouse_position.to_b2();
                    mouse_joint_def.hertz = 5.0;
                    mouse_joint_def.dampingRatio = 0.7;
                    mouse_joint_def.maxForce = 1000.0 * b2.b2Body_GetMass(query_context.body_id);

                    //b2.b2Body_SetFixedRotation(query_context.body_id, true); // XXX

                    self.has_mouse_joint = true;
                    self.mouse_joint = b2.b2CreateMouseJoint(self.world.world_id, &mouse_joint_def);
                }
            }
        }
    }

    pub fn getTransform(self: *const Player) Transform2 {
        const t = b2.b2Body_GetTransform(self.body_id); // TODO do only once per frame in update?
        return Transform2.from_b2(t);
    }

    pub fn teleportTo(self: *Self, position: vec2) void {
        b2.b2Body_SetTransform(self.body_id, position.to_b2(), b2.b2Rot_identity);
        b2.b2Body_SetAwake(self.body_id, true);
    }
};
