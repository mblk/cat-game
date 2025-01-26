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
const physics = @import("physics.zig");
const refs = @import("refs.zig");
const ItemRef = refs.ItemRef;

pub const PlayerDef = struct {
    //
    shape_radius: f32 = 0.25,

    //
    sk_aft_pivot: vec2 = vec2.init(-0.2, 0.1),
    sk_fwd_pivot: vec2 = vec2.init(0.2, 0.1),

    sk_fwd_leg_length: f32 = 1.0,
    sk_aft_leg_length: f32 = 1.0,

    //
    max_walk_velocity: f32 = 1, // m/s
    max_run_velocity: f32 = 5, // m/s
    max_move_force_factor: f32 = 2, // F_max = m*g*factor
};

pub const State = enum {
    Standing,
    Walking,
    Jumping,
    Falling,

    //Running,
    //Climbing,
    //InSeat,
};

pub const Leg = struct {
    min_length: f32,
    max_length: f32,

    pivot_local: vec2,

    contact_age: f32 = 0,
    contact_max_phase: f32 = 0,

    has_contact: bool = false,
    contact_body_id: b2.b2BodyId = b2.b2_nullBodyId, // touched body
    contact_pos_local: vec2 = vec2.zero, // in local space of touched body

    has_prev_contact: bool = false,
    prev_contact_body_id: b2.b2BodyId = b2.b2_nullBodyId, // touched body
    prev_contact_pos_local: vec2 = vec2.zero, // in local space of touched body

    // calculated by player.update
    pivot_pos_world: vec2 = vec2.zero,
    paw_pos_world: vec2 = vec2.zero,
};

