const std = @import("std");
const zgui = @import("zgui");
const gl = @import("zopengl").bindings;

const engine = @import("../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

pub fn getScene() engine.SceneDescriptor {
    return engine.SceneDescriptor{
        .id = .ShaderToy,
        .name = "shader_toy",
        .load = ShaderToyScene.load,
        .unload = ShaderToyScene.unload,
        .update = ShaderToyScene.update,
        .render = ShaderToyScene.render,
        .draw_ui = ShaderToyScene.drawUi,
    };
}

const ShaderToyScene = struct {
    const Self = @This();

    const initial_color = [3]f32{ 1.0, 1.0, 1.0 };
    const initial_uv_min = [2]f32{ 0.0, 0.0 };
    const initial_uv_max = [2]f32{ 1.0, 1.0 };

    camera: engine.Camera,
    renderer: engine.Renderer2D,

    selected_material_index: usize = 0,
    color: [3]f32 = initial_color,
    uv_min: [2]f32 = initial_uv_min,
    uv_max: [2]f32 = initial_uv_max,

    fn load(context: *const engine.LoadContext) !*anyopaque {
        const self = try context.allocator.create(Self);

        self.* = .{
            .camera = engine.Camera.create(),
            .renderer = undefined,
        };

        try self.renderer.init(context.allocator, context.content_manager);

        return self;
    }

    fn unload(self_ptr: *anyopaque, context: *const engine.UnloadContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.renderer.deinit();

        context.allocator.destroy(self);
    }

    fn update(self_ptr: *anyopaque, context: *const engine.UpdateContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.camera.setViewportSize(context.viewport_size);

        if (context.input_state.consumeMouseScroll()) |scroll| {
            self.camera.changeZoom(-scroll);
        }

        if (context.input_state.consumeKeyDownEvent(.backspace)) {
            self.camera.reset();
        }

        if (context.input_state.getKeyState(.left)) self.camera.changeOffset(vec2.init(-100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.right)) self.camera.changeOffset(vec2.init(100.0 * context.dt, 0.0));
        if (context.input_state.getKeyState(.up)) self.camera.changeOffset(vec2.init(0.0, 100.0 * context.dt));
        if (context.input_state.getKeyState(.down)) self.camera.changeOffset(vec2.init(0.0, -100.0 * context.dt));

        if (context.input_state.consumeKeyDownEvent(.escape)) {
            if (context.input_state.getKeyState(.left_shift)) {
                context.scene_commands.new_scene = .Menu;
            } else {
                context.scene_commands.exit = true;
            }
        }
    }

    fn render(self_ptr: *anyopaque, context: *const engine.RenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        const s = 50.0;
        const hs = s * 0.5;

        const mat_ref = engine.MaterialRef{
            .index = self.selected_material_index,
        };

        const color = Color.initFloat(self.color[0], self.color[1], self.color[2], 1.0);

        self.renderer.addQuadPCU(
            [_]vec2{
                vec2.init(-hs, -hs),
                vec2.init(hs, -hs),
                vec2.init(hs, hs),
                vec2.init(-hs, hs),
            },
            color,
            [_]vec2{
                vec2.init(self.uv_min[0], self.uv_min[1]),
                vec2.init(self.uv_max[0], self.uv_min[1]),
                vec2.init(self.uv_max[0], self.uv_max[1]),
                vec2.init(self.uv_min[0], self.uv_max[1]),
            },
            0,
            mat_ref,
        );

        self.renderer.addLine(vec2.init(-hs, -hs), vec2.init(hs, -hs), 1, Color.white);
        self.renderer.addLine(vec2.init(-hs, hs), vec2.init(hs, hs), 1, Color.white);
        self.renderer.addLine(vec2.init(-hs, -hs), vec2.init(-hs, hs), 1, Color.white);
        self.renderer.addLine(vec2.init(hs, -hs), vec2.init(hs, hs), 1, Color.white);

        self.renderer.render(&self.camera, context.dt);
    }

    fn drawUi(self_ptr: *anyopaque, context: *const engine.DrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = context;

        var buffer: [128]u8 = undefined;

        zgui.setNextWindowPos(.{ .x = 10.0, .y = 300.0, .cond = .appearing });
        //zgui.setNextWindowSize(.{ .w = 400, .h = 400 });

        if (zgui.begin("Shader toy", .{ .flags = .{ .always_auto_resize = true } })) {
            zgui.text("Materials:", .{});

            if (zgui.beginListBox("##materials", .{ .w = 0, .h = 200 })) {
                for (self.renderer.materials.materials, 0..) |m, i| {
                    const s = std.fmt.bufPrintZ(&buffer, "{s}", .{m.name}) catch unreachable;

                    if (zgui.selectable(s, .{ .selected = self.selected_material_index == i })) {
                        self.selected_material_index = i;
                    }
                }

                zgui.endListBox();
            }

            if (zgui.button("reset", .{})) {
                self.color = initial_color;
                self.uv_min = initial_uv_min;
                self.uv_max = initial_uv_max;
            }

            _ = zgui.colorEdit3("Color", .{
                .col = &self.color,
            });

            _ = zgui.dragFloat2("UV Min", .{
                .v = &self.uv_min,

                .speed = 0.1,
                .min = -10,
                .max = 0,
                .cfmt = "%.1f",
            });

            _ = zgui.dragFloat2("UV Max", .{
                .v = &self.uv_max,

                .speed = 0.1,
                .min = 0,
                .max = 10,
                .cfmt = "%.1f",
            });

            const shader = self.renderer.materials.materials[self.selected_material_index].shader;

            zgui.separator();
            zgui.text("Shader: {s} {s}", .{ shader.vs_name, shader.fs_name });

            var attr_count: i32 = 0;
            var uniform_count: i32 = 0;

            gl.getProgramiv(shader.id, gl.ACTIVE_ATTRIBUTES, &attr_count);
            gl.getProgramiv(shader.id, gl.ACTIVE_UNIFORMS, &uniform_count);

            zgui.text("attr count: {d}", .{attr_count});
            zgui.text("uniform count: {d}", .{uniform_count});

            for (0..@as(usize, @intCast(attr_count))) |i| {
                var length: gl.Sizei = undefined;
                var size: gl.Int = undefined;
                var attr_type: gl.Enum = undefined;

                gl.getActiveAttrib(
                    shader.id,
                    @as(c_uint, @intCast(i)),
                    buffer.len,
                    &length,
                    &size,
                    &attr_type,
                    &buffer,
                );

                const name: []u8 = buffer[0..@as(usize, @intCast(length))];

                zgui.text("attr '{s}' size={d} type={d}", .{ name, size, attr_type });
            }

            for (0..@as(usize, @intCast(uniform_count))) |i| {
                var length: gl.Sizei = undefined;
                var size: gl.Int = undefined;
                var uniform_type: gl.Enum = undefined;

                _ = gl.getActiveUniform(
                    shader.id,
                    @as(c_uint, @intCast(i)),
                    buffer.len,
                    &length,
                    &size,
                    &uniform_type,
                    &buffer,
                );

                const name: []u8 = buffer[0..@as(usize, @intCast(length))];

                zgui.text("uniform '{s}' size={d} type={d}", .{ name, size, uniform_type });
            }
        }
        zgui.end();
    }
};
