const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const game = @import("../game/game.zig");

const VehicleDefs = game.VehicleDefs;

const World = game.World;
const Vehicle = game.Vehicle;
const Player = game.Player;

const world_export = @import("../game/world_export.zig");
const WorldExporter = world_export.WorldExporter;
const WorldImporter = world_export.WorldImporter;

const vehicle_export = @import("../game/vehicle_export.zig");
const VehicleExporter = vehicle_export.VehicleExporter;
const VehicleImporter = vehicle_export.VehicleImporter;

const tools = @import("../game/tools/tools.zig");
const ToolManager = tools.ToolManager;
const GroundEditTool = @import("../game/tools/ground_edit_tool.zig").GroundEditTool;
const VehicleEditTool = @import("../game/tools/vehicle_edit_tool.zig").VehicleEditTool;

pub fn getScene() engine.SceneDescriptor {
    return engine.SceneDescriptor{
        .name = "game",
        .load = GameScene.load,
        .unload = GameScene.unload,
        .update = GameScene.update,
        .render = GameScene.render,
        .draw_ui = GameScene.drawUi,
    };
}

const GameScene = struct {
    const Self = GameScene;

    const MasterMode = enum {
        Idle,
        ControlPlayer,
        CreateBox,
    };

    // defs
    vehicle_defs: VehicleDefs,

    // state
    world: World,
    player: Player,

    // visual
    camera: engine.Camera,
    renderer: *engine.Renderer2D,
    zbox_renderer: engine.ZBoxRenderer,

    // input
    mouse_position: vec2 = vec2.init(0, 0), // XXX
    prev_mouse_position: vec2 = vec2.init(0, 0),
    mouse_diff: vec2 = vec2.init(0, 0),

    master_mode: MasterMode = .Idle,

    moving_camera: bool = false,

    world_save_name_buffer: [10:0]u8 = [_:0]u8{0} ** 10,
    vehicle_save_name_buffer: [10:0]u8 = [_:0]u8{0} ** 10,

    // tools
    tool_manager: ToolManager,

    fn load(context: *const engine.LoadContext) !*anyopaque {
        const vehicle_defs = try VehicleDefs.load(context.allocator);

        var world = World.create(context.allocator);
        errdefer world.free();
        //try world.load();
        //world.createDynamicBox(vec2.init(10, 10));
        //world.createDynamicBox(vec2.init(15, 10));
        world.createDynamicBox(vec2.init(20, 10));

        const player = Player.create(world.world_id);

        const camera = engine.Camera.create();

        var renderer = try engine.Renderer2D.create(context.allocator, context.content_manager);
        errdefer renderer.free();

        const zbox_renderer = engine.ZBoxRenderer.create(renderer);

        const self = try context.allocator.create(Self);
        self.* = Self{
            .vehicle_defs = vehicle_defs,
            .world = world, // Note: This makes a copy
            .player = player,
            .camera = camera,
            .renderer = renderer,
            .zbox_renderer = zbox_renderer,
            .tool_manager = undefined, // XXX needs world address
        };

        @memcpy(self.world_save_name_buffer[0..7], "world_1");
        @memcpy(self.vehicle_save_name_buffer[0..9], "vehicle_1");

        var tool_manager = ToolManager.create(context.allocator, .{
            //.allocator = context.allocator,
            .vehicle_defs = &self.vehicle_defs,
            .world = &self.world,
            .renderer2D = self.renderer,
        });

        try tool_manager.register(GroundEditTool.getVTable());
        try tool_manager.register(VehicleEditTool.getVTable());
        self.tool_manager = tool_manager;

        return self;
    }

    fn unload(self_ptr: *anyopaque, context: *const engine.UnloadContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.tool_manager.destroy();
        self.renderer.free();
        self.world.free();
        self.vehicle_defs.free();

        context.allocator.destroy(self);
    }

    fn update(self_ptr: *anyopaque, context: *const engine.UpdateContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        // TODO only set when changed?
        self.camera.setViewportSize(context.viewport_size);

        // convert screen coords to world coords
        const mouse_position = self.camera.screenToWorld(context.input_state.mouse_position_screen);
        self.mouse_position = mouse_position;
        self.mouse_diff = mouse_position.sub(self.prev_mouse_position);
        self.prev_mouse_position = mouse_position;

        // update physics
        // TODO figure out optimal order of things
        self.player.update(context.dt, context.input_state, mouse_position, self.master_mode == .ControlPlayer);
        self.world.update(context.dt, context.per_frame_allocator);

        switch (self.master_mode) {
            .Idle => {
                // data.selection = .None;
                // data.moving_selected = false;
            },

            .ControlPlayer => {
                //
            },

            .CreateBox => {
                var spawn = false;

                if (context.input_state.getKeyState(.left_shift)) {
                    if (context.input_state.getMouseButtonState(.left)) {
                        spawn = true;
                    }
                } else {
                    if (context.input_state.consumeMouseButtonDownEvent(.left)) {
                        spawn = true;
                    }
                }

                if (spawn) {
                    self.world.createDynamicBox(mouse_position);
                }
            },
        }

        // tool
        self.tool_manager.update(.{
            .input = context.input_state,
            .mouse_position = mouse_position,
            .mouse_diff = self.mouse_diff,
        });

        // camera movement
        if (context.input_state.consumeMouseScroll()) |scroll| {
            self.camera.changeZoom(-scroll);
        }

        if (context.input_state.consumeKeyDownEvent(.backspace)) {
            self.camera.reset();
        }

        if (context.input_state.getKeyState(.left)) self.camera.changePosition(vec2.init(-100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.right)) self.camera.changePosition(vec2.init(100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.up)) self.camera.changePosition(vec2.init(0.0, 100.0 * context.dt));
        if (context.input_state.getKeyState(.down)) self.camera.changePosition(vec2.init(0.0, -100.0 * context.dt));

        // pan camera?
        if (!self.moving_camera and context.input_state.consumeMouseButtonDownEvent(.right)) {
            self.moving_camera = true;
        } else if (self.moving_camera and !context.input_state.getMouseButtonState(.right)) {
            self.moving_camera = false;
        } else if (self.moving_camera) {
            self.camera.changePosition(self.mouse_diff.neg());
        }

        // must update after camera has moved
        self.prev_mouse_position = self.camera.screenToWorld(context.input_state.mouse_position_screen);

        // scene management
        if (context.input_state.consumeKeyDownEvent(.escape)) {
            context.scene_commands.exit = true;
        }
    }

    fn render(self_ptr: *anyopaque, context: *const engine.RenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        // mouse
        //self.renderer.addPointWithPixelSize(self.mouse_position, 10.0, Color.green);

        // physics
        b2.b2World_Draw(self.world.world_id, &self.zbox_renderer.b2_debug_draw);

        // player
        self.player.render(context.dt, self.renderer);

        // tool
        self.tool_manager.render(.{});

        self.renderer.render(&self.camera);
    }

    fn drawUi(self_ptr: *anyopaque, context: *const engine.DrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        // xxx
        self.renderer.render_to_zgui(&self.camera);
        // xxx

        zgui.setNextWindowPos(.{ .x = 10.0, .y = 400.0, .cond = .appearing });
        //zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

        if (zgui.begin("Game", .{})) {
            zgui.text("mouse: {d:.1} {d:.1}", .{ self.mouse_position.x, self.mouse_position.y });

            if (zgui.button("clear", .{})) {
                self.master_mode = .Idle;

                self.world.clear();
            }

            _ = zgui.inputText("world save name", .{
                .buf = &self.world_save_name_buffer,
            });

            if (zgui.button("export world", .{})) {
                const s = getSliceFromSentinelArray(&self.world_save_name_buffer);
                exportWorld(&self.world, context.save_manager, context.per_frame_allocator, s) catch |e| {
                    std.log.err("export world: {any}", .{e});
                };
            }
            if (zgui.button("import world", .{})) {
                self.master_mode = .Idle;

                const s = getSliceFromSentinelArray(&self.world_save_name_buffer);
                importWorld(&self.world, context.save_manager, context.per_frame_allocator, s) catch |e| {
                    std.log.err("import world: {any}", .{e});
                };
            }

            _ = zgui.inputText("vehicle save name", .{
                .buf = &self.vehicle_save_name_buffer,
            });

            if (zgui.button("import vehicle", .{})) {
                self.master_mode = .Idle;

                const s = getSliceFromSentinelArray(&self.vehicle_save_name_buffer);
                importVehicle(&self.world, context.save_manager, context.per_frame_allocator, &self.vehicle_defs, s) catch |e| {
                    std.log.err("import vehicle: {any}", .{e});
                };
            }

            //
            // tools
            //

            zgui.separator();

            if (self.tool_manager.active_tool) |tool| {
                zgui.text("tool: {s}", .{tool.vtable.name});
            } else {
                zgui.text("tool: ---", .{});
            }

            if (zgui.button("tool: ---", .{})) {
                self.tool_manager.deselect();
            }

            var buffer: [128]u8 = undefined;
            for (self.tool_manager.all_tools.items) |tool_vtable| {
                const b = std.fmt.bufPrintZ(&buffer, "tool: {s}", .{tool_vtable.name}) catch unreachable;
                if (zgui.button(b, .{})) {
                    self.tool_manager.select(tool_vtable);
                }
            }

            self.tool_manager.drawUi(.{});

            //
            // master mode
            //
            zgui.separator();
            zgui.text("master mode: {s}", .{@tagName(self.master_mode)});

            inline for (@typeInfo(MasterMode).@"enum".fields) |field| {
                const enumValue = @field(MasterMode, field.name);

                if (zgui.radioButton(field.name, .{ .active = self.master_mode == enumValue })) {
                    self.master_mode = enumValue;
                }
            }

            //
            // physics
            //

            if (zgui.collapsingHeader("physics", .{})) {
                self.zbox_renderer.drawUi();
            }

            //
            // vehicles
            //

            if (zgui.collapsingHeader("vehicles", .{})) {
                for (self.world.vehicles.items) |*vehicle| {
                    zgui.pushPtrId(vehicle);
                    zgui.text("vehicle alive={} blocks={d}", .{ vehicle.alive, vehicle.blocks.items.len });

                    // arraylist only valid if alive
                    if (vehicle.alive) {
                        if (zgui.button("export", .{})) {
                            const s = getSliceFromSentinelArray(&self.vehicle_save_name_buffer);
                            exportVehicle(vehicle, context.save_manager, context.per_frame_allocator, s) catch |e| {
                                std.log.err("export vehicle: {any}", .{e});
                            };
                        }

                        for (vehicle.blocks.items) |block| {
                            zgui.text("  block alive={} def={s} pos={d} {d}", .{ block.alive, block.def.id, block.local_position.x, block.local_position.y });
                        }
                    }

                    zgui.popId();
                }
            }

            zgui.end();
        }
    }

    fn getSliceFromSentinelArray(a: [*:0]const u8) []const u8 {
        //const ptr_to_string: [*:0]const u8 = a;
        const len = std.mem.len(a);
        const s: []const u8 = a[0..len];
        std.debug.assert(std.mem.indexOfScalar(u8, s, 0) == null); // no 0 character in string

        return s;
    }

    fn exportWorld(world: *World, save_manager: *engine.SaveManager, temp_allocator: std.mem.Allocator, name: []const u8) !void {
        const data = try WorldExporter.exportWorld(world, temp_allocator);
        defer temp_allocator.free(data);

        //std.log.info("world data: {s}", .{data});

        try save_manager.save(.WorldExport, name, data, temp_allocator);
    }

    fn importWorld(world: *World, save_manager: *engine.SaveManager, temp_allocator: std.mem.Allocator, name: []const u8) !void {
        const data = try save_manager.load(.WorldExport, name, temp_allocator);
        defer temp_allocator.free(data);

        //std.log.info("world data: {s}", .{data});

        try WorldImporter.importWorld(world, data, temp_allocator);
    }

    fn exportVehicle(vehicle: *Vehicle, save_manager: *engine.SaveManager, temp_allocator: std.mem.Allocator, name: []const u8) !void {
        const data = try VehicleExporter.exportVehicle(vehicle, temp_allocator);
        defer temp_allocator.free(data);

        std.log.info("vehicle data: {s}", .{data});

        try save_manager.save(.VehicleExport, name, data, temp_allocator);
    }

    fn importVehicle(world: *World, save_manager: *engine.SaveManager, temp_allocator: std.mem.Allocator, vehicle_defs: *const VehicleDefs, name: []const u8) !void {
        const data = try save_manager.load(.VehicleExport, name, temp_allocator);
        defer temp_allocator.free(data);

        std.log.info("vehicle data: {s}", .{data});

        try VehicleImporter.importVehicle(world, data, temp_allocator, vehicle_defs);
    }
};