pub const Player = struct {
    const Self = @This();

    const DebugLayer = engine.Renderer2D.Layers.Debug;

    def: PlayerDef,
    world: *World,
    main_body_id: b2.b2BodyId = b2.b2_nullBodyId,

    state: State = .Standing,
    jump_cooldown: f32 = 0,

    sk_transform: Transform2 = undefined,
    body_up_target: vec2 = undefined,
    body_up_curr: vec2 = vec2.init(0, 1),

    legs: [4]Leg,
    //leg_speed: f32 = 1.0,
    leg_phase: f32 = 0.0, // 0..
    leg_update_order: [4]usize = [_]usize{ 0, 2, 1, 3 },
    leg_update_index: usize = 0,

    force_request: vec2 = vec2.zero,

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

    // xxx
    pid_i_hor: f32 = 0,
    pid_i_vert: f32 = 0,

    walking_idle_time: f32 = 0,
    // xxx

    pub fn init(self: *Self, world: *World, position: vec2) void {
        std.log.info("player init", .{});

        const def = PlayerDef{};

        self.* = Self{
            .def = def,

            .world = world,

            .legs = [_]Leg{
                // aft
                Leg{
                    .min_length = 0.25,
                    .max_length = 0.5,
                    .pivot_local = def.sk_aft_pivot,
                },
                Leg{
                    .min_length = 0.25,
                    .max_length = 0.5,
                    .pivot_local = def.sk_aft_pivot,
                },

                // front
                Leg{
                    .min_length = 0.25,
                    .max_length = 0.5,
                    .pivot_local = def.sk_fwd_pivot,
                },
                Leg{
                    .min_length = 0.25,
                    .max_length = 0.5,
                    .pivot_local = def.sk_fwd_pivot,
                },
            },
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
                .radius = self.def.shape_radius,
            };

            var shape_def = b2.b2DefaultShapeDef();
            shape_def.density = 10.0;
            shape_def.friction = 0.1;
            shape_def.filter = physics.Filters.getPlayerFilter();

            _ = b2.b2CreateCircleShape(self.main_body_id, &shape_def, &circle);
        }
    }

    pub fn deinit(self: *Self) void {
        std.log.info("player deinit", .{});

        b2.b2DestroyBody(self.main_body_id);
    }

    pub const PlayerUpdateContext = struct {
        dt: f32,
        input: *engine.InputState,
        mouse_position: vec2,
        control_enabled: bool,
        renderer: *engine.Renderer2D,
    };

    pub fn update(
        self: *Self,
        dt: f32,
        input: *engine.InputState,
        mouse_position: vec2,
        control_enabled: bool,
        renderer: *engine.Renderer2D,
    ) void {
        //
        const context = PlayerUpdateContext{
            .dt = dt,
            .input = input,
            .mouse_position = mouse_position,
            .control_enabled = control_enabled,
            .renderer = renderer,
        };

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

        renderer.addText(player_position.add(vec2.init(0, 3)), DebugLayer, Color.white, "vel {d:.2} mass {d:.2}", .{ player_velocity, player_mass });
        //renderer.addText(player_position.add(vec2.init(0, 2.5)), DebugLayer, Color.white, "phase {d}", .{self.leg_phase});
        renderer.addText(player_position.add(vec2.init(0, 2)), DebugLayer, Color.white, "{s}", .{@tagName(self.state)});

        // ... reset things ...
        self.body_up_target = vec2.init(0, 1);
        self.force_request = vec2.zero;

        // xxx
        const contact_situation = self.determineContactSituation();
        if (contact_situation.has_contact) {
            self.body_up_target = contact_situation.avg_normal;
        }
        // xxx

        switch (self.state) {
            .Standing => {
                self.updateStanding(context);
            },
            .Walking => {
                self.updateWalking(context);
            },
            .Jumping => {
                self.updateJumping(context);
            },
            .Falling => {
                self.updateFalling(context);
            },
        }

        const angle_target = self.body_up_target.angle();
        const angle_curr = self.body_up_curr.angle();
        var angle_diff = angle_target - angle_curr;

        if (angle_diff < -std.math.pi) {
            angle_diff += std.math.pi * 2.0;
        } else if (angle_diff > std.math.pi) {
            angle_diff -= std.math.pi * 2.0;
        }

        const am: f32 = std.math.degreesToRadians(180.0);
        const angle_rate_per_s = std.math.clamp(angle_diff * 10.0, -am, am);
        const angle_rate_per_frame = angle_rate_per_s * dt;

        self.body_up_curr = self.body_up_curr.rotate(angle_rate_per_frame);

        //std.log.info("angle diff {d}", .{angle_diff});
        //std.log.info("angle_rate_per_s {d}", .{angle_rate_per_s});
        //self.body_up_curr = self.body_up_curr.add(self.body_up_target).normalize();

        self.sk_transform = Transform2{
            .pos = player_position,
            .rot = rot2.from_up_vector(self.body_up_curr),
        };

        self.updateLegsTest(context);
        self.applyForceRequest();

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
                //.player_body_id = self.main_body_id,
            };

            var query_filter = b2.b2DefaultQueryFilter();
            query_filter.categoryBits = physics.Categories.Player;
            query_filter.maskBits = physics.Categories.Vehicle | physics.Categories.Item;

            _ = b2.b2World_OverlapAABB(
                self.world.world_id,
                aabb,
                //b2.b2DefaultQueryFilter(),
                query_filter,
                my_query_func,
                &query_context,
            );

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

    fn applyForceRequest(self: *Self) void {
        const force_request = self.force_request;
        self.force_request = vec2.zero;

        // TODO maybe do clamping here?

        var contact_count: usize = 0;

        for (&self.legs) |*leg| {
            if (leg.has_contact) {
                contact_count += 1;
            }
        }

        if (contact_count > 0) {
            const count_f32: f32 = @floatFromInt(contact_count);
            const force_per_contact = force_request.neg().scale(1 / count_f32);

            // apply to self
            b2.b2Body_ApplyForceToCenter(self.main_body_id, force_request.to_b2(), true);

            // apply opposite force to other bodies
            for (&self.legs) |*leg| {
                if (leg.has_contact) {
                    if (b2.b2Body_GetType(leg.contact_body_id) == b2.b2_dynamicBody) {
                        b2.b2Body_ApplyForceToCenter(leg.contact_body_id, force_per_contact.to_b2(), true);
                    }
                }
            }
        }
    }

    fn updateLegsTest(self: *Self, context: PlayerUpdateContext) void {
        const player_vel = vec2.from_b2(b2.b2Body_GetLinearVelocity(self.main_body_id));

        // determine update-rate
        const update_rate = std.math.clamp(
            player_vel.len() * 5.0,
            1, // min
            100, // max
        );

        var max_phase: f32 = 0;
        if (update_rate > 0.001) {
            max_phase = 1.0 / update_rate;
        }

        // update due to phase-timing?
        self.leg_phase += context.dt;
        var do_update = false;
        if (self.leg_phase > max_phase) {
            do_update = true;
            self.leg_phase = 0.0;
        }

        // find best direction for ray-casting
        const sk_transform = self.sk_transform;

        var best_direction = vec2.init(0, -1);
        if (player_vel.len() > 0.1) {
            best_direction = player_vel.normalize();
        } else {
            best_direction = sk_transform.rotateLocalToWorld(vec2.init(0, -1));
        }
        //_ = self.findGroundContacts(sk_transform.transformLocalToWorld(self.def.sk_fwd_pivot), best_direction, self.legs[0].max_length, true);

        // update leg
        if (do_update) {
            const next_leg_index = self.leg_update_order[self.leg_update_index];
            const active_leg = &self.legs[next_leg_index];

            self.leg_update_index = (self.leg_update_index + 1) % 4;

            // shift contact
            active_leg.has_prev_contact = active_leg.has_contact;
            active_leg.prev_contact_body_id = active_leg.contact_body_id;
            active_leg.prev_contact_pos_local = active_leg.contact_pos_local;

            active_leg.has_contact = false;
            active_leg.contact_body_id = b2.b2_nullBodyId;
            active_leg.contact_pos_local = vec2.zero;

            // find new contact point
            const pivot_world = sk_transform.transformLocalToWorld(active_leg.pivot_local);
            const ground_contacts = self.findGroundContacts(pivot_world, best_direction, active_leg.max_length * 1.3, false);
            //const ground_contacts = self.findGroundContacts(pivot_world, best_direction, active_leg.max_length, false);
            if (ground_contacts.contact_count > 0) {
                const contact = ground_contacts.contact1.?;

                active_leg.contact_age = 0;
                active_leg.contact_max_phase = max_phase;

                active_leg.has_contact = true;
                active_leg.contact_body_id = contact.body_id;
                active_leg.contact_pos_local = contact.pos_local;
            }
        }

        // TODO must be done after physics step
        // update calculated positions
        for (&self.legs) |*leg| {
            leg.contact_age += context.dt;

            leg.pivot_pos_world = sk_transform.transformLocalToWorld(leg.pivot_local);

            if (!leg.has_contact) {
                // Case 1: hanging free in the air
                const paw_pos_local = leg.pivot_local.add(vec2.init(1, -1).normalize().scale(leg.min_length));
                leg.paw_pos_world = sk_transform.transformLocalToWorld(paw_pos_local);
            } else {
                const contact_transform = Transform2.from_b2(b2.b2Body_GetTransform(leg.contact_body_id));
                const contact_pos_world = contact_transform.transformLocalToWorld(leg.contact_pos_local);

                if (!leg.has_prev_contact) {
                    // Case 2: contact but no prev contact
                    leg.paw_pos_world = contact_pos_world;
                } else {
                    const prev_contact_transform = Transform2.from_b2(b2.b2Body_GetTransform(leg.prev_contact_body_id));
                    const prev_contact_pos_world = prev_contact_transform.transformLocalToWorld(leg.prev_contact_pos_local);

                    // Case 3: contact and prev contact
                    const p_prev = prev_contact_pos_world;
                    const p_curr = contact_pos_world;

                    if (vec2.dist(p_prev, p_curr) < 0.01) {
                        // same
                        leg.paw_pos_world = p_curr;
                    } else {
                        // not same
                        const lerp_time = leg.contact_max_phase * 1.5;

                        if (leg.contact_age < lerp_time) {
                            const t = leg.contact_age / lerp_time;
                            const offset_fn = (-@abs(t - 0.5) + 0.5) * 2.0; // 0..1, peak at t=0.5, zero at t=0 and t=1
                            const up = sk_transform.rotateLocalToWorld(vec2.init(0, 1));
                            const offset = up.scale(offset_fn * 0.2);

                            leg.paw_pos_world = vec2.lerp(p_prev, p_curr, t).add(offset);
                        } else {
                            leg.paw_pos_world = p_curr;
                        }
                    }
                }
            }

            // limit to min/max
            const p0 = leg.pivot_pos_world;
            const p1 = leg.paw_pos_world;
            const dist = vec2.dist(p0, p1);
            if (dist > 0.001) {
                const dist2 = std.math.clamp(dist, leg.min_length, leg.max_length);
                const dir = p1.sub(p0).normalize();

                leg.paw_pos_world = p0.add(dir.scale(dist2));
            } else {
                // ?
                std.log.err("pivot/paw distance to small", .{});
            }
        }
    }

    fn changeState(self: *Self, new_state: State) void {
        std.log.info("changeState: {s}", .{@tagName(new_state)});

        self.state = new_state;

        if (new_state == .Jumping) {
            self.jump_cooldown = 0.5;
        } else {
            self.jump_cooldown = -1.0;
        }
    }

    fn doJump(self: *Self) void {
        const player_velocity = vec2.from_b2(b2.b2Body_GetLinearVelocity(self.main_body_id));
        const player_mass = b2.b2Body_GetMass(self.main_body_id);

        const target_vel = vec2.init(1, 1).scale(5);
        const vel_err = target_vel.sub(player_velocity);
        const p = vel_err.scale(player_mass);

        // const curr_vy = player_velocity.y;
        // const target_vy = 10.0;
        // const err_vy = target_vy - curr_vy;
        // const i_y = player_mass * err_vy;

        b2.b2Body_ApplyLinearImpulseToCenter(self.main_body_id, p.to_b2(), true);

        self.total_kcal_burned += 10.0;
    }

    fn updateStanding(self: *Self, context: PlayerUpdateContext) void {
        //
        const player_velocity = vec2.from_b2(b2.b2Body_GetLinearVelocity(self.main_body_id));

        const move_input = self.getMoveInputAxis(context.input);

        //const ground_contacts = self.findGroundContacts(self.getTransform().pos, vec2.init(0, -1), 1.0, false);

        // if (ground_contacts.contact_count > 0) {
        //     self.body_up_target = ground_contacts.avg_normal;
        // } else {
        //     self.body_up_target = vec2.init(0, 1);
        // }

        // jump?
        if (context.input.consumeKeyDownEvent(.space)) {
            self.doJump();

            self.changeState(.Jumping);
            return;
        }

        // start walking?
        if (move_input.len() > 0.1 or player_velocity.len() > 0.1) {
            self.changeState(.Walking);
            return;
        }
    }

    fn updateWalking(self: *Self, context: PlayerUpdateContext) void {
        //
        const player_position = vec2.from_b2(b2.b2Body_GetPosition(self.main_body_id));
        const player_velocity2 = vec2.from_b2(b2.b2Body_GetLinearVelocity(self.main_body_id));
        const player_mass = b2.b2Body_GetMass(self.main_body_id);

        const contact_situation = self.determineContactSituation();

        if (contact_situation.has_contact) {
            self.body_up_target = contact_situation.avg_normal;
        } else {
            self.body_up_target = vec2.init(0, 1);
        }

        const move_input = self.getMoveInputAxis(context.input);

        // return to idle?
        if (contact_situation.has_contact and player_velocity2.len() < 0.1 and move_input.len() < 0.1) {
            self.walking_idle_time += context.dt;

            if (self.walking_idle_time > 1.0) {
                self.walking_idle_time = 0;
                self.changeState(.Standing);
                return;
            }
        }

        // falling?
        if (!contact_situation.has_contact) {
            self.changeState(.Falling);
            return;
        }

        // jump?
        if (context.input.consumeKeyDownEvent(.space)) {
            self.doJump();

            self.changeState(.Jumping);
            return;
        }

        // ...

        // ...
        const v_n = contact_situation.avg_normal;

        var v_right = v_n.turn90cw();
        var v_up = v_n;

        var f_total_vec = vec2.zero;

        const max_velocity = if (context.input.getKeyState(.left_shift)) self.def.max_run_velocity else self.def.max_walk_velocity;

        //if (horizontal_move_dir.len() > 0.1) {
        if (true) {
            //
            //const proj_vel = player_velocity.dot(v_right);
            const proj_vel = contact_situation.avg_rvel.dot(v_right);
            const target_vel = move_input.x * max_velocity;
            const err_vel = target_vel - proj_vel;

            self.pid_i_hor += err_vel;

            //std.log.info("err_vel {d} pid_i {d}", .{ err_vel, self.pid_i });

            const acc = err_vel * 50 + self.pid_i_hor * 1;
            const f = player_mass * acc;
            const f_vec = v_right.scale(f);

            f_total_vec = f_total_vec.add(f_vec);
        }

        // hold on?
        //if (context.input.getKeyState(.left_shift)) {
        if (true) {
            const rel_pos = player_position.sub(contact_situation.avg_pos);
            const proj_dist = vec2.dot(contact_situation.avg_normal, rel_pos);
            const target_dist = self.def.shape_radius;
            const err_dist = target_dist - proj_dist;

            //const proj_vel = vec2.dot(contact_situation.avg_normal, player_velocity);
            const proj_vel = vec2.dot(contact_situation.avg_normal, contact_situation.avg_rvel);
            const target_vel = err_dist * 10.0;
            const err_vel = target_vel - proj_vel;

            //self.pid_i_vert += err_vel;

            //std.log.info("dist_err {d:.3} vel_err {d:.3} pid_i {d:.3}", .{ err_dist, err_vel, self.pid_i_vert });

            const acc = err_vel * 50 + self.pid_i_vert * 1;
            const f = player_mass * acc;
            const f_vec = v_up.scale(f);

            f_total_vec = f_total_vec.add(f_vec);
        }

        // control dist with input?
        if (false) {
            //const proj_vel = player_velocity.dot(v_up);
            const proj_vel = contact_situation.avg_rvel.dot(v_up);
            const target_vel = move_input.y * max_velocity;
            const err_vel = target_vel - proj_vel;

            self.pid_i_vert += err_vel;

            //std.log.info("err_vel {d} pid_i {d}", .{ err_vel, self.pid_i });

            const acc = err_vel * 50 + self.pid_i_vert * 1;
            const f = player_mass * acc;
            const f_vec = v_up.scale(f);

            f_total_vec = f_total_vec.add(f_vec);
        }

        if (true) {

            // clamp force here?
            //const max_move_force = player_mass * 9.81 * self.def.max_move_force_factor;
            // const f = std.math.clamp(player_mass * acc, 0, max_move_force);

            const drender = engine.Renderer2D.Instance;
            drender.addLine(player_position, player_position.add(f_total_vec.normalize()), DebugLayer, Color.blue);
            drender.addText(player_position.add(f_total_vec.normalize()), DebugLayer, Color.white, "{d:.1} N", .{f_total_vec.len()});

            //b2.b2Body_ApplyForceToCenter(self.main_body_id, f_total_vec.to_b2(), true);

            self.force_request = self.force_request.add(f_total_vec);

            // const count_f32: f32 = @floatFromInt(ground_contacts.contact_count);
            // const force_per_contact = f_total_vec.neg().scale(1 / count_f32);

            // // opposite force to other bodies
            // if (ground_contacts.contact1) |contact| {
            //     if (b2.b2Body_GetType(contact.body_id) == b2.b2_dynamicBody) {
            //         b2.b2Body_ApplyForceToCenter(contact.body_id, force_per_contact.to_b2(), true);
            //     }
            // }
            // if (ground_contacts.contact2) |contact| {
            //     if (b2.b2Body_GetType(contact.body_id) == b2.b2_dynamicBody) {
            //         b2.b2Body_ApplyForceToCenter(contact.body_id, force_per_contact.to_b2(), true);
            //     }
            // }
        }
    }

    fn updateJumping(self: *Self, context: PlayerUpdateContext) void {
        //
        //_ = self;
        //_ = context;

        self.jump_cooldown -= context.dt;

        if (self.jump_cooldown < 0.0) {
            self.changeState(.Falling);
        }
    }

    fn updateFalling(self: *Self, context: PlayerUpdateContext) void {
        //
        const ground_contacts = self.findGroundContacts(self.getTransform().pos, vec2.init(0, -1), 1.0, false);

        _ = context;

        if (ground_contacts.contact_count > 0) {
            self.changeState(.Walking);
            return;
        }
    }

    pub fn getTransform(self: *const Self) Transform2 {
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

    const QueryData = struct {
        point: vec2,
        hit: bool,
        body_id: b2.b2BodyId,
        //player_body_id: b2.b2BodyId, // TODO use filters instead
        //ignore_body_id: b2.b2BodyId = b2.b2_nullBodyId,
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

        // if (b2.B2_ID_EQUALS(body_id, query_data.player_body_id)) {
        //     return true; // continue
        // }
        // if (b2.B2_ID_EQUALS(body_id, query_data.ignore_body_id)) {
        //     return true; // continue
        // }

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
        pos_local: vec2,
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

    pub fn findGroundContacts(
        self: *Self,
        //origin_local: vec2,
        //best_dir: vec2,

        origin_world: vec2,
        best_dir_world: vec2,
        max_dist: f32,
        debug: bool,
    ) FindGroundContactResult {
        //
        std.debug.assert(best_dir_world.len() > 0.1);

        const drender = engine.Renderer2D.Instance;

        //const num_steps = 16;
        const num_steps = 32;
        //const ray_length = 1.0; //5.0;
        const ray_length = max_dist;

        const full_circle = std.math.pi * 2;
        const half_circle = std.math.pi;
        const angle_per_step = full_circle / @as(comptime_float, num_steps);

        //const t = self.getTransform();

        //const ray_start = t.transformLocalToWorld(origin_local);
        const ray_start = origin_world;

        var best_score1: f32 = -1.0;
        var best_contact1: ?GroundContact = null;
        var best_score2: f32 = -1.0;
        var best_contact2: ?GroundContact = null;

        for (0..num_steps) |step_index| {
            const angle: f32 = @as(f32, @floatFromInt(step_index)) * angle_per_step;

            // 0=right
            const dir = vec2.init(
                std.math.cos(angle),
                std.math.sin(angle),
            );

            const diff_cos = vec2.dot(best_dir_world, dir);
            const diff_angle = std.math.acos(diff_cos); // 0..pi

            // clamping to 0..1 in case of floating point errors
            const angle_factor = std.math.clamp(1.0 - diff_angle / half_circle, 0, 1); // 0..1

            const ray_translation = dir.scale(ray_length);
            const ray_end = ray_start.add(ray_translation);

            if (debug) {
                drender.addLine(ray_start, ray_end, DebugLayer, Color.red);
                drender.addText(ray_end, DebugLayer, Color.white, "{d:.3}", .{angle_factor});

                drender.addLine(ray_start, ray_start.add(best_dir_world), DebugLayer + 1, Color.blue);
            }

            var query_filter = b2.b2DefaultQueryFilter();
            query_filter.categoryBits = physics.Categories.Player; // who we are
            query_filter.maskBits = physics.Categories.Ground | physics.Categories.Vehicle | physics.Categories.Item; // what we want to hit

            const ray_result = b2.b2World_CastRayClosest(
                self.world.world_id,
                ray_start.to_b2(),
                ray_translation.to_b2(),
                //b2.b2DefaultQueryFilter(),
                query_filter,
            );

            if (ray_result.hit) {

                // TODO use distance for score calculation

                const hit_pos_world = vec2.from_b2(ray_result.point);
                const dist = ray_start.dist(hit_pos_world);

                //std.debug.assert(dist < max_dist); // xxx

                const hit_normal = vec2.from_b2(ray_result.normal);
                const hit_body_id = b2.b2Shape_GetBody(ray_result.shapeId);

                const closeness_factor = std.math.clamp((ray_length - dist) / ray_length, 0, 1);
                _ = closeness_factor;
                // 0..1
                // 0 = far away
                // 1 = very close

                const effective_score = angle_factor; // * closeness_factor;

                const hit_pos_local = vec2.from_b2(b2.b2Body_GetLocalPoint(hit_body_id, ray_result.point));

                //renderer.addPointWithPixelSize(hit_pos_world, 10, Color.red);

                if (effective_score > best_score1) {
                    best_score2 = best_score1;
                    best_contact2 = best_contact1;

                    best_score1 = effective_score;
                    best_contact1 = GroundContact{
                        .angle = angle,
                        .pos_local = hit_pos_local,
                        .pos_world = hit_pos_world,
                        .normal = hit_normal,
                        .body_id = hit_body_id,
                    };
                } else if (effective_score > best_score2) {
                    best_score2 = effective_score;
                    best_contact2 = GroundContact{
                        .angle = angle,
                        .pos_local = hit_pos_local,
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

            if (debug) {
                engine.Renderer2D.Instance.addLine(ray_start, contact.pos_world, DebugLayer + 1, Color.green);
                //renderer.addLine(t.pos, contact.pos_world, DebugLayer, Color.green);
                //renderer.addText(contact.pos_world, Color.white, "best1 {d:.1}", .{best_score1});
            }
        }
        if (best_contact2) |contact| {
            contact_count += 1;
            avg_pos = avg_pos.add(contact.pos_world);
            avg_normal = avg_normal.add(contact.normal);

            if (debug) {
                engine.Renderer2D.Instance.addLine(ray_start, contact.pos_world, DebugLayer + 1, Color.blue);
                //renderer.addLine(t.pos, contact.pos_world, DebugLayer, Color.green);
                //renderer.addText(contact.pos_world, Color.white, "best2 {d:.1}", .{best_score2});
            }
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

    const ContactSituation = struct {
        has_contact: bool,
        avg_normal: vec2,
        avg_pos: vec2,
        avg_rvel: vec2,
    };

    pub fn determineContactSituation(
        self: *Self,
    ) ContactSituation {
        //
        const debug = false;
        const drender = engine.Renderer2D.Instance;

        const num_steps = 32;
        const ray_length = 1.0;

        const half_circle = std.math.pi;
        const full_circle = half_circle * 2;
        const angle_per_step = full_circle / @as(comptime_float, num_steps);

        const t = self.getTransform();
        const ray_start = t.pos;

        const player_vel = vec2.from_b2(b2.b2Body_GetLinearVelocity(self.main_body_id));

        var hit_normal_sum: vec2 = vec2.zero;
        var hit_weight_sum: f32 = 0;
        var hit_count: usize = 0;

        var hit_pos_sum: vec2 = vec2.zero;
        var hit_rel_vel_sum: vec2 = vec2.zero;

        for (0..num_steps) |step_index| {
            const angle: f32 = @as(f32, @floatFromInt(step_index)) * angle_per_step;

            const dir = vec2.init( // 0=right
                std.math.cos(angle),
                std.math.sin(angle),
            );

            const ray_translation = dir.scale(ray_length);
            const ray_end = ray_start.add(ray_translation);

            if (debug) {
                drender.addLine(ray_start, ray_end, DebugLayer, Color.red);
                //drender.addText(ray_end, DebugLayer, Color.white, "{d:.3}", .{angle_factor});
            }

            var query_filter = b2.b2DefaultQueryFilter();
            query_filter.categoryBits = physics.Categories.Player; // who we are
            query_filter.maskBits = physics.Categories.Ground | physics.Categories.Vehicle | physics.Categories.Item; // what we want to hit

            const ray_result = b2.b2World_CastRayClosest(
                self.world.world_id,
                ray_start.to_b2(),
                ray_translation.to_b2(),
                query_filter,
            );

            if (ray_result.hit) {
                const hit_pos_world = vec2.from_b2(ray_result.point);
                const dist = ray_start.dist(hit_pos_world);

                const hit_normal = vec2.from_b2(ray_result.normal);
                const hit_body_id = b2.b2Shape_GetBody(ray_result.shapeId);
                const hit_body_vel = vec2.from_b2(b2.b2Body_GetLinearVelocity(hit_body_id));
                const rel_vel = player_vel.sub(hit_body_vel);

                // 0..1
                // 0 = far away
                // 1 = very close
                const closeness_factor = std.math.clamp((ray_length - dist) / ray_length, 0, 1);

                hit_normal_sum = hit_normal_sum.add(hit_normal.scale(closeness_factor));
                hit_pos_sum = hit_pos_sum.add(hit_pos_world.scale(closeness_factor));
                hit_rel_vel_sum = hit_rel_vel_sum.add(rel_vel.scale(closeness_factor));

                hit_weight_sum += closeness_factor;
                hit_count += 1;

                if (debug) {
                    drender.addLine(ray_start, hit_pos_world, DebugLayer, Color.red);
                    drender.addPointWithPixelSize(hit_pos_world, 10, DebugLayer, Color.red);
                    //drender.addText(hit_pos_world, DebugLayer, Color.white, "{d:.3}", .{closeness_factor});
                }
            }
        }

        if (hit_count > 0) {
            var hit_normal_avg = hit_normal_sum.scale(1.0 / hit_weight_sum);
            const hit_pos_avg = hit_pos_sum.scale(1.0 / hit_weight_sum);
            const hit_rel_vel_avg = hit_rel_vel_sum.scale(1.0 / hit_weight_sum);

            if (hit_normal_avg.len() < 0.1) {
                std.debug.assert(false);
            }

            hit_normal_avg = hit_normal_avg.normalize();

            if (debug) {
                drender.addPointWithPixelSize(hit_pos_avg, 10.0, DebugLayer, Color.blue);
                drender.addLine(hit_pos_avg, hit_pos_avg.add(hit_normal_avg), DebugLayer, Color.blue);
            }

            return ContactSituation{
                .has_contact = true,
                .avg_normal = hit_normal_avg,
                .avg_pos = hit_pos_avg,
                .avg_rvel = hit_rel_vel_avg,
            };
        } else {
            return ContactSituation{
                .has_contact = false,
                .avg_normal = vec2.zero,
                .avg_pos = vec2.zero,
                .avg_rvel = vec2.zero,
            };
        }
    }
};
