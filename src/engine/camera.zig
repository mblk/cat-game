const std = @import("std");
const zmath = @import("zmath");

const vec2 = @import("math.zig").vec2;

pub const Camera = struct {
    viewport_size: [2]i32,
    zoom_level: i32,
    focus_position: vec2,
    offset: vec2,

    projection: zmath.Mat,
    view: zmath.Mat,

    pub fn create() Camera {
        var camera = Camera{
            .viewport_size = [2]i32{ 600, 600 },
            .zoom_level = 0,
            .focus_position = vec2.zero,
            .offset = vec2.zero,
            .projection = undefined,
            .view = undefined,
        };

        camera.update();

        return camera;
    }

    fn update(self: *Camera) void {
        const window_width: f32 = @floatFromInt(self.viewport_size[0]);
        const window_height: f32 = @floatFromInt(self.viewport_size[1]);
        const window_ratio: f32 = window_width / window_height;

        const zoom: f32 = std.math.pow(f32, 1.2, @as(f32, @floatFromInt(self.zoom_level)));

        const width = 100.0 * zoom; // target x-visibility at 100% zoom
        const height = width / window_ratio;

        const near = 0.001;
        const far = 1000.0;

        self.projection = zmath.orthographicRhGl(width, height, near, far); // -width/2 ... +width/2
        //self.view = zmath.identity(); // focuspoint + offset

        //self.projection = zmath.Mat4.ortho(left, right, bottom, top, near, far);
        //self.view = zmath.Mat4.identity();

        //const effective_pos = self.focus_position + self.offset;
        //self.view = zmath.Mat4.translate(self.view, zmath.Vec3.init(-effective_pos.x, -effective_pos.y, 0.0));

        const effective_pos = self.focus_position.add(self.offset);

        // const effective_pos_x = self.focus_position[0] + self.offset[0];
        // const effective_pos_y = self.focus_position[1] + self.offset[1];

        self.view = zmath.translation(-effective_pos.x, -effective_pos.y, 0.0);
    }

    pub fn setViewportSize(self: *Camera, size: [2]i32) void {
        self.viewport_size = size;
        self.update();
    }

    pub fn reset(self: *Camera) void {
        self.zoom_level = 0;
        self.offset = vec2.zero;
        self.focus_position = vec2.zero;
        self.update();
    }

    pub fn changeZoom(self: *Camera, delta: i32) void {
        self.zoom_level += delta;
        self.update();
    }

    pub fn changeOffset(self: *Camera, delta: vec2) void {
        self.offset = self.offset.add(delta);
        self.update();
    }

    pub fn setOffset(self: *Camera, position: vec2) void {
        self.offset = position;
        self.update();
    }

    pub fn setFocusPosition(self: *Camera, position: vec2) void {
        self.focus_position = position;
        self.update();
    }

    pub fn screenToWorld(self: *const Camera, screen_position: [2]f32) vec2 {
        //
        const vp_x: f32 = @as(f32, @floatFromInt(self.viewport_size[0]));
        const vp_y: f32 = @as(f32, @floatFromInt(self.viewport_size[1]));

        const ndc_x: f32 = (2.0 * screen_position[0]) / vp_x - 1.0;
        const ndc_y: f32 = 1.0 - (2.0 * screen_position[1]) / vp_y;

        const clip_coords = zmath.f32x4(ndc_x, ndc_y, -1.0, 1.0);

        //const inv_projection = zmath.inverse(self.projection);
        const inv_projection = myInverseDet(self.projection, null);
        const inv_view = zmath.inverse(self.view);

        var view_coords = zmath.mul(clip_coords, inv_projection);
        view_coords[2] = -1.0;
        view_coords[3] = 1.0; // apply translation

        const world_coords = zmath.mul(view_coords, inv_view);

        return vec2.init(world_coords[0], world_coords[1]);
    }

    pub fn worldToScreen(self: *const Camera, world_position: vec2) vec2 {
        // Konvertiere die Weltposition in 4D-Koordinaten (x, y, z = -1.0 für 2D, w = 1.0)
        const world_coords = zmath.f32x4(world_position.x, world_position.y, -1.0, 1.0);

        // Transformiere die Weltkoordinaten in View-Koordinaten
        const view_coords = zmath.mul(world_coords, self.view);

        // Transformiere die View-Koordinaten in Clip-Koordinaten
        const clip_coords = zmath.mul(view_coords, self.projection);

        // NDC-Koordinaten durch Division der Clip-Koordinaten durch w
        const ndc_x = clip_coords[0] / clip_coords[3];
        const ndc_y = clip_coords[1] / clip_coords[3];

        // Bildschirmkoordinaten berechnen
        const vp_x: f32 = @as(f32, @floatFromInt(self.viewport_size[0]));
        const vp_y: f32 = @as(f32, @floatFromInt(self.viewport_size[1]));

        const screen_x = (ndc_x + 1.0) * 0.5 * vp_x;
        const screen_y = (1.0 - ndc_y) * 0.5 * vp_y;

        return vec2.init(screen_x, screen_y);
    }

    pub fn myInverseDet(m: zmath.Mat, out_det: ?*zmath.F32x4) zmath.Mat {
        const mt = zmath.transpose(m);
        var v0: [4]zmath.F32x4 = undefined;
        var v1: [4]zmath.F32x4 = undefined;

        v0[0] = zmath.swizzle(mt[2], .x, .x, .y, .y);
        v1[0] = zmath.swizzle(mt[3], .z, .w, .z, .w);
        v0[1] = zmath.swizzle(mt[0], .x, .x, .y, .y);
        v1[1] = zmath.swizzle(mt[1], .z, .w, .z, .w);
        v0[2] = @shuffle(f32, mt[2], mt[0], [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) });
        v1[2] = @shuffle(f32, mt[3], mt[1], [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) });

        var d0 = v0[0] * v1[0];
        var d1 = v0[1] * v1[1];
        var d2 = v0[2] * v1[2];

        v0[0] = zmath.swizzle(mt[2], .z, .w, .z, .w);
        v1[0] = zmath.swizzle(mt[3], .x, .x, .y, .y);
        v0[1] = zmath.swizzle(mt[0], .z, .w, .z, .w);
        v1[1] = zmath.swizzle(mt[1], .x, .x, .y, .y);
        v0[2] = @shuffle(f32, mt[2], mt[0], [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) });
        v1[2] = @shuffle(f32, mt[3], mt[1], [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) });

        d0 = zmath.mulAdd(-v0[0], v1[0], d0);
        d1 = zmath.mulAdd(-v0[1], v1[1], d1);
        d2 = zmath.mulAdd(-v0[2], v1[2], d2);

        v0[0] = zmath.swizzle(mt[1], .y, .z, .x, .y);
        v1[0] = @shuffle(f32, d0, d2, [4]i32{ ~@as(i32, 1), 1, 3, 0 });
        v0[1] = zmath.swizzle(mt[0], .z, .x, .y, .x);
        v1[1] = @shuffle(f32, d0, d2, [4]i32{ 3, ~@as(i32, 1), 1, 2 });
        v0[2] = zmath.swizzle(mt[3], .y, .z, .x, .y);
        v1[2] = @shuffle(f32, d1, d2, [4]i32{ ~@as(i32, 3), 1, 3, 0 });
        v0[3] = zmath.swizzle(mt[2], .z, .x, .y, .x);
        v1[3] = @shuffle(f32, d1, d2, [4]i32{ 3, ~@as(i32, 3), 1, 2 });

        var c0 = v0[0] * v1[0];
        var c2 = v0[1] * v1[1];
        var c4 = v0[2] * v1[2];
        var c6 = v0[3] * v1[3];

        v0[0] = zmath.swizzle(mt[1], .z, .w, .y, .z);
        v1[0] = @shuffle(f32, d0, d2, [4]i32{ 3, 0, 1, ~@as(i32, 0) });
        v0[1] = zmath.swizzle(mt[0], .w, .z, .w, .y);
        v1[1] = @shuffle(f32, d0, d2, [4]i32{ 2, 1, ~@as(i32, 0), 0 });
        v0[2] = zmath.swizzle(mt[3], .z, .w, .y, .z);
        v1[2] = @shuffle(f32, d1, d2, [4]i32{ 3, 0, 1, ~@as(i32, 2) });
        v0[3] = zmath.swizzle(mt[2], .w, .z, .w, .y);
        v1[3] = @shuffle(f32, d1, d2, [4]i32{ 2, 1, ~@as(i32, 2), 0 });

        c0 = zmath.mulAdd(-v0[0], v1[0], c0);
        c2 = zmath.mulAdd(-v0[1], v1[1], c2);
        c4 = zmath.mulAdd(-v0[2], v1[2], c4);
        c6 = zmath.mulAdd(-v0[3], v1[3], c6);

        v0[0] = zmath.swizzle(mt[1], .w, .x, .w, .x);
        v1[0] = @shuffle(f32, d0, d2, [4]i32{ 2, ~@as(i32, 1), ~@as(i32, 0), 2 });
        v0[1] = zmath.swizzle(mt[0], .y, .w, .x, .z);
        v1[1] = @shuffle(f32, d0, d2, [4]i32{ ~@as(i32, 1), 0, 3, ~@as(i32, 0) });
        v0[2] = zmath.swizzle(mt[3], .w, .x, .w, .x);
        v1[2] = @shuffle(f32, d1, d2, [4]i32{ 2, ~@as(i32, 3), ~@as(i32, 2), 2 });
        v0[3] = zmath.swizzle(mt[2], .y, .w, .x, .z);
        v1[3] = @shuffle(f32, d1, d2, [4]i32{ ~@as(i32, 3), 0, 3, ~@as(i32, 2) });

        const c1 = zmath.mulAdd(-v0[0], v1[0], c0);
        const c3 = zmath.mulAdd(v0[1], v1[1], c2);
        const c5 = zmath.mulAdd(-v0[2], v1[2], c4);
        const c7 = zmath.mulAdd(v0[3], v1[3], c6);

        c0 = zmath.mulAdd(v0[0], v1[0], c0);
        c2 = zmath.mulAdd(-v0[1], v1[1], c2);
        c4 = zmath.mulAdd(v0[2], v1[2], c4);
        c6 = zmath.mulAdd(-v0[3], v1[3], c6);

        var mr = zmath.Mat{
            zmath.f32x4(c0[0], c1[1], c0[2], c1[3]),
            zmath.f32x4(c2[0], c3[1], c2[2], c3[3]),
            zmath.f32x4(c4[0], c5[1], c4[2], c5[3]),
            zmath.f32x4(c6[0], c7[1], c6[2], c7[3]),
        };

        const det = zmath.dot4(mr[0], mt[0]);
        if (out_det != null) {
            out_det.?.* = det;
        }

        // TODO
        //std.log.debug("det {d}", .{det[0]});
        //debug: det -0.000000052224646

        // if (std.math.approxEqAbs(f32, det[0], 0.0, float.floatEps(f32))) {
        //     std.log.debug("!!!! mat inv is zero", .{});
        //     return .{
        //         zmath.f32x4(0.0, 0.0, 0.0, 0.0),
        //         zmath.f32x4(0.0, 0.0, 0.0, 0.0),
        //         zmath.f32x4(0.0, 0.0, 0.0, 0.0),
        //         zmath.f32x4(0.0, 0.0, 0.0, 0.0),
        //     };
        // }

        const scale = zmath.splat(zmath.F32x4, 1.0) / det;
        mr[0] *= scale;
        mr[1] *= scale;
        mr[2] *= scale;
        mr[3] *= scale;
        return mr;
    }
};
