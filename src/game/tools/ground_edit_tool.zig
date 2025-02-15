const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const geometry_utils = @import("../../utils/geometry.zig");

const World = @import("../world.zig").World;

const GroundSegment = @import("../ground_segment.zig").GroundSegment;

const GroundSegmentRef = @import("../refs.zig").GroundSegmentRef;

const tools = @import("tools.zig");
const ToolVTable = tools.ToolVTable;
const ToolDeps = tools.ToolDeps;
const ToolUpdateContext = tools.ToolUpdateContext;
const ToolRenderContext = tools.ToolRenderContext;
const ToolDrawUiContext = tools.ToolDrawUiContext;

const Selection = union(enum) {
    None: void,

    MakeCircle: void,
    MakeBox: void,
    MakePolygon: void,

    GroundSegment: GroundSegmentRef,
    GroundPoint: struct {
        segment: GroundSegmentRef,
        point_index: usize,
    },
};

pub const GroundEditTool = struct {
    const Self = GroundEditTool;
    const Layer = engine.Renderer2D.Layers.Tools;

    allocator: std.mem.Allocator,
    world: *World,
    renderer2D: *engine.Renderer2D,

    selection: Selection = .None,
    moving_selected: bool = false,

    temp_points: std.ArrayList(vec2),

    pub fn getVTable() ToolVTable {
        return ToolVTable{
            .name = "Ground edit",
            .shortcut = .F2,
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

            .temp_points = .init(allocator),
        };

        return self;
    }

    fn destroy(self_ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.temp_points.deinit();

        self.allocator.destroy(self);
    }

    fn update(self_ptr: *anyopaque, context: ToolUpdateContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        const input = context.input;
        const mouse_position = context.mouse_position;

        const max_pick_distance = 25.0 * context.world_per_pixel;

        switch (self.selection) {
            .None => {
                // select ground segment?
                if (self.world.findGroundSegment(mouse_position, max_pick_distance)) |ref| {
                    const ground_segment = self.world.getGroundSegment(ref);

                    self.renderer2D.addLine(mouse_position, ground_segment.position, Layer, Color.green);
                    self.renderer2D.addPointWithPixelSize(ground_segment.position, 20.0, Layer, Color.green);

                    if (input.consumeMouseButtonDownEvent(.left)) {
                        self.selection = .{
                            .GroundSegment = ref,
                        };
                    }
                }
            },

            .MakeCircle => {
                // preview
                self.renderer2D.addCircle(mouse_position, 1.0, Layer, Color.green);

                // create new segment?
                if (input.consumeMouseButtonDownEvent(.left)) {
                    const new_ref = self.world.createGroundSegment(mouse_position, .{
                        .Circle = .{
                            .radius = 1.0,
                        },
                    });

                    self.selection = .{
                        .GroundSegment = new_ref,
                    };
                }
            },
            .MakeBox => {
                // preview
                {
                    const hw = 0.5;
                    const hh = 0.5;

                    const points = [4]vec2{
                        mouse_position.add(vec2.init(-hw, -hh)),
                        mouse_position.add(vec2.init(hw, -hh)),
                        mouse_position.add(vec2.init(hw, hh)),
                        mouse_position.add(vec2.init(-hw, hh)),
                    };
                    self.renderer2D.addLine(points[0], points[1], Layer, Color.green);
                    self.renderer2D.addLine(points[1], points[2], Layer, Color.green);
                    self.renderer2D.addLine(points[2], points[3], Layer, Color.green);
                    self.renderer2D.addLine(points[3], points[0], Layer, Color.green);
                }

                // create new segment?
                if (input.consumeMouseButtonDownEvent(.left)) {
                    const new_ref = self.world.createGroundSegment(mouse_position, .{
                        .Box = .{
                            .width = 1.0,
                            .height = 1.0,
                            .angle = 0.0,
                        },
                    });

                    self.selection = .{
                        .GroundSegment = new_ref,
                    };
                }
            },
            .MakePolygon => {
                // preview temp points
                {
                    var p_last: ?vec2 = null;

                    for (self.temp_points.items) |p| {
                        self.renderer2D.addPointWithPixelSize(p, 10.0, Layer, Color.green);

                        if (p_last) |pl| {
                            self.renderer2D.addLine(pl, p, Layer, Color.green);
                        }

                        p_last = p;
                    }
                }

                // check if polygon can be finished
                var can_finish = false;

                if (self.temp_points.items.len > 2) {
                    const p_first = self.temp_points.items[0];
                    const dist_to_first = p_first.dist(mouse_position);

                    if (dist_to_first < max_pick_distance) {
                        can_finish = true;
                    }
                }

                // preview what mouse click will do
                if (self.temp_points.items.len > 0) {
                    const p_first = self.temp_points.items[0];
                    const p_last = self.temp_points.items[self.temp_points.items.len - 1];

                    if (can_finish) {
                        self.renderer2D.addLine(p_last, p_first, Layer, Color.green);
                        self.renderer2D.addText(p_last, Layer, Color.white, "finish", .{});
                    } else {
                        self.renderer2D.addLine(p_last, mouse_position, Layer, Color.green);
                    }
                }

                // remove last point or cancel selection?
                if (input.consumeMouseButtonDownEvent(.right)) {
                    if (self.temp_points.items.len > 0) {
                        // remove last point
                        _ = self.temp_points.orderedRemove(self.temp_points.items.len - 1);
                    } else {
                        // cancel
                        self.selection = .None;
                    }
                }
                // add point/finish?
                else if (input.consumeMouseButtonDownEvent(.left)) {
                    if (can_finish) {
                        self.createPolygonSegmentFromTempPoints();
                    } else {
                        self.temp_points.append(mouse_position) catch unreachable;
                    }
                }
            },

            .GroundSegment => |ref| {
                const ground_segment = self.world.getGroundSegment(ref);
                const dist = mouse_position.dist(ground_segment.position);

                // Select point?
                var stop = false;
                if (ground_segment.shape == .Polygon) {

                    // select point?
                    if (ground_segment.findPoint(mouse_position, max_pick_distance)) |point_index| {
                        const p_local = ground_segment.shape.Polygon.points[point_index];
                        const p_world = ground_segment.position.add(p_local);

                        self.renderer2D.addLine(mouse_position, p_world, Layer, Color.green);
                        self.renderer2D.addPointWithPixelSize(p_world, 20.0, Layer, Color.green);

                        if (input.consumeMouseButtonDownEvent(.left)) {
                            self.selection = .{
                                .GroundPoint = .{
                                    .segment = ref,
                                    .point_index = point_index,
                                },
                            };
                            self.moving_selected = false;
                            stop = true;
                        }
                    }
                }

                if (stop) {
                    //
                }
                // delete?
                else if (input.consumeKeyDownEvent(.delete)) {
                    self.world.deleteGroundSegment(ref);

                    self.selection = .None;
                    self.moving_selected = false;
                }
                // stop moving?
                else if (self.moving_selected and !input.getMouseButtonState(.left)) {
                    self.moving_selected = false;
                }
                // keep moving?
                else if (self.moving_selected and input.getMouseButtonState(.left)) {
                    self.world.moveGroundSegment(ref, mouse_position);
                }
                // start moving?
                else if (dist < max_pick_distance and input.consumeMouseButtonDownEvent(.left)) {
                    self.moving_selected = true;
                }
            },
            .GroundPoint => |sel| {
                const ground_segment = self.world.getGroundSegment(sel.segment);
                const ground_point = ground_segment.shape.Polygon.points[sel.point_index];
                const dist = mouse_position.dist(ground_segment.position.add(ground_point));

                // delete?
                if (input.consumeKeyDownEvent(.delete)) {
                    ground_segment.destroyPoint(sel.point_index);

                    self.selection = .{ .GroundSegment = sel.segment };
                    self.moving_selected = false;
                }
                // stop moving?
                else if (self.moving_selected and !input.getMouseButtonState(.left)) {
                    self.moving_selected = false;
                }
                // keep moving?
                else if (self.moving_selected and input.getMouseButtonState(.left)) {
                    ground_segment.movePoint(sel.point_index, mouse_position, true);
                }
                // start moving?
                else if (dist < max_pick_distance and input.consumeMouseButtonDownEvent(.left)) {
                    self.moving_selected = true;
                }
                // create new point?
                else {
                    // show preview
                    const prev_point_index = if (sel.point_index > 0)
                        sel.point_index - 1
                    else
                        ground_segment.shape.Polygon.points.len - 1;

                    const p1 = ground_segment.position.add(ground_point);
                    const p2 = mouse_position;
                    const p3_local = ground_segment.shape.Polygon.points[prev_point_index];
                    const p3 = ground_segment.position.add(p3_local);

                    self.renderer2D.addLine(p1, p2, Layer, Color.red);
                    self.renderer2D.addLine(p2, p3, Layer, Color.red);

                    // create new point?
                    if (input.consumeMouseButtonDownEvent(.left)) {
                        ground_segment.createPoint(sel.point_index, mouse_position, true);

                        self.selection = .{
                            .GroundPoint = .{
                                .segment = sel.segment,
                                .point_index = sel.point_index,
                            },
                        };
                    }
                }

                // return to ground-segment selection?
                if (input.consumeMouseButtonDownEvent(.right)) {
                    self.selection = .{ .GroundSegment = sel.segment };
                    self.moving_selected = false;
                }
            },
        }

        // clear selection?
        if (self.selection != .None and input.consumeMouseButtonDownEvent(.right)) {
            self.selection = .None;
            self.moving_selected = false;
        }
    }

    fn renderCirclePreview() void {}
    fn renderBoxPreview() void {}

    fn renderGroundSegmentOutline(self: *Self, ground_segment: *const GroundSegment) void {
        const p = ground_segment.position;

        const layer = Self.Layer;
        const color = Color.white;

        switch (ground_segment.shape) {
            .Circle => |circle| {
                self.renderer2D.addCircle(p, circle.radius, layer, color);
            },
            .Box => |box| {
                const hw = box.width * 0.5;
                const hh = box.height * 0.5;

                // TODO angle

                const points = [4]vec2{
                    p.add(vec2.init(-hw, -hh)),
                    p.add(vec2.init(hw, -hh)),
                    p.add(vec2.init(hw, hh)),
                    p.add(vec2.init(-hw, hh)),
                };
                self.renderer2D.addLine(points[0], points[1], layer, color);
                self.renderer2D.addLine(points[1], points[2], layer, color);
                self.renderer2D.addLine(points[2], points[3], layer, color);
                self.renderer2D.addLine(points[3], points[0], layer, color);
            },
            .Polygon => |polygon| {
                const count = polygon.points.len;
                for (0..count) |i| {
                    const p1 = p.add(polygon.points[i]);
                    const p2 = p.add(polygon.points[(i + 1) % count]);

                    self.renderer2D.addLine(p1, p2, layer, color);
                    self.renderer2D.addPointWithPixelSize(p1, 10.0, layer, color);
                }
            },
        }
    }

    fn createPolygonSegmentFromTempPoints(self: *Self) void {
        std.debug.assert(self.temp_points.items.len >= 3);

        const points = self.temp_points.toOwnedSlice() catch unreachable;

        var p_avg = vec2.zero;
        for (points) |p| {
            p_avg = p_avg.add(p);
        }
        const count_f32: f32 = @floatFromInt(points.len);
        p_avg = p_avg.scale(1.0 / count_f32);

        for (points) |*p| {
            p.* = p.*.sub(p_avg);
        }

        //xxx
        if (geometry_utils.isClockwisePolygon(points)) {
            std.log.info(">>> points are CW, reversing", .{});

            // reverse order
            for (0..points.len / 2) |i| {
                const temp = points[i];

                points[i] = points[points.len - i - 1];
                points[points.len - i - 1] = temp;
            }
        }
        //xxx

        const new_ref = self.world.createGroundSegment(p_avg, .{
            .Polygon = .{
                .points = points, // owned by segment
            },
        });

        self.selection = .{
            .GroundSegment = new_ref,
        };
    }

    fn render(self_ptr: *anyopaque, context: ToolRenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = context;

        for (self.world.ground_segments.items) |*segment| {
            // show grab handle
            self.renderer2D.addPointWithPixelSize(segment.position, 15.0, Layer, Color.white);
        }

        switch (self.selection) {
            .None => {},
            .GroundSegment => |sel| {
                const segment = self.world.getGroundSegment(sel);

                //xxx
                self.renderGroundSegmentOutline(segment);
                //xxx

                self.renderer2D.addPointWithPixelSize(segment.position, 20.0, Layer + 1, Color.red);
            },
            .GroundPoint => |sel| {
                const segment = self.world.getGroundSegment(sel.segment);

                //xxx
                self.renderGroundSegmentOutline(segment);
                //xxx

                const point: vec2 = segment.shape.Polygon.points[sel.point_index];
                const p = segment.position.add(point);

                self.renderer2D.addPointWithPixelSize(p, 20.0, Layer + 1, Color.red);
            },

            else => {},
        }
    }

    fn drawUi(self_ptr: *anyopaque, context: ToolDrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = context;

        zgui.setNextWindowPos(.{ .x = 10.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 300, .h = 500 });

        if (zgui.begin("Ground segments", .{
            .flags = .{
                .no_resize = true,
            },
        })) {
            self.drawListWindowContent();
        }
        zgui.end();

        if (self.selection == .GroundSegment) {
            zgui.setNextWindowPos(.{ .x = 320.0, .y = 300.0, .cond = .appearing });
            zgui.setNextWindowSize(.{ .w = 300, .h = 0 });

            if (zgui.begin("Edit ground segment", .{
                .flags = .{
                    .no_resize = true,
                },
            })) {
                const ref = self.selection.GroundSegment;
                const ground_segment = self.world.getGroundSegment(ref);
                self.drawEditGroundSegmentContent(ground_segment);
            }
            zgui.end();
        }
    }

    fn drawListWindowContent(self: *Self) void {
        var buffer: [128]u8 = undefined;

        _ = zgui.beginChild("#SelectionBox", .{
            .h = 75,
            .child_flags = .{
                .border = true,
            },
        });
        {
            zgui.text("Sel: {s}", .{@tagName(self.selection)});

            switch (self.selection) {
                .None => {
                    if (zgui.button("Circle", .{})) {
                        self.selection = .MakeCircle;
                    }
                    zgui.sameLine(.{});
                    if (zgui.button("Box", .{})) {
                        self.selection = .MakeBox;
                    }
                    zgui.sameLine(.{});
                    if (zgui.button("Polygon", .{})) {
                        self.selection = .MakePolygon;
                    }
                },
                .MakeCircle => {
                    zgui.text("Place new circle ...", .{});
                },
                .MakeBox => {
                    zgui.text("Place new box ...", .{});
                },
                .MakePolygon => {
                    zgui.text("Place new polygon ...", .{});
                },
                else => {},
            }
        }
        zgui.endChild();

        _ = zgui.beginChild("#GroundSegmentsList", .{
            .child_flags = .{
                .border = true,
            },
        });
        defer zgui.endChild();

        for (self.world.ground_segments.items, 0..) |ground_segment, ground_segmend_index| {
            const label = std.fmt.bufPrintZ(&buffer, "Segment {d} {s}", .{ ground_segmend_index, @tagName(ground_segment.shape) }) catch unreachable;

            const is_selected = self.selection == .GroundSegment and self.selection.GroundSegment.index == ground_segmend_index;

            if (zgui.selectable(label, .{ .selected = is_selected })) {
                self.selection = .{
                    .GroundSegment = .{
                        .index = ground_segmend_index,
                    },
                };
            }
        }
    }

    fn drawEditGroundSegmentContent(self: *Self, ground_segment: *GroundSegment) void {
        _ = self;

        zgui.text("Shape: {s}", .{@tagName(ground_segment.shape)});
        zgui.text("Position: {d:.3}", .{ground_segment.position});

        switch (ground_segment.shape) {
            .Box => |*box| {
                if (zgui.dragFloat("Width", .{
                    .v = &box.width,
                    .min = 0.1,
                    .max = 100.0,
                    .speed = 0.1,
                    .cfmt = "%.1f",
                })) {
                    ground_segment.dirty = true;
                }

                if (zgui.dragFloat("Height", .{
                    .v = &box.height,
                    .min = 0.1,
                    .max = 100.0,
                    .speed = 0.1,
                    .cfmt = "%.1f",
                })) {
                    ground_segment.dirty = true;
                }

                if (zgui.sliderAngle("Angle", .{
                    .cfmt = "%.0f deg",
                    .deg_min = -180,
                    .deg_max = 180,
                    .flags = .{},
                    .vrad = &box.angle,
                })) {
                    ground_segment.dirty = true;
                }
            },
            .Circle => |*circle| {
                if (zgui.dragFloat("Radius", .{
                    .v = &circle.radius,
                    .min = 0.1,
                    .max = 100.0,
                    .speed = 0.1,
                    .cfmt = "%.1f",
                })) {
                    ground_segment.dirty = true;
                }
            },
            .Polygon => |*polygon| {
                zgui.text("Polygon points:", .{});
                for (polygon.points) |point| {
                    zgui.text("Point {d:.3}", .{point});
                }
            },
        }
    }
};
