const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const World = @import("../world.zig").World;
const VehicleRef = @import("../world.zig").VehicleRef;
const VehicleAndBlockRef = @import("../world.zig").VehicleAndBlockRef;

const Vehicle = @import("../vehicle.zig").Vehicle;
const Block = @import("../vehicle.zig").Block;
const BlockDef = @import("../vehicle.zig").BlockDef;
const BlockRef = @import("../vehicle.zig").BlockRef;

const tools = @import("tools.zig");
const ToolVTable = tools.ToolVTable;
const ToolDeps = tools.ToolDeps;
const ToolUpdateContext = tools.ToolUpdateContext;
const ToolRenderContext = tools.ToolRenderContext;
const ToolDrawUiContext = tools.ToolDrawUiContext;

const Mode = union(enum) {
    Idle,
    CreateBlock: BlockDef,
    EditBlock: VehicleAndBlockRef,
    EditVehicle: struct {
        vehicle_ref: VehicleRef,
        moving: bool,
    },
    // ?
};

pub const VehicleEditTool = struct {
    const Self = VehicleEditTool;

    allocator: std.mem.Allocator,
    world: *World,
    renderer2D: *engine.Renderer2D,

    block_defs: []BlockDef,

    mode: Mode = .Idle,

    pub fn getVTable() ToolVTable {
        return ToolVTable{
            .name = "Vehicle edit",
            .create = Self.create,
            .destroy = Self.destroy,
            .update = Self.update,
            .render = Self.render,
            .drawUi = Self.drawUi,
        };
    }

    fn create(allocator: std.mem.Allocator, deps: ToolDeps) !*anyopaque {
        const self = try allocator.create(Self);

        self.* = Self{
            .allocator = allocator,
            .world = deps.world,
            .renderer2D = deps.renderer2D,
            .block_defs = try BlockDef.getAll(allocator),
        };

        return self;
    }

    fn destroy(self_ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.allocator.free(self.block_defs);

        self.allocator.destroy(self);
    }

    const QueryData = struct {
        hit: bool,
        polygon: b2.b2Polygon,
    };

    fn my_query_func(shape_id: b2.b2ShapeId, context: ?*anyopaque) callconv(.c) bool {
        const query_data: *QueryData = @ptrCast(@alignCast(context));

        switch (b2.b2Shape_GetType(shape_id)) {
            b2.b2_polygonShape => {
                const other_polygon = b2.b2Shape_GetPolygon(shape_id);
                const other_body = b2.b2Shape_GetBody(shape_id);
                const other_transform = b2.b2Body_GetTransform(other_body);

                // std.log.info("my polygon {any}", .{query_data.polygon});
                // std.log.info("othor polygon {any}", .{other_polygon});

                const manifold = b2.b2CollidePolygons(&query_data.polygon, b2.b2Transform_identity, &other_polygon, other_transform);

                for (0..@intCast(manifold.pointCount)) |i| {
                    const sep = manifold.points[i].separation;
                    //std.log.info("sep {d}", .{sep});

                    // allow some penetration
                    if (sep < -0.1) {
                        query_data.hit = true;
                        return false; // stop
                    }
                }
            },

            else => {},
        }

        return true; // continue;
    }

    fn update(self_ptr: *anyopaque, context: ToolUpdateContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        const input = context.input;
        const mouse_position = context.mouse_position;

        const max_select_distance: f32 = 10.0;
        const max_build_distance: f32 = 5.0;

        if (self.mode != .Idle and input.consumeMouseButtonDownEvent(.right)) {
            self.mode = .Idle;
        }

        switch (self.mode) {
            .Idle => {
                //
                if (self.world.getClosestVehicle(mouse_position, max_select_distance)) |result| {

                    //
                    self.renderer2D.addLine(mouse_position, result.block_world, Color.red);

                    // select block?
                    if (input.consumeMouseButtonDownEvent(.left)) {
                        self.mode = .{ .EditBlock = result.vehicle_and_block_ref };
                    }
                }
            },
            .CreateBlock => |block_def| {
                //
                const new_block_half_size = block_def.size.scale(0.5);
                const min_overlap: f32 = 0.5;

                const max_overhang_local = new_block_half_size.sub(vec2.init(min_overlap, min_overlap));
                std.debug.assert(max_overhang_local.x >= 0.0 and max_overhang_local.y >= 0.0);

                if (self.world.getClosestBlockAttachPoint(mouse_position, max_build_distance, max_overhang_local)) |result| {
                    // show normal
                    {
                        const n = result.normal_world;
                        self.renderer2D.addLine(result.attach_world, result.attach_world.add(n), Color.green);
                    }

                    const vehicle = self.world.getVehicle(result.vehicle_ref).?;
                    const vehicle_rot = b2.b2Body_GetRotation(vehicle.body_id);

                    const build_offset_local = result.normal_local.mulPairwise(block_def.size.scale(0.5));
                    const build_pos_local = result.attach_local.add(build_offset_local);
                    const build_pos_world = vehicle.transformLocalToWorld(build_pos_local);

                    const can_build = self.checkCanBuildBlock(block_def, build_pos_world, vehicle_rot);
                    const preview_color = if (can_build) Color.white else Color.red;

                    self.renderBlockPreviewOnVehicle(block_def, vehicle, build_pos_local, preview_color);

                    if (can_build and input.consumeMouseButtonDownEvent(.left)) {
                        vehicle.createBlock(block_def, build_pos_local);
                    }
                } else {
                    const build_pos_world = mouse_position;
                    const can_build = self.checkCanBuildBlock(block_def, build_pos_world, b2.b2Rot_identity);
                    const preview_color = if (can_build) Color.white else Color.red;

                    self.renderBlockPreview(block_def, build_pos_world, preview_color);

                    if (can_build and input.consumeMouseButtonDownEvent(.left)) {
                        const vehicle_ref = self.world.createVehicle(build_pos_world);
                        const vehicle = self.world.getVehicle(vehicle_ref).?;

                        vehicle.createBlock(block_def, vec2.init(0, 0));
                    }
                }
            },
            .EditBlock => |vehicle_and_block_ref| {
                //

                if (self.world.getVehicleAndBlock(vehicle_and_block_ref)) |result| {
                    const vehicle = result.vehicle;

                    if (input.consumeKeyDownEvent(.delete)) {
                        vehicle.destroyBlock(vehicle_and_block_ref.block);
                        self.mode = .Idle;
                    }
                }

                if (self.world.getClosestVehicle(mouse_position, max_select_distance)) |result| {
                    self.renderer2D.addLine(mouse_position, result.block_world, Color.red);

                    if (input.consumeMouseButtonDownEvent(.left)) {
                        if (std.meta.eql(result.vehicle_and_block_ref.block, vehicle_and_block_ref.block)) {
                            self.mode = .{ .EditVehicle = .{
                                .vehicle_ref = result.vehicle_and_block_ref.vehicle,
                                .moving = false,
                            } };
                        } else {
                            self.mode = .{ .EditBlock = result.vehicle_and_block_ref };
                        }
                    }
                }
            },
            .EditVehicle => |edit_vehicle_data| {
                const vehicle_ref = edit_vehicle_data.vehicle_ref;
                const moving = edit_vehicle_data.moving;

                if (self.world.getVehicle(vehicle_ref)) |vehicle| {

                    // stop moving?
                    if (moving and !input.getMouseButtonState(.left)) {
                        self.mode = .{ .EditVehicle = .{
                            .vehicle_ref = vehicle_ref,
                            .moving = false,
                        } };

                        b2.b2Body_SetType(vehicle.body_id, b2.b2_dynamicBody);
                    }
                    // start moving?
                    else if (input.consumeMouseButtonDownEvent(.left)) {
                        self.mode = .{ .EditVehicle = .{
                            .vehicle_ref = vehicle_ref,
                            .moving = true,
                        } };

                        b2.b2Body_SetType(vehicle.body_id, b2.b2_kinematicBody);
                    }
                    // move?
                    else if (moving and input.getMouseButtonState(.left)) {
                        var transform = b2.b2Body_GetTransform(vehicle.body_id);

                        transform.p = vec2.from_b2(transform.p).add(context.mouse_diff).to_b2();

                        if (input.consumeMouseScroll()) |scroll| {
                            var angle = b2.b2Rot_GetAngle(transform.q);
                            angle += @as(f32, @floatFromInt(scroll)) * std.math.degreesToRadians(10.0);
                            transform.q = b2.b2MakeRot(angle);
                        }

                        b2.b2Body_SetTransform(vehicle.body_id, transform.p, transform.q);
                        b2.b2Body_SetLinearVelocity(vehicle.body_id, b2.b2Vec2_zero);
                        b2.b2Body_SetAngularVelocity(vehicle.body_id, 0);
                        b2.b2Body_SetAwake(vehicle.body_id, true);
                    }

                    // destroy vehicle?
                    if (input.consumeKeyDownEvent(.delete)) {
                        vehicle.destroy();
                        self.mode = .Idle;
                    }
                }
            },
        }
    }

    fn render(self_ptr: *anyopaque, context: ToolRenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = context;

        switch (self.mode) {
            .EditBlock => |vehicle_and_block_ref| {
                if (self.world.getVehicleAndBlock(vehicle_and_block_ref)) |result| {
                    const vehicle = result.vehicle;
                    const block = result.block;

                    const p = vehicle.transformLocalToWorld(block.local_position);

                    self.renderer2D.addPointWithPixelSize(p, 10.0, Color.red);
                }
            },

            .EditVehicle => |edit_vehicle_data| {
                const vehicle_ref = edit_vehicle_data.vehicle_ref;

                if (self.world.getVehicle(vehicle_ref)) |vehicle| {
                    const p = vec2.from_b2(b2.b2Body_GetWorldCenterOfMass(vehicle.body_id));

                    self.renderer2D.addPointWithPixelSize(p, 20.0, Color.green);
                }
            },

            else => {},
        }
    }

    fn checkCanBuildBlock(self: *Self, block_def: BlockDef, position_world: vec2, rot: b2.b2Rot) bool {
        const d = 10; // XXX

        const aabb = b2.b2AABB{
            .lowerBound = b2.b2Vec2{
                .x = position_world.x - d,
                .y = position_world.y - d,
            },
            .upperBound = b2.b2Vec2{
                .x = position_world.x + d,
                .y = position_world.y + d,
            },
        };

        const half_size = block_def.size.scale(0.5);

        var query_context = QueryData{
            .hit = false,
            .polygon = b2.b2MakeOffsetBox(half_size.x, half_size.y, position_world.to_b2(), rot),
        };

        _ = b2.b2World_OverlapAABB(self.world.world_id, aabb, b2.b2DefaultQueryFilter(), my_query_func, &query_context);

        return !query_context.hit;
    }

    fn renderBlockPreviewOnVehicle(self: *Self, block_def: BlockDef, vehicle: *Vehicle, local_position: vec2, color: Color) void {
        const transform = b2.b2Body_GetTransform(vehicle.body_id);

        const w = block_def.size.x;
        const h = block_def.size.y;
        const hw = w * 0.5;
        const hh = h * 0.5;

        // using ccw because thats what box2d uses
        const p1_local = local_position.add(vec2.init(-hw, -hh));
        const p2_local = local_position.add(vec2.init(hw, -hh));
        const p3_local = local_position.add(vec2.init(hw, hh));
        const p4_local = local_position.add(vec2.init(-hw, hh));

        const p1_world = vec2.from_b2(b2.b2TransformPoint(transform, p1_local.to_b2()));
        const p2_world = vec2.from_b2(b2.b2TransformPoint(transform, p2_local.to_b2()));
        const p3_world = vec2.from_b2(b2.b2TransformPoint(transform, p3_local.to_b2()));
        const p4_world = vec2.from_b2(b2.b2TransformPoint(transform, p4_local.to_b2()));

        self.renderer2D.addLine(p1_world, p2_world, color);
        self.renderer2D.addLine(p2_world, p3_world, color);
        self.renderer2D.addLine(p3_world, p4_world, color);
        self.renderer2D.addLine(p4_world, p1_world, color);
    }

    fn renderBlockPreview(self: *Self, block_def: BlockDef, world_position: vec2, color: Color) void {
        const w = block_def.size.x;
        const h = block_def.size.y;
        const hw = w * 0.5;
        const hh = h * 0.5;

        // using ccw because thats what box2d uses
        const p1_local = vec2.init(-hw, -hh);
        const p2_local = vec2.init(hw, -hh);
        const p3_local = vec2.init(hw, hh);
        const p4_local = vec2.init(-hw, hh);

        const p1_world = world_position.add(p1_local);
        const p2_world = world_position.add(p2_local);
        const p3_world = world_position.add(p3_local);
        const p4_world = world_position.add(p4_local);

        self.renderer2D.addLine(p1_world, p2_world, color);
        self.renderer2D.addLine(p2_world, p3_world, color);
        self.renderer2D.addLine(p3_world, p4_world, color);
        self.renderer2D.addLine(p4_world, p1_world, color);
    }

    fn drawUi(self_ptr: *anyopaque, context: ToolDrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = context;

        switch (self.mode) {
            .Idle => {
                zgui.text("create:", .{});

                var buffer: [128]u8 = undefined;
                for (self.block_defs) |block_def| {
                    const s = std.fmt.bufPrintZ(&buffer, "block: {s}", .{block_def.id}) catch unreachable;
                    if (zgui.button(s, .{})) {
                        self.mode = .{ .CreateBlock = block_def };
                    }
                }
            },
            .CreateBlock => |block_def| {
                zgui.text("create block {s}", .{block_def.id});
            },
            .EditBlock => |vehicle_and_block_ref| {
                zgui.text("edit block {s}", .{vehicle_and_block_ref});
            },
            .EditVehicle => |edit_vehicle_data| {
                const vehicle_ref = edit_vehicle_data.vehicle_ref;

                zgui.text("edit vehicle {s}", .{vehicle_ref});

                if (self.world.getVehicle(vehicle_ref)) |vehicle| {
                    const mass_data = b2.b2Body_GetMassData(vehicle.body_id);

                    zgui.text("mass: {d:.2} kg", .{mass_data.mass});
                    zgui.text("MoI: {d:.2} kg*m^2", .{mass_data.rotationalInertia});
                    zgui.text("com: {d:.2} {d:.2}", .{ mass_data.center.x, mass_data.center.y });
                }
            },
        }
    }
};
