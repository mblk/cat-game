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

const PIDController = @import("../utils/pid_controller.zig").PIDController;

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
    max_move_force_factor: f32 = 2.0, // F_max = m*g*factor

    max_turn_rate: f32 = std.math.degreesToRadians(180.0), // rad/s

    jump_min_dv: f32 = 1.0,
    jump_max_dv: f32 = 10.0,
};

pub const State = enum {
    Standing,
    Walking,
    JumpCharging,
    Jumping,
    Falling,

    //Running,
    //Climbing,
    //InSeat,
};

pub const Leg = struct {
    const Self = @This();

    // def
    min_length: f32,
    max_length: f32,

    pivot_local: vec2,

    // state
    contact_age: f32 = 0,
    contact_max_phase: f32 = 0,

    has_contact: bool = false,
    contact_body_id: b2.b2BodyId = b2.b2_nullBodyId, // touched body
    contact_pos_local: vec2 = vec2.zero, // in local space of touched body
    contact_normal_world: vec2 = vec2.zero, // TODO world space i think

    has_prev_contact: bool = false,
    prev_contact_body_id: b2.b2BodyId = b2.b2_nullBodyId, // touched body
    prev_contact_pos_local: vec2 = vec2.zero, // in local space of touched body

    // calculated by player.update
    pivot_pos_world: vec2 = vec2.zero,
    paw_pos_world: vec2 = vec2.zero,

    pub fn copyStateTo(self: Self, target: *Self) void {
        target.contact_age = self.contact_age;
        target.contact_max_phase = self.contact_max_phase;

        target.has_contact = self.has_contact;
        target.contact_body_id = self.contact_body_id;
        target.contact_pos_local = self.contact_pos_local;
        target.contact_normal_world = self.contact_normal_world;

        target.has_prev_contact = self.has_prev_contact;
        target.prev_contact_body_id = self.prev_contact_body_id;
        target.prev_contact_pos_local = self.prev_contact_pos_local;

        target.pivot_pos_world = self.pivot_pos_world;
        target.paw_pos_world = self.paw_pos_world;
    }
};

pub const PlayerTransform = struct {
    const Self = @This();

    transform: Transform2,
    flipped: bool,

    fn flip(self: Self, in: vec2) vec2 {
        if (self.flipped) {
            return vec2{
                .x = -in.x,
                .y = in.y,
            };
        } else {
            return in;
        }
    }

    pub fn rotateLocalToWorld(self: Self, local_vector: vec2) vec2 {
        return self.transform.rotateLocalToWorld(self.flip(local_vector));
    }

    pub fn rotateWorldToLocal(self: Self, world_vector: vec2) vec2 {
        return self.flip(self.transform.rotateWorldToLocal(world_vector));
    }

    pub fn transformLocalToWorld(self: Self, local_position: vec2) vec2 {
        return self.transform.transformLocalToWorld(self.flip(local_position));
    }

    pub fn transformWorldToLocal(self: Self, world_position: vec2) vec2 {
        return self.flip(self.transform.transformWorldToLocal(world_position));
    }
};

