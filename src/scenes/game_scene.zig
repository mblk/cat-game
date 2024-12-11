const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const World = @import("../game/world.zig").World;
const GroundPointIndex = @import("../game/world.zig").GroundPointIndex;
const GroundSegmentIndex = @import("../game/world.zig").GroundSegmentIndex;
const GroundSegment = @import("../game/world.zig").GroundSegment;

const WorldExporter = @import("../game/world_export.zig").WorldExporter;
const WorldImporter = @import("../game/world_export.zig").WorldImporter;

const Player = @import("../game/player.zig").Player;

const Tool = @import("../game/tools/tool.zig").Tool;
const ToolVTable = @import("../game/tools/tool.zig").ToolVTable;
const GroundEditTool = @import("../game/tools/ground_edit_tool.zig").GroundEditTool;
const VehicleEditTool = @import("../game/tools/vehicle_edit_tool.zig").VehicleEditTool;

pub fn getScene() engine.Scene {
    return engine.Scene{
        .name = "game",
        .load = load,
        .unload = unload,
        .update = update,
        .render = render,
        .draw_ui = drawUi,
    };
}

const Data = struct {
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

    build_mode: BuildMode = .Idle,

    moving_camera: bool = false,

    save_name_buffer: [10:0]u8 = [_:0]u8{0} ** 10,

    // tools
    all_tools: []ToolVTable,
    active_tool: ?Tool = null,
};

const BuildMode = enum {
    Idle,
    ControlPlayer,
    CreateBox,
};

fn load(context: *const engine.LoadContext) !*anyopaque {
    var world = World.create(context.allocator);
    errdefer world.free();
    //try world.load();
    world.createDynamicBox(vec2.init(10, 10));
    world.createDynamicBox(vec2.init(15, 10));
    world.createDynamicBox(vec2.init(20, 10));

    const player = Player.create(world.world_id);

    const camera = engine.Camera.create();

    var renderer = try engine.Renderer2D.create(context.allocator, context.content_manager);
    errdefer renderer.free();

    const zbox_renderer = engine.ZBoxRenderer.create(renderer);

    // tools
    var all_tools = std.ArrayList(ToolVTable).init(context.allocator);
    defer all_tools.deinit();
    try all_tools.append(GroundEditTool.getVTable());
    try all_tools.append(VehicleEditTool.getVTable());

    const data = try context.allocator.create(Data);
    data.* = Data{
        .world = world, // Note: This makes a copy
        .player = player,
        .camera = camera,
        .renderer = renderer,
        .zbox_renderer = zbox_renderer,
        .all_tools = try all_tools.toOwnedSlice(),
    };

    @memcpy(data.save_name_buffer[0..4], "test");

    return data;
}

fn unload(context: *const engine.UnloadContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    if (data.active_tool) |tool| {
        tool.vtable.destroy(tool.context);
    }

    context.allocator.free(data.all_tools);

    data.renderer.free();
    data.world.free();

    context.allocator.destroy(data);
}

fn update(context: *const engine.UpdateContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    // update physics
    // TODO figure out optimal order of things
    // data.player.update(context.dt, context.input_state);
    // data.world.update(context.dt);

    // TODO only set when changed?
    data.camera.setViewportSize(context.viewport_size);

    // convert screen coords to world coords
    const mouse_position = data.camera.screenToWorld(context.input_state.mouse_position_screen);
    data.mouse_position = mouse_position;
    data.mouse_diff = mouse_position.sub(data.prev_mouse_position);
    data.prev_mouse_position = mouse_position;

    // update physics
    // TODO figure out optimal order of things
    data.player.update(context.dt, context.input_state, mouse_position, data.build_mode == .ControlPlayer);
    data.world.update(context.dt);

    switch (data.build_mode) {
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
                data.world.createDynamicBox(mouse_position);
            }
        },
    }

    // tool
    if (data.active_tool) |tool| {
        tool.vtable.update(tool.context, context.input_state, mouse_position);
    }

    // camera movement
    if (context.input_state.consumeMouseScroll()) |scroll| {
        data.camera.changeZoom(-scroll);
    }

    if (context.input_state.consumeKeyDownEvent(.backspace)) {
        data.camera.reset();
    }

    if (context.input_state.getKeyState(.left)) data.camera.changePosition(vec2.init(-100.0 * context.dt, 0.0));
    if (context.input_state.getKeyState(.right)) data.camera.changePosition(vec2.init(100.0 * context.dt, 0.0));
    if (context.input_state.getKeyState(.up)) data.camera.changePosition(vec2.init(0.0, 100.0 * context.dt));
    if (context.input_state.getKeyState(.down)) data.camera.changePosition(vec2.init(0.0, -100.0 * context.dt));

    // pan camera?
    if (!data.moving_camera and context.input_state.consumeMouseButtonDownEvent(.right)) {
        //std.log.info("start moving camera", .{});
        data.moving_camera = true;
    } else if (data.moving_camera and !context.input_state.getMouseButtonState(.right)) {
        //std.log.info("stop moving camera", .{});
        data.moving_camera = false;
    } else if (data.moving_camera) {
        data.camera.changePosition(data.mouse_diff.neg());
    }

    // must update after camera has moved
    data.prev_mouse_position = data.camera.screenToWorld(context.input_state.mouse_position_screen);

    // scene management
    if (context.input_state.consumeKeyDownEvent(.escape)) {
        context.scene_commands.exit = true;
    }
}

