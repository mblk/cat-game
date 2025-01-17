const std = @import("std");

const zopengl = @import("zopengl");
const gl = zopengl.bindings;

const vec2 = @import("math.zig").vec2;
const Color = @import("math.zig").Color;

pub fn DynamicVertexBuffer(comptime T: type) type {

    // TODO assert that T is struct

    return struct {
        const Self = @This();
        const initial_capacity = 1024;

        vbo: c_uint,
        vao: c_uint,
        data: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) !Self {

            // data buffer
            var data = try std.ArrayList(T).initCapacity(allocator, initial_capacity);
            errdefer data.deinit();

            // vertex array object
            var vao: c_uint = undefined;
            gl.genVertexArrays(1, &vao);

            // vertex buffer object
            var vbo: c_uint = undefined;
            gl.genBuffers(1, &vbo);

            gl.bindVertexArray(vao);
            {
                gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
                gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(T) * initial_capacity, null, gl.DYNAMIC_DRAW);

                configureVertexAttributes();

                gl.bindBuffer(gl.ARRAY_BUFFER, 0); // TODO not sure
            }
            gl.bindVertexArray(0);

            return Self{
                .vbo = vbo,
                .vao = vao,
                .data = data,
            };
        }

        fn configureVertexAttributes() void {
            std.log.info("configureVertexAttributes: {s}", .{@typeName(T)});

            const stride = @sizeOf(T);
            std.log.info(" stride: {d}", .{stride});

            var index: c_uint = 0;
            inline for (@typeInfo(T).@"struct".fields) |field_info| {
                std.log.info(" attr-{d}: name={s} type={s}", .{ index, field_info.name, @typeName(field_info.type) });

                const offset = @offsetOf(T, field_info.name);
                const offset_ptr: [*c]c_uint = @ptrFromInt(offset);
                const d = getVertexAttributeData(field_info.type);

                std.log.info("  size={d} type={d} norm={d} offset={d}", .{ d.size, d.type, d.norm, offset });

                gl.vertexAttribPointer(index, d.size, d.type, d.norm, stride, offset_ptr);
                gl.enableVertexAttribArray(index);

                index += 1;
            }
        }

        fn getVertexAttributeData(comptime AttributeType: type) struct {
            size: c_int,
            type: c_uint,
            norm: u8,
        } {
            if (AttributeType == f32) {
                return .{
                    .size = 1,
                    .type = gl.FLOAT,
                    .norm = gl.FALSE,
                };
            }

            if (AttributeType == vec2) {
                return .{
                    .size = 2,
                    .type = gl.FLOAT,
                    .norm = gl.FALSE,
                };
            }

            if (AttributeType == Color) {
                return .{
                    .size = 3,
                    .type = gl.UNSIGNED_BYTE,
                    .norm = gl.TRUE,
                };
            }

            std.log.err("unknown vertex attribute type: {s}", .{@typeName(AttributeType)});
            @panic("unknown vertex attribute type");
        }

        pub fn deinit(self: Self) void {
            //
            gl.deleteVertexArrays(1, &self.vao);
            gl.deleteBuffers(1, &self.vbo);

            self.data.deinit();
        }

        pub fn bind(self: Self) void {
            //
            gl.bindVertexArray(self.vao);
        }

        pub fn unbind(self: Self) void {
            _ = self;
            //
            gl.bindVertexArray(0);
        }

        pub fn getVertexCount(self: Self) usize {
            return self.data.items.len;
        }

        pub fn upload(self: *Self) void {
            std.debug.assert(self.data.items.len > 0);

            gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);

            gl.bufferData(
                gl.ARRAY_BUFFER,
                @intCast(@sizeOf(T) * self.data.items.len),
                self.data.items.ptr,
                gl.DYNAMIC_DRAW,
            );

            gl.bindBuffer(gl.ARRAY_BUFFER, 0);
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.data.items.len > 0);

            self.data.clearRetainingCapacity();
        }

        pub fn addVertex(self: *Self, vertex: T) void {
            self.data.append(vertex) catch unreachable;
        }
    };
}
