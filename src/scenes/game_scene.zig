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
    selection: Selection = .None,
    moving_selected: bool = false, // XXX

    moving_camera: bool = false,

    save_name_buffer: [10:0]u8 = [_:0]u8{0} ** 10,
};

// XXX merge?
// Idle,
// CreateGroundSegment,
// Select,
// EditGroundSegment,
// EditGroundPoint,
//

const BuildMode = enum {
    Idle,
    Create,
    Edit,

    CreateBox,
};

const Selection = union(enum) {
    None: void,
    GroundSegment: GroundSegmentIndex,
    GroundPoint: GroundPointIndex,
};

fn load(context: *const engine.LoadContext) !*anyopaque {
    var world = World.create(context.allocator);
    errdefer world.free();
    //try world.load();

    const player = Player.create(world.world_id);

    const camera = engine.Camera.create();

    var renderer = try engine.Renderer2D.create(context.allocator, context.content_manager);
    errdefer renderer.free();

    const zbox_renderer = engine.ZBoxRenderer.create(renderer);

    const data = try context.allocator.create(Data);
    data.* = Data{
        .world = world, // Note: This makes a copy
        .player = player,
        .camera = camera,
        .renderer = renderer,
        .zbox_renderer = zbox_renderer,
    };

    @memcpy(data.save_name_buffer[0..4], "test");

    return data;
}

fn unload(context: *const engine.UnloadContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    data.renderer.free();
    data.world.free();

    context.allocator.destroy(data);
}

