const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Transform2 = engine.Transform2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const World = @import("../world.zig").World;
const VehicleAndBlockRef = @import("../world.zig").VehicleAndBlockRef;
const VehicleAndDeviceRef = @import("../world.zig").VehicleAndDeviceRef;

const Vehicle = @import("../vehicle.zig").Vehicle;
const Block = @import("../vehicle.zig").Block;
const BlockDef = @import("../vehicle.zig").BlockDef;
const BlockRef = @import("../vehicle.zig").BlockRef;
const BlockConnectionEdge = @import("../vehicle.zig").BlockConnectionEdge;
const DeviceDef = @import("../vehicle.zig").DeviceDef;
const DeviceRef = @import("../vehicle.zig").DeviceRef;

const refs = @import("../refs.zig");
const VehicleRef = refs.VehicleRef;

const tools = @import("tools.zig");
const ToolVTable = tools.ToolVTable;
const ToolDeps = tools.ToolDeps;
const ToolUpdateContext = tools.ToolUpdateContext;
const ToolRenderContext = tools.ToolRenderContext;
const ToolDrawUiContext = tools.ToolDrawUiContext;

const vehicle_export = @import("../vehicle_export.zig");
const VehicleExporter = vehicle_export.VehicleExporter;
const VehicleImporter = vehicle_export.VehicleImporter;

const VehicleExportDialog = @import("../ui/editor/vehicle_export_dialog.zig").VehicleExportDialog;
const VehicleImportDialog = @import("../ui/editor/vehicle_import_dialog.zig").VehicleImportDialog;

const Mode = union(enum) {
    Idle,
    CreateBlock: BlockDef,
    CreateDevice: DeviceDef,
    EditBlock: VehicleAndBlockRef,
    EditDevice: VehicleAndDeviceRef,
    EditVehicle: struct {
        vehicle_ref: VehicleRef,
        moving: bool,
    },
    PlaceImportedVehicle: VehicleRef,
};

