const std = @import("std");

const zearcut = @import("zearcut");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const rot2 = engine.rot2;
const Transform2 = engine.Transform2;
const Color = engine.Color;

const Renderer2D = engine.Renderer2D;
const Camera = engine.Camera;

const world_ns = @import("../world.zig");
const World = world_ns.World;

const ground_segment_ns = @import("../ground_segment.zig");
const GroundSegment = ground_segment_ns.GroundSegment;

const vehicle_ns = @import("../vehicle.zig");
const Vehicle = vehicle_ns.Vehicle;
const Block = vehicle_ns.Block;
const Device = vehicle_ns.Device;
const WheelDevice = vehicle_ns.WheelDevice;
const ThrusterDevice = vehicle_ns.ThrusterDevice;

const item_ns = @import("../item.zig");
const Item = item_ns.Item;

const player_ns = @import("../player.zig");
const Player = player_ns.Player;

// TODO remove
const zbox = @import("zbox");
const b2 = zbox.API;
// TODO remove

pub const WorldRendererSettings = struct {
    show_player_skeleton: bool = false,

    tail_angle: f32 = std.math.degreesToRadians(30),
    head_angle: f32 = std.math.degreesToRadians(30),
};

pub const WorldRenderer = struct {
    const Self = @This();

    settings: WorldRendererSettings = .{},

    renderer2D: *Renderer2D,

    mat_default: engine.MaterialRef,

    mat_background: engine.MaterialRef,
    mat_brick: engine.MaterialRef,
    mat_wood: engine.MaterialRef,
    mat_cardboard: engine.MaterialRef,

    mat_face: engine.MaterialRef,

    const Layers = struct {
        const _base = Renderer2D.Layers.World;

        const Background = _base + 0;
        const Ground = _base + 10;
        const Outer_Bounds = _base + 20;
        const Vehicle_Block = _base + 30;
        const Vehicle_Device = _base + 40;
        const Items = _base + 50;
        const Player = _base + 60;
        const Overlay = _base + 70;

        const Debug = Renderer2D.Layers.Debug;
    };

    // const LLL = enum {
    //     Background,
    //     Outer_Bounds,
    //     Ground,
    // };
    // const LLL2: type = makeLayersEnum(LLL, Renderer2D.Layers.Tools);
    // const LayerValues: LLL2 = undefined;

    // fn makeLayersEnum(comptime T: type, start_value: i32) type {
    //     const fieldInfos = @typeInfo(T).@"enum".fields;

    //     var enumDecls: [fieldInfos.len]std.builtin.Type.EnumField = undefined;
    //     var decls = [_]std.builtin.Type.Declaration{};

    //     var next_value: i32 = start_value;

    //     inline for (fieldInfos, 0..) |field, i| {
    //         //@compileLog("iter " ++ field.name);
    //         enumDecls[i] = .{ .name = field.name ++ "", .value = next_value };
    //         next_value += 1;
    //     }

    //     return @Type(.{
    //         .@"enum" = .{
    //             .tag_type = i32,
    //             .fields = &enumDecls,
    //             .decls = &decls,
    //             .is_exhaustive = true,
    //         },
    //     });
    // }

    pub fn init(self: *Self, renderer2D: *Renderer2D) !void {
        self.* = Self{
            .renderer2D = renderer2D,

            .mat_default = renderer2D.getMaterial("default"),

            .mat_background = renderer2D.getMaterial("background"),
            .mat_brick = renderer2D.getMaterial("brick"),
            .mat_wood = renderer2D.getMaterial("wood"),
            .mat_cardboard = renderer2D.getMaterial("cardboard"),

            .mat_face = renderer2D.getMaterial("face1"),
        };
    }

    pub fn deinit(self: *Self) void {
        //
        _ = self;
    }

    pub fn render(self: *Self, world: *const World, camera: *const Camera) void {

        //
        self.renderBackground(camera);
        self.renderOuterBounds(world);
        self.renderStartFinish(world);

        // ground segments
        for (world.ground_segments.items) |*ground_segment| {
            self.renderGroundSegment(ground_segment);
        }

        for (world.test_platforms.items) |joint_id| {
            self.renderTestPlatform(joint_id);
        }

        // vehicles
        for (world.vehicles.items) |*vehicle| {
            if (!vehicle.alive) continue;
            self.renderVehicle(vehicle);
        }

        // items
        for (world.items.items) |*item| {
            if (!item.alive) continue;
            self.renderItem(item);
        }

        // players
        for (world.players.items) |*player| {
            self.renderPlayer(player);
            self.renderScore(player, camera);
        }
    }

    fn renderTestPlatform(self: *Self, joint_id: b2.b2JointId) void {
        //
        const platform_body_id = b2.b2Joint_GetBodyB(joint_id);

        const t = Transform2.from_b2(b2.b2Body_GetTransform(platform_body_id));

        const hw = 5.0;
        const hh = 1.0;

        const p0 = t.transformLocalToWorld(vec2.init(-hw, -hh));
        const p1 = t.transformLocalToWorld(vec2.init(hw, -hh));
        const p2 = t.transformLocalToWorld(vec2.init(hw, hh));
        const p3 = t.transformLocalToWorld(vec2.init(-hw, hh));

        const points = [4]vec2{ p0, p1, p2, p3 };

        self.renderer2D.addQuadPC(points, Layers.Ground + 1, Color.gray3, self.mat_default);
    }

    fn renderBackground(self: *Self, camera: *const Camera) void {
        const screen_size = camera.viewport_size;
        const width: f32 = @floatFromInt(screen_size[0]);
        const height: f32 = @floatFromInt(screen_size[1]);

        const p1 = camera.screenToWorld([_]f32{ 0, height });
        const p2 = camera.screenToWorld([_]f32{ width, height });
        const p3 = camera.screenToWorld([_]f32{ width, 0 });
        const p4 = camera.screenToWorld([_]f32{ 0, 0 });

        const points = [4]vec2{ p1, p2, p3, p4 };

        self.renderer2D.addQuadP(points, Layers.Background, self.mat_background);
    }

    fn renderOuterBounds(self: *Self, world: *const World) void {
        const hs = world.settings.size.scale(0.5);

        const brick_size = 100;

        const left_quad = [4]vec2{
            vec2.init(-hs.x - brick_size, -hs.y - brick_size),
            vec2.init(-hs.x, -hs.y - brick_size),
            vec2.init(-hs.x, hs.y + brick_size),
            vec2.init(-hs.x - brick_size, hs.y + brick_size),
        };

        const right_quad = [4]vec2{
            vec2.init(hs.x, -hs.y - brick_size),
            vec2.init(hs.x + brick_size, -hs.y - brick_size),
            vec2.init(hs.x + brick_size, hs.y + brick_size),
            vec2.init(hs.x, hs.y + brick_size),
        };

        const top_quad = [4]vec2{
            vec2.init(-hs.x, hs.y),
            vec2.init(hs.x, hs.y),
            vec2.init(hs.x, hs.y + brick_size),
            vec2.init(-hs.x, hs.y + brick_size),
        };

        const bottom_quad = [4]vec2{
            vec2.init(-hs.x, -hs.y - brick_size),
            vec2.init(hs.x, -hs.y - brick_size),
            vec2.init(hs.x, -hs.y),
            vec2.init(-hs.x, -hs.y),
        };

        self.renderer2D.addQuadRepeatingP(left_quad, Layers.Outer_Bounds, 0.05, self.mat_brick);
        self.renderer2D.addQuadRepeatingP(right_quad, Layers.Outer_Bounds, 0.05, self.mat_brick);
        self.renderer2D.addQuadRepeatingP(top_quad, Layers.Outer_Bounds, 0.05, self.mat_brick);
        self.renderer2D.addQuadRepeatingP(bottom_quad, Layers.Outer_Bounds, 0.05, self.mat_brick);
    }

    fn renderGroundSegment(self: *Self, ground_segment: *const GroundSegment) void {
        const tex_scaling = 0.05;

        // Body not yet created ?
        if (b2.B2_IS_NULL(ground_segment.body_id)) {
            return;
        }

        switch (ground_segment.shape) {
            //.None => {},
            .Box => |box| {
                const box_t = Transform2.from_b2(b2.b2Body_GetTransform(ground_segment.body_id));

                const box_t2 = Transform2{
                    .pos = box_t.pos,
                    .rot = rot2.identity,
                };

                const hw = box.width * 0.5;
                const hh = box.height * 0.5;
                const box_points = [4]vec2{ // ccw
                    box_t.transformLocalToWorld(vec2.init(-hw, -hh)),
                    box_t.transformLocalToWorld(vec2.init(hw, -hh)),
                    box_t.transformLocalToWorld(vec2.init(hw, hh)),
                    box_t.transformLocalToWorld(vec2.init(-hw, hh)),
                };

                const box_uvs = [4]vec2{
                    box_t2.transformLocalToWorld(vec2.init(-hw, -hh)).scale(tex_scaling),
                    box_t2.transformLocalToWorld(vec2.init(hw, -hh)).scale(tex_scaling),
                    box_t2.transformLocalToWorld(vec2.init(hw, hh)).scale(tex_scaling),
                    box_t2.transformLocalToWorld(vec2.init(-hw, hh)).scale(tex_scaling),
                };

                self.renderer2D.addQuadPU(box_points, box_uvs, Layers.Ground, self.mat_wood);
            },
            .Circle => |circle| {
                self.renderer2D.addSolidCircle(ground_segment.position, circle.radius, Layers.Ground, Color.white, self.mat_wood);
            },
            .Polygon => |polygon| {

                // if (false) {
                //const point_count: usize = polygon.points.len;
                //     for (0..point_count) |i| {
                //         const p1_local = ground_segment.points.items[i];
                //         const p2_local = ground_segment.points.items[(i + 1) % point_count];

                //         const p1_world = ground_segment.position.add(p1_local);
                //         const p2_world = ground_segment.position.add(p2_local);

                //         self.renderer2D.addLine(p1_world, p2_world, Color.white);
                //     }
                // }

                // ----------------------------------------------

                const points: []vec2 = polygon.points;

                const count: usize = points.len;
                const data: [*]const zearcut.vec2 = @ptrCast(points.ptr);

                const data_slice: []const zearcut.vec2 = data[0..count];

                var result = zearcut.create(data_slice) catch unreachable;
                defer result.deinit();

                // TODO
                // - only call when changed + cache result
                // - static geometry renderer

                // ----------------------------------------------

                var i: usize = 0;
                while (i < result.indices.len) : (i += 3) {

                    // Note: Earcut output triangles are clockwise.
                    const p1_local = points[result.indices[i]];
                    const p2_local = points[result.indices[i + 1]];
                    const p3_local = points[result.indices[i + 2]];

                    const p1_world = ground_segment.position.add(p1_local);
                    const p2_world = ground_segment.position.add(p2_local);
                    const p3_world = ground_segment.position.add(p3_local);

                    const p1_uv = vec2.init(
                        p1_world.x * tex_scaling,
                        p1_world.y * tex_scaling,
                    );
                    const p2_uv = vec2.init(
                        p2_world.x * tex_scaling,
                        p2_world.y * tex_scaling,
                    );
                    const p3_uv = vec2.init(
                        p3_world.x * tex_scaling,
                        p3_world.y * tex_scaling,
                    );

                    // TODO: order ?
                    self.renderer2D.addTrianglePU(
                        [3]vec2{ p1_world, p2_world, p3_world },
                        [3]vec2{ p1_uv, p2_uv, p3_uv },
                        Layers.Ground,
                        self.mat_wood,
                    );
                }
            },
        }
    }

    fn renderVehicle(self: *Self, vehicle: *const Vehicle) void {
        for (vehicle.blocks.items) |*block| {
            if (!block.alive) continue;

            const hs = block.def.size.scale(0.5);
            const center_local = block.local_position;
            const points_local = [4]vec2{
                center_local.add(vec2.init(-hs.x, -hs.y)),
                center_local.add(vec2.init(hs.x, -hs.y)),
                center_local.add(vec2.init(hs.x, hs.y)),
                center_local.add(vec2.init(-hs.x, hs.y)),
            };
            const points_world = [4]vec2{
                vehicle.transformLocalToWorld(points_local[0]),
                vehicle.transformLocalToWorld(points_local[1]),
                vehicle.transformLocalToWorld(points_local[2]),
                vehicle.transformLocalToWorld(points_local[3]),
            };

            self.renderer2D.addQuadP(points_world, Layers.Vehicle_Block, self.mat_cardboard);
        }

        for (vehicle.devices.items) |*device| {
            if (!device.alive) continue;

            //

            switch (device.type) {
                .Wheel => {
                    const wheel: *const WheelDevice = &vehicle.wheels.items[device.data_index];
                    const radius = wheel.def.radius;

                    const t = wheel.getWheelTransform();
                    const center_world = t.pos;

                    const num_knobs = 10;
                    const angle_per_knob: f32 = 2.0 * std.math.pi / @as(f32, num_knobs);
                    var knob_positions_world: [num_knobs]vec2 = undefined;

                    for (0..num_knobs) |knob_index| {
                        const knob_angle: f32 = angle_per_knob * @as(f32, @floatFromInt(knob_index));
                        const knob_rot = rot2.from_angle(knob_angle);

                        const offset_local = knob_rot.rotateLocalToWorld(vec2.init(radius * 0.666, 0));
                        const offset_world = t.rotateLocalToWorld(offset_local);
                        const knob_world = center_world.add(offset_world);

                        knob_positions_world[knob_index] = knob_world;
                    }

                    self.renderer2D.addSolidCircle(center_world, radius, Layers.Vehicle_Device, Color.black, self.mat_default);
                    self.renderer2D.addSolidCircle(center_world, radius * 0.9, Layers.Vehicle_Device + 1, Color.gray4, self.mat_default);
                    for (knob_positions_world) |p| {
                        self.renderer2D.addSolidCircle(p, radius * 0.1, Layers.Vehicle_Device + 2, Color.white, self.mat_default);
                    }
                },
                .Thruster => {
                    const thruster: *const ThrusterDevice = &vehicle.thrusters.items[device.data_index];

                    const hs = thruster.def.size.scale(0.5);

                    const center_local = device.local_position;
                    const points_local = [4]vec2{
                        center_local.add(vec2.init(-hs.x, -hs.y)),
                        center_local.add(vec2.init(hs.x, -hs.y)),
                        center_local.add(vec2.init(hs.x, hs.y)),
                        center_local.add(vec2.init(-hs.x, hs.y)),
                    };
                    const points_world = [4]vec2{
                        vehicle.transformLocalToWorld(points_local[0]),
                        vehicle.transformLocalToWorld(points_local[1]),
                        vehicle.transformLocalToWorld(points_local[2]),
                        vehicle.transformLocalToWorld(points_local[3]),
                    };

                    self.renderer2D.addQuadPC(points_world, Layers.Vehicle_Device, Color.gray4, self.mat_default);

                    // TODO thrust/exhaust
                },
            }
        }
    }

    fn renderBlock(self: *Self, block: *Block) void {
        //
        _ = self;
        _ = block;
    }

    fn renderDevice(self: *Self, device: *Device) void {
        //
        _ = self;
        _ = device;
    }

    fn renderItem(self: *Self, item: *Item) void {
        const t = item.getTransform();

        var color = Color.white;
        switch (item.def.data) {
            .Food => |food_data| {
                //
                _ = food_data;
                color = Color.init(153, 102, 51, 255); // brown
            },
            .Debris => |debris_data| {
                //
                _ = debris_data;
            },
        }

        switch (item.def.shape) {
            .Circle => |radius| {
                self.renderer2D.addSolidCircle(t.pos, radius, Layers.Items, color, self.mat_default);
            },
            .Rect => |size| {
                const hs = size.scale(0.5);
                const center_local = vec2.zero;
                const points_local = [4]vec2{
                    center_local.add(vec2.init(-hs.x, -hs.y)),
                    center_local.add(vec2.init(hs.x, -hs.y)),
                    center_local.add(vec2.init(hs.x, hs.y)),
                    center_local.add(vec2.init(-hs.x, hs.y)),
                };
                const points_world = [4]vec2{
                    t.transformLocalToWorld(points_local[0]),
                    t.transformLocalToWorld(points_local[1]),
                    t.transformLocalToWorld(points_local[2]),
                    t.transformLocalToWorld(points_local[3]),
                };
                // ccw
                self.renderer2D.addTrianglePC([3]vec2{ points_world[0], points_world[1], points_world[2] }, Layers.Items, color, self.mat_default);
                self.renderer2D.addTrianglePC([3]vec2{ points_world[0], points_world[2], points_world[3] }, Layers.Items, color, self.mat_default);
            },
        }
    }

    fn renderPlayer(self: *Self, player: *const Player) void {
        //
        const sk_t = player.sk_transform;
        const def = player.def;

        const body_color = Color.init(140, 140, 140, 255);

        // def
        const neck_length: f32 = 0.2;
        const tail_length: f32 = 0.5;

        // local
        const sk_center = vec2.init(0, 0);

        const sk_aft = def.sk_aft_pivot;
        const sk_fwd = def.sk_fwd_pivot;

        const sk_tail = sk_aft.add(vec2.init(-tail_length, 0).rotate(self.settings.tail_angle));

        const body_offset_x = 0.1;
        const body_offset_top = 0.05;
        const body_offset_bottom = 0.2;

        const body_p0 = sk_aft.add(vec2.init(-body_offset_x, -body_offset_bottom)); // lower left
        const body_p1 = sk_fwd.add(vec2.init(body_offset_x, -body_offset_bottom)); // lower right
        const body_p2 = sk_fwd.add(vec2.init(body_offset_x, body_offset_top)); // upper right
        const body_p3 = sk_aft.add(vec2.init(-body_offset_x, body_offset_top)); // upper left

        const sk_neck_base = def.sk_fwd_pivot.add(vec2.init(0, (body_offset_top - body_offset_bottom) * 0.5));
        const sk_neck_head = sk_neck_base.add(vec2.init(neck_length, 0).rotate(self.settings.head_angle));
        const sk_head = sk_neck_head;

        // world
        const sk_center_world = sk_t.transformLocalToWorld(sk_center);

        const sk_aft_world = sk_t.transformLocalToWorld(sk_aft);
        const sk_fwd_world = sk_t.transformLocalToWorld(sk_fwd);

        const sk_tail_world = sk_t.transformLocalToWorld(sk_tail);

        const sk_neck_base_world = sk_t.transformLocalToWorld(sk_neck_base);
        const sk_neck_head_world = sk_t.transformLocalToWorld(sk_neck_head);
        const sk_head_world = sk_t.transformLocalToWorld(sk_head);

        const body_p0_world = sk_t.transformLocalToWorld(body_p0);
        const body_p1_world = sk_t.transformLocalToWorld(body_p1);
        const body_p2_world = sk_t.transformLocalToWorld(body_p2);
        const body_p3_world = sk_t.transformLocalToWorld(body_p3);

        // ------------

        // skeleton lines
        if (self.settings.show_player_skeleton) {
            // physics shape
            self.renderer2D.addCircle(sk_center_world, player.def.shape_radius, Layers.Debug, Color.white);

            self.renderer2D.addLine(sk_aft_world, sk_fwd_world, Layers.Debug, Color.white);
            self.renderer2D.addLine(sk_aft_world, sk_tail_world, Layers.Debug, Color.white);
            //self.renderer2D.addLine(sk_fwd_world, sk_head_world, Layers.Debug, Color.white);
        }

        // main body
        self.renderer2D.addQuadPC([4]vec2{ body_p0_world, body_p1_world, body_p2_world, body_p3_world }, Layers.Player, body_color, self.mat_default);

        self.renderNeck(sk_neck_base_world, sk_neck_head_world, Layers.Player);

        const half_head_size = 0.20;
        const head_points = [4]vec2{
            sk_head_world.add(vec2.init(-half_head_size, -half_head_size)),
            sk_head_world.add(vec2.init(half_head_size, -half_head_size)),
            sk_head_world.add(vec2.init(half_head_size, half_head_size)),
            sk_head_world.add(vec2.init(-half_head_size, half_head_size)),
        };

        //_ = head_points;

        self.renderer2D.addQuadP(head_points, Layers.Player + 4, self.mat_face);

        // self.renderer2D.addLine(head_points[0], head_points[1], Layers.Debug, Color.white);
        // self.renderer2D.addLine(head_points[1], head_points[2], Layers.Debug, Color.white);
        // self.renderer2D.addLine(head_points[2], head_points[3], Layers.Debug, Color.white);
        // self.renderer2D.addLine(head_points[3], head_points[0], Layers.Debug, Color.white);

        // ------------

        // for (player.legs) |leg| {
        //     self.renderLeg(leg.pivot_pos_world, leg.paw_pos_world, Layers.Player);
        // }

        var leg_hide_index: ?usize = null;

        if (player.show_hand) {
            //
            if (player.orientation_flipped) {
                //
                leg_hide_index = 3;
                self.renderLeg(player.legs[3].pivot_pos_world, player.hand_end, Layers.Player + 3);
            } else {
                //
                leg_hide_index = 3;
                self.renderLeg(player.legs[3].pivot_pos_world, player.hand_end, Layers.Player + 3);
            }
        }

        if (leg_hide_index != 0) self.renderLeg(player.legs[0].pivot_pos_world, player.legs[0].paw_pos_world, Layers.Player - 3);
        if (leg_hide_index != 1) self.renderLeg(player.legs[1].pivot_pos_world, player.legs[1].paw_pos_world, Layers.Player + 3);
        if (leg_hide_index != 2) self.renderLeg(player.legs[2].pivot_pos_world, player.legs[2].paw_pos_world, Layers.Player - 3);
        if (leg_hide_index != 3) self.renderLeg(player.legs[3].pivot_pos_world, player.legs[3].paw_pos_world, Layers.Player + 3);

        // ------------

        // if (player.show_hand) {
        //     const hand_color1 = Color.init(63, 63, 63, 255);
        //     const hand_color2 = Color.init(51, 51, 51, 255);

        //     const hand_dir = vec2.sub(player.hand_end, player.hand_start).normalize();
        //     const hand_left = hand_dir.turn90ccw();

        //     const p1_left = player.hand_start.add(hand_left.scale(0.05));
        //     const p1_right = player.hand_start.add(hand_left.scale(0.05).neg());

        //     const p2_left = player.hand_end.add(hand_left.scale(0.05));
        //     const p2_right = player.hand_end.add(hand_left.scale(0.05).neg());

        //     self.renderer2D.addTrianglePC([3]vec2{ p1_left, p2_right, p2_left }, Layers.Player, hand_color1, self.mat_default);
        //     self.renderer2D.addTrianglePC([3]vec2{ p1_right, p2_right, p1_left }, Layers.Player, hand_color1, self.mat_default);
        //     self.renderer2D.addSolidCircle(player.hand_end, 0.075, Layers.Player, hand_color2, self.mat_default);
        // }

        if (player.show_hint) {
            self.renderer2D.addText(player.hint_position, Layers.Overlay, Color.white, "{s}", .{player.hint_text.?});
        }

        // 1m line for reference
        {
            const p1 = sk_t.transform.pos.add(vec2.init(0, 2));
            const p2 = p1.add(vec2.init(1, 0));
            self.renderer2D.addLine(p1, p2, Layers.Player, Color.white);
        }
    }

    fn renderNeck(self: *Self, pivot: vec2, head: vec2, layer: i32) void {
        const color = Color.init(140, 140, 140, 255);

        if (self.settings.show_player_skeleton) {
            self.renderer2D.addLine(pivot, head, Layers.Debug, Color.white);
        }

        const dir = head.sub(pivot).normalize();
        const left = dir.turn90ccw();

        const width_base = 0.25;
        const width_head = 0.2;

        const p1_left = pivot.add(left.scale(width_base * 0.5));
        const p1_right = pivot.add(left.scale(width_base * 0.5).neg());

        const p2_left = head.add(left.scale(width_head * 0.5));
        const p2_right = head.add(left.scale(width_head * 0.5).neg());

        self.renderer2D.addTrianglePC([3]vec2{ p1_left, p2_right, p2_left }, layer, color, self.mat_default);
        self.renderer2D.addTrianglePC([3]vec2{ p1_right, p2_right, p1_left }, layer, color, self.mat_default);
    }

    fn renderLeg(self: *Self, pivot: vec2, paw: vec2, layer: i32) void {
        const color = Color.init(160, 160, 160, 255);
        const color2 = Color.init(100, 100, 100, 255);

        if (self.settings.show_player_skeleton) {
            self.renderer2D.addLine(pivot, paw, Layers.Debug, Color.white);
        }

        const dir = paw.sub(pivot).normalize();
        const left = dir.turn90ccw();

        const p1_left = pivot.add(left.scale(0.05));
        const p1_right = pivot.add(left.scale(0.05).neg());

        const p2_left = paw.add(left.scale(0.05));
        const p2_right = paw.add(left.scale(0.05).neg());

        self.renderer2D.addTrianglePC([3]vec2{ p1_left, p2_right, p2_left }, layer, color, self.mat_default);
        self.renderer2D.addTrianglePC([3]vec2{ p1_right, p2_right, p1_left }, layer, color, self.mat_default);
        self.renderer2D.addSolidCircle(paw, 0.04, layer + 1, color2, self.mat_default);
    }

    fn renderScore(self: *Self, player: *const Player, camera: *const Camera) void {
        //
        _ = self;
        _ = player;
        _ = camera;

        //const p = player.getTransform().pos.add(vec2.init(0, 5));

        //self.renderer2D.addText(p, Color.black, "eaten={d:.1} burned={d:.1}", .{ player.total_kcal_eaten, player.total_kcal_burned });
    }

    fn renderStartFinish(self: *Self, world: *const World) void {
        self.renderer2D.addCircle(world.settings.start_position, 1.0, Layers.Overlay, Color.white);
        self.renderer2D.addCircle(world.settings.finish_position, 1.0, Layers.Overlay, Color.white);

        self.renderer2D.addText(world.settings.start_position, Layers.Overlay, Color.white, "start", .{});
        self.renderer2D.addText(world.settings.finish_position, Layers.Overlay, Color.white, "finish", .{});
    }
};
