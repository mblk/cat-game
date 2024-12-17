const std = @import("std");

const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zm = @import("zmath");

const zgui = @import("zgui");

const ContentManager = @import("content_manager.zig").ContentManager;
const Shader = @import("shader.zig").Shader;
const Camera = @import("camera.zig").Camera;

const vec2 = @import("math.zig").vec2;
const Color = @import("math.zig").Color;

const PointVertexData = struct {
    position: vec2,
    color: Color,
    size: f32,
    scale: f32,
};

const VertexData = struct {
    position: vec2,
    color: Color,
};

const TextData = struct {
    position: vec2,
    color: Color,
    buffer: [128]u8,
    len: usize,
};

pub const Renderer2D = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    point_shader: Shader,
    line_shader: Shader,
    triangle_shader: Shader,

    point_vbo: c_uint,
    point_vao: c_uint,

    line_vbo: c_uint,
    line_vao: c_uint,

    triangle_vbo: c_uint,
    triangle_vao: c_uint,

    point_data: std.ArrayList(PointVertexData),
    line_data: std.ArrayList(VertexData),
    triangle_data: std.ArrayList(VertexData),
    text_data: std.ArrayList(TextData),

    pub fn create(
        allocator: std.mem.Allocator,
        content_manager: *ContentManager,
    ) !*Self {

        //
        const point_shader = try content_manager.loadShader(allocator, "point.vs", "point.fs");
        const line_shader = try content_manager.loadShader(allocator, "line.vs", "line.fs");
        const triangle_shader = try content_manager.loadShader(allocator, "triangle.vs", "triangle.fs");

        // point buffers
        var point_vao: c_uint = undefined;
        gl.genVertexArrays(1, &point_vao);

        var point_vbo: c_uint = undefined;
        gl.genBuffers(1, &point_vbo);

        gl.bindVertexArray(point_vao);
        {
            gl.bindBuffer(gl.ARRAY_BUFFER, point_vbo);
            gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(PointVertexData) * 1024, null, gl.DYNAMIC_DRAW);

            const stride: usize = @sizeOf(PointVertexData);
            const offset0: [*c]c_uint = @offsetOf(PointVertexData, "position");
            const offset1: [*c]c_uint = @offsetOf(PointVertexData, "color");
            const offset2: [*c]c_uint = @offsetOf(PointVertexData, "size");
            const offset3: [*c]c_uint = @offsetOf(PointVertexData, "scale");

            gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, offset0); // position
            gl.enableVertexAttribArray(0);

            gl.vertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, gl.TRUE, stride, offset1); // color
            gl.enableVertexAttribArray(1);

            gl.vertexAttribPointer(2, 1, gl.FLOAT, gl.FALSE, stride, offset2); // size
            gl.enableVertexAttribArray(2);

            gl.vertexAttribPointer(3, 1, gl.FLOAT, gl.FALSE, stride, offset3); // scale
            gl.enableVertexAttribArray(3);

            gl.bindBuffer(gl.ARRAY_BUFFER, 0); // ?
        }
        gl.bindVertexArray(0);

        // line buffers
        var line_vao: c_uint = undefined;
        gl.genVertexArrays(1, &line_vao);

        var line_vbo: c_uint = undefined;
        gl.genBuffers(1, &line_vbo);

        gl.bindVertexArray(line_vao);
        {
            gl.bindBuffer(gl.ARRAY_BUFFER, line_vbo);
            gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(VertexData) * 1024, null, gl.DYNAMIC_DRAW);

            const stride: usize = @sizeOf(VertexData);
            const offset0: [*c]c_uint = @offsetOf(VertexData, "position");
            const offset1: [*c]c_uint = @offsetOf(VertexData, "color");

            gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, offset0); // position
            gl.enableVertexAttribArray(0);

            gl.vertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, gl.TRUE, stride, offset1); // color
            gl.enableVertexAttribArray(1);

            gl.bindBuffer(gl.ARRAY_BUFFER, 0); // ?
        }
        gl.bindVertexArray(0);

        // triangle buffers
        var triangle_vao: c_uint = undefined;
        gl.genVertexArrays(1, &triangle_vao);

        var triangle_vbo: c_uint = undefined;
        gl.genBuffers(1, &triangle_vbo);

        gl.bindVertexArray(triangle_vao);
        {
            gl.bindBuffer(gl.ARRAY_BUFFER, triangle_vbo);
            gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(VertexData) * 1024, null, gl.DYNAMIC_DRAW);

            const stride: usize = @sizeOf(VertexData);
            const offset0: [*c]c_uint = @offsetOf(VertexData, "position");
            const offset1: [*c]c_uint = @offsetOf(VertexData, "color");

            gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, offset0);
            gl.enableVertexAttribArray(0);

            gl.vertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, gl.TRUE, stride, offset1);
            gl.enableVertexAttribArray(1);

            gl.bindBuffer(gl.ARRAY_BUFFER, 0); // ?
        }
        gl.bindVertexArray(0);

        const renderer = try allocator.create(Self);

        renderer.* = Renderer2D{
            .allocator = allocator,

            .point_shader = point_shader,
            .line_shader = line_shader,
            .triangle_shader = triangle_shader,

            .point_vao = point_vao,
            .point_vbo = point_vbo,
            .line_vao = line_vao,
            .line_vbo = line_vbo,
            .triangle_vao = triangle_vao,
            .triangle_vbo = triangle_vbo,

            .point_data = .init(allocator),
            .line_data = .init(allocator),
            .triangle_data = .init(allocator),
            .text_data = .init(allocator),
        };

        return renderer;
    }

    pub fn free(self: *Self) void {
        self.text_data.deinit();
        self.point_data.deinit();
        self.line_data.deinit();
        self.triangle_data.deinit();

        gl.deleteVertexArrays(1, &self.point_vao);
        gl.deleteBuffers(1, &self.point_vbo);

        gl.deleteVertexArrays(1, &self.line_vao);
        gl.deleteBuffers(1, &self.line_vbo);

        gl.deleteVertexArrays(1, &self.triangle_vao);
        gl.deleteBuffers(1, &self.triangle_vbo);

        self.point_shader.free();
        self.line_shader.free();
        self.triangle_shader.free();

        self.allocator.destroy(self);
    }

    pub fn addPoint(self: *Self, position: vec2, size: f32, color: Color) void {
        self.point_data.append(PointVertexData{
            .position = position,
            .color = color,
            .size = size,
            .scale = 1.0, // size is worldpos
        }) catch unreachable;
    }

    pub fn addPointWithPixelSize(self: *Self, position: vec2, size: f32, color: Color) void {
        self.point_data.append(PointVertexData{
            .position = position,
            .color = color,
            .size = size,
            .scale = 0.0, // size is pixels
        }) catch unreachable;
    }

    pub fn addLine(self: *Self, p1: vec2, p2: vec2, color: Color) void {
        self.line_data.append(VertexData{
            .position = p1,
            .color = color,
        }) catch unreachable;
        self.line_data.append(VertexData{
            .position = p2,
            .color = color,
        }) catch unreachable;
    }

    // pub fn addArrow(self: *Self, from: vec2, to: vec2, color: Color) void {

    // }

    pub fn addCircle(self: *Self, center: vec2, radius: f32, color: Color) void {
        const segments: usize = 32;
        const segment_angle: f32 = 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));

        var prev_point = center.add(vec2.init(radius, 0));
        for (1..segments + 1) |i| {
            const angle = segment_angle * @as(f32, @floatFromInt(i));
            const point = center.add(vec2{
                .x = std.math.cos(angle) * radius,
                .y = std.math.sin(angle) * radius,
            });
            self.addLine(prev_point, point, color);
            prev_point = point;
        }
    }

    pub fn addSolidCircle(self: *Self, center: vec2, radius: f32, color: Color) void {
        const segments: usize = 32;
        const segment_angle: f32 = 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));

        var prev_point = center.add(vec2.init(radius, 0));
        for (1..segments + 1) |i| {
            const angle = segment_angle * @as(f32, @floatFromInt(i));
            const point = center.add(vec2{
                .x = std.math.cos(angle) * radius,
                .y = std.math.sin(angle) * radius,
            });
            self.addTriangle(center, prev_point, point, color);
            prev_point = point;
        }
    }

    pub fn addTriangle(self: *Self, p1: vec2, p2: vec2, p3: vec2, color: Color) void {
        self.triangle_data.append(VertexData{
            .position = p1,
            .color = color,
        }) catch unreachable;
        self.triangle_data.append(VertexData{
            .position = p2,
            .color = color,
        }) catch unreachable;
        self.triangle_data.append(VertexData{
            .position = p3,
            .color = color,
        }) catch unreachable;
    }

    pub fn addText(self: *Self, position: vec2, color: Color, comptime fmt: []const u8, args: anytype) void {
        self.text_data.append(TextData{
            .position = position,
            .color = color,
            .buffer = undefined,
            .len = 0,
        }) catch unreachable;

        var data: *TextData = &self.text_data.items[self.text_data.items.len - 1];

        // copy to buffer
        const s = std.fmt.bufPrintZ(&data.buffer, fmt, args) catch unreachable;

        data.len = s.len;
    }

    pub fn render(self: *Self, camera: *Camera) void {
        const model: zm.Mat = zm.identity();
        const view = camera.view;
        const projection = camera.projection;

        const viewport_size = [2]f32{
            @floatFromInt(camera.viewport_size[0]),
            @floatFromInt(camera.viewport_size[1]),
        };

        // triangles
        if (self.triangle_data.items.len > 0) {
            // upload data
            gl.bindBuffer(gl.ARRAY_BUFFER, self.triangle_vbo);
            gl.bufferData(
                gl.ARRAY_BUFFER,
                @intCast(@sizeOf(VertexData) * self.triangle_data.items.len),
                self.triangle_data.items.ptr,
                gl.DYNAMIC_DRAW,
            );
            gl.bindBuffer(gl.ARRAY_BUFFER, 0);

            // render
            self.triangle_shader.bind();
            {
                self.triangle_shader.setMat4("uModel", model);
                self.triangle_shader.setMat4("uView", view);
                self.triangle_shader.setMat4("uProjection", projection);

                gl.bindVertexArray(self.triangle_vao);
                gl.drawArrays(gl.TRIANGLES, 0, @intCast(self.triangle_data.items.len));
                gl.bindVertexArray(0);
            }
            self.triangle_shader.unbind();

            // clear buffer
            self.triangle_data.clearRetainingCapacity();
        }

        // lines
        if (self.line_data.items.len > 0) {
            // upload data
            gl.bindBuffer(gl.ARRAY_BUFFER, self.line_vbo);
            gl.bufferData(
                gl.ARRAY_BUFFER,
                @intCast(@sizeOf(VertexData) * self.line_data.items.len),
                self.line_data.items.ptr,
                gl.DYNAMIC_DRAW,
            );
            gl.bindBuffer(gl.ARRAY_BUFFER, 0);

            // render
            self.line_shader.bind();
            {
                self.line_shader.setMat4("uModel", model);
                self.line_shader.setMat4("uView", view);
                self.line_shader.setMat4("uProjection", projection);

                gl.bindVertexArray(self.line_vao);
                gl.drawArrays(gl.LINES, 0, @intCast(self.line_data.items.len));
                gl.bindVertexArray(0);
            }
            self.line_shader.unbind();

            // clear buffer
            self.line_data.clearRetainingCapacity();
        }

        // points
        if (self.point_data.items.len > 0) {
            // upload data
            gl.bindBuffer(gl.ARRAY_BUFFER, self.point_vbo);
            gl.bufferData(
                gl.ARRAY_BUFFER,
                @intCast(@sizeOf(PointVertexData) * self.point_data.items.len),
                self.point_data.items.ptr,
                gl.DYNAMIC_DRAW,
            );
            gl.bindBuffer(gl.ARRAY_BUFFER, 0);

            // render
            self.point_shader.bind();
            {
                self.point_shader.setMat4("uModel", model);
                self.point_shader.setMat4("uView", view);
                self.point_shader.setMat4("uProjection", projection);
                self.point_shader.setVec2("uViewportSize", viewport_size);

                gl.enable(gl.PROGRAM_POINT_SIZE);
                gl.bindVertexArray(self.point_vao);
                gl.drawArrays(gl.POINTS, 0, @intCast(self.point_data.items.len));
                gl.bindVertexArray(0);
                gl.disable(gl.PROGRAM_POINT_SIZE);
            }
            self.point_shader.unbind();

            // clear buffer
            self.point_data.clearRetainingCapacity();
        }
    }

    pub fn render_to_zgui(self: *Self, camera: *Camera) void {
        if (self.text_data.items.len > 0) {
            zgui.setNextWindowPos(.{
                .x = 0,
                .y = 0,
                .cond = .always,
            });

            _ = zgui.begin("foo", .{ .flags = .{
                .no_title_bar = true,
                .no_nav_inputs = true,
                .no_mouse_inputs = true,
                .always_auto_resize = true,
                .no_scrollbar = true,
                .no_background = true,
                .no_bring_to_front_on_focus = true,
                .no_collapse = true,
                .no_docking = true,
                .no_focus_on_appearing = true,
                .no_move = true,
                .no_nav_focus = true,
                .no_resize = true,
                .no_saved_settings = true,
                .no_scroll_with_mouse = true,
            } });

            for (self.text_data.items) |*text_data| {
                const screen_pos = camera.worldToScreen(text_data.position);

                zgui.setCursorPosX(screen_pos.x);
                zgui.setCursorPosY(screen_pos.y);

                const c = [4]f32{ 1, 1, 1, 1 };
                const s: []u8 = text_data.buffer[0..text_data.len];

                zgui.textUnformattedColored(c, s);
            }

            zgui.end();

            self.text_data.clearRetainingCapacity();
        }
    }
};
