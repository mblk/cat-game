const std = @import("std");

const vec2 = @import("math.zig").vec2;
const Color = @import("math.zig").Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const zgui = @import("zgui");

const Renderer2D = @import("renderer_2d.zig").Renderer2D;

pub const ZBoxRenderer = struct {
    b2_debug_draw: b2.b2DebugDraw,
    renderer: *Renderer2D,

    pub fn create(renderer: *Renderer2D) ZBoxRenderer {
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

        b2_debug_draw.drawShapes = true;
        b2_debug_draw.drawJoints = true;
        //b2_debug_draw.drawAABBs = true;

        b2_debug_draw.context = renderer;

        return ZBoxRenderer{
            .b2_debug_draw = b2_debug_draw,
            .renderer = renderer,
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
        //std.log.info("b2_draw_polygon", .{});

        const renderer = getRenderer(context);
        const color = convertColor(b2color);

        std.debug.assert(vertices != null);
        std.debug.assert(vertex_count >= 3);

        // 0 1 2 3 ..
        // 0 + 12
        // 0 + 23

        const p0 = convertVec2(vertices[0]);

        var i: usize = 1;
        while (i < vertex_count - 1) : (i += 1) {
            const p1 = convertVec2(vertices[i]);
            const p2 = convertVec2(vertices[i + 1]);

            renderer.addTriangle(p0, p1, p2, color);
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

        const renderer = getRenderer(context);
        const color = convertColor(b2color);

        var abs_points: [8]vec2 = undefined;
        var i: usize = 0;
        while (i < vertex_count) : (i += 1) {
            const p = b2.b2TransformPoint(transform, vertices[i]);
            abs_points[i] = convertVec2(p);
        }

        i = 0;
        while (i < vertex_count) : (i += 1) {
            const count: usize = @intCast(vertex_count);
            const index1: usize = i;
            const index2: usize = (i + 1) % count;

            renderer.addLine(abs_points[index1], abs_points[index2], color);
        }
    }

    // Draw a circle.
    // void ( *DrawCircle )( b2Vec2 center, float radius, b2HexColor color, void* context );
    fn b2_draw_circle(b2center: b2.b2Vec2, radius: f32, b2color: b2.b2HexColor, context: ?*anyopaque) callconv(.c) void {
        //_ = center;
        //_ = radius;
        //_ = b2color;
        //_ = context;

        //std.log.info("b2_draw_circle", .{});

        const renderer = getRenderer(context);
        const color = convertColor(b2color);

        const center = convertVec2(b2center);

        renderer.addPoint(center, radius, color); // TODO not solid
    }

    // Draw a solid circle.
    // void ( *DrawSolidCircle )( b2Transform transform, float radius, b2HexColor color, void* context );
    fn b2_draw_solid_circle(
        transform: b2.b2Transform,
        radius: f32,
        b2color: b2.b2HexColor,
        context: ?*anyopaque,
    ) callconv(.c) void {
        //_ = transform;
        //_ = radius;
        //_ = b2color;
        //_ = context;

        //std.log.info("b2_draw_solid_circle", .{});

        const renderer = getRenderer(context);
        const color = convertColor(b2color);

        const center = convertVec2(transform.p);
        // TODO show rotation

        renderer.addPoint(center, radius, color);
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
        // _ = p1;
        // _ = p2;
        // _ = color;
        // _ = context;

        //std.log.info("b2_draw_segment", .{});

        const renderer = getRenderer(context);
        const color = convertColor(b2color);

        const p1 = convertVec2(b2p1);
        const p2 = convertVec2(b2p2);

        renderer.addLine(p1, p2, color);
    }

    // Draw a transform. Choose your own length scale.
    // void ( *DrawTransform )( b2Transform transform, void* context );
    fn b2_draw_transform(transform: b2.b2Transform, context: ?*anyopaque) callconv(.c) void {
        _ = transform;
        _ = context;

        std.log.info("b2_draw_transform", .{});
    }

    // Draw a point.
    // void ( *DrawPoint )( b2Vec2 p, float size, b2HexColor color, void* context );
    fn b2_draw_point(b2p: b2.b2Vec2, size: f32, b2color: b2.b2HexColor, context: ?*anyopaque) callconv(.c) void {
        //_ = p;
        //_ = size;
        //_ = color;
        //_ = context;

        //std.log.info("b2_draw_point {d}", .{size});

        const renderer = getRenderer(context);
        const color = convertColor(b2color);

        const p = convertVec2(b2p);

        renderer.addPointWithPixelSize(p, size, color);
    }

    // Draw a string.
    // void ( *DrawString )( b2Vec2 p, const char* s, void* context );
    fn b2_draw_string(p: b2.b2Vec2, s: [*c]const u8, context: ?*anyopaque) callconv(.c) void {
        _ = p;
        _ = s;
        _ = context;

        std.log.info("b2_draw_string", .{});
    }

    inline fn getRenderer(context: ?*anyopaque) *Renderer2D {
        std.debug.assert(context != null);
        const renderer: *Renderer2D = @ptrCast(@alignCast(context));
        return renderer;
    }

    inline fn convertColor(color: b2.b2HexColor) Color {
        // TODO no idea if this is correct

        //var c: [4]u8 = [_]u8{ 255, 255, 255, 255 };
        var c: [4]u8 = undefined;

        //@memcpy(&c, &color);

        c[0] = @intCast(color & 0xFF);
        c[1] = @intCast((color & 0xFF00) >> 8);
        c[2] = @intCast((color & 0xFF0000) >> 16);
        c[3] = @intCast((color & 0xFF000000) >> 24);

        // c[3] = @intCast(color & 0xFF);
        // c[2] = @intCast((color & 0xFF00) >> 8);
        // c[1] = @intCast((color & 0xFF0000) >> 16);
        // c[0] = @intCast((color & 0xFF000000) >> 24);

        return Color{
            .r = c[0],
            .g = c[1],
            .b = c[2],
            .a = c[3],
        };
    }

    inline fn convertVec2(vec: b2.b2Vec2) vec2 {
        return vec2{
            .x = vec.x,
            .y = vec.y,
        };
    }
};
