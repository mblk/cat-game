const std = @import("std");

const vec2 = @import("math.zig").vec2;
const Color = @import("math.zig").Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const zgui = @import("zgui");

const Renderer2D = @import("renderer_2d.zig").Renderer2D;
const MaterialRef = @import("material.zig").MaterialRef;

pub const ZBoxRenderer = struct {
    const Self = @This();
    //const Layer = Renderer2D.Layers.ZBox;

    const FillLayer = Renderer2D.Layers.ZBox;
    const LineLayer = Renderer2D.Layers.ZBox + 1;

    b2_debug_draw: b2.b2DebugDraw,
    renderer: *Renderer2D,

    mat_default: MaterialRef,

    pub fn init(self: *Self, renderer: *Renderer2D) void {
        var b2_debug_draw: b2.b2DebugDraw = b2.b2DefaultDebugDraw();

        b2_debug_draw.DrawPolygon = b2_draw_polygon;
        b2_debug_draw.DrawSolidPolygon = b2_draw_solid_polygon;
        b2_debug_draw.DrawCircle = b2_draw_circle;
        b2_debug_draw.DrawSolidCircle = b2_draw_solid_circle;
        b2_debug_draw.DrawSolidCapsule = b2_draw_solid_capsule;
        b2_debug_draw.DrawSegment = b2_draw_segment;
        b2_debug_draw.DrawTransform = b2_draw_transform;
        b2_debug_draw.DrawPoint = b2_draw_point;
        b2_debug_draw.DrawString = b2_draw_string;

        //b2_debug_draw.drawShapes = true;
        //b2_debug_draw.drawJoints = true;
        //b2_debug_draw.drawAABBs = true;

        b2_debug_draw.context = self;

        self.* = ZBoxRenderer{
            .b2_debug_draw = b2_debug_draw,
            .renderer = renderer,

            .mat_default = renderer.getMaterial("default"),
        };
    }

    pub fn drawUi(self: *ZBoxRenderer) void {
        _ = zgui.checkbox("use drawing bounds", .{ .v = &self.b2_debug_draw.useDrawingBounds });
        _ = zgui.checkbox("draw shapes", .{ .v = &self.b2_debug_draw.drawShapes });
        _ = zgui.checkbox("draw joints", .{ .v = &self.b2_debug_draw.drawJoints });
        _ = zgui.checkbox("draw joint extras", .{ .v = &self.b2_debug_draw.drawJointExtras });
        _ = zgui.checkbox("draw AABBs", .{ .v = &self.b2_debug_draw.drawAABBs });
        _ = zgui.checkbox("draw mass", .{ .v = &self.b2_debug_draw.drawMass });
        _ = zgui.checkbox("draw contacts", .{ .v = &self.b2_debug_draw.drawContacts });
        _ = zgui.checkbox("draw graph colors", .{ .v = &self.b2_debug_draw.drawGraphColors });
        _ = zgui.checkbox("draw contact normals", .{ .v = &self.b2_debug_draw.drawContactNormals });
        _ = zgui.checkbox("draw contact impulses", .{ .v = &self.b2_debug_draw.drawContactImpulses });
        _ = zgui.checkbox("draw friction impulses", .{ .v = &self.b2_debug_draw.drawFrictionImpulses });
    }

    // Draw a closed polygon provided in CCW order.
    // void ( *DrawPolygon )( const b2Vec2* vertices, int vertexCount, b2HexColor color, void* context );
    fn b2_draw_polygon(
        vertices: [*c]const b2.b2Vec2,
        vertex_count: c_int,
        b2color: b2.b2HexColor,
        context: ?*anyopaque,
    ) callconv(.c) void {
        //std.log.info("b2_draw_polygon count={d}", .{vertex_count});

        const self = getSelfPtr(context);
        const renderer = self.renderer;

        const color = convertColor(b2color);
        const count: usize = @intCast(vertex_count);

        std.debug.assert(vertices != null);
        std.debug.assert(count >= 3);

        for (0..count) |i| {
            const p1 = convertVec2(vertices[i]);
            const p2 = convertVec2(vertices[(i + 1) % count]);

            renderer.addLine(p1, p2, LineLayer, color);
        }
    }

    // Draw a solid closed polygon provided in CCW order.
    // void ( *DrawSolidPolygon )( b2Transform transform, const b2Vec2* vertices, int vertexCount, float radius, b2HexColor color, void* context );
    fn b2_draw_solid_polygon(
        transform: b2.b2Transform,
        vertices: [*c]const b2.b2Vec2,
        vertex_count: c_int,
        radius: f32,
        b2color: b2.b2HexColor,
        context: ?*anyopaque,
    ) callconv(.c) void {
        _ = radius; // TODO

        //std.log.info("b2_draw_solid_polygon", .{});

        const self = getSelfPtr(context);
        const renderer = self.renderer;

        const color = convertColor(b2color);
        const fill_color = Color{
            .r = color.r / 4,
            .g = color.g / 4,
            .b = color.b / 4,
            .a = color.a,
        };
        const count: usize = @intCast(vertex_count);

        var abs_points: [8]vec2 = undefined;
        for (0..count) |i| {
            const p = b2.b2TransformPoint(transform, vertices[i]);
            abs_points[i] = convertVec2(p);
        }

        for (0..count) |i| {
            const index1: usize = i;
            const index2: usize = (i + 1) % count;

            renderer.addLine(abs_points[index1], abs_points[index2], LineLayer, color);
        }

        // 0 1 2 3 ..
        // 0 + 12
        // 0 + 23
        // ...
        const p0 = abs_points[0];
        for (1..count - 1) |i| {
            const p1 = abs_points[i];
            const p2 = abs_points[i + 1];

            renderer.addTrianglePC([3]vec2{ p0, p1, p2 }, FillLayer, fill_color, self.mat_default);
        }
    }

    // Draw a circle.
    // void ( *DrawCircle )( b2Vec2 center, float radius, b2HexColor color, void* context );
    fn b2_draw_circle(b2center: b2.b2Vec2, radius: f32, b2color: b2.b2HexColor, context: ?*anyopaque) callconv(.c) void {
        //std.log.info("b2_draw_circle", .{});

        const self = getSelfPtr(context);
        const renderer = self.renderer;

        const color = convertColor(b2color);
        const center = convertVec2(b2center);

        renderer.addCircle(center, radius, LineLayer, color);
    }

    // Draw a solid circle.
    // void ( *DrawSolidCircle )( b2Transform transform, float radius, b2HexColor color, void* context );
    fn b2_draw_solid_circle(
        transform: b2.b2Transform,
        radius: f32,
        b2color: b2.b2HexColor,
        context: ?*anyopaque,
    ) callconv(.c) void {
        //std.log.info("b2_draw_solid_circle", .{});

        const self = getSelfPtr(context);
        const renderer = self.renderer;

        const color = convertColor(b2color);
        const fill_color = Color{
            .r = color.r / 4,
            .g = color.g / 4,
            .b = color.b / 4,
            .a = color.a,
        };

        const center = convertVec2(transform.p);
        const right_vector = vec2.from_b2(b2.b2RotateVector(transform.q, vec2.init(1, 0).to_b2()));
        const right = center.add(right_vector.scale(radius));

        renderer.addSolidCircle(center, radius, FillLayer, fill_color, self.mat_default);
        renderer.addCircle(center, radius, LineLayer, color);
        renderer.addLine(center, right, LineLayer, color);
    }

    // Draw a solid capsule.
    // void ( *DrawSolidCapsule )( b2Vec2 p1, b2Vec2 p2, float radius, b2HexColor color, void* context );
    fn b2_draw_solid_capsule(p1: b2.b2Vec2, p2: b2.b2Vec2, radius: f32, color: b2.b2HexColor, context: ?*anyopaque) callconv(.c) void {
        _ = p1;
        _ = p2;
        _ = radius;
        _ = color;
        _ = context;

        std.log.info("b2_draw_solid_capsule", .{});
    }

    // Draw a line segment.
    // void ( *DrawSegment )( b2Vec2 p1, b2Vec2 p2, b2HexColor color, void* context );
    fn b2_draw_segment(b2p1: b2.b2Vec2, b2p2: b2.b2Vec2, b2color: b2.b2HexColor, context: ?*anyopaque) callconv(.c) void {
        //std.log.info("b2_draw_segment", .{});

        const self = getSelfPtr(context);
        const renderer = self.renderer;

        const color = convertColor(b2color);
        const p1 = convertVec2(b2p1);
        const p2 = convertVec2(b2p2);

        renderer.addLine(p1, p2, LineLayer, color);
    }

    // Draw a transform. Choose your own length scale.
    // void ( *DrawTransform )( b2Transform transform, void* context );
    fn b2_draw_transform(transform: b2.b2Transform, context: ?*anyopaque) callconv(.c) void {
        //std.log.info("b2_draw_transform", .{});

        const self = getSelfPtr(context);
        const renderer = self.renderer;

        const axis_scale = 0.5;

        const p1 = vec2.from_b2(transform.p);
        const p2 = vec2.from_b2(b2.b2MulAdd(transform.p, axis_scale, b2.b2Rot_GetXAxis(transform.q)));
        const p3 = vec2.from_b2(b2.b2MulAdd(transform.p, axis_scale, b2.b2Rot_GetYAxis(transform.q)));

        renderer.addLine(p1, p2, LineLayer, Color.red);
        renderer.addLine(p1, p3, LineLayer, Color.green);
    }

    // Draw a point.
    // void ( *DrawPoint )( b2Vec2 p, float size, b2HexColor color, void* context );
    fn b2_draw_point(b2p: b2.b2Vec2, size: f32, b2color: b2.b2HexColor, context: ?*anyopaque) callconv(.c) void {
        //std.log.info("b2_draw_point {d}", .{size});

        const self = getSelfPtr(context);
        const renderer = self.renderer;

        const color = convertColor(b2color);
        const p = convertVec2(b2p);

        renderer.addPointWithPixelSize(p, size, FillLayer, color);
    }

    // Draw a string.
    // void ( *DrawString )( b2Vec2 p, const char* s, void* context );
    fn b2_draw_string(b2p: b2.b2Vec2, b2s: [*c]const u8, context: ?*anyopaque) callconv(.c) void {
        //std.log.info("b2_draw_string {s}", .{b2s});

        const self = getSelfPtr(context);
        const renderer = self.renderer;

        const p = convertVec2(b2p);
        const s: []const u8 = std.mem.span(b2s); // convert c-string-pointer to slice

        renderer.addText(p, LineLayer, Color.white, "{s}", .{s});
    }

    inline fn getSelfPtr(context: ?*anyopaque) *Self {
        std.debug.assert(context != null);
        const self: *Self = @ptrCast(@alignCast(context));
        return self;
    }

    inline fn convertColor(color: b2.b2HexColor) Color {
        return Color{
            .r = @intCast(color & 0xFF),
            .g = @intCast((color & 0xFF00) >> 8),
            .b = @intCast((color & 0xFF0000) >> 16),
            .a = @intCast((color & 0xFF000000) >> 24),
        };
    }

    inline fn convertVec2(vec: b2.b2Vec2) vec2 {
        return vec2{
            .x = vec.x,
            .y = vec.y,
        };
    }
};
