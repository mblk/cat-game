const std = @import("std");

const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zm = @import("zmath");
const zgui = @import("zgui");

const ContentManager = @import("content_manager.zig").ContentManager;
const Shader = @import("shader.zig").Shader;
const Texture = @import("texture.zig").Texture;
const Camera = @import("camera.zig").Camera;

const MaterialDefs = @import("material.zig").MaterialDefs;
const MaterialDef = @import("material.zig").MaterialDef;
const Materials = @import("material.zig").Materials;
const Material = @import("material.zig").Material;
const MaterialRef = @import("material.zig").MaterialRef;

const DynamicVertexBuffer = @import("vertex_buffer.zig").DynamicVertexBuffer;

const vec2 = @import("math.zig").vec2;
const Color = @import("math.zig").Color;

// Vertex data for material-based rendering
const CommonVertexData = struct {
    position: [3]f32,
    color: Color = Color.white,
    tex_coord: vec2 = vec2.zero, // TODO [2]f32 ?
};

const PointVertexData = struct {
    position: [3]f32,
    color: Color,
    size: f32,
    scale: f32,
};

const LineVertexData = struct {
    position: [3]f32,
    color: Color,
};

const TextData = struct {
    position: [3]f32,
    color: Color,
    buffer: [128]u8,
    len: usize,
};

