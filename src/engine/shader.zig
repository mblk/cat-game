const std = @import("std");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zm = @import("zmath");

pub const ShaderError = error{
    VertexShaderError,
    FragmentShaderError,
    ProgramLinkError,
    OutOfMemory,
};

pub const Shader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    id: c_uint,
    vs_name: []const u8,
    fs_name: []const u8,

    pub fn init(
        self: *Self,
        allocator: std.mem.Allocator,
        vs_name: []const u8,
        fs_name: []const u8,
        vertex_shader_source: [:0]const u8,
        fragment_shader_source: [:0]const u8,
    ) ShaderError!void {
        //
        const id = try compileProgram(vs_name, fs_name, vertex_shader_source, fragment_shader_source);

        const vs_name_copy = try allocator.dupe(u8, vs_name);
        const fs_name_copy = try allocator.dupe(u8, fs_name);

        self.* = .{
            .allocator = allocator,
            .id = id,
            .vs_name = vs_name_copy,
            .fs_name = fs_name_copy,
        };
    }

    pub fn reload(
        self: *Self,
        vertex_shader_source: [:0]const u8,
        fragment_shader_source: [:0]const u8,
    ) ShaderError!void {
        std.log.info("reloading shader {s}+{s} ...", .{ self.vs_name, self.fs_name });

        const id = try compileProgram(self.vs_name, self.fs_name, vertex_shader_source, fragment_shader_source);

        // only if reload was successul
        gl.deleteProgram(self.id);
        self.id = id;
    }

    pub fn deinit(self: *Self) void {
        //
        gl.deleteProgram(self.id);

        self.allocator.free(self.vs_name);
        self.allocator.free(self.fs_name);
    }

    fn compileProgram(
        vs_name: []const u8,
        fs_name: []const u8,
        vertex_shader_source: [:0]const u8,
        fragment_shader_source: [:0]const u8,
    ) ShaderError!c_uint {

        // vertex shader
        const vertex_shader = gl.createShader(gl.VERTEX_SHADER);
        defer gl.deleteShader(vertex_shader);

        gl.shaderSource(vertex_shader, 1, @ptrCast(&vertex_shader_source), 0);
        gl.compileShader(vertex_shader);

        {
            var success: c_int = undefined;
            gl.getShaderiv(vertex_shader, gl.COMPILE_STATUS, &success);

            if (success == 0) {
                //var infoLogLength: c_int = undefined;
                //gl.getShaderiv(vertex_shader, gl.INFO_LOG_LENGTH, &infoLogLength);
                //std.log.err("vertex shader error: {d}", .{infoLogLength});

                var info_log: [512]u8 = [_]u8{0} ** 512;
                gl.getShaderInfoLog(vertex_shader, info_log.len, 0, &info_log);
                std.log.err("error in vertex shader {s}: {s}", .{ vs_name, info_log });
                return ShaderError.VertexShaderError;
            }
        }

        // fragment shader
        const fragment_shader = gl.createShader(gl.FRAGMENT_SHADER);
        defer gl.deleteShader(fragment_shader);

        gl.shaderSource(fragment_shader, 1, @ptrCast(&fragment_shader_source), 0);
        gl.compileShader(fragment_shader);

        {
            var success: c_int = undefined;
            gl.getShaderiv(fragment_shader, gl.COMPILE_STATUS, &success);

            if (success == 0) {
                var info_log: [512]u8 = [_]u8{0} ** 512;
                gl.getShaderInfoLog(fragment_shader, info_log.len, 0, &info_log);
                std.log.err("error in fragment shader {s}: {s}\n", .{ fs_name, info_log });
                return ShaderError.FragmentShaderError;
            }
        }

        // program
        const shader_program: c_uint = gl.createProgram();

        gl.attachShader(shader_program, vertex_shader);
        gl.attachShader(shader_program, fragment_shader);
        gl.linkProgram(shader_program);

        {
            var success: c_int = undefined;
            gl.getProgramiv(shader_program, gl.LINK_STATUS, &success);

            if (success == 0) {
                var info_log: [512]u8 = [_]u8{0} ** 512;
                gl.getProgramInfoLog(shader_program, info_log.len, 0, &info_log);
                std.log.err("link error in program {s}+{s}: {s}\n", .{ vs_name, fs_name, info_log });
                return ShaderError.ProgramLinkError;
            }
        }

        return shader_program;
    }

    pub fn bind(self: Shader) void {
        gl.useProgram(self.id);
    }

    pub fn unbind(self: Shader) void {
        _ = self;
        gl.useProgram(0);
    }

    pub fn setBool(self: Shader, name: [:0]const u8, value: bool) void {
        const loc: c_int = gl.getUniformLocation(self.id, name.ptr);

        if (loc < 0) {
            std.log.err("uniform not found: {s}", .{name});
            return;
        }

        gl.uniform1i(loc, @intFromBool(value));
    }

    pub fn setInt(self: Shader, name: [:0]const u8, value: i32) void {
        const loc: c_int = gl.getUniformLocation(self.id, name.ptr);

        if (loc < 0) {
            std.log.err("uniform not found: {s}", .{name});
            return;
        }

        //std.log.info("loc={d} {s} = {d}", .{ loc, name, value });

        gl.uniform1i(loc, @intCast(value));
    }

    pub fn setUInt(self: Shader, name: [:0]const u8, value: u32) void {
        const loc: c_int = gl.getUniformLocation(self.id, name.ptr);

        if (loc < 0) {
            std.log.err("uniform not found: {s}", .{name});
            return;
        }

        gl.uniform1ui(loc, @intCast(value));
    }

    pub fn setFloat(self: Shader, name: [:0]const u8, value: f32) void {
        const loc: c_int = gl.getUniformLocation(self.id, name.ptr);

        if (loc < 0) {
            std.log.err("uniform not found: {s}", .{name});
            return;
        }

        gl.uniform1f(loc, value);
    }

    pub fn setVec2(self: Shader, name: [:0]const u8, value: [2]f32) void {
        const loc: c_int = gl.getUniformLocation(self.id, name.ptr);

        if (loc < 0) {
            std.log.err("uniform not found: {s}", .{name});
            return;
        }

        gl.uniform2f(loc, value[0], value[1]);
    }

    pub fn setVec3(self: Shader, name: [:0]const u8, value: [3]f32) void {
        const loc: c_int = gl.getUniformLocation(self.id, name.ptr);

        if (loc < 0) {
            std.log.err("uniform not found: {s}", .{name});
            return;
        }

        gl.uniform3f(loc, value[0], value[1], value[2]);
    }

    pub fn setVec4(self: Shader, name: [:0]const u8, value: [4]f32) void {
        const loc: c_int = gl.getUniformLocation(self.id, name.ptr);

        if (loc < 0) {
            std.log.err("uniform not found: {s}", .{name});
            return;
        }

        gl.uniform4f(loc, value[0], value[1], value[2], value[3]);
    }

    //pub fn setMat4(self: Shader, name: [:0]const u8, value: [16]f32) void { // TODO by value vs by reference ?
    pub fn setMat4(self: Shader, name: [:0]const u8, value: zm.Mat) void {
        const loc: c_int = gl.getUniformLocation(self.id, name.ptr);

        if (loc < 0) {
            std.log.err("uniform not found: {s}", .{name});
            return;
        }

        var mem: [16]f32 = undefined;

        zm.storeMat(&mem, value);

        gl.uniformMatrix4fv(loc, 1, gl.FALSE, &mem);
    }
};