pub const Player = struct {
    const Self = @This();

    const DebugLayer = engine.Renderer2D.Layers.Debug;

    def: PlayerDef,
    world: *World,
    main_body_id: b2.b2BodyId = b2.b2_nullBodyId,

    state: State = .Standing,
    orientation_flipped: bool = false, // default: looking right, flipped=looking left

    jump_cooldown: f32 = 0,
    jump_charge: f32 = 0,

    walking_idle_time: f32 = 0,
    walk_pid: PIDController(f32) = PIDController(f32){
        .kp = 10.0, //100.0,
        .ki = 0.0, //20.0,
        .kd = 0.0,
        //.integral_min = -1.0,
        //.integral_max = 1.0,
    },

    sk_transform: PlayerTransform = undefined,
    body_up_curr: vec2 = vec2.init(0, 1),

    legs: [4]Leg,
    leg_phase: f32 = 0.0, // 0..
    leg_update_order: [4]usize = [_]usize{ 0, 2, 1, 3 },
    leg_update_order2: [4]usize = [_]usize{ 0, 1, 2, 3 },
    leg_update_index: usize = 0,

    // hand
    show_hand: bool = false,
    //hand_start: vec2 = undefined,
    hand_end: vec2 = undefined,

    has_mouse_joint: bool = false,
    mouse_joint: b2.b2JointId = b2.b2_nullJointId,

    // hint
    show_hint: bool = false,
    hint_position: vec2 = undefined,
    hint_buffer: [128]u8 = undefined,
    hint_text: ?[]const u8 = null,

    // debug settings
    debug_show_state: bool = false,
    debug_show_force: bool = false,
    debug_show_leg_cast: bool = false,
    debug_show_pid: bool = false,

    // ...
    total_kcal_eaten: f32 = 0,
    total_kcal_burned: f32 = 0,

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

    const PlayerUpdateContext = struct {
        dt: f32,
        input: *engine.InputState,
        mouse_position: vec2,
        control_enabled: bool,

        player_position: vec2,
        player_velocity: vec2,
        player_mass: f32,
        input_axis: vec2,

        contact_situation: ContactSituation,
    };

    pub fn update(
        self: *Self,
        dt: f32,
        input: *engine.InputState,
        mouse_position: vec2,
        control_enabled: bool,
    ) void {

        // reset hand/hint
        self.show_hand = false;
        self.show_hint = false;
        self.hint_text = null;

        // if (!control_enabled) {
        //     if (self.has_mouse_joint) {
        //         b2.b2DestroyJoint(self.mouse_joint);
        //         self.mouse_joint = b2.b2_nullJointId;
        //         self.has_mouse_joint = false;
        //     }
        //     //return;
        // }

        // Step 0: Get basic state
        const player_position = vec2.from_b2(b2.b2Body_GetPosition(self.main_body_id));
        const player_velocity = vec2.from_b2(b2.b2Body_GetLinearVelocity(self.main_body_id));
        const player_mass = b2.b2Body_GetMass(self.main_body_id);
        const input_axis = self.getMoveInputAxis(input);

        // Step 1: Determine contact situation
        std.debug.assert(self.body_up_curr.len() > 0.9 and self.body_up_curr.len() < 1.1);
        const preferred_attach_dir = self.body_up_curr.neg();
        const contact_situation = self.determineContactSituation(preferred_attach_dir);

        const context = PlayerUpdateContext{
            .dt = dt,
            .input = input,
            .mouse_position = mouse_position,
            .control_enabled = control_enabled,

            .player_position = player_position,
            .player_velocity = player_velocity,
            .player_mass = player_mass,
            .input_axis = input_axis,

            .contact_situation = contact_situation,
        };

        // debug
        if (self.debug_show_state) {
            const drender = engine.Renderer2D.Instance;
            drender.addText(player_position.add(vec2.init(0, 3)), DebugLayer, Color.white, "vel {d:.2} rvel {d:.2} mass {d:.2}", .{
                player_velocity.len(),
                contact_situation.avg_rvel.len(),
                player_mass,
            });
            drender.addText(player_position.add(vec2.init(0, 2)), DebugLayer, Color.white, "{s} flipped={any}", .{
                @tagName(self.state),
                self.orientation_flipped,
            });
        }

        // Step 2: Update state
        self.updateState(context);

        // Step 3: Update body orientation
        self.updateBodyOrientation(context);

        // Step 4: Update legs
        self.updateLegsTest(context, contact_situation);

        // Step 5: Apply forces
        var force_request = vec2.zero;

        if (self.state == .Standing or self.state == .Walking or self.state == .JumpCharging) {
            self.updateWalking(context, &force_request);
        }

        self.applyForceRequest(force_request);

        // Step 6: grab stuff?
        self.updateItemHandling(context);
    }

    fn updateBodyOrientation(self: *Self, context: PlayerUpdateContext) void {

        // flip orientation?
        if (true) {
            const vel_world = if (context.contact_situation.has_contact)
                context.contact_situation.avg_rvel
            else
                context.player_velocity;
            const vel_sk = self.sk_transform.rotateWorldToLocal(vel_world);

            // moving backwards and has input?
            if (vel_sk.x < -0.5 and context.input_axis.len() > 0.1) {
                std.log.info("flip", .{});
                self.orientation_flipped = !self.orientation_flipped;
                self.flipLegs();
            }
        }

        // get up target
        const body_up_target = self.getBodyUpTarget(context);

        // change current up
        const angle_diff = vec2.angleFromTo(self.body_up_curr, body_up_target);
        const angle_rate_per_s = std.math.clamp(angle_diff * 10.0, -self.def.max_turn_rate, self.def.max_turn_rate);
        const angle_rate_per_frame = angle_rate_per_s * context.dt;

        self.body_up_curr = self.body_up_curr.rotate(angle_rate_per_frame);

        self.sk_transform = PlayerTransform{
            .transform = Transform2{
                .pos = context.player_position,
                .rot = rot2.from_up_vector(self.body_up_curr),
            },
            .flipped = self.orientation_flipped,
        };
    }

    fn updateItemHandling(self: *Self, context: PlayerUpdateContext) void {
        const input = context.input;
        const mouse_position = context.mouse_position;

        //
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
            };

            var query_filter = b2.b2DefaultQueryFilter();
            query_filter.categoryBits = physics.Categories.Player;
            query_filter.maskBits = physics.Categories.Vehicle | physics.Categories.Item;

            _ = b2.b2World_OverlapAABB(
                self.world.world_id,
                aabb,
                query_filter,
                my_query_func,
                &query_context,
            );

            if (query_context.hit) {
                std.debug.assert(b2.B2_IS_NON_NULL(query_context.body_id));

                self.show_hand = true;
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
                            else => {},
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

    fn updateState(self: *Self, context: PlayerUpdateContext) void {
        const contact_situation = context.contact_situation;
        const input_axis = context.input_axis;

        if (self.jump_cooldown > 0.0) {
            self.jump_cooldown -= context.dt;
        }

        switch (self.state) {
            .Standing => {
                // jump?
                if (context.input.consumeKeyDownEvent(.space)) {
                    self.changeState(.JumpCharging);
                    return;
                }

                // start walking?
                if (input_axis.len() > 0.1 or contact_situation.avg_rvel.len() > 0.1) {
                    self.changeState(.Walking);
                    return;
                }
            },
            .Walking => {
                // falling?
                if (!contact_situation.has_contact) {
                    self.changeState(.Falling);
                    return;
                }

                // jump?
                if (context.input.consumeKeyDownEvent(.space)) {
                    self.changeState(.JumpCharging);
                    return;
                }

                // return to idle?
                if (contact_situation.has_contact and contact_situation.avg_rvel.len() < 0.1 and input_axis.len() < 0.1) {
                    self.walking_idle_time += context.dt;

                    if (self.walking_idle_time > 2.5) {
                        self.walking_idle_time = 0;
                        self.changeState(.Standing);
                        return;
                    }
                }
            },
            .JumpCharging => {
                //
                self.jump_charge += context.dt;

                if (self.jump_charge > 0.25) {
                    const v_player_to_mouse = context.mouse_position.sub(context.player_position);

                    const jump_power = std.math.clamp(
                        v_player_to_mouse.len() * 2.5, // TODO scale depending on camera-distance?
                        self.def.jump_min_dv,
                        self.def.jump_max_dv,
                    );

                    const jump_dir = if (v_player_to_mouse.len() > 0.1)
                        v_player_to_mouse.normalize()
                    else
                        self.sk_transform.rotateLocalToWorld(vec2.init(1, 1)).normalize();

                    if (true) {
                        const drender = engine.Renderer2D.Instance;

                        const p1 = context.player_position;
                        const p2 = context.mouse_position; //p1.add(jump_dir);

                        drender.addLine(p1, p2, DebugLayer, Color.white);
                        drender.addText(context.mouse_position, DebugLayer, Color.white, "Jump power: {d:.1} (c to cancel)", .{jump_power});

                        self.simulateJump(jump_dir, jump_power);
                    }

                    if (context.input.consumeKeyDownEvent(.c)) {
                        self.changeState(.Walking);
                        return;
                    }

                    if (!context.input.getKeyState(.space)) {
                        self.doJump(jump_dir, jump_power);
                        self.changeState(.Jumping);
                    }
                } else {
                    //
                    if (!context.input.getKeyState(.space)) {
                        const jump_dir = self.sk_transform.rotateLocalToWorld(vec2.init(1, 1)).normalize();
                        const jump_power = (self.def.jump_max_dv - self.def.jump_min_dv) * 0.5;

                        self.doJump(jump_dir, jump_power);
                        self.changeState(.Jumping);
                    }
                }
            },
            .Jumping => {
                //
                if (self.jump_cooldown < 0.0) {
                    self.changeState(.Falling);
                }
            },
            .Falling => {
                //
                if (contact_situation.has_contact) {
                    self.changeState(.Walking);
                    return;
                }
            },
        }
    }

    fn changeState(self: *Self, new_state: State) void {
        std.log.info("changeState: {s} -> {s}", .{ @tagName(self.state), @tagName(new_state) });

        self.state = new_state;

        if (new_state == .JumpCharging) {
            self.jump_cooldown = 0.5;
            self.jump_charge = 0.0;
        }
        if (new_state == .Jumping) {
            self.jump_cooldown = 0.5;
            //self.jump_power = 0.0;
        }

        //self.walk_pid.reset();
    }

    fn getBodyUpTarget(self: Self, context: PlayerUpdateContext) vec2 {
        const contact_situation = context.contact_situation;

        _ = self;

        if (contact_situation.has_contact) {
            return contact_situation.avg_normal;
        } else {
            return vec2.init(0, 1);
        }
    }

    fn applyForceRequest(self: *Self, force_request: vec2) void {
        //
        const drender = engine.Renderer2D.Instance;

        if (force_request.len() < 0.001) {
            return;
        }

        // clamp force
        const player_mass = b2.b2Body_GetMass(self.main_body_id);
        const max_force = player_mass * 9.81 * self.def.max_move_force_factor;
        const force_len_to_apply = std.math.clamp(force_request.len(), 0, max_force);
        const force_dir = force_request.normalize();
        const force_to_apply = force_dir.scale(force_len_to_apply);

        if (self.debug_show_force) {
            const player_position = self.getTransform().pos;

            drender.addLine(player_position, player_position.add(force_dir), DebugLayer, Color.blue);
            drender.addText(player_position.add(force_dir), DebugLayer, Color.white, "{d:.1}/{d:.1} N", .{ force_len_to_apply, force_request.len() });
        }

        var contact_count: usize = 0;

        for (&self.legs) |*leg| {
            if (leg.has_contact) {
                contact_count += 1;
            }
        }

        if (contact_count > 0) {
            const count_f32: f32 = @floatFromInt(contact_count);

            const force_per_self = force_to_apply.scale(1 / count_f32);
            const force_per_contact = force_to_apply.neg().scale(1 / count_f32);

            // apply opposite force to self and other bodies
            for (&self.legs) |*leg| {
                if (leg.has_contact) {
                    //
                    const contact_pos_world = vec2.from_b2(b2.b2Body_GetWorldPoint(leg.contact_body_id, leg.contact_pos_local.to_b2()));
                    const gravity_dir = vec2.init(0, -1);
                    const angle_gravity_normal = std.math.radiansToDegrees(vec2.angleBetween(gravity_dir, leg.contact_normal_world)); // Note: in deg

                    if (false) {
                        const pp = contact_pos_world.add(leg.contact_normal_world);
                        drender.addLine(contact_pos_world, pp, DebugLayer, Color.red);
                        drender.addText(pp, DebugLayer, Color.white, "{d:.1}", .{angle_gravity_normal});
                    }

                    // don't walk on the ceiling
                    if (angle_gravity_normal < 85.0) {
                        continue;
                    }

                    // apply to self
                    b2.b2Body_ApplyForceToCenter(self.main_body_id, force_per_self.to_b2(), true);

                    // apply to other body
                    if (b2.b2Body_GetType(leg.contact_body_id) == b2.b2_dynamicBody) {
                        b2.b2Body_ApplyForce(leg.contact_body_id, force_per_contact.to_b2(), contact_pos_world.to_b2(), true);
                    }
                }
            }
        }
    }

    fn updateLegsTest(self: *Self, context: PlayerUpdateContext, contact_situation: ContactSituation) void {
        //
        const player_vel = contact_situation.avg_rvel;

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
        var best_direction = vec2.zero;
        best_direction = best_direction.add(player_vel);
        best_direction = best_direction.add(self.sk_transform.rotateLocalToWorld(vec2.init(0, -1)));
        if (best_direction.len() < 0.01) {
            // TODO
            std.log.err("best_direction.len < 0.01", .{});
            best_direction = best_direction.add(self.sk_transform.rotateLocalToWorld(vec2.init(0, -1)));
        }
        best_direction = best_direction.normalize();

        if (self.debug_show_leg_cast) {
            _ = self.findGroundContacts(self.sk_transform.transformLocalToWorld(self.def.sk_fwd_pivot), best_direction, self.legs[0].max_length, true);
        }

        // clear legs with invalid body reference (eg. body was destroyed since last frame)
        for (&self.legs) |*leg| {
            if (leg.has_contact) {
                if (!b2.b2Body_IsValid(leg.contact_body_id)) {
                    std.log.warn("leg contact is no longer valid, resetting ...", .{});

                    leg.has_contact = false;
                    // TODO clear other stuff as well?
                }
            }

            if (leg.has_prev_contact) {
                if (!b2.b2Body_IsValid(leg.prev_contact_body_id)) {
                    std.log.warn("prev leg contact is no longer valid, resetting ...", .{});

                    leg.has_prev_contact = false;
                    // TODO clear other stuff as well?
                }
            }
        }

        // update leg
        if (do_update) {
            const leg_order = if (player_vel.len() > 2.5)
                self.leg_update_order2
            else
                self.leg_update_order;

            const next_leg_index = leg_order[self.leg_update_index];
            const active_leg = &self.legs[next_leg_index];

            self.leg_update_index = (self.leg_update_index + 1) % 4;

            // shift contact
            active_leg.has_prev_contact = active_leg.has_contact;
            active_leg.prev_contact_body_id = active_leg.contact_body_id;
            active_leg.prev_contact_pos_local = active_leg.contact_pos_local;

            active_leg.has_contact = false;
            active_leg.contact_body_id = b2.b2_nullBodyId;
            active_leg.contact_pos_local = vec2.zero;
            active_leg.contact_normal_world = vec2.zero;

            // find new contact point
            const pivot_world = self.sk_transform.transformLocalToWorld(active_leg.pivot_local);
            const ground_contacts = self.findGroundContacts(pivot_world, best_direction, active_leg.max_length * 1.3, false);

            if (ground_contacts.contact_count > 0) {
                const contact = ground_contacts.contact1.?;

                active_leg.contact_age = 0;
                active_leg.contact_max_phase = max_phase;

                active_leg.has_contact = true;
                active_leg.contact_body_id = contact.body_id;
                active_leg.contact_pos_local = contact.pos_local;
                active_leg.contact_normal_world = contact.normal;
            }
        }

        // TODO must be done after physics step
        // update calculated positions
        for (&self.legs) |*leg| {
            leg.contact_age += context.dt;

            leg.pivot_pos_world = self.sk_transform.transformLocalToWorld(leg.pivot_local);

            if (!leg.has_contact) {
                // Case 1: hanging free in the air
                const paw_pos_local = leg.pivot_local.add(vec2.init(1, -1).normalize().scale(leg.min_length));
                leg.paw_pos_world = self.sk_transform.transformLocalToWorld(paw_pos_local);
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
                            const up = self.sk_transform.rotateLocalToWorld(vec2.init(0, 1));
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

    fn flipLegs(self: *Self) void {
        //
        const before: [4]Leg = self.legs;

        before[0].copyStateTo(&self.legs[2]);
        before[1].copyStateTo(&self.legs[3]);
        before[2].copyStateTo(&self.legs[0]);
        before[3].copyStateTo(&self.legs[1]);
    }

    fn doJump(self: *Self, dir: vec2, power: f32) void {
        std.log.info("doJump dir={d:.3} power={d:.3}", .{ dir, power });

        const player_mass = b2.b2Body_GetMass(self.main_body_id);

        const vel_to_add = power;
        const p = player_mass * vel_to_add;
        const p_vec = dir.normalize().scale(p);

        var contact_count: usize = 0;
        for (&self.legs) |*leg| {
            if (leg.has_contact) {
                contact_count += 1;
            }
        }

        if (contact_count > 0) {
            const count_f32: f32 = @floatFromInt(contact_count);
            const impulse_per_contact = p_vec.neg().scale(1 / count_f32);

            // apply to self
            b2.b2Body_ApplyLinearImpulseToCenter(self.main_body_id, p_vec.to_b2(), true);

            // apply opposite impulse to other bodies
            for (&self.legs) |*leg| {
                if (leg.has_contact) {
                    if (b2.b2Body_GetType(leg.contact_body_id) == b2.b2_dynamicBody) {
                        b2.b2Body_ApplyLinearImpulseToCenter(leg.contact_body_id, impulse_per_contact.to_b2(), true);
                    }
                }
            }
        } else {
            std.log.err("doJump: legs have not ground contact", .{});
        }

        self.total_kcal_burned += 10.0;
    }

    fn simulateJump(self: Self, dir: vec2, power: f32) void {
        //
        const drender = engine.Renderer2D.Instance;

        const p0 = vec2.from_b2(b2.b2Body_GetPosition(self.main_body_id));

        const v0_before = vec2.from_b2(b2.b2Body_GetLinearVelocity(self.main_body_id));
        const dv_jump = dir.normalize().scale(power);
        const v0 = v0_before.add(dv_jump);

        const g = vec2.init(0, -9.81);

        const dt: f32 = 0.05;

        var time: f32 = 0;

        var p_last: ?vec2 = null;
        for (0..100) |_| {
            const a = v0.scale(time);
            const b = g.scale(0.5 * time * time);

            const p_curr = p0.add(a).add(b);
            const v_curr = v0.add(g.scale(time));

            if (self.checkJumpCollision(p_curr, v_curr.scale(dt * 1.1))) {
                break;
            }

            drender.addPointWithPixelSize(p_curr, 5.0, DebugLayer, Color.red);
            if (p_last) |p| drender.addLine(p, p_curr, DebugLayer, Color.red);

            p_last = p_curr;
            time += dt;
        }
    }

    fn checkJumpCollision(self: Self, pos: vec2, translation: vec2) bool {
        //
        var query_filter = b2.b2DefaultQueryFilter();
        query_filter.categoryBits = physics.Categories.Player; // who we are
        query_filter.maskBits = physics.Categories.Ground | physics.Categories.Vehicle | physics.Categories.Item; // what we want to hit

        const ray_result = b2.b2World_CastRayClosest( // TODO ray cast sphere instead for more accurate results?
            self.world.world_id,
            pos.to_b2(),
            translation.to_b2(),
            query_filter,
        );

        return ray_result.hit;
    }

    fn updateStanding(self: *Self, context: PlayerUpdateContext) void {
        _ = self;
        _ = context;
    }

    fn updateWalking(self: *Self, context: PlayerUpdateContext, force_request: *vec2) void {
        const contact_situation = context.contact_situation;
        const move_input = context.input_axis;

        if (!contact_situation.has_contact) {
            //std.log.err("updateWalking: no ground contact", .{});
            return;
        }

        //
        const player_position = vec2.from_b2(b2.b2Body_GetPosition(self.main_body_id));
        const player_mass = b2.b2Body_GetMass(self.main_body_id);

        const v_n = contact_situation.avg_normal;
        const v_right = v_n.turn90cw();
        const v_up = v_n;

        const max_velocity = if (context.input.getKeyState(.left_shift)) self.def.max_run_velocity else self.def.max_walk_velocity;

        //
        if (true) {
            //if (move_input.len() > 0.1) {
            const f_g = player_mass * 9.81;

            force_request.* = force_request.add(vec2.init(0, f_g));
            //}
        }

        // move?
        if (true) {
            const proj_vel = contact_situation.avg_rvel.dot(v_right);
            const target_vel = move_input.x * max_velocity;

            const output = self.walk_pid.update(context.dt, target_vel, proj_vel);
            const acc = output;

            const f = player_mass * acc;
            const f_vec = v_right.scale(f);

            force_request.* = force_request.add(f_vec);
        }

        // hold on?
        if (true) {
            const rel_pos = player_position.sub(contact_situation.avg_pos);
            const proj_dist = vec2.dot(contact_situation.avg_normal, rel_pos);
            const target_dist = self.def.shape_radius * 1.25;
            const err_dist = target_dist - proj_dist;

            const proj_vel = vec2.dot(contact_situation.avg_normal, contact_situation.avg_rvel);
            const target_vel = err_dist * 10.0;
            const err_vel = target_vel - proj_vel;

            // TODO use PID

            const acc = err_vel * 50;
            const f = player_mass * acc;
            const f_vec = v_up.scale(f);

            force_request.* = force_request.add(f_vec);
        }
    }

    fn updateJumping(self: *Self, context: PlayerUpdateContext) void {
        //
        _ = self;
        _ = context;
    }

    fn updateFalling(self: *Self, context: PlayerUpdateContext) void {
        //
        _ = self;
        _ = context;
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

    const QueryData = struct {
        point: vec2,
        hit: bool,
        body_id: b2.b2BodyId,
        //exact_hit: bool = true,
    };

    // pub const b2OverlapResultFcn = fn (b2ShapeId, ?*anyopaque) callconv(.c) bool;
    fn my_query_func(shape_id: b2.b2ShapeId, context: ?*anyopaque) callconv(.c) bool {
        const query_data: *QueryData = @ptrCast(@alignCast(context));

        const body_id = b2.b2Shape_GetBody(shape_id);
        const body_type = b2.b2Body_GetType(body_id);

        if (body_type != b2.b2_dynamicBody) {
            return true; // continue
        }

        const b2point = b2.b2Vec2{
            .x = query_data.point.x,
            .y = query_data.point.y,
        };

        // if (!query_data.exact_hit) {
        //     query_data.hit = true;
        //     query_data.body_id = body_id;
        //     return false;
        // }

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
                query_filter,
            );

            if (ray_result.hit) {
                const hit_pos_world = vec2.from_b2(ray_result.point);
                const dist = ray_start.dist(hit_pos_world);

                const hit_normal = vec2.from_b2(ray_result.normal);
                const hit_body_id = b2.b2Shape_GetBody(ray_result.shapeId);

                const closeness_factor = std.math.clamp((ray_length - dist) / ray_length, 0, 1);
                // 0..1
                // 0 = far away
                // 1 = very close

                //const effective_score = angle_factor * closeness_factor;
                _ = closeness_factor;
                const effective_score = angle_factor;

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

    const ContactSituation = struct {
        has_contact: bool,
        avg_normal: vec2,
        avg_pos: vec2,
        avg_rvel: vec2,
    };

    pub fn determineContactSituation(
        self: *Self,
        preferred_attach_dir: vec2,
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

        var hit_count: usize = 0;
        var hit_weight_sum: f32 = 0;
        var hit_normal_sum: vec2 = vec2.zero;
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

                // 0..1
                // 0 = bad angle
                // 1 = good angle
                const angle_factor = std.math.clamp(1.0 - vec2.angleBetween(ray_translation, preferred_attach_dir) / std.math.pi, 0, 1);

                std.debug.assert(closeness_factor >= 0 and closeness_factor <= 1);
                std.debug.assert(angle_factor >= 0 and angle_factor <= 1);

                //const weight = (closeness_factor * 1.0 + angle_factor * 3.0) / 4.0;
                const weight = std.math.clamp(closeness_factor * angle_factor, 0, 1);

                std.debug.assert(weight >= 0 and weight <= 1);

                //_ = angle_factor;

                hit_count += 1;
                hit_weight_sum += weight;
                hit_normal_sum = hit_normal_sum.add(hit_normal.scale(weight));
                hit_pos_sum = hit_pos_sum.add(hit_pos_world.scale(weight));
                hit_rel_vel_sum = hit_rel_vel_sum.add(rel_vel.scale(weight));

                if (debug) {
                    drender.addLine(ray_start, hit_pos_world, DebugLayer, Color.red);
                    drender.addPointWithPixelSize(hit_pos_world, 10, DebugLayer, Color.red);
                    drender.addText(hit_pos_world, DebugLayer, Color.white, "{d:.3}", .{weight});
                }
            }
        }

        if (hit_count > 0) {
            var hit_normal_avg = hit_normal_sum.scale(1.0 / hit_weight_sum);
            const hit_pos_avg = hit_pos_sum.scale(1.0 / hit_weight_sum);
            const hit_rel_vel_avg = hit_rel_vel_sum.scale(1.0 / hit_weight_sum);

            if (hit_normal_avg.len() < 0.1) {
                std.log.err("unknown contact situation", .{});
                //std.debug.assert(false);

                return ContactSituation{
                    .has_contact = true,
                    .avg_normal = vec2.init(0, 1),
                    .avg_pos = hit_pos_avg,
                    .avg_rvel = hit_rel_vel_avg,
                };
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
