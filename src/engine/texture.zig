const std = @import("std");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zstbi = @import("zstbi");

pub const TextureError = error{
    ParseError,
    OutOfMemory,
};

pub const Texture = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    id: c_uint,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, data: []const u8) TextureError!Texture {
        //
        const name_copy = try allocator.dupe(u8, name);
        const id = try loadFromMemory(name, data);

        return Texture{
            .allocator = allocator,
            .name = name_copy,
            .id = id,
        };
    }

    pub fn reload(self: *Self, data: []const u8) TextureError!void {
        std.log.info("reloading texture {s} ...", .{self.name});
        //
        const id = try loadFromMemory(self.name, data);

        // Only if load was successful
        gl.deleteTextures(1, &self.id);
        self.id = id;
    }

    pub fn free(self: *Texture) void {
        //
        gl.deleteTextures(1, &self.id);

        self.allocator.free(self.name);
    }

    fn loadFromMemory(name: []const u8, data: []const u8) !c_uint {
        //
        var image = zstbi.Image.loadFromMemory(data, 0) catch |e| {
            std.log.err("loadfromMemory failed: {any}", .{e});
            return TextureError.ParseError;
        };
        defer image.deinit();

        std.log.info("{s}: size {d}x{d} components {d}x{d}", .{
            name,
            image.width,
            image.height,
            image.num_components,
            image.bytes_per_component,
        });

        // Create and bind texture1 resource
        var id: c_uint = undefined;

        gl.genTextures(1, &id);
        gl.bindTexture(gl.TEXTURE_2D, id);

        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);

        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            @intCast(image.width),
            @intCast(image.height),
            0,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            @ptrCast(image.data),
        );
        gl.generateMipmap(gl.TEXTURE_2D);

        gl.bindTexture(gl.TEXTURE_2D, 0);

        return id;
    }

    // TODO bind/unbind-etc?

    pub fn bind(self: Self) void {
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, self.id);
    }

    pub fn unbind(self: Self) void {
        _ = self;
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, 0);
    }
};