fn update(context: *const engine.UpdateContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    // update physics
    // TODO figure out optimal order of things

    data.player.update(context.dt, context.input_state);

    data.world.update(context.dt);

    // TODO only set when changed?
    data.camera.setViewportSize(context.viewport_size);

    // convert screen coords to world coords
    const mouse_position = data.camera.screenToWorld(context.input_state.mouse_position_screen);
    data.mouse_position = mouse_position;
    data.mouse_diff = mouse_position.sub(data.prev_mouse_position);
    data.prev_mouse_position = mouse_position;

    switch (data.build_mode) {
        .Idle => {
            data.selection = .None;
            data.moving_selected = false;
        },

        .Create => {
            data.selection = .None;
            data.moving_selected = false;

            if (context.input_state.consumeMouseButtonDownEvent(.left)) {
                const new_index = data.world.createGroundSegment(mouse_position);

                // box2d uses ccw order.
                _ = data.world.createGroundPoint(GroundPointIndex{ .ground_segment_index = new_index.index, .ground_point_index = 0 }, vec2.init(-10, -10), false);
                _ = data.world.createGroundPoint(GroundPointIndex{ .ground_segment_index = new_index.index, .ground_point_index = 1 }, vec2.init(10, -10), false);
                _ = data.world.createGroundPoint(GroundPointIndex{ .ground_segment_index = new_index.index, .ground_point_index = 2 }, vec2.init(10, 10), false);
                _ = data.world.createGroundPoint(GroundPointIndex{ .ground_segment_index = new_index.index, .ground_point_index = 3 }, vec2.init(-10, 10), false);

                data.build_mode = .Edit;
                data.selection = .{ .GroundSegment = new_index };

                // TODO vielleicht besser einen Modus hinzufügen bei dem man das gewünschte Polygon zeichnet und es dann erst angelegt wird?
            }
        },

        .Edit => {
            switch (data.selection) {
                .None => {
                    // select ground segment?
                    if (data.world.getGroundSegment(mouse_position, 10.0)) |ground_segment_index| {
                        const ground_segment = data.world.ground_segments.items[ground_segment_index.index];

                        data.renderer.addLine(mouse_position, ground_segment.position, Color.red);

                        if (context.input_state.consumeMouseButtonDownEvent(.left)) {
                            data.selection = .{ .GroundSegment = ground_segment_index };
                        }
                    }
                    // select ground point?
                    else if (data.world.getGroundPoint(mouse_position, 10.0)) |ground_point_index| {
                        const ground_segment = data.world.ground_segments.items[ground_point_index.ground_segment_index];
                        const ground_point = ground_segment.points.items[ground_point_index.ground_point_index];
                        const p = ground_segment.position.add(ground_point);

                        data.renderer.addLine(mouse_position, p, Color.red);

                        if (context.input_state.consumeMouseButtonDownEvent(.left)) {
                            data.selection = .{ .GroundPoint = ground_point_index };
                        }
                    }
                },
                .GroundSegment => |ground_segment_index| {
                    const ground_segment = data.world.ground_segments.items[ground_segment_index.index];
                    const dist = mouse_position.dist(ground_segment.position);

                    // delete?
                    if (context.input_state.consumeKeyDownEvent(.delete)) {
                        data.world.deleteGroundSegment(ground_segment_index);

                        data.selection = .None;
                        data.moving_selected = false;
                    }
                    // stop moving?
                    else if (data.moving_selected and !context.input_state.getMouseButtonState(.left)) {
                        data.moving_selected = false;
                    }
                    // keep moving?
                    else if (data.moving_selected and context.input_state.getMouseButtonState(.left)) {
                        data.world.moveGroundSegment(ground_segment_index, mouse_position);
                    }
                    // start moving?
                    else if (dist < 10.0 and context.input_state.consumeMouseButtonDownEvent(.left)) {
                        data.moving_selected = true;
                    }
                },
                .GroundPoint => |ground_point_index| {
                    const ground_segment = data.world.ground_segments.items[ground_point_index.ground_segment_index];
                    const ground_point = ground_segment.points.items[ground_point_index.ground_point_index];
                    const dist = mouse_position.dist(ground_segment.position.add(ground_point));

                    // delete?
                    if (context.input_state.consumeKeyDownEvent(.delete)) {
                        data.world.deleteGroundPoint(ground_point_index);

                        data.selection = .None;
                        data.moving_selected = false;
                    }
                    // stop moving?
                    else if (data.moving_selected and !context.input_state.getMouseButtonState(.left)) {
                        data.moving_selected = false;
                    }
                    // keep moving?
                    else if (data.moving_selected and context.input_state.getMouseButtonState(.left)) {
                        data.world.moveGroundPoint(ground_point_index, mouse_position);
                    }
                    // start moving?
                    else if (dist < 10) {

                        // start moving?
                        if (context.input_state.consumeMouseButtonDownEvent(.left)) {
                            data.moving_selected = true;
                        }
                    }
                    // create new point?
                    else {
                        // show preview
                        var prev_point_index = ground_point_index.ground_point_index;

                        if (prev_point_index > 0) {
                            prev_point_index -= 1;
                        } else {
                            prev_point_index = ground_segment.points.items.len - 1;
                        }

                        const p1 = ground_segment.position.add(ground_point);
                        const p2 = mouse_position;
                        //const p3_local = ground_segment.points.items[(ground_point_index.ground_point_index - 1) % ground_segment.points.items.len];
                        const p3_local = ground_segment.points.items[prev_point_index];
                        const p3 = ground_segment.position.add(p3_local);

                        data.renderer.addLine(p1, p2, Color.red);
                        data.renderer.addLine(p2, p3, Color.red);

                        // create new point?
                        if (context.input_state.consumeMouseButtonDownEvent(.left)) {
                            const new_index = data.world.createGroundPoint(ground_point_index, mouse_position, true);
                            data.selection = .{ .GroundPoint = new_index };
                        }
                    }
                },
            }

            if (data.selection != .None and context.input_state.consumeMouseButtonDownEvent(.right)) {
                data.selection = .None;
                data.moving_selected = false;
            }
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

    for (0.., data.world.ground_segments.items) |ground_segment_index, ground_segment| {
        const ground_segment_color = if (data.selection == Selection.GroundSegment and
            data.selection.GroundSegment.index == ground_segment_index) Color.red else Color.white;

        data.renderer.addPointWithPixelSize(ground_segment.position, 20.0, ground_segment_color);

        for (0.., ground_segment.points.items) |ground_point_index, ground_point| {
            const p1_local = ground_point;
            const p2_local = ground_segment.points.items[(ground_point_index + 1) % ground_segment.points.items.len];
            const p1 = ground_segment.position.add(p1_local);
            const p2 = ground_segment.position.add(p2_local);

            const ground_point_color = if (data.selection == .GroundPoint and
                data.selection.GroundPoint.ground_segment_index == ground_segment_index and
                data.selection.GroundPoint.ground_point_index == ground_point_index) Color.red else Color.white;

            data.renderer.addPointWithPixelSize(p1, 10.0, ground_point_color);
            data.renderer.addLine(p1, p2, Color.white);
        }
    }

    // physics
    b2.b2World_Draw(data.world.world_id, &data.zbox_renderer.b2_debug_draw);

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
            data.selection = .None;

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
            data.selection = .None;

            const s = getSliceFromSentinelArray(&data.save_name_buffer);
            importWorld(&data.world, context.save_manager, s) catch |e| {
                std.log.err("import: {any}", .{e});
            };
        }

        zgui.text("build mode:", .{});

        inline for (@typeInfo(BuildMode).@"enum".fields) |field| {
            const enumValue = @field(BuildMode, field.name);

            if (zgui.radioButton(field.name, .{ .active = data.build_mode == enumValue })) {
                data.build_mode = enumValue;
            }
        }

        zgui.text("selection: {any}", .{data.selection});

        if (zgui.collapsingHeader("physics", .{})) {
            data.zbox_renderer.drawUi();
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
