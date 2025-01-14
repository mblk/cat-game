const std = @import("std");

const zearcut = @import("zearcut");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const rot2 = engine.rot2;
const Transform = engine.Transform2;
const Color = engine.Color;

const Renderer2D = engine.Renderer2D;
const Camera = engine.Camera;

const world_ns = @import("../world.zig");
const World = world_ns.World;
const GroundSegment = world_ns.GroundSegment;

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

pub const WorldRenderer = struct {
    const Self = @This();

    renderer2D: *Renderer2D,
    tex_cardboard1: u32,
    tex_cat1: u32,
    tex_background1: u32,
    tex_wood1: u32,
    tex_brick1: u32,

    pub fn init(self: *Self, renderer2D: *Renderer2D) !void {
        //

        const tex_cardboard1 = try renderer2D.loadTexture("cardboard1.png");
        const tex_cat1 = try renderer2D.loadTexture("cat2.png");
        const tex_background1 = try renderer2D.loadTexture("background2.png");
        const tex_wood1 = try renderer2D.loadTexture("wood1.png");
        const tex_brick1 = try renderer2D.loadTexture("brick1.png");

        self.* = Self{
            .renderer2D = renderer2D,
            .tex_cardboard1 = tex_cardboard1,
            .tex_cat1 = tex_cat1,
            .tex_background1 = tex_background1,
            .tex_wood1 = tex_wood1,
            .tex_brick1 = tex_brick1,
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

    fn renderBackground(self: *Self, camera: *const Camera) void {
        const screen_size = camera.viewport_size;
        const width: f32 = @floatFromInt(screen_size[0]);
        const height: f32 = @floatFromInt(screen_size[1]);

        const p1 = camera.screenToWorld([_]f32{ 0, height });
        const p2 = camera.screenToWorld([_]f32{ width, height });
        const p3 = camera.screenToWorld([_]f32{ width, 0 });
        const p4 = camera.screenToWorld([_]f32{ 0, 0 });

        const points = [4]vec2{ p1, p2, p3, p4 };

        const g = 255;
        const c = Color{
            .r = g,
            .g = g,
            .b = g,
            .a = 255,
        };

        self.renderer2D.addTexturedQuad(points, c, self.tex_background1);
    }

    fn renderOuterBounds(self: *Self, world: *const World) void {
        const hs = world.settings.size.scale(0.5);

        if (false) {
            const points = [4]vec2{
                vec2.init(-hs.x, -hs.y),
                vec2.init(hs.x, -hs.y),
                vec2.init(hs.x, hs.y),
                vec2.init(-hs.x, hs.y),
            };

            self.renderer2D.addLine(points[0], points[1], Color.white);
            self.renderer2D.addLine(points[1], points[2], Color.white);
            self.renderer2D.addLine(points[2], points[3], Color.white);
            self.renderer2D.addLine(points[3], points[0], Color.white);
        }

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

        self.renderer2D.addTexturedQuadRepeating(left_quad, Color.white, self.tex_brick1, 0.05);
        self.renderer2D.addTexturedQuadRepeating(right_quad, Color.white, self.tex_brick1, 0.05);
        self.renderer2D.addTexturedQuadRepeating(top_quad, Color.white, self.tex_brick1, 0.05);
        self.renderer2D.addTexturedQuadRepeating(bottom_quad, Color.white, self.tex_brick1, 0.05);
    }

    fn renderGroundSegment(self: *Self, ground_segment: *const GroundSegment) void {
        const point_count: usize = ground_segment.points.items.len;

        if (false) {
            for (0..point_count) |i| {
                const p1_local = ground_segment.points.items[i];
                const p2_local = ground_segment.points.items[(i + 1) % point_count];

                const p1_world = ground_segment.position.add(p1_local);
                const p2_world = ground_segment.position.add(p2_local);

                self.renderer2D.addLine(p1_world, p2_world, Color.white);
            }
        }

        // ----------------------------------------------

        const points: []vec2 = ground_segment.points.items;

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

            // Output triangles are clockwise.
            const p1_local = points[result.indices[i]];
            const p2_local = points[result.indices[i + 1]];
            const p3_local = points[result.indices[i + 2]];

            const p1_world = ground_segment.position.add(p1_local);
            const p2_world = ground_segment.position.add(p2_local);
            const p3_world = ground_segment.position.add(p3_local);

            const s = 0.05;

            const p1_uv = vec2.init(
                p1_world.x * s,
                p1_world.y * s,
            );
            const p2_uv = vec2.init(
                p2_world.x * s,
                p2_world.y * s,
            );
            const p3_uv = vec2.init(
                p3_world.x * s,
                p3_world.y * s,
            );

            //self.renderer2D.addTriangle(p1_world, p2_world, p3_world, Color.white);
            //self.renderer2D.addTexturedTriangle(p1_world, p2_world, p3_world, Color.white, p1_uv, p2_uv, p3_uv, self.tex_wood1);
            self.renderer2D.addWoodTriangle(p1_world, p2_world, p3_world, p1_uv, p2_uv, p3_uv);
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

            self.renderer2D.addTexturedQuad(points_world, Color.white, self.tex_cardboard1);
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

                    self.renderer2D.addSolidCircle(center_world, radius, Color.black);
                    self.renderer2D.addSolidCircle(center_world, radius * 0.9, Color.gray4);
                    for (knob_positions_world) |p| {
                        self.renderer2D.addSolidCircle(p, radius * 0.1, Color.white);
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

                    self.renderer2D.addSolidQuad(points_world, Color.gray4);

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
                self.renderer2D.addSolidCircle(t.pos, radius, color);
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
                self.renderer2D.addTriangle(points_world[0], points_world[1], points_world[2], color);
                self.renderer2D.addTriangle(points_world[0], points_world[2], points_world[3], color);
            },
        }
    }

    fn renderPlayer(self: *Self, player: *const Player) void {
        const t = player.getTransform();

        // def
        const spine_length: f32 = 0.5;
        const neck_length: f32 = 0.25;
        const tail_length: f32 = 0.5;
        const aft_leg_length: f32 = 0.5;
        const fwd_leg_length: f32 = 0.5;

        // poses:
        // - sitting (possibly on slope)
        // - standing (")
        // - climbing on side (")
        // - climbing on ceiling (")

        const sk_center = vec2.init(0, 0);

        const sk_head_angle: f32 = std.math.degreesToRadians(30); // 30deg up
        const sk_tail_angle: f32 = std.math.degreesToRadians(45); // 45deg down

        const sk_aft = sk_center.add(vec2.init(-spine_length * 0.5, 0));
        const sk_fwd = sk_center.add(vec2.init(spine_length * 0.5, 0));
        const sk_head = sk_fwd.add(vec2.init(neck_length, 0).rotate(sk_head_angle)); // rotate
        const sk_tail = sk_aft.add(vec2.init(-tail_length, 0).rotate(sk_tail_angle)); // rotate

        const sk_aft_leg1 = sk_aft.add(vec2.init(0, -aft_leg_length));
        const sk_aft_leg2 = sk_aft.add(vec2.init(0, -aft_leg_length));
        const sk_fwd_leg1 = sk_fwd.add(vec2.init(0, -fwd_leg_length));
        const sk_fwd_leg2 = sk_fwd.add(vec2.init(0, -fwd_leg_length));

        // ------------

        const sk_aft_world = t.transformLocalToWorld(sk_aft);
        const sk_fwd_world = t.transformLocalToWorld(sk_fwd);
        const sk_head_world = t.transformLocalToWorld(sk_head);
        const sk_tail_world = t.transformLocalToWorld(sk_tail);

        const sk_aft_leg1_world = t.transformLocalToWorld(sk_aft_leg1);
        const sk_aft_leg2_world = t.transformLocalToWorld(sk_aft_leg2);
        const sk_fwd_leg1_world = t.transformLocalToWorld(sk_fwd_leg1);
        const sk_fwd_leg2_world = t.transformLocalToWorld(sk_fwd_leg2);

        self.renderer2D.addLine(sk_aft_world, sk_fwd_world, Color.white);
        self.renderer2D.addLine(sk_aft_world, sk_tail_world, Color.white);
        self.renderer2D.addLine(sk_fwd_world, sk_head_world, Color.white);

        self.renderer2D.addLine(sk_aft_world, sk_aft_leg1_world, Color.white);
        self.renderer2D.addLine(sk_aft_world, sk_aft_leg2_world, Color.white);
        self.renderer2D.addLine(sk_fwd_world, sk_fwd_leg1_world, Color.white);
        self.renderer2D.addLine(sk_fwd_world, sk_fwd_leg2_world, Color.white);

        // ------------

        //const fur_color = Color.init(51, 51, 51, 255);

        // const front_circle_local = vec2.init(0.25 / 2.0, 0);
        // const aft_circle_local = vec2.init(-0.25 / 2.0, 0);
        // const head_circle_local = vec2.init(0.3 / 2.0, 0.3 / 2.0);

        // const front_circle_world = t.transformLocalToWorld(front_circle_local);
        // const aft_circle_world = t.transformLocalToWorld(aft_circle_local);
        // const head_circle_world = t.transformLocalToWorld(head_circle_local);

        // self.renderer2D.addSolidCircle(front_circle_world, 0.25 / 2.0, fur_color);
        // self.renderer2D.addSolidCircle(aft_circle_world, 0.25 / 2.0, fur_color);
        // self.renderer2D.addSolidCircle(head_circle_world, 0.20 / 2.0, fur_color);

        // const hs = vec2.init(1.0, 1.0);
        // const center_local = vec2.init(0, 0.4);
        // const points_local = [4]vec2{
        //     center_local.add(vec2.init(-hs.x, -hs.y)),
        //     center_local.add(vec2.init(hs.x, -hs.y)),
        //     center_local.add(vec2.init(hs.x, hs.y)),
        //     center_local.add(vec2.init(-hs.x, hs.y)),
        // };
        // const points_world = [4]vec2{
        //     t.transformLocalToWorld(points_local[0]),
        //     t.transformLocalToWorld(points_local[1]),
        //     t.transformLocalToWorld(points_local[2]),
        //     t.transformLocalToWorld(points_local[3]),
        // };

        // self.renderer2D.addTexturedQuad(points_world, Color.white, self.tex_cat1);

        if (player.show_hand) {
            const hand_color1 = Color.init(63, 63, 63, 255);
            const hand_color2 = Color.init(51, 51, 51, 255);

            const hand_dir = vec2.sub(player.hand_end, player.hand_start).normalize();
            const hand_left = hand_dir.turn90ccw();

            const p1_left = player.hand_start.add(hand_left.scale(0.05));
            const p1_right = player.hand_start.add(hand_left.scale(0.05).neg());

            const p2_left = player.hand_end.add(hand_left.scale(0.05));
            const p2_right = player.hand_end.add(hand_left.scale(0.05).neg());

            self.renderer2D.addTriangle(p1_left, p2_right, p2_left, hand_color1);
            self.renderer2D.addTriangle(p1_right, p2_right, p1_left, hand_color1);
            self.renderer2D.addSolidCircle(player.hand_end, 0.075, hand_color2);
        }

        if (player.show_hint) {
            self.renderer2D.addText(player.hint_position, Color.white, "{s}", .{player.hint_text.?});
        }

        {
            const p1 = t.pos.add(vec2.init(0, 2));
            const p2 = p1.add(vec2.init(1, 0));
            self.renderer2D.addLine(p1, p2, Color.white);
        }
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
        self.renderer2D.addCircle(world.settings.start_position, 1.0, Color.white);
        self.renderer2D.addCircle(world.settings.finish_position, 1.0, Color.white);

        self.renderer2D.addText(world.settings.start_position, Color.white, "start", .{});
        self.renderer2D.addText(world.settings.finish_position, Color.white, "finish", .{});
    }
};