pub const Renderer2D = struct {
    const Self = @This();

    // TODO: make this so it is only declared in debug-builds?
    // xxx
    pub var Instance: *Renderer2D = undefined;
    // xxx

    pub const Layers = struct {
        pub const Min = 0;
        pub const Max = 1000;

        pub const World = 0; // 0..99
        pub const Tools = 100; // 100..199
        pub const ZBox = 200; // ...
        pub const Debug = 300;
    };

    allocator: std.mem.Allocator,
    content_manager: *ContentManager,

    materials: Materials,
    material_vertex_buffers: std.AutoArrayHashMap(MaterialRef, *DynamicVertexBuffer(CommonVertexData)),

    point_vertex_buffer: DynamicVertexBuffer(PointVertexData),
    line_vertex_buffer: DynamicVertexBuffer(LineVertexData),

    point_shader: *Shader,
    line_shader: *Shader,

    text_data: std.ArrayList(TextData),

    time: f32 = 0,

    pub fn init(
        self: *Self,
        allocator: std.mem.Allocator,
        content_manager: *ContentManager,
    ) !void {
        Self.Instance = self;

        // TODO: move to contentmanager?
        // Load materials.
        const material_defs = try MaterialDefs.load(allocator);
        defer material_defs.deinit();
        const materials = try Materials.init(&material_defs, allocator, content_manager);

        // Create dynamic vertex buffer for each material.
        var material_vertex_buffers = std.AutoArrayHashMap(MaterialRef, *DynamicVertexBuffer(CommonVertexData)).init(allocator);
        for (materials.materials, 0..) |_, material_index| {
            const material_ref = MaterialRef{
                .index = material_index,
            };

            // Note: We need a stable pointer to the dynamic vertex buffer so it can be stored in the hashmap.
            const vertex_buffer = try allocator.create(DynamicVertexBuffer(CommonVertexData));
            vertex_buffer.* = try .init(allocator);

            try material_vertex_buffers.putNoClobber(material_ref, vertex_buffer);
        }

        // TODO: what about these? >> convert to material?
        const point_shader = try content_manager.getShader("point.vs", "point.fs");
        const line_shader = try content_manager.getShader("line.vs", "line.fs");

        // -----

        self.* = Renderer2D{
            .allocator = allocator,
            .content_manager = content_manager,

            .materials = materials,
            .material_vertex_buffers = material_vertex_buffers,

            .point_vertex_buffer = try .init(allocator),
            .line_vertex_buffer = try .init(allocator),

            .point_shader = point_shader,
            .line_shader = line_shader,

            .text_data = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // TODO order

        var iter = self.material_vertex_buffers.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }

        self.material_vertex_buffers.deinit();
        self.materials.deinit();

        self.text_data.deinit();

        self.point_vertex_buffer.deinit();
        self.line_vertex_buffer.deinit();
    }

    pub fn getMaterial(self: Self, name: []const u8) MaterialRef {
        return self.materials.getRefByName(name);
    }

    fn getBufferForMaterial(self: *Self, material: MaterialRef) *DynamicVertexBuffer(CommonVertexData) {
        if (self.material_vertex_buffers.get(material)) |buffer| {
            return buffer;
        }

        std.log.err("No dynamic vertex buffer for material: {any}", .{material});
        @panic("No dynamic vertex buffer for material");
    }

    inline fn getLayerZ(layer: i32) f32 {
        std.debug.assert(layer >= Layers.Min);
        std.debug.assert(layer < Layers.Max);

        const v: f32 = @floatFromInt(layer);
        const z: f32 = -10.0 + v * 0.01;
        return z;
    }

    //
    // Add-functions for points & lines
    //

    pub fn addPoint(
        self: *Self,
        position: vec2,
        size: f32,
        layer: i32,
        color: Color,
    ) void {
        const z = getLayerZ(layer);

        self.point_vertex_buffer.addVertex(.{
            .position = [3]f32{ position.x, position.y, z },
            .color = color,
            .size = size,
            .scale = 1.0, // size is worldpos
        });
    }

    pub fn addPointWithPixelSize(
        self: *Self,
        position: vec2,
        size: f32,
        layer: i32,
        color: Color,
    ) void {
        const z = getLayerZ(layer);

        self.point_vertex_buffer.addVertex(.{
            .position = [3]f32{ position.x, position.y, z },
            .color = color,
            .size = size,
            .scale = 0.0, // size is pixels
        });
    }

    pub fn addLine(
        self: *Self,
        p1: vec2,
        p2: vec2,
        layer: i32,
        color: Color,
    ) void {
        const z = getLayerZ(layer);

        self.line_vertex_buffer.addVertex(.{
            .position = [3]f32{ p1.x, p1.y, z },
            .color = color,
        });
        self.line_vertex_buffer.addVertex(.{
            .position = [3]f32{ p2.x, p2.y, z },
            .color = color,
        });
    }

    pub fn addCircle(
        self: *Self,
        center: vec2,
        radius: f32,
        layer: i32,
        color: Color,
    ) void {
        const segments: usize = 32;
        const segment_angle: f32 = 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));

        var prev_point = center.add(vec2.init(radius, 0));
        for (1..segments + 1) |i| {
            const angle = segment_angle * @as(f32, @floatFromInt(i));
            const point = center.add(vec2{
                .x = std.math.cos(angle) * radius,
                .y = std.math.sin(angle) * radius,
            });
            self.addLine(prev_point, point, layer, color);
            prev_point = point;
        }
    }

    //
    // Add-functions for triangles / quads
    //

    pub fn addTriangleP(
        self: *Self,
        pos: [3]vec2,
        layer: i32,
        material: MaterialRef,
    ) void {
        const z = getLayerZ(layer);

        const buffer = self.getBufferForMaterial(material);

        buffer.addVertex(.{ .position = [3]f32{ pos[0].x, pos[0].y, z } });
        buffer.addVertex(.{ .position = [3]f32{ pos[1].x, pos[1].y, z } });
        buffer.addVertex(.{ .position = [3]f32{ pos[2].x, pos[2].y, z } });
    }

    pub fn addTrianglePC(
        self: *Self,
        pos: [3]vec2,
        layer: i32,
        color: Color,
        material: MaterialRef,
    ) void {
        const z = getLayerZ(layer);

        const buffer = self.getBufferForMaterial(material);

        buffer.addVertex(.{ .position = [3]f32{ pos[0].x, pos[0].y, z }, .color = color });
        buffer.addVertex(.{ .position = [3]f32{ pos[1].x, pos[1].y, z }, .color = color });
        buffer.addVertex(.{ .position = [3]f32{ pos[2].x, pos[2].y, z }, .color = color });
    }

    pub fn addTrianglePU(
        self: *Self,
        pos: [3]vec2,
        uv: [3]vec2,
        layer: i32,
        material: MaterialRef,
    ) void {
        const z = getLayerZ(layer);

        const buffer = self.getBufferForMaterial(material);

        buffer.addVertex(.{ .position = [3]f32{ pos[0].x, pos[0].y, z }, .tex_coord = uv[0] });
        buffer.addVertex(.{ .position = [3]f32{ pos[1].x, pos[1].y, z }, .tex_coord = uv[1] });
        buffer.addVertex(.{ .position = [3]f32{ pos[2].x, pos[2].y, z }, .tex_coord = uv[2] });
    }

    pub fn addQuadP(
        self: *Self,
        points: [4]vec2,
        layer: i32,
        material: MaterialRef,
    ) void {
        const z = getLayerZ(layer);

        const buffer = self.getBufferForMaterial(material);

        // Note: using ccw because that's what box2d uses
        const p_bottom_left = points[0];
        const p_bottom_right = points[1];
        const p_top_right = points[2];
        const p_top_left = points[3];

        const uv_bottom_left = vec2.init(0, 0);
        const uv_bottom_right = vec2.init(1, 0);
        const uv_top_right = vec2.init(1, 1);
        const uv_top_left = vec2.init(0, 1);

        // 1
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_right.x, p_bottom_right.y, z }, .tex_coord = uv_bottom_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .tex_coord = uv_top_right });

        // 2
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .tex_coord = uv_top_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_left.x, p_top_left.y, z }, .tex_coord = uv_top_left });
    }

    pub fn addQuadPC(
        self: *Self,
        points: [4]vec2,
        layer: i32,
        color: Color,
        material: MaterialRef,
    ) void {
        const z = getLayerZ(layer);

        const buffer = self.getBufferForMaterial(material);

        // Note: using ccw because that's what box2d uses
        const p_bottom_left = points[0];
        const p_bottom_right = points[1];
        const p_top_right = points[2];
        const p_top_left = points[3];

        const uv_bottom_left = vec2.init(0, 0);
        const uv_bottom_right = vec2.init(1, 0);
        const uv_top_right = vec2.init(1, 1);
        const uv_top_left = vec2.init(0, 1);

        // 1
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .color = color, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_right.x, p_bottom_right.y, z }, .color = color, .tex_coord = uv_bottom_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .color = color, .tex_coord = uv_top_right });

        // 2
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .color = color, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .color = color, .tex_coord = uv_top_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_left.x, p_top_left.y, z }, .color = color, .tex_coord = uv_top_left });
    }

    pub fn addQuadPU(
        self: *Self,
        points: [4]vec2,
        uv: [4]vec2,
        layer: i32,
        material: MaterialRef,
    ) void {
        const z = getLayerZ(layer);

        const buffer = self.getBufferForMaterial(material);

        // Note: using ccw because that's what box2d uses
        const p_bottom_left = points[0];
        const p_bottom_right = points[1];
        const p_top_right = points[2];
        const p_top_left = points[3];

        const uv_bottom_left = uv[0];
        const uv_bottom_right = uv[1];
        const uv_top_right = uv[2];
        const uv_top_left = uv[3];

        // 1
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_right.x, p_bottom_right.y, z }, .tex_coord = uv_bottom_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .tex_coord = uv_top_right });

        // 2
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .tex_coord = uv_top_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_left.x, p_top_left.y, z }, .tex_coord = uv_top_left });
    }

    pub fn addQuadPCU(
        self: *Self,
        points: [4]vec2,
        color: Color,
        uv: [4]vec2,
        layer: i32,
        material: MaterialRef,
    ) void {
        const z = getLayerZ(layer);

        const buffer = self.getBufferForMaterial(material);

        // Note: using ccw because that's what box2d uses
        const p_bottom_left = points[0];
        const p_bottom_right = points[1];
        const p_top_right = points[2];
        const p_top_left = points[3];

        const uv_bottom_left = uv[0];
        const uv_bottom_right = uv[1];
        const uv_top_right = uv[2];
        const uv_top_left = uv[3];

        // 1
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .color = color, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_right.x, p_bottom_right.y, z }, .color = color, .tex_coord = uv_bottom_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .color = color, .tex_coord = uv_top_right });

        // 2
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .color = color, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .color = color, .tex_coord = uv_top_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_left.x, p_top_left.y, z }, .color = color, .tex_coord = uv_top_left });
    }

    pub fn addQuadRepeatingP(
        self: *Self,
        points: [4]vec2,
        layer: i32,
        tex_scaling: f32,
        material: MaterialRef,
    ) void {
        const z = getLayerZ(layer);

        const buffer = self.getBufferForMaterial(material);

        // Note: using ccw because that's what box2d uses
        const p_bottom_left = points[0];
        const p_bottom_right = points[1];
        const p_top_right = points[2];
        const p_top_left = points[3];

        const uv_bottom_left = points[0].scale(tex_scaling);
        const uv_bottom_right = points[1].scale(tex_scaling);
        const uv_top_right = points[2].scale(tex_scaling);
        const uv_top_left = points[3].scale(tex_scaling);

        // 1
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_right.x, p_bottom_right.y, z }, .tex_coord = uv_bottom_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .tex_coord = uv_top_right });

        // 2
        buffer.addVertex(.{ .position = [3]f32{ p_bottom_left.x, p_bottom_left.y, z }, .tex_coord = uv_bottom_left });
        buffer.addVertex(.{ .position = [3]f32{ p_top_right.x, p_top_right.y, z }, .tex_coord = uv_top_right });
        buffer.addVertex(.{ .position = [3]f32{ p_top_left.x, p_top_left.y, z }, .tex_coord = uv_top_left });
    }

    //
    // Add-functions for more complex shapes (made out of triangles or quads)
    //

    pub fn addSolidCircle(
        self: *Self,
        center: vec2,
        radius: f32,
        layer: i32,
        color: Color,
        material: MaterialRef,
    ) void {
        const segments: usize = 32;
        const segment_angle: f32 = 2.0 * std.math.pi / @as(f32, @floatFromInt(segments));

        var prev_point = center.add(vec2.init(radius, 0));
        for (1..segments + 1) |i| {
            const angle = segment_angle * @as(f32, @floatFromInt(i));
            const point = center.add(vec2{
                .x = std.math.cos(angle) * radius,
                .y = std.math.sin(angle) * radius,
            });

            // TODO calculate UV

            self.addTrianglePC([3]vec2{ center, prev_point, point }, layer, color, material);

            prev_point = point;
        }
    }

    //
    // Add-functions for text
    //

    pub fn addText(
        self: *Self,
        position: vec2,
        layer: i32,
        color: Color,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        const z = getLayerZ(layer);

        self.text_data.append(TextData{
            .position = [3]f32{ position.x, position.y, z },
            .color = color,
            .buffer = undefined,
            .len = 0,
        }) catch unreachable;

        var data: *TextData = &self.text_data.items[self.text_data.items.len - 1];

        // copy to buffer
        const s = std.fmt.bufPrintZ(&data.buffer, fmt, args) catch unreachable;

        data.len = s.len;
    }

    //
    // ...
    //

    pub fn render(self: *Self, camera: *Camera, dt: f32) void {
        const model: zm.Mat = zm.identity();
        const view = camera.view;
        const projection = camera.projection;

        self.time += dt;

        const viewport_size = [2]f32{
            @floatFromInt(camera.viewport_size[0]),
            @floatFromInt(camera.viewport_size[1]),
        };

        // material-based rendering
        var iter = self.material_vertex_buffers.iterator();
        while (iter.next()) |entry| {
            const mat_ref: MaterialRef = entry.key_ptr.*;
            const dynamic_vertex_buffer: *DynamicVertexBuffer(CommonVertexData) = entry.value_ptr.*;

            const vertex_count = dynamic_vertex_buffer.getVertexCount();
            if (vertex_count == 0) continue;

            // upload data
            dynamic_vertex_buffer.upload();
            defer dynamic_vertex_buffer.clear();

            // set material
            const mat: *const Material = self.materials.getMaterial(mat_ref); // TODO xxx xxx xxx
            self.bindMaterial(mat, camera);
            defer self.unbindMaterial(mat);

            // set vertex array
            dynamic_vertex_buffer.bind();
            defer dynamic_vertex_buffer.unbind();

            // render
            gl.drawArrays(gl.TRIANGLES, 0, @intCast(vertex_count));
        }

        // lines
        const line_vertex_count = self.line_vertex_buffer.getVertexCount();
        if (line_vertex_count > 0) {
            // upload data
            self.line_vertex_buffer.upload();
            defer self.line_vertex_buffer.clear();

            // set material
            self.line_shader.bind();
            defer self.line_shader.unbind();

            self.line_shader.setMat4("uModel", model);
            self.line_shader.setMat4("uView", view);
            self.line_shader.setMat4("uProjection", projection);

            // set vertex array
            self.line_vertex_buffer.bind();
            defer self.line_vertex_buffer.unbind();

            // render
            gl.drawArrays(gl.LINES, 0, @intCast(line_vertex_count));
        }

        // points
        const point_vertex_count = self.point_vertex_buffer.getVertexCount();
        if (point_vertex_count > 0) {
            // upload data
            self.point_vertex_buffer.upload();
            defer self.point_vertex_buffer.clear();

            // set material
            self.point_shader.bind();
            defer self.point_shader.unbind();

            self.point_shader.setMat4("uModel", model);
            self.point_shader.setMat4("uView", view);
            self.point_shader.setMat4("uProjection", projection);
            self.point_shader.setVec2("uViewportSize", viewport_size);

            gl.enable(gl.PROGRAM_POINT_SIZE);
            defer gl.disable(gl.PROGRAM_POINT_SIZE);

            // set vertex array
            self.point_vertex_buffer.bind();
            defer self.point_vertex_buffer.unbind();

            // render
            gl.drawArrays(gl.POINTS, 0, @intCast(point_vertex_count));
        }
    }

    pub fn renderToZGui(self: *Self, camera: *Camera) void {
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
                const world_pos = vec2.init(text_data.position[0], text_data.position[1]);
                const screen_pos = camera.worldToScreen(world_pos);

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

    fn bindMaterial(self: *Self, mat: *const Material, camera: *const Camera) void {
        const model: zm.Mat = zm.identity();
        const view = camera.view;
        const projection = camera.projection;

        mat.shader.bind();

        mat.shader.setMat4("uModel", model);
        mat.shader.setMat4("uView", view);
        mat.shader.setMat4("uProjection", projection);

        mat.shader.trySetFloat("uTime", self.time); // don't report error

        if (mat.textures.len > 0) {
            // bind texture(s)
            for (mat.textures, 0..) |texture, texture_index| {
                gl.activeTexture(gl.TEXTURE0 + @as(c_uint, @intCast(texture_index)));
                gl.bindTexture(gl.TEXTURE_2D, texture.id);
            }
            gl.activeTexture(gl.TEXTURE0); // activate unit0 by default

            // assign texture-unit(s) to shader uniforms
            if (mat.textures.len == 1) {
                mat.shader.setInt("uTexture", 0); // GL_TEXTURE0
            } else {
                var buffer: [128]u8 = undefined;
                for (0..mat.textures.len) |texture_index| {
                    const s = std.fmt.bufPrintZ(&buffer, "uTextures[{d}]", .{texture_index}) catch unreachable;
                    mat.shader.setInt(s, @intCast(texture_index));
                    // uTextures[0] = GL_TEXTURE0
                    // uTextures[1] = GL_TEXTURE1
                    // ...
                }
            }
        }
    }

    fn unbindMaterial(self: *Self, mat: *const Material) void {
        _ = self;

        if (mat.textures.len > 0) {
            for (0..mat.textures.len) |texture_index| {
                gl.activeTexture(gl.TEXTURE0 + @as(c_uint, @intCast(texture_index)));
                gl.bindTexture(gl.TEXTURE_2D, 0);
            }
            gl.activeTexture(gl.TEXTURE0); // activate unit0 by default
        }

        mat.shader.unbind();
    }
};
