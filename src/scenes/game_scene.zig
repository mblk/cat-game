const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../engine/engine.zig");

const vec2 = engine.vec2;
const Color = engine.Color;

const World = @import("../game/world.zig").World;

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

    // visuals
    camera: engine.Camera,
    renderer: engine.Renderer2D,

    // input
    mouse_position: vec2 = vec2.init(0, 0), // XXX shit
    prev_mouse_position: vec2 = vec2.init(0, 0),
    mouse_diff: vec2 = vec2.init(0, 0),

    build_mode: BuildMode = .Idle,
    selection: Selection = .None,
    moving_selected: bool = false, // XXX shit

    moving_camera: bool = false,
};

const BuildMode = enum {
    Idle,
    Create,
    Edit,
};

const Selection = union(enum) {
    None: void,
    GroundSegment: World.GroundSegmentIndex,
    GroundPoint: World.GroundPointIndex,
};

fn load(context: *const engine.LoadContext) !*anyopaque {
    var world = World.create(context.allocator);
    errdefer world.free();
    try world.load();

    const camera = engine.Camera.create();

    var renderer = try engine.Renderer2D.create(context.allocator, context.content_manager);
    errdefer renderer.free();

    const data = try context.allocator.create(Data);
    data.* = Data{
        .world = world,
        .camera = camera,
        .renderer = renderer,
    };
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

    data.camera.setViewportSize(context.viewport_size);

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
                const new_index = data.world.createGroundSegment(mouse_position) catch unreachable;

                data.build_mode = .Edit;
                data.selection = .{ .GroundSegment = new_index };
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
                        const p1 = ground_segment.position.add(ground_point);
                        const p2 = mouse_position;
                        const p3_local = ground_segment.points.items[(ground_point_index.ground_point_index + 1) % ground_segment.points.items.len];
                        const p3 = ground_segment.position.add(p3_local);

                        data.renderer.addLine(p1, p2, Color.red);
                        data.renderer.addLine(p2, p3, Color.red);

                        // create new point?
                        if (context.input_state.consumeMouseButtonDownEvent(.left)) {
                            const new_index = data.world.createGroundPoint(ground_point_index, mouse_position) catch unreachable;
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

    data.renderer.addPoint(data.mouse_position, 1.0, Color.green);

    for (data.world.ground_segments.items) |ground_segment| {
        data.renderer.addPoint(ground_segment.position, 1.0, Color.red);

        for (0.., ground_segment.points.items) |i, ground_point| {
            const p1_local = ground_point;
            const p2_local = ground_segment.points.items[(i + 1) % ground_segment.points.items.len];
            const p1 = ground_segment.position.add(p1_local);
            const p2 = ground_segment.position.add(p2_local);

            data.renderer.addPointWithPixelSize(p1, 10.0, Color.white);
            data.renderer.addLine(p1, p2, Color.white);
        }
    }

    data.renderer.render(&data.camera);
}

fn drawUi(context: *const engine.DrawUiContext) void {
    const data: *Data = @ptrCast(@alignCast(context.scene_data));

    zgui.setNextWindowPos(.{ .x = 10.0, .y = 500.0, .cond = .appearing });
    //zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

    if (zgui.begin("Game", .{})) {
        zgui.text("build mode:", .{});

        inline for (@typeInfo(BuildMode).@"enum".fields) |field| {
            const enumValue = @field(BuildMode, field.name);

            if (zgui.radioButton(field.name, .{ .active = data.build_mode == enumValue })) {
                data.build_mode = enumValue;
            }
        }

        zgui.text("selection: {any}", .{data.selection});

        zgui.end();
    }
}