fn render(context: *const engine.RenderContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    // mouse
    data.renderer.addPointWithPixelSize(data.mouse_position, 10.0, Color.green);

    // physics
    b2.b2World_Draw(data.world.world_id, &data.zbox_renderer.b2_debug_draw);

    // player
    data.player.render(context.dt, data.renderer);

    // tool
    if (data.active_tool) |tool| {
        tool.vtable.render(tool.context);
    }

    data.renderer.render(&data.camera);
}

fn drawUi(context: *const engine.DrawUiContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    zgui.setNextWindowPos(.{ .x = 10.0, .y = 500.0, .cond = .appearing });
    //zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

    if (zgui.begin("Game", .{})) {
        zgui.text("mouse: {d:.1} {d:.1}", .{ data.mouse_position.x, data.mouse_position.y });

        if (zgui.button("clear", .{})) {
            data.build_mode = .Idle;

            data.world.clear();
        }

        _ = zgui.inputText("save name", .{
            .buf = &data.save_name_buffer,
        });

        //std.log.info("b1 {} buffer '{s}'", .{ b1, data.save_name_buffer });

        if (zgui.button("export", .{})) {
            const s = getSliceFromSentinelArray(&data.save_name_buffer);
            exportWorld(&data.world, context.save_manager, s) catch |e| {
                std.log.err("export: {any}", .{e});
            };
        }
        if (zgui.button("import", .{})) {
            data.build_mode = .Idle;

            const s = getSliceFromSentinelArray(&data.save_name_buffer);
            importWorld(&data.world, context.save_manager, s) catch |e| {
                std.log.err("import: {any}", .{e});
            };
        }

        if (data.active_tool) |tool| {
            zgui.text("tool: {s}", .{tool.vtable.name});
        } else {
            zgui.text("tool: ---", .{});
        }

        if (zgui.button("tool: ---", .{})) {
            if (data.active_tool) |tool| {
                tool.vtable.destroy(tool.context);
            }
            data.active_tool = null;
        }

        var buffer: [128]u8 = undefined;

        for (data.all_tools) |tool_vtable| {
            const b = std.fmt.bufPrintZ(&buffer, "tool: {s}", .{tool_vtable.name}) catch unreachable;
            if (zgui.button(b, .{})) {
                //
                if (data.active_tool) |tool| {
                    tool.vtable.destroy(tool.context);
                }
                data.active_tool = Tool{
                    .vtable = tool_vtable,
                    .context = tool_vtable.create(context.allocator, &data.world, data.renderer) catch unreachable,
                };
            }
        }

        // tool
        if (data.active_tool) |tool| {
            tool.vtable.drawUi(tool.context);
        }

        zgui.text("build mode:", .{});

        inline for (@typeInfo(BuildMode).@"enum".fields) |field| {
            const enumValue = @field(BuildMode, field.name);

            if (zgui.radioButton(field.name, .{ .active = data.build_mode == enumValue })) {
                data.build_mode = enumValue;
            }
        }

        if (zgui.collapsingHeader("physics", .{})) {
            data.zbox_renderer.drawUi();
        }

        if (zgui.collapsingHeader("vehicles", .{})) {
            for (data.world.vehicles.items) |vehicle| {
                zgui.text("vehicle alive={} blocks={d}", .{ vehicle.alive, vehicle.blocks.items.len });

                for (vehicle.blocks.items) |block| {
                    zgui.text("  block alive={} pos={d} {d}", .{ block.alive, block.local_position.x, block.local_position.y });
                }
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

fn exportWorld(world: *World, save_manager: *engine.SaveManager, name: []const u8) !void {

    // XXX provide via arg?
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const data = try WorldExporter.exportWorld(world, allocator);
    //std.log.info("data: {s}", .{data});

    try save_manager.save(name, data, allocator);
}

fn importWorld(world: *World, save_manager: *engine.SaveManager, name: []const u8) !void {

    // XXX provide via arg?
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const data = try save_manager.load(name, allocator);
    //std.log.info("data: {s}", .{data});

    try WorldImporter.importWorld(world, data, allocator);
}
