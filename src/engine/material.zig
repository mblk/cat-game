const std = @import("std");

const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const zm = @import("zmath");
const zgui = @import("zgui");

const vec2 = @import("math.zig").vec2;
const Color = @import("math.zig").Color;

const ContentManager = @import("content_manager.zig").ContentManager;
const Shader = @import("shader.zig").Shader;
const Texture = @import("texture.zig").Texture;

pub const MaterialDefs = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    materials: []const MaterialDef,

    // TODO: load from external file
    pub fn load(allocator: std.mem.Allocator) !MaterialDefs {
        var materials = std.ArrayList(MaterialDef).init(allocator);
        defer materials.deinit();

        try materials.append(MaterialDef{
            .name = "default",
            .vs = "default.vs",
            .fs = "default.fs",
            .textures = &[_][]const u8{},
        });

        try materials.append(MaterialDef{
            .name = "background",
            .vs = "textured.vs",
            .fs = "textured.fs",
            .textures = &[_][]const u8{
                "background2.png",
            },
        });

        try materials.append(MaterialDef{
            .name = "brick",
            .vs = "textured.vs",
            .fs = "textured.fs",
            .textures = &[_][]const u8{
                "brick1.png",
            },
        });

        try materials.append(MaterialDef{
            .name = "cardboard",
            .vs = "textured.vs",
            .fs = "textured.fs",
            .textures = &[_][]const u8{
                "cardboard1.png",
            },
        });

        try materials.append(MaterialDef{
            .name = "wood",
            .vs = "wood.vs",
            .fs = "wood.fs",
            .textures = &[_][]const u8{
                "noise1_256.png",
            },
        });

        return MaterialDefs{
            .allocator = allocator,
            .materials = try materials.toOwnedSlice(),
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.materials);
    }
};

pub const MaterialDef = struct {
    name: []const u8,

    // shader
    vs: []const u8,
    fs: []const u8,

    // textures
    textures: []const []const u8,

    // renderstate
    // ?
};

pub const Materials = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    materials: []const Material,

    pub fn init(
        defs: *const MaterialDefs,
        allocator: std.mem.Allocator,
        content_manager: *ContentManager,
    ) !Self {
        //
        var materials = try std.ArrayList(Material).initCapacity(allocator, defs.materials.len);
        defer materials.deinit();

        errdefer {
            for (materials.items) |m| {
                m.deinit();
            }
        }

        for (0..defs.materials.len) |i| {
            const def = &defs.materials[i];
            const material = try Material.init(def, allocator, content_manager);

            materials.appendAssumeCapacity(material);
        }

        return Self{
            .allocator = allocator,
            .materials = try materials.toOwnedSlice(),
        };
    }

    pub fn deinit(self: Self) void {
        for (self.materials) |m| {
            m.deinit();
        }
        self.allocator.free(self.materials);
    }

    pub fn getRefByName(self: Self, name: []const u8) MaterialRef {
        for (self.materials, 0..) |m, i| {
            if (std.mem.eql(u8, name, m.name)) {
                return MaterialRef{
                    .index = i,
                };
            }
        }

        std.log.err("Material not found: '{s}'", .{name});
        @panic("Material not found");
    }

    pub fn getMaterial(self: Self, ref: MaterialRef) *const Material {
        return &self.materials[ref.index];
    }
};

pub const Material = struct {
    const Self = @This();

    // Note: Could store required render-state here as well.
    // Note: Might need more complex shader setups later.

    allocator: std.mem.Allocator,
    name: []const u8,
    shader: *Shader, // vertex shader + fragment shader
    textures: []const *Texture, // 0..* bound to texture units 0,1,2,...

    pub fn init(
        def: *const MaterialDef,
        allocator: std.mem.Allocator,
        content_manager: *ContentManager,
    ) !Material {
        // copy name
        const name = try allocator.dupe(u8, def.name);
        errdefer allocator.free(name);

        // get shader (owned by content manager)
        const shader = try content_manager.getShader(def.vs, def.fs);

        // get textures (owned by content manager)
        var textures: []*Texture = &[0]*Texture{};

        if (def.textures.len > 0) {
            textures = try allocator.alloc(*Texture, def.textures.len);
            errdefer allocator.free(textures);

            for (0..def.textures.len) |i| {
                textures[i] = try content_manager.getTexture(def.textures[i]);
            }
        }

        return Material{
            .allocator = allocator,
            .name = name,
            .shader = shader,
            .textures = textures,
        };
    }

    pub fn deinit(self: Self) void {
        if (self.textures.len > 0) {
            self.allocator.free(self.textures);
        }
        self.allocator.free(self.name);
    }
};

pub const MaterialRef = struct {
    index: usize,
};