pub const VehicleEditTool = struct {
    const Self = VehicleEditTool;
    const Layer = engine.Renderer2D.Layers.Tools;

    self_allocator: std.mem.Allocator, // TODO not sure, same as long-term-alloc?
    long_term_allocator: std.mem.Allocator,
    per_frame_allocator: std.mem.Allocator,

    save_manager: *engine.SaveManager,
    renderer2D: *engine.Renderer2D,
    camera: *engine.Camera,

    world: *World,

    // state
    mode: Mode = .Idle,

    // ui
    vehicle_export_dialog: VehicleExportDialog = undefined,
    vehicle_import_dialog: VehicleImportDialog = undefined,

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
            .self_allocator = allocator,
            .long_term_allocator = deps.long_term_allocator,
            .per_frame_allocator = deps.per_frame_allocator,
            .save_manager = deps.save_manager,
            .renderer2D = deps.renderer2D,
            .camera = deps.camera,
            .world = deps.world,
        };

        self.vehicle_export_dialog.init(deps.save_manager, deps.long_term_allocator, deps.per_frame_allocator);
        self.vehicle_import_dialog.init(deps.world, deps.save_manager, deps.long_term_allocator, deps.per_frame_allocator);

        self.vehicle_import_dialog.after_import = .{
            .function = afterVehicleImport,
            .context = self,
        };

        return self;
    }

    fn afterVehicleImport(vehicle_ref: VehicleRef, context: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context));

        std.log.info("after vehilce imported {any}", .{vehicle_ref});

        self.mode = .{
            .PlaceImportedVehicle = vehicle_ref,
        };
    }

    fn destroy(self_ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.self_allocator.destroy(self);
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

        switch (self.mode) {
            .Idle => {
                if (self.world.getClosestVehicleAndBlockOrDevice(mouse_position, max_select_distance)) |result| {
                    switch (result) {
                        .VehicleAndBlock => |vehicle_and_block| {
                            self.renderer2D.addLine(mouse_position, vehicle_and_block.block_world, Layer, Color.red);

                            // select block?
                            if (input.consumeMouseButtonDownEvent(.left)) {
                                self.mode = .{ .EditBlock = vehicle_and_block.ref };
                            }
                        },
                        .VehicleAndDevice => |vehicle_and_device| {
                            self.renderer2D.addLine(mouse_position, vehicle_and_device.device_world, Layer, Color.red);

                            // select device?
                            if (input.consumeMouseButtonDownEvent(.left)) {
                                self.mode = .{ .EditDevice = vehicle_and_device.ref };
                            }
                        },
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
                        self.renderer2D.addLine(result.attach_world, result.attach_world.add(n), Layer, Color.green);
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
                        const new_block_ref = vehicle.createBlock(block_def, build_pos_local);
                        _ = new_block_ref;
                    }
                } else {
                    const build_pos_world = mouse_position;
                    const can_build = self.checkCanBuildBlock(block_def, build_pos_world, b2.b2Rot_identity);
                    const preview_color = if (can_build) Color.white else Color.red;

                    self.renderBlockPreview(block_def, build_pos_world, preview_color);

                    if (can_build and input.consumeMouseButtonDownEvent(.left)) {
                        const vehicle_ref = self.world.createVehicle(Transform2.from_pos(build_pos_world));
                        const vehicle = self.world.getVehicle(vehicle_ref).?;

                        const new_block_ref = vehicle.createBlock(block_def, vec2.init(0, 0));
                        _ = new_block_ref;
                    }
                }
            },
            .CreateDevice => |device_def| {
                if (self.world.getClosestVehicleAndBlock(mouse_position, max_build_distance)) |result| {
                    const vehicle = self.world.getVehicle(result.ref.vehicle).?;
                    const device_local_position = vehicle.transformWorldToLocal(mouse_position);

                    self.renderDevicePreview(device_def, vehicle, device_local_position, Color.white);

                    if (input.consumeMouseButtonDownEvent(.left)) {
                        _ = vehicle.createDevice(device_def, device_local_position);
                    }
                }
            },
            .EditBlock => |vehicle_and_block_ref| {
                if (self.world.getVehicleAndBlock(vehicle_and_block_ref)) |result| {
                    const vehicle = result.vehicle;

                    if (input.consumeKeyDownEvent(.delete)) {
                        vehicle.destroyBlock(vehicle_and_block_ref.block);
                        self.mode = .Idle;
                    }
                }

                // change selection?
                if (self.world.getClosestVehicleAndBlock(mouse_position, max_select_distance)) |result| {
                    self.renderer2D.addLine(mouse_position, result.block_world, Layer, Color.red);

                    if (input.consumeMouseButtonDownEvent(.left)) {
                        if (std.meta.eql(result.ref.block, vehicle_and_block_ref.block)) {
                            self.mode = .{ .EditVehicle = .{
                                .vehicle_ref = result.ref.vehicle,
                                .moving = false,
                            } };
                        } else {
                            self.mode = .{ .EditBlock = result.ref };
                        }
                    }
                }
            },
            .EditDevice => |vehicle_and_device_ref| {
                _ = vehicle_and_device_ref;
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
            .PlaceImportedVehicle => |vehicle_ref| {
                if (self.world.getVehicle(vehicle_ref)) |vehicle| {
                    var transform = b2.b2Body_GetTransform(vehicle.body_id);
                    transform.p = mouse_position.to_b2();

                    if (input.consumeMouseScroll()) |scroll| {
                        var angle = b2.b2Rot_GetAngle(transform.q);
                        angle += @as(f32, @floatFromInt(scroll)) * std.math.degreesToRadians(10.0);
                        transform.q = b2.b2MakeRot(angle);
                    }

                    b2.b2Body_SetType(vehicle.body_id, b2.b2_kinematicBody);
                    b2.b2Body_SetTransform(vehicle.body_id, transform.p, transform.q);

                    if (input.consumeMouseButtonDownEvent(.left)) {
                        b2.b2Body_SetType(vehicle.body_id, b2.b2_dynamicBody);
                        self.mode = .Idle;
                    } else if (input.consumeMouseButtonDownEvent(.right)) {
                        b2.b2Body_SetType(vehicle.body_id, b2.b2_dynamicBody);
                        vehicle.destroy();
                        self.mode = .Idle;
                    }
                }
            },
        }

        // general abort via right click?
        if (self.mode != .Idle and input.consumeMouseButtonDownEvent(.right)) {
            self.mode = .Idle;
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

                    self.renderer2D.addPointWithPixelSize(p, 10.0, Layer, Color.red);
                }
            },

            .EditVehicle => |edit_vehicle_data| {
                const vehicle_ref = edit_vehicle_data.vehicle_ref;

                if (self.world.getVehicle(vehicle_ref)) |vehicle| {
                    const p = vec2.from_b2(b2.b2Body_GetWorldCenterOfMass(vehicle.body_id));

                    self.renderer2D.addPointWithPixelSize(p, 20.0, Layer, Color.green);
                }
            },

            else => {},
        }

        // -----
        for (self.world.vehicles.items) |*vehicle| {
            if (!vehicle.alive) continue;

            for (vehicle.block_connection_graph.edges.items) |edge| {
                // const block1: BlockRef = edge.block1;
                // const block2: BlockRef = edge.block2;

                const p_local = edge.center_local;
                const n_local = edge.normal_local;

                const p_world = vehicle.transformLocalToWorld(p_local);
                const n_world = vehicle.rotateLocalToWorld(n_local);

                const p1 = p_world.add(n_world.scale(0.2));
                const p2 = p_world.sub(n_world.scale(0.2));

                self.renderer2D.addLine(p1, p2, Layer, Color.green);
            }
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

        self.renderer2D.addLine(p1_world, p2_world, Layer, color);
        self.renderer2D.addLine(p2_world, p3_world, Layer, color);
        self.renderer2D.addLine(p3_world, p4_world, Layer, color);
        self.renderer2D.addLine(p4_world, p1_world, Layer, color);
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

        self.renderer2D.addLine(p1_world, p2_world, Layer, color);
        self.renderer2D.addLine(p2_world, p3_world, Layer, color);
        self.renderer2D.addLine(p3_world, p4_world, Layer, color);
        self.renderer2D.addLine(p4_world, p1_world, Layer, color);
    }

    fn renderDevicePreview(self: *Self, def: DeviceDef, vehicle: *Vehicle, local_position: vec2, color: Color) void {
        switch (def.data) {
            .Wheel => |wheel_def| {
                //
                const center_world_position = vehicle.transformLocalToWorld(local_position);

                self.renderer2D.addPointWithPixelSize(center_world_position, 3.0, Layer, color);
                self.renderer2D.addCircle(center_world_position, wheel_def.radius, Layer, color);

                // TODO suspension
            },
            .Thruster => |thruster_def| {
                //
                _ = thruster_def;
            },
        }
    }

    fn drawUi(self_ptr: *anyopaque, context: ToolDrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        zgui.setNextWindowPos(.{ .x = 10.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 300, .h = 600 });

        if (zgui.begin("Vehicle list", .{})) {
            self.drawListWindowContent();
        }
        zgui.end();

        zgui.setNextWindowPos(.{ .x = 320.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 300, .h = 300 });

        if (zgui.begin("Vehicle edit", .{})) {
            self.drawEditWindowContent(context);
        }
        zgui.end();

        // dialogs
        self.vehicle_export_dialog.drawUi();
        self.vehicle_import_dialog.drawUi();
    }

    fn drawEditWindowContent(self: *Self, context: ToolDrawUiContext) void {
        //
        switch (self.mode) {
            .Idle => {
                zgui.text("create:", .{});

                var buffer: [128]u8 = undefined;
                for (self.world.defs.block_defs) |block_def| {
                    const s = std.fmt.bufPrintZ(&buffer, "block: {s}", .{block_def.id}) catch unreachable;
                    if (zgui.button(s, .{})) {
                        self.mode = .{ .CreateBlock = block_def };
                    }
                }
                for (self.world.defs.device_defs) |device_def| {
                    const s = std.fmt.bufPrintZ(&buffer, "device: {s}", .{device_def.id}) catch unreachable;
                    if (zgui.button(s, .{})) {
                        self.mode = .{ .CreateDevice = device_def };
                    }
                }
            },
            .CreateBlock => |block_def| {
                zgui.text("create block {s}", .{block_def.id});
            },
            .CreateDevice => |device_def| {
                zgui.text("create device {s}", .{device_def.id});
            },
            .EditBlock => |vehicle_and_block_ref| {
                zgui.text("edit block {s}", .{vehicle_and_block_ref});
            },
            .EditDevice => |vehicle_and_device_ref| {
                zgui.text("edit device {s}", .{vehicle_and_device_ref});

                if (self.world.getVehicle(vehicle_and_device_ref.vehicle)) |vehicle| {
                    if (vehicle.getDevice(vehicle_and_device_ref.device)) |device| {
                        std.debug.assert(device.alive);

                        switch (device.type) {
                            .Wheel => {
                                //
                                const wheel = &vehicle.wheels.items[device.data_index];

                                zgui.text("wheel control left key: {any}", .{wheel.control_left_key});
                                zgui.text("wheel control right key: {any}", .{wheel.control_right_key});

                                _ = zgui.button("hover to assign left", .{});

                                if (zgui.isItemHovered(.{})) {
                                    if (context.input.consumeSingleKeyDownEvent()) |key| {
                                        wheel.control_left_key = key;
                                    }
                                }

                                zgui.sameLine(.{});
                                _ = zgui.button("hover to assign right", .{});

                                if (zgui.isItemHovered(.{})) {
                                    if (context.input.consumeSingleKeyDownEvent()) |key| {
                                        wheel.control_right_key = key;
                                    }
                                }
                            },
                            .Thruster => {
                                //
                                const thruster = &vehicle.thrusters.items[device.data_index];

                                zgui.text("thruster control key: {any}", .{thruster.control_key});

                                _ = zgui.button("hover to assign", .{});

                                if (zgui.isItemHovered(.{})) {
                                    if (context.input.consumeSingleKeyDownEvent()) |key| {
                                        thruster.control_key = key;
                                    }
                                }
                            },
                        }
                    }
                }
            },
            .EditVehicle => |edit_vehicle_data| {
                const vehicle_ref = edit_vehicle_data.vehicle_ref;

                zgui.text("edit vehicle {s}", .{vehicle_ref});

                if (self.world.getVehicle(vehicle_ref)) |vehicle| {
                    const mass_data = b2.b2Body_GetMassData(vehicle.body_id);

                    zgui.text("mass: {d:.2} kg", .{mass_data.mass});
                    zgui.text("MoI: {d:.2} kg*m^2", .{mass_data.rotationalInertia});
                    zgui.text("CoM: {d:.2} {d:.2}", .{ mass_data.center.x, mass_data.center.y });
                }
            },
            .PlaceImportedVehicle => |vehicle_ref| {
                zgui.text("place imported {s}", .{vehicle_ref});
            },
        }
    }

    fn drawListWindowContent(self: *Self) void {
        var buffer: [128]u8 = undefined;

        if (zgui.button("import", .{})) {
            self.vehicle_import_dialog.open() catch |e| {
                std.log.err("open dialog: {any}", .{e});
            };
        }

        zgui.sameLine(.{});

        if (zgui.button("destroy all", .{})) {
            for (self.world.vehicles.items) |*vehicle| {
                if (vehicle.alive) {
                    vehicle.destroy();
                }
            }
        }

        zgui.separator();

        for (self.world.vehicles.items, 0..) |*vehicle, vehicle_index| {
            zgui.pushPtrId(vehicle);

            const s = std.fmt.bufPrintZ(&buffer, "Vehicle {d}", .{vehicle_index}) catch unreachable;

            if (zgui.collapsingHeader(s, .{})) {
                if (vehicle.alive and zgui.isItemHovered(.{})) {
                    self.highlightVehicle(vehicle);
                }

                zgui.indent(.{ .indent_w = 20 });
                zgui.text("vehicle alive={} blocks={d}", .{ vehicle.alive, vehicle.blocks.items.len });

                if (vehicle.alive) {
                    var do_focus = false;
                    var do_export = false;
                    var do_destroy = false;

                    if (zgui.button("focus", .{})) {
                        do_focus = true;
                    }
                    zgui.sameLine(.{});
                    if (zgui.button("export", .{})) {
                        do_export = true;
                    }
                    zgui.sameLine(.{});
                    if (zgui.button("destroy", .{})) {
                        do_destroy = true;
                    }

                    // arraylist only valid if alive
                    if (zgui.collapsingHeader("blocks", .{})) {
                        for (vehicle.blocks.items) |block| {
                            zgui.text("block alive={} def={s} pos={d:.1} {d:.1}", .{ block.alive, block.def.id, block.local_position.x, block.local_position.y });
                        }
                    }
                    if (zgui.collapsingHeader("devices", .{})) {
                        for (vehicle.devices.items) |device| {
                            zgui.text("device alive={} def={s} pos={d:.1} {d:.1}", .{ device.alive, device.def.id, device.local_position.x, device.local_position.y });
                        }
                    }

                    if (do_focus) {
                        self.focusVehicle(vehicle);
                    } else if (do_export) {
                        self.vehicle_export_dialog.open(vehicle) catch |e| {
                            std.log.err("open dialog: {any}", .{e});
                        };
                    } else if (do_destroy) {
                        vehicle.destroy();
                    }
                }

                zgui.indent(.{ .indent_w = -20 });
            } else {
                if (vehicle.alive and zgui.isItemHovered(.{})) {
                    self.highlightVehicle(vehicle);
                }
            }

            zgui.popId();
        }
    }

    fn highlightVehicle(self: *Self, vehicle: *const Vehicle) void {
        std.debug.assert(vehicle.alive);

        const mouse_pos_screen = zgui.getMousePos();
        const mouse_pos_world = self.camera.screenToWorld(mouse_pos_screen);

        const vehicle_com_world = vehicle.getCenterOfMassWorld();

        self.renderer2D.addCircle(vehicle_com_world, 1.0, Layer, Color.red);
        self.renderer2D.addLine(mouse_pos_world, vehicle_com_world, Layer, Color.red);
    }

    fn focusVehicle(self: *Self, vehicle: *const Vehicle) void {
        std.debug.assert(vehicle.alive);

        const vehicle_com_world = vehicle.getCenterOfMassWorld();

        self.camera.setFocusPosition(vec2.zero);
        self.camera.setOffset(vehicle_com_world);
    }
};
