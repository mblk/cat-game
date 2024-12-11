const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const World = @import("../world.zig").World;
const GroundPointIndex = @import("../world.zig").GroundPointIndex;
const GroundSegmentIndex = @import("../world.zig").GroundSegmentIndex;
const GroundSegment = @import("../world.zig").GroundSegment;

const ToolVTable = @import("tool.zig").ToolVTable;

const Selection = union(enum) {
    None: void,
    GroundSegment: GroundSegmentIndex,
    GroundPoint: GroundPointIndex,
};

pub const GroundEditTool = struct {
    const Self = GroundEditTool;

    allocator: std.mem.Allocator,
    world: *World,
    renderer2D: *engine.Renderer2D,

    selection: Selection = .None,
    moving_selected: bool = false,

    pub fn getVTable() ToolVTable {
        return ToolVTable{
            .name = "Ground edit",
            .create = Self.create,
            .destroy = Self.destroy,
            .update = Self.update,
            .render = Self.render,
            .drawUi = Self.drawUi,
        };
    }

    fn create(allocator: std.mem.Allocator, world: *World, renderer2D: *engine.Renderer2D) !*anyopaque {
        const self = try allocator.create(Self);

        self.* = Self{
            .allocator = allocator,
            .world = world,
            .renderer2D = renderer2D,
        };

        return self;
    }

    fn destroy(context: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context));

        self.allocator.destroy(self);
    }

    fn update(context: *anyopaque, input: *engine.InputState, mouse_position: vec2) void {
        const self: *Self = @ptrCast(@alignCast(context));

        switch (self.selection) {
            .None => {
                // select ground segment?
                if (self.world.getGroundSegment(mouse_position, 10.0)) |ground_segment_index| {
                    const ground_segment = self.world.ground_segments.items[ground_segment_index.index];

                    self.renderer2D.addLine(mouse_position, ground_segment.position, Color.red);
                    self.renderer2D.addPointWithPixelSize(ground_segment.position, 20.0, Color.green);

                    if (input.consumeMouseButtonDownEvent(.left)) {
                        self.selection = .{ .GroundSegment = ground_segment_index };
                    }
                }
                // select ground point?
                else if (self.world.getGroundPoint(mouse_position, 10.0)) |ground_point_index| {
                    const ground_segment = self.world.ground_segments.items[ground_point_index.ground_segment_index];
                    const ground_point = ground_segment.points.items[ground_point_index.ground_point_index];
                    const p = ground_segment.position.add(ground_point);

                    self.renderer2D.addLine(mouse_position, p, Color.red);
                    self.renderer2D.addPointWithPixelSize(p, 20.0, Color.green);

                    if (input.consumeMouseButtonDownEvent(.left)) {
                        self.selection = .{ .GroundPoint = ground_point_index };
                    }
                }
                // create new segment?
                else {
                    if (input.consumeMouseButtonDownEvent(.left)) {
                        const new_index = self.world.createGroundSegment(mouse_position);

                        // box2d uses ccw order.
                        _ = self.world.createGroundPoint(GroundPointIndex{ .ground_segment_index = new_index.index, .ground_point_index = 0 }, vec2.init(-10, -10), false);
                        _ = self.world.createGroundPoint(GroundPointIndex{ .ground_segment_index = new_index.index, .ground_point_index = 1 }, vec2.init(10, -10), false);
                        _ = self.world.createGroundPoint(GroundPointIndex{ .ground_segment_index = new_index.index, .ground_point_index = 2 }, vec2.init(10, 10), false);
                        _ = self.world.createGroundPoint(GroundPointIndex{ .ground_segment_index = new_index.index, .ground_point_index = 3 }, vec2.init(-10, 10), false);

                        self.selection = .{ .GroundSegment = new_index };

                        // TODO vielleicht besser einen Modus hinzufügen bei dem man das gewünschte Polygon zeichnet und es dann erst angelegt wird?
                    }
                }
            },
            .GroundSegment => |ground_segment_index| {
                const ground_segment = self.world.ground_segments.items[ground_segment_index.index];
                const dist = mouse_position.dist(ground_segment.position);

                // delete?
                if (input.consumeKeyDownEvent(.delete)) {
                    self.world.deleteGroundSegment(ground_segment_index);

                    self.selection = .None;
                    self.moving_selected = false;
                }
                // stop moving?
                else if (self.moving_selected and !input.getMouseButtonState(.left)) {
                    self.moving_selected = false;
                }
                // keep moving?
                else if (self.moving_selected and input.getMouseButtonState(.left)) {
                    self.world.moveGroundSegment(ground_segment_index, mouse_position);
                }
                // start moving?
                else if (dist < 10.0 and input.consumeMouseButtonDownEvent(.left)) {
                    self.moving_selected = true;
                }
            },
            .GroundPoint => |ground_point_index| {
                const ground_segment = self.world.ground_segments.items[ground_point_index.ground_segment_index];
                const ground_point = ground_segment.points.items[ground_point_index.ground_point_index];
                const dist = mouse_position.dist(ground_segment.position.add(ground_point));

                // delete?
                if (input.consumeKeyDownEvent(.delete)) {
                    self.world.deleteGroundPoint(ground_point_index);

                    self.selection = .None;
                    self.moving_selected = false;
                }
                // stop moving?
                else if (self.moving_selected and !input.getMouseButtonState(.left)) {
                    self.moving_selected = false;
                }
                // keep moving?
                else if (self.moving_selected and input.getMouseButtonState(.left)) {
                    self.world.moveGroundPoint(ground_point_index, mouse_position);
                }
                // start moving?
                else if (dist < 10) {

                    // start moving?
                    if (input.consumeMouseButtonDownEvent(.left)) {
                        self.moving_selected = true;
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

                    self.renderer2D.addLine(p1, p2, Color.red);
                    self.renderer2D.addLine(p2, p3, Color.red);

                    // create new point?
                    if (input.consumeMouseButtonDownEvent(.left)) {
                        const new_index = self.world.createGroundPoint(ground_point_index, mouse_position, true);
                        self.selection = .{ .GroundPoint = new_index };
                    }
                }
            },
        }

        if (self.selection != .None and input.consumeMouseButtonDownEvent(.right)) {
            self.selection = .None;
            self.moving_selected = false;
        }
    }

    fn render(context: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context));

        for (self.world.ground_segments.items) |*segment| {
            // show grab handle
            self.renderer2D.addPointWithPixelSize(segment.position, 15.0, Color.white);
        }

        switch (self.selection) {
            .None => {},
            .GroundSegment => |segment_index| {
                const segment = &self.world.ground_segments.items[segment_index.index];

                self.renderer2D.addPointWithPixelSize(segment.position, 20.0, Color.red);
            },
            .GroundPoint => |point_index| {
                const segment: *GroundSegment = &self.world.ground_segments.items[point_index.ground_segment_index];
                const point: vec2 = segment.points.items[point_index.ground_point_index];

                const p = segment.position.add(point);

                self.renderer2D.addPointWithPixelSize(p, 20.0, Color.red);
            },
        }
    }

    fn drawUi(context: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context));

        switch (self.selection) {
            .None => {
                zgui.text("selection: ---", .{});
            },
            .GroundSegment => |segment_index| {
                zgui.text("selection: seg {d}", .{segment_index.index});
            },
            .GroundPoint => |point_index| {
                zgui.text("selection: seg {d} p {d}", .{ point_index.ground_segment_index, point_index.ground_point_index });
            },
        }
    }
};
