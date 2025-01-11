const std = @import("std");

const log = std.log.scoped(.ContentManager);

const FilesystemWatcher = @import("../utils/filesystem_watcher.zig").FilesystemWatcher;
const Shader = @import("shader.zig").Shader;
const Texture = @import("texture.zig").Texture;

pub const ContentManager = struct {
    const Self = @This();

    const root_dir_name = "content";
    const textures_dir_name = "textures";
    const shaders_dir_name = "shaders";

    allocator: std.mem.Allocator,
    content_root_path: []const u8,

    mutex: std.Thread.Mutex,
    watcher: ?*FilesystemWatcher,
    has_dirty_items: bool,

    shaders: std.ArrayList(Shader),
    shader_lookup: std.StringHashMap(usize), // vs_name+fs_name to index
    shader_files: std.StringHashMap(usize), // file path to index
    shader_modifications: std.AutoHashMap(usize, std.time.Instant), // shader index to time of last modification

    textures: std.ArrayList(Texture),
    texture_lookup: std.StringHashMap(usize), // name to index
    texture_files: std.StringHashMap(usize), // file path to index
    texture_modifications: std.AutoHashMap(usize, std.time.Instant), // texture index to time of last modification

    pub fn init(self: *Self, allocator: std.mem.Allocator, enable_reload: bool) !void {
        const content_root_path = try findContentRootPath(allocator);

        var maybe_watcher: ?*FilesystemWatcher = null;
        if (enable_reload) {
            // Note: Address of filesystem watcher must not change (self-ptr passed to worker thread)
            const watcher: *FilesystemWatcher = try allocator.create(FilesystemWatcher);
            try watcher.init(allocator, content_root_path, .{ .function = fileModifiedCb, .context = self });
            maybe_watcher = watcher;
        }

        self.* = .{
            .allocator = allocator,
            .content_root_path = content_root_path,

            .watcher = maybe_watcher,
            .mutex = .{},
            .has_dirty_items = false,

            .shaders = .init(allocator),
            .shader_lookup = .init(allocator),
            .shader_files = .init(allocator),
            .shader_modifications = .init(allocator),

            .textures = .init(allocator),
            .texture_lookup = .init(allocator),
            .texture_files = .init(allocator),
            .texture_modifications = .init(allocator),
        };
    }

    pub fn deinit(self: *ContentManager) void {
        if (self.watcher) |w| {
            w.deinit();
            self.allocator.destroy(w);
        }

        {
            var iter = self.texture_files.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
        }

        {
            var iter = self.texture_lookup.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
        }

        for (self.textures.items) |*texture| {
            texture.free();
        }

        {
            var iter = self.shader_files.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
        }

        {
            var iter = self.shader_lookup.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
        }

        for (self.shaders.items) |*shader| {
            shader.deinit();
        }

        self.texture_modifications.deinit();
        self.texture_files.deinit();
        self.texture_lookup.deinit();
        self.textures.deinit();

        self.shader_modifications.deinit();
        self.shader_files.deinit();
        self.shader_lookup.deinit();
        self.shaders.deinit();

        self.allocator.free(self.content_root_path);
    }

    pub fn update(self: *Self) void {
        if (!self.has_dirty_items) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        const reload_after_ms = 100;
        const reload_after_ns = reload_after_ms * std.time.ns_per_ms;

        const now = std.time.Instant.now() catch unreachable;

        // find items to reload (enough time has passed)
        var shaders_to_reload = std.ArrayList(usize).init(self.allocator); // TODO use temp alloc?
        defer shaders_to_reload.deinit();
        {
            var iter = self.shader_modifications.iterator();
            while (iter.next()) |entry| {
                const ns_since = now.since(entry.value_ptr.*);
                if (ns_since > reload_after_ns) {
                    shaders_to_reload.append(entry.key_ptr.*) catch unreachable;
                }
            }
        }

        var textures_to_reload = std.ArrayList(usize).init(self.allocator);
        defer textures_to_reload.deinit();
        {
            var iter = self.texture_modifications.iterator();
            while (iter.next()) |entry| {
                const ns_since = now.since(entry.value_ptr.*);
                if (ns_since > reload_after_ns) {
                    textures_to_reload.append(entry.key_ptr.*) catch unreachable;
                }
            }
        }

        // reload items
        for (shaders_to_reload.items) |shader_index| {
            self.reloadShader(shader_index) catch |e| {
                std.log.err("failed to reload shader: {any}", .{e});
            };
            const was_removed = self.shader_modifications.remove(shader_index);
            std.debug.assert(was_removed);
        }

        for (textures_to_reload.items) |texture_index| {
            self.reloadTexture(texture_index) catch |e| {
                std.log.err("failed to reload texture: {any}", .{e});
            };
            const was_removed = self.texture_modifications.remove(texture_index);
            std.debug.assert(was_removed);
        }

        if (self.shader_modifications.count() == 0 and
            self.texture_modifications.count() == 0)
        {
            self.has_dirty_items = false;
        }
    }

    fn fileModifiedCb(path: []const u8, context: *anyopaque) void {
        const self: *Self = @alignCast(@ptrCast(context));
        const now = std.time.Instant.now() catch unreachable;

        log.info("file modified: '{s}'", .{path});

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.shader_files.get(path)) |shader_index| {
            log.info("shader {d} was modified", .{shader_index});

            self.has_dirty_items = true;
            self.shader_modifications.put(shader_index, now) catch unreachable;
        }

        if (self.texture_files.get(path)) |texture_index| {
            log.info("texture {d} was modified", .{texture_index});

            self.has_dirty_items = true;
            self.texture_modifications.put(texture_index, now) catch unreachable;
        }
    }

    fn findContentRootPath(
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        const data_dir_path: []u8 = try std.fs.cwd().realpathAlloc(allocator, Self.root_dir_name);

        return data_dir_path; // must be freed by caller
    }

    fn getDataFilePath(
        self: *ContentManager,
        allocator: std.mem.Allocator,
        file_type: []const u8,
        file_name: []const u8,
    ) ![]const u8 {
        const file_path = try std.fs.path.join(allocator, &.{ self.content_root_path, file_type, file_name });

        return file_path; // must be freed by caller
    }

    fn loadDataFile(
        allocator: std.mem.Allocator,
        file_path: []const u8,
    ) ![]const u8 {
        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const file_buffer: []const u8 = try file.readToEndAllocOptions(allocator, file_size, null, @alignOf(u8), null); // not terminated

        return file_buffer; // must be freed by caller
    }

    fn loadDataFileWithSentinel(
        allocator: std.mem.Allocator,
        file_path: []const u8,
    ) ![:0]const u8 {
        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const file_buffer: [:0]u8 = try file.readToEndAllocOptions(allocator, file_size, null, @alignOf(u8), 0); // 0-terminated

        return file_buffer; // must be freed by caller
    }

    pub fn getShader(
        self: *Self,
        vs_name: []const u8,
        fs_name: []const u8,
    ) !*Shader {
        log.info("getShader({s}, {s})", .{ vs_name, fs_name });

        self.mutex.lock();
        defer self.mutex.unlock();

        var key_buffer: [128]u8 = undefined;
        const temp_key = try std.fmt.bufPrint(&key_buffer, "{s}+{s}", .{ vs_name, fs_name });

        if (self.shader_lookup.get(temp_key)) |shader_index| {
            return &self.shaders.items[shader_index];
        }

        const perm_key = try self.allocator.dupe(u8, temp_key);
        const shader_index = try self.loadShader(vs_name, fs_name);
        try self.shader_lookup.put(perm_key, shader_index);

        return &self.shaders.items[shader_index];
    }

    fn loadShader(
        self: *ContentManager,
        vs_name: []const u8,
        fs_name: []const u8,
    ) !usize {

        // Note: Not freeing the paths because they are used as keys in a hashmap.
        const vs_file_path = try self.getDataFilePath(self.allocator, Self.shaders_dir_name, vs_name);
        const fs_file_path = try self.getDataFilePath(self.allocator, Self.shaders_dir_name, fs_name);

        const vs_source = try loadDataFileWithSentinel(self.allocator, vs_file_path);
        defer self.allocator.free(vs_source);
        const fs_source = try loadDataFileWithSentinel(self.allocator, fs_file_path);
        defer self.allocator.free(fs_source);

        var shader: Shader = undefined;
        try shader.init(self.allocator, vs_name, fs_name, vs_source, fs_source);

        const shader_index = self.shaders.items.len;
        try self.shaders.append(shader);

        // Note: Key memory is managed by the caller.
        try self.shader_files.put(vs_file_path, shader_index);
        try self.shader_files.put(fs_file_path, shader_index);

        return shader_index;
    }

    fn reloadShader(self: *Self, shader_index: usize) !void {
        const shader: *Shader = &self.shaders.items[shader_index];

        const vs_file_path = try self.getDataFilePath(self.allocator, Self.shaders_dir_name, shader.vs_name);
        defer self.allocator.free(vs_file_path);
        const fs_file_path = try self.getDataFilePath(self.allocator, Self.shaders_dir_name, shader.fs_name);
        defer self.allocator.free(fs_file_path);

        const vs_source = try loadDataFileWithSentinel(self.allocator, vs_file_path);
        defer self.allocator.free(vs_source);
        const fs_source = try loadDataFileWithSentinel(self.allocator, fs_file_path);
        defer self.allocator.free(fs_source);

        try shader.reload(vs_source, fs_source);
    }

    pub fn getTexture(self: *Self, name: []const u8) !*Texture {
        std.log.info("getTexture({s})", .{name});

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.texture_lookup.get(name)) |texture_index| {
            return &self.textures.items[texture_index];
        }

        const key_copy = try self.allocator.dupe(u8, name);
        const texture_index = try self.loadTexture(name);
        try self.texture_lookup.put(key_copy, texture_index);

        return &self.textures.items[texture_index];
    }

    fn loadTexture(
        self: *ContentManager,
        name: []const u8,
    ) !usize {

        // Note: Not freeing the path because it is used as key in a hashmap.
        const file_path = try self.getDataFilePath(self.allocator, Self.textures_dir_name, name);

        const data = try loadDataFile(self.allocator, file_path);
        defer self.allocator.free(data);

        const texture = try Texture.init(self.allocator, name, data);

        const texture_index = self.textures.items.len;
        try self.textures.append(texture);

        // Note: Key memory is managed by the caller.
        try self.texture_files.put(file_path, texture_index);

        return texture_index;
    }

    fn reloadTexture(self: *Self, texture_index: usize) !void {
        const texture: *Texture = &self.textures.items[texture_index];

        const file_path = try self.getDataFilePath(self.allocator, Self.textures_dir_name, texture.name);
        defer self.allocator.free(file_path);

        const data = try loadDataFile(self.allocator, file_path);
        defer self.allocator.free(data);

        try texture.reload(data);
    }
};
