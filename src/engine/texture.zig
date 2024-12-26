const std = @import("std");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zstbi = @import("zstbi");

pub const TextureError = error{
    ParseError,
};

pub const Texture = struct {
    id: c_uint,

    pub fn loadFromMemory(data: []const u8) TextureError!Texture {
        //
        var image = zstbi.Image.loadFromMemory(data, 0) catch |e| {
            std.log.err("loadfromMemory faild: {any}", .{e});
            return TextureError.ParseError;
        };
        defer image.deinit();

        std.log.info("image: w={d} h={d} components={d} bytes_per_comp={d} byter_per_row={d} is_hdr={any}", .{
            image.width,
            image.height,
            image.num_components,
            image.bytes_per_component,
            image.bytes_per_row,
            image.is_hdr,
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

        return Texture{
            .id = id,
        };
    }

    pub fn free(self: *Texture) void {
        //
        gl.deleteTextures(1, &self.id);
    }

    // TODO bind/unbind-etc?
};
