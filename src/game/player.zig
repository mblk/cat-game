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

pub const PlayerDef = struct {
    //
    max_move_velocity: f32 = 10, // m/s
    max_move_force_factor: f32 = 2, // F_max = m*g*factor

};

pub const PlayerOrientation = enum {
    LookingLeft,
    LookingRight,
};

pub const PlayerPose = union(enum) {
    Sitting: void,
    Standing: void,
    Walking: void,
    Running: void,
    Climbing: void,
};

pub const Player = struct {
    const Self = @This();

    def: PlayerDef = PlayerDef{},

    world: *World,

    main_body_id: b2.b2BodyId = b2.b2_nullBodyId,

    //orientation: PlayerOrientation,
    //pose: PlayerPose,

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

    pub fn init(self: *Self, world: *World, position: vec2) void {
        std.log.info("player init", .{});

        self.* = Self{
            .world = world,
        };

        self.createPhysics(position);
    }

    fn createPhysics(self: *Self, position: vec2) void {
        const world_id = self.world.world_id;

        // main body
        {
            const main_body_pos = position;

            var main_body_def = b2.b2DefaultBodyDef();
            main_body_def.type = b2.b2_dynamicBody;
            main_body_def.position = main_body_pos.to_b2();
            main_body_def.fixedRotation = true;

            self.main_body_id = b2.b2CreateBody(world_id, &main_body_def);

            var circle = b2.b2Circle{
                .center = b2.b2Vec2{ .x = 0.0, .y = 0.0 },
                .radius = 0.25,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 10.0;
            shape_def.friction = 0.1;

            _ = b2.b2CreateCircleShape(self.main_body_id, &shape_def, &circle);
        }
    }

    pub fn deinit(self: *Player) void {
        std.log.info("player deinit", .{});

        b2.b2DestroyBody(self.main_body_id);
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

    const GroundContact = struct {
        angle: f32,
        pos_world: vec2,
        normal: vec2,
        body_id: b2.b2BodyId,
    };

    const FindGroundContactResult = struct {
        contact_count: usize,
        avg_pos: vec2,
        avg_normal: vec2,

        contact1: ?GroundContact,
        contact2: ?GroundContact,
    };

    pub fn findGroundContacts(self: *Self, renderer: *engine.Renderer2D) FindGroundContactResult {
        const num_steps = 16;
        const ray_length = 5.0;

        const full_circle = std.math.pi * 2;
        const half_circle = std.math.pi;
        const angle_per_step = full_circle / @as(comptime_float, num_steps);

        // Offset so we never cast directly down/up/left/right
        const angle_offset = angle_per_step / 2.0;

        const t = self.getTransform();

        var best_score1: f32 = -1.0;
        var best_contact1: ?GroundContact = null;
        var best_score2: f32 = -1.0;
        var best_contact2: ?GroundContact = null;

        for (0..num_steps) |step_index| {
            const angle: f32 = @as(f32, @floatFromInt(step_index)) * angle_per_step + angle_offset;

            const dir = vec2.init(
                std.math.sin(angle),
                -std.math.cos(angle),
            );

            const angle_from_down: f32 = if (angle < half_circle)
                angle
            else
                @abs(angle - full_circle);

            // clamping to 0..1 in case of floating point errors
            const angle_factor: f32 = std.math.clamp((half_circle - angle_from_down) / half_circle, 0, 1);

            const ray_start = t.pos;
            const ray_translation = dir.scale(ray_length);
            // const ray_end = ray_start.add(ray_translation);

            // renderer.addLine(ray_start, ray_end, Color.red);
            // renderer.addText(ray_end, Color.white, "{d:.3}", .{angle_factor});

            const ray_result = b2.b2World_CastRayClosest(
                self.world.world_id,
                ray_start.to_b2(),
                ray_translation.to_b2(),
                b2.b2DefaultQueryFilter(),
            );

            if (ray_result.hit) {

                // TODO use distance for score calculation

                const hit_pos_world = vec2.from_b2(ray_result.point);
                const dist = ray_start.dist(hit_pos_world);

                const hit_normal = vec2.from_b2(ray_result.normal);
                const hit_body_id = b2.b2Shape_GetBody(ray_result.shapeId);

                const closeness_factor = std.math.clamp((ray_length - dist) / ray_length, 0, 1);
                // 0..1
                // 0 = far away
                // 1 = very close

                const effective_score = angle_factor * closeness_factor;

                //renderer.addPointWithPixelSize(hit_pos_world, 10, Color.red);

                if (effective_score > best_score1) {
                    best_score2 = best_score1;
                    best_contact2 = best_contact1;

                    best_score1 = effective_score;
                    best_contact1 = GroundContact{
                        .angle = angle,
                        .pos_world = hit_pos_world,
                        .normal = hit_normal,
                        .body_id = hit_body_id,
                    };
                } else if (effective_score > best_score2) {
                    best_score2 = effective_score;
                    best_contact2 = GroundContact{
                        .angle = angle,
                        .pos_world = hit_pos_world,
                        .normal = hit_normal,
                        .body_id = hit_body_id,
                    };
                }
            }
        }

        var contact_count: usize = 0;
        var avg_pos = vec2.zero;
        var avg_normal = vec2.zero;

        if (best_contact1) |contact| {
            contact_count += 1;
            avg_pos = avg_pos.add(contact.pos_world);
            avg_normal = avg_normal.add(contact.normal);

            renderer.addLine(t.pos, contact.pos_world, Color.green);
            //renderer.addText(contact.pos_world, Color.white, "best1 {d:.1}", .{best_score1});
        }
        if (best_contact2) |contact| {
            contact_count += 1;
            avg_pos = avg_pos.add(contact.pos_world);
            avg_normal = avg_normal.add(contact.normal);

            renderer.addLine(t.pos, contact.pos_world, Color.green);
            //renderer.addText(contact.pos_world, Color.white, "best2 {d:.1}", .{best_score2});
        }

        if (contact_count > 0) {
            const count_f32: f32 = @floatFromInt(contact_count);
            avg_pos = avg_pos.scale(1 / count_f32);
            avg_normal = avg_normal.scale(1 / count_f32);
        }

        return FindGroundContactResult{
            .contact_count = contact_count,
            .avg_pos = avg_pos,
            .avg_normal = avg_normal,
            .contact1 = best_contact1,
            .contact2 = best_contact2,
        };
    }

    fn getMoveInputAxis(self: *Self, input: *engine.InputState) vec2 {
        _ = self;

        var x: f32 = 0;
        var y: f32 = 0;

        if (input.getKeyState(.d)) {
            x += 1;
        }
        if (input.getKeyState(.a)) {
            x -= 1;
        }
        if (input.getKeyState(.w)) {
            y += 1;
        }
        if (input.getKeyState(.s)) {
            y -= 1;
        }

        // TODO add gamepad etc

        return vec2.init(x, y);
    }

    pub fn update(self: *Player, dt: f32, input: *engine.InputState, mouse_position: vec2, control_enabled: bool, renderer: *engine.Renderer2D) void {
        //
        _ = dt;

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

        // get state
        const player_position = vec2.from_b2(b2.b2Body_GetPosition(self.main_body_id));
        const player_velocity = vec2.from_b2(b2.b2Body_GetLinearVelocity(self.main_body_id));
        const player_mass = b2.b2Body_GetMass(self.main_body_id);
        //const world_gravity = vec2.from_b2(b2.b2World_GetGravity(self.world.world_id));

        const ground_contacts = self.findGroundContacts(renderer);

        renderer.addText(player_position.add(vec2.init(0, 3)), Color.white, "vel {d:.2} mass {d:.2}", .{ player_velocity, player_mass });

        // move?
        if (ground_contacts.contact_count > 0) {
            const v_n = ground_contacts.avg_normal;
            const angle = v_n.turn90cw().angle();
            //std.log.info("angle {d:.3}", .{std.math.radiansToDegrees(angle)});

            // walking on normal floor
            var v_right = v_n.turn90cw();
            var v_up = v_n;

            var hold_on = false;
            var hold_on_axis: vec2 = vec2.zero;

            const move_input = self.getMoveInputAxis(input);

            if (@abs(angle) > std.math.degreesToRadians(120)) {
                // hanging at the ceiling
                v_right = v_n.turn90ccw();
                v_up = v_n.neg();

                hold_on = true;
                hold_on_axis = v_n;

                if (@abs(move_input.y) > 0.1) {
                    hold_on = false;
                }
            } else if (angle < -std.math.degreesToRadians(60)) {
                // upwards on the left
                v_right = v_n;
                v_up = v_n.turn90ccw();

                hold_on = true;
                hold_on_axis = v_n;

                if (@abs(move_input.x) > 0.1) {
                    hold_on = false;
                }
            } else if (angle > std.math.degreesToRadians(60)) {
                // upwards on the right
                v_right = v_n.neg();
                v_up = v_n.turn90cw();

                hold_on = true;
                hold_on_axis = v_n;

                if (@abs(move_input.x) > 0.1) {
                    hold_on = false;
                }
            }

            const horizontal_move_dir = v_right.scale(move_input.x);
            const vertical_move_dir = v_up.scale(move_input.y);

            const max_move_force = player_mass * 9.81 * self.def.max_move_force_factor;

            var f_total_vec = vec2.zero;

            if (horizontal_move_dir.len() > 0.1) {
                //
                const proj_vel = player_velocity.dot(horizontal_move_dir.normalize());
                const target_vel = horizontal_move_dir.len() * self.def.max_move_velocity;
                const err_vel = target_vel - proj_vel;
                const acc = err_vel * 10;
                const f = std.math.clamp(player_mass * acc, 0, max_move_force);
                const f_vec = horizontal_move_dir.normalize().scale(f);

                f_total_vec = f_total_vec.add(f_vec);
            }
            if (vertical_move_dir.len() > 0.1) {
                //
                const proj_vel = player_velocity.dot(vertical_move_dir.normalize());
                const target_vel = vertical_move_dir.len() * self.def.max_move_velocity;
                const err_vel = target_vel - proj_vel;
                const acc = err_vel * 10;
                const f = std.math.clamp(player_mass * acc, 0, max_move_force);
                const f_vec = vertical_move_dir.normalize().scale(f);

                f_total_vec = f_total_vec.add(f_vec);
            }

            if (hold_on and !input.getKeyState(.left_shift)) {
                const d = player_position.sub(ground_contacts.avg_pos);
                const proj_dist = hold_on_axis.normalize().dot(d);
                const target_dist = 1.0;
                const err_dist = target_dist - proj_dist;

                const proj_vel = hold_on_axis.normalize().dot(player_velocity);

                const hold_on_force = err_dist * 100 - proj_vel * 10;
                const hold_on_force_vec = hold_on_axis.normalize().scale(hold_on_force);

                f_total_vec = f_total_vec.add(hold_on_force_vec);
            }

            if (f_total_vec.len() > 0.1) {
                b2.b2Body_ApplyForceToCenter(self.main_body_id, f_total_vec.to_b2(), true);

                // clamp force here?

                renderer.addLine(player_position, player_position.add(f_total_vec), Color.blue);

                const count_f32: f32 = @floatFromInt(ground_contacts.contact_count);
                const force_per_contact = f_total_vec.neg().scale(1 / count_f32);

                // opposite force to other bodies
                if (ground_contacts.contact1) |contact| {
                    if (b2.b2Body_GetType(contact.body_id) == b2.b2_dynamicBody) {
                        b2.b2Body_ApplyForceToCenter(contact.body_id, force_per_contact.to_b2(), true);
                    }
                }
                if (ground_contacts.contact2) |contact| {
                    if (b2.b2Body_GetType(contact.body_id) == b2.b2_dynamicBody) {
                        b2.b2Body_ApplyForceToCenter(contact.body_id, force_per_contact.to_b2(), true);
                    }
                }
            }
        }

        // jump?
        if (input.consumeKeyDownEvent(.space)) {
            const curr_vy = player_velocity.y;
            const target_vy = 10.0;
            const err_vy = target_vy - curr_vy;
            const i_y = player_mass * err_vy;

            var can_jump = false;

            if (ground_contacts.contact1) |contact| {
                _ = contact;
                can_jump = true;
            }
            if (ground_contacts.contact2) |contact| {
                _ = contact;
                can_jump = true;
            }

            if (can_jump) {
                b2.b2Body_ApplyLinearImpulseToCenter(self.main_body_id, vec2.init(0, i_y).to_b2(), true);

                self.total_kcal_burned += 10.0;
            }
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
                b2.b2MouseJoint_SetTarget(self.mouse_joint, mouse_position.to_b2());
                b2.b2Body_SetAwake(target_body, true);
            }

            self.show_hand = true;
            self.hand_start = player_position;
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
                .player_body_id = self.main_body_id,
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
                    mouse_joint_def.bodyIdA = self.main_body_id;
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
        const t = b2.b2Body_GetTransform(self.main_body_id); // TODO do only once per frame in update?
        return Transform2.from_b2(t);
    }

    pub fn teleportTo(self: *Self, position: vec2) void {
        std.log.info("player teleport to {d:.1}", .{position});

        b2.b2Body_SetTransform(self.main_body_id, position.to_b2(), b2.b2Rot_identity);
        b2.b2Body_SetAwake(self.main_body_id, true);
        //_ = self;
        //_ = position;
    }
};
