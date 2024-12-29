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

const WorldExporter = game.WorldExporter;
const WorldImporter = game.WorldImporter;

const VehicleExporter = game.VehicleExporter;
const VehicleImporter = game.VehicleImporter;

const ToolManager = game.ToolManager;
const GroundEditTool = game.GroundEditTool;
const VehicleEditTool = game.VehicleEditTool;

const WorldRenderer = game.WorldRenderer;

const WorldImportDialog = game.WorldImportDialog;
const WorldExportDialog = game.WorldExportDialog;

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

//////////
// TODO //
//////////
//
// - generic datastructures:
//   - graph + findPartitions
//   - refs / versioned-index
//
// - check memory consumption (2MB per rendere2d, 5MB per game)
//
// - vehicle-center vs vehicle-CoM (maybe fix it in world.update ?)
//
// world:
// - start+finish positions
// - change world size (and maybe other settings like gravity?)
//
// - food/treat/snack positions
//
// - debris from destroyable things?
//

const GameScene = struct {
    const Self = GameScene;

    const MasterMode = enum {
        Edit,
        Play,
    };

    // defs
    vehicle_defs: VehicleDefs,

    // state
    world: World,

    // visual
    camera: engine.Camera,
    renderer: engine.Renderer2D,
    zbox_renderer: engine.ZBoxRenderer,
    world_renderer: WorldRenderer,

    // input
    mouse_position: vec2 = vec2.init(0, 0),
    prev_mouse_position: vec2 = vec2.init(0, 0),
    mouse_diff: vec2 = vec2.init(0, 0),

    master_mode: MasterMode = .Play,

    moving_camera: bool = false,

    // tools
    tool_manager: ToolManager,

    // editor ui
    import_world_dialog: WorldImportDialog = undefined,
    export_world_dialog: WorldExportDialog = undefined,

    vehicle_save_name_buffer: [10:0]u8 = [_:0]u8{0} ** 10,

    fn load(context: *const engine.LoadContext) !*anyopaque {
        // TODO correct error handling (eg. errdefer)

        const vehicle_defs = try VehicleDefs.load(context.allocator);

        var world = World.create(context.allocator);
        errdefer world.free();

        const camera = engine.Camera.create();

        const self = try context.allocator.create(Self);
        self.* = Self{
            .vehicle_defs = vehicle_defs,
            .world = world, // Note: This makes a copy
            .camera = camera,
            .renderer = undefined,
            .zbox_renderer = undefined,
            .world_renderer = undefined,
            .tool_manager = undefined, // XXX needs world address
        };

        try self.renderer.init(context.allocator, context.content_manager);
        self.zbox_renderer.init(&self.renderer);
        try self.world_renderer.init(&self.renderer);

        //@memcpy(self.world_save_name_buffer[0..7], "world_1");
        @memcpy(self.vehicle_save_name_buffer[0..9], "vehicle_1");

        var tool_manager = ToolManager.create(context.allocator, .{
            .long_term_allocator = context.allocator,
            .per_frame_allocator = context.per_frame_allocator,
            .save_manager = context.save_manager,
            .renderer2D = &self.renderer,
            .camera = &self.camera,
            .vehicle_defs = &self.vehicle_defs,
            .world = &self.world,
        });

        try tool_manager.register(GroundEditTool.getVTable());
        try tool_manager.register(VehicleEditTool.getVTable());
        self.tool_manager = tool_manager;

        self.import_world_dialog.init(&self.world, context.save_manager, context.allocator, context.per_frame_allocator);
        self.export_world_dialog.init(&self.world, context.save_manager, context.allocator, context.per_frame_allocator);

        // -----------
        if (true) {
            importWorld(&self.world, context.save_manager, context.allocator, "world_1") catch |e| {
                std.log.err("import world: {any}", .{e});
            };
            importVehicle(&self.world, context.save_manager, context.allocator, &self.vehicle_defs, "vehicle_2") catch |e| {
                std.log.err("import vehicle: {any}", .{e});
            };

            self.world.createPlayer(vec2.init(0, 0));
        }
        // -----------
        //self.enterPlayMode();
        self.enterEditMode();
        // -----------

        return self;
    }

    fn unload(self_ptr: *anyopaque, context: *const engine.UnloadContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.import_world_dialog.deinit();
        self.export_world_dialog.deinit();

        self.tool_manager.destroy();
        self.world_renderer.deinit();
        self.renderer.deinit();
        self.world.free();
        self.vehicle_defs.free();

        context.allocator.destroy(self);
    }

    fn update(self_ptr: *anyopaque, context: *const engine.UpdateContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        // change mode?
        if (context.input_state.consumeKeyDownEvent(.F1)) {
            self.enterPlayMode();
        }
        if (context.input_state.consumeKeyDownEvent(.F2)) {
            self.enterEditMode();
        }
        if (context.input_state.consumeKeyDownEvent(.tab)) { // TODO tab does not work sometimes?
            self.toggleMasterMode();
        }

        // TODO only set if changed?
        self.camera.setViewportSize(context.viewport_size);

        // convert screen coords to world coords
        const mouse_position = self.camera.screenToWorld(context.input_state.mouse_position_screen);
        self.mouse_position = mouse_position;
        self.mouse_diff = mouse_position.sub(self.prev_mouse_position);
        self.prev_mouse_position = mouse_position;

        // update physics
        // TODO figure out optimal order of things
        if (self.world.players.items.len > 0) {
            const player: *Player = &self.world.players.items[0];
            player.update(context.dt, context.input_state, mouse_position, self.master_mode == .Play);
        }

        self.world.update(context.dt, context.per_frame_allocator, context.input_state, &self.renderer);

        if (self.world.players.items.len > 0) {
            const player: *Player = &self.world.players.items[0];
            if (self.master_mode == .Play) {
                const t = player.getTransform();
                const p = t.pos;

                self.camera.setFocusPosition(p);
            } else {
                self.camera.setFocusPosition(vec2.zero);
            }
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

        if (context.input_state.getKeyState(.left)) self.camera.changeOffset(vec2.init(-100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.right)) self.camera.changeOffset(vec2.init(100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.up)) self.camera.changeOffset(vec2.init(0.0, 100.0 * context.dt));
        if (context.input_state.getKeyState(.down)) self.camera.changeOffset(vec2.init(0.0, -100.0 * context.dt));

        // pan camera?
        if (!self.moving_camera and context.input_state.consumeMouseButtonDownEvent(.right)) {
            self.moving_camera = true;
        } else if (self.moving_camera and !context.input_state.getMouseButtonState(.right)) {
            self.moving_camera = false;
        } else if (self.moving_camera) {
            self.camera.changeOffset(self.mouse_diff.neg());
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

        _ = context;

        // mouse
        //self.renderer.addPointWithPixelSize(self.mouse_position, 10.0, Color.green);

        // physics
        b2.b2World_Draw(self.world.world_id, &self.zbox_renderer.b2_debug_draw);

        // world
        self.world_renderer.render(&self.world, &self.camera);

        // tool
        self.tool_manager.render(.{});

        self.renderer.render(&self.camera);
    }

    fn drawUi(self_ptr: *anyopaque, context: *const engine.DrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        // xxx
        self.renderer.render_to_zgui(&self.camera);
        // xxx

        if (self.master_mode == .Edit) {
            self.drawEditUi(context);
        }
    }

    fn drawEditUi(self: *Self, context: *const engine.DrawUiContext) void {
        // Note: "End and EndChild are special and must be called even if Begin{,Child} returns false."

        var buffer: [128]u8 = undefined;

        var show_import_world_dialog = false;
        var show_export_world_dialog = false;

        if (zgui.beginMainMenuBar()) {
            if (zgui.beginMenu("File", true)) {
                if (zgui.menuItem("New world", .{})) {
                    self.world.clear();
                }
                if (zgui.menuItem("Import world...", .{})) {
                    show_import_world_dialog = true;
                }
                if (zgui.menuItem("Export world...", .{})) {
                    show_export_world_dialog = true;
                }

                zgui.separator();

                if (zgui.menuItem("Exit editor", .{})) {
                    self.enterPlayMode();
                }

                zgui.endMenu();
            }

            if (zgui.beginMenu("Tools", true)) {
                if (zgui.menuItem("Tool: ---", .{ .selected = self.tool_manager.active_tool == null })) {
                    self.tool_manager.deselect();
                }

                for (self.tool_manager.all_tools.items) |tool_vtable| {
                    const b = std.fmt.bufPrintZ(&buffer, "Tool: {s}", .{tool_vtable.name}) catch unreachable;

                    var sel = false;
                    if (self.tool_manager.active_tool) |tool| {
                        if (std.meta.eql(tool.vtable.name, tool_vtable.name)) {
                            sel = true;
                        }
                    }

                    if (zgui.menuItem(b, .{ .selected = sel })) {
                        self.tool_manager.select(tool_vtable);
                    }
                }

                zgui.endMenu();
            }

            zgui.endMainMenuBar();
        }

        if (show_import_world_dialog) {
            self.import_world_dialog.open() catch |e| {
                std.log.err("open dialog: {any}", .{e});
            };
        }

        if (show_export_world_dialog) {
            self.export_world_dialog.open() catch |e| {
                std.log.err("open dialog: {any}", .{e});
            };
        }

        self.import_world_dialog.drawUi();
        self.export_world_dialog.drawUi();

        self.tool_manager.drawUi(.{
            .input = context.input_state,
        });

        // ...
        // zgui.setNextWindowPos(.{ .x = 10.0, .y = 400.0, .cond = .appearing });
        // //zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

        // if (zgui.begin("Editor", .{})) {
        //     zgui.text("mouse: {d:.1} {d:.1}", .{ self.mouse_position.x, self.mouse_position.y });

        //     //
        //     // physics
        //     //

        //     if (zgui.collapsingHeader("physics", .{})) {
        //         self.zbox_renderer.drawUi();
        //     }
        // }
        // zgui.end();
    }

    fn toggleMasterMode(self: *Self) void {
        switch (self.master_mode) {
            .Edit => {
                self.enterPlayMode();
            },
            .Play => {
                self.enterEditMode();
            },
        }
    }

    fn enterPlayMode(self: *Self) void {
        std.log.info("entering play mode", .{});

        self.master_mode = .Play;

        self.tool_manager.deselect();
        self.camera.reset();
    }

    fn enterEditMode(self: *Self) void {
        std.log.info("entering edit mode", .{});

        // keep camera where it is
        const cam_pos = self.camera.focus_position.add(self.camera.offset);

        self.master_mode = .Edit;

        self.camera.reset();
        self.camera.offset = cam_pos;
    }

    fn importWorld(world: *World, save_manager: *engine.SaveManager, temp_allocator: std.mem.Allocator, name: []const u8) !void {
        const data = try save_manager.load(.WorldExport, name, temp_allocator);
        defer temp_allocator.free(data);

        //std.log.info("world data: {s}", .{data});

        try WorldImporter.importWorld(world, data, temp_allocator);
    }

    fn importVehicle(world: *World, save_manager: *engine.SaveManager, temp_allocator: std.mem.Allocator, vehicle_defs: *const VehicleDefs, name: []const u8) !void {
        const data = try save_manager.load(.VehicleExport, name, temp_allocator);
        defer temp_allocator.free(data);

        //std.log.info("vehicle data: {s}", .{data});

        _ = try VehicleImporter.importVehicle(world, data, temp_allocator, vehicle_defs);
    }
};
