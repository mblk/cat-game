const std = @import("std");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

pub const Player = struct {
    world_id: b2.b2WorldId,

    body_id: b2.b2BodyId,

    show_hand: bool = false,
    hand_start: vec2 = undefined,
    hand_end: vec2 = undefined,

    has_mouse_joint: bool = false,
    mouse_joint: b2.b2JointId = b2.b2_nullJointId,

    pub fn create(world_id: b2.b2WorldId) Player {
        var body_def = b2.b2DefaultBodyDef();
        body_def.type = b2.b2_dynamicBody;
        body_def.position = b2.b2Vec2{
            .x = 0,
            .y = 0,
        };
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

        return Player{
            .world_id = world_id,
            .body_id = body_id,
        };
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
        _ = dt;

        _ = control_enabled;

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

        if (@abs(f_x) > 0.1) {
            b2.b2Body_ApplyForceToCenter(self.body_id, b2.b2Vec2{ .x = f_x, .y = 0 }, true);
        }

        // jump?
        if (input.consumeKeyDownEvent(.space)) {
            const curr_vy = player_velocity.y;
            const target_vy = 10.0;
            const err_vy = target_vy - curr_vy;
            const i_y = player_mass * err_vy;

            b2.b2Body_ApplyLinearImpulseToCenter(self.body_id, b2.b2Vec2{ .x = 0, .y = i_y }, true);
        }

        // grab stuff?
        self.show_hand = false;

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
                const d = 10;
                const aabb = b2.b2AABB{
                    .lowerBound = b2.b2Vec2{
                        .x = mouse_position.x - d,
                        .y = mouse_position.y - d,
                    },
                    .upperBound = b2.b2Vec2{
                        .x = mouse_position.x + d,
                        .y = mouse_position.y + d,
                    },
                };

                var query_context = QueryData{
                    .point = mouse_position,
                    .hit = false,
                    .body_id = b2.b2_nullBodyId,
                    .player_body_id = self.body_id,
                    .ignore_body_id = target_body,
                    .exact_hit = false,
                };

                _ = b2.b2World_OverlapAABB(self.world_id, aabb, b2.b2DefaultQueryFilter(), my_query_func, &query_context);

                if (query_context.hit) {
                    const p1 = b2.b2Body_GetWorldCenterOfMass(target_body);
                    const p2 = b2.b2Body_GetWorldCenterOfMass(query_context.body_id);

                    self.show_hand = true;
                    self.hand_start = vec2.init(p1.x, p1.y);
                    self.hand_end = vec2.init(p2.x, p2.y);

                    if (input.consumeKeyDownEvent(.b)) {
                        var weld_joint_def = b2.b2DefaultWeldJointDef();

                        var target_transform = b2.b2Body_GetTransform(target_body);
                        target_transform.p = b2.b2Vec2_zero;

                        var target2_transform = b2.b2Body_GetTransform(query_context.body_id);
                        target2_transform.p = b2.b2Vec2_zero;

                        const dd = b2.b2Sub(p2, p1); // p1 -> p2 in global space
                        const dd_local = b2.b2InvTransformPoint(target_transform, dd);
                        const ff = b2.b2Sub(p1, p2); // p1 -> p2 in global space
                        const ff_local = b2.b2InvTransformPoint(target2_transform, ff);

                        std.log.info("dd {any}", .{dd});
                        std.log.info("dd_local {any}", .{dd_local});

                        std.log.info("ff {any}", .{ff});
                        std.log.info("ff_local {any}", .{ff_local});

                        weld_joint_def.bodyIdA = target_body;
                        weld_joint_def.bodyIdB = query_context.body_id;
                        weld_joint_def.collideConnected = false;
                        weld_joint_def.localAnchorA = b2.b2Vec2{
                            .x = dd_local.x * 0.5,
                            .y = dd_local.y * 0.5,
                        };
                        weld_joint_def.localAnchorB = b2.b2Vec2{
                            .x = ff_local.x * 0.5,
                            .y = ff_local.y * 0.5,
                        };

                        const angle1 = b2.b2Rot_GetAngle(target_transform.q);
                        const angle2 = b2.b2Rot_GetAngle(target2_transform.q);

                        weld_joint_def.referenceAngle = angle2 - angle1;

                        _ = b2.b2CreateWeldJoint(self.world_id, &weld_joint_def);

                        // .......
                        b2.b2DestroyJoint(self.mouse_joint);

                        //b2.b2Body_SetFixedRotation(target_body, false); // XXX

                        self.mouse_joint = b2.b2_nullJointId;
                        self.has_mouse_joint = false;
                    }
                }

                // update mouse joint
                if (self.has_mouse_joint) {
                    b2.b2MouseJoint_SetTarget(self.mouse_joint, b2.b2Vec2{
                        .x = mouse_position.x,
                        .y = mouse_position.y,
                    });
                    b2.b2Body_SetAwake(target_body, true);
                }
            }
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

            _ = b2.b2World_OverlapAABB(self.world_id, aabb, b2.b2DefaultQueryFilter(), my_query_func, &query_context);

            if (query_context.hit) {
                std.debug.assert(b2.B2_IS_NON_NULL(query_context.body_id));

                const target_com = b2.b2Body_GetWorldCenterOfMass(query_context.body_id);

                self.show_hand = true;
                self.hand_start = vec2.init(player_position.x, player_position.y);
                self.hand_end = vec2.init(target_com.x, target_com.y);

                // start grab?
                if (input.consumeMouseButtonDownEvent(.left)) {
                    var mouse_joint_def = b2.b2DefaultMouseJointDef();
                    mouse_joint_def.bodyIdA = self.body_id;
                    mouse_joint_def.bodyIdB = query_context.body_id;
                    mouse_joint_def.target = b2.b2Vec2{
                        .x = mouse_position.x,
                        .y = mouse_position.y,
                    };
                    mouse_joint_def.hertz = 5.0;
                    mouse_joint_def.dampingRatio = 0.7;
                    mouse_joint_def.maxForce = 1000.0 * b2.b2Body_GetMass(query_context.body_id);

                    //b2.b2Body_SetFixedRotation(query_context.body_id, true); // XXX

                    self.has_mouse_joint = true;
                    self.mouse_joint = b2.b2CreateMouseJoint(self.world_id, &mouse_joint_def);
                }
            }
        }
    }

    pub fn render(self: *Player, dt: f32, renderer: *engine.Renderer2D) void {
        //_ = self;
        _ = dt;
        //_ = renderer;

        if (self.show_hand) {
            renderer.addLine(self.hand_start, self.hand_end, Color.red);
        }
    }
};
