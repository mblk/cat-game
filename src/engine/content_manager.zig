const std = @import("std");

const Shader = @import("shader.zig").Shader;
const ShaderError = @import("shader.zig").ShaderError;

pub const ContentManager = struct {
    // deps
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !*ContentManager { // TODO no need for allocating?
        var content_manager = try allocator.create(ContentManager);

        content_manager.allocator = allocator;

        return content_manager;
    }

    pub fn destroy(self: *ContentManager) void {
        self.allocator.destroy(self);
    }

    pub fn getDataFilePath(
        self: *ContentManager,
        allocator: std.mem.Allocator,
        file_type: []const u8,
        file_name: []const u8,
    ) ![]const u8 {
        const data_dir_path: []u8 = try std.fs.cwd().realpathAlloc(allocator, "content");
        defer allocator.free(data_dir_path);

        const file_path = try std.fs.path.join(allocator, &.{ data_dir_path, file_type, file_name });

        _ = self;

        return file_path; // must be freed by caller
    }

    pub fn loadDataFile(
        self: *ContentManager,
        allocator: std.mem.Allocator,
        file_type: []const u8,
        file_name: []const u8,
    ) ![]const u8 {
        const file_path = try self.getDataFilePath(allocator, file_type, file_name);
        defer allocator.free(file_path);

        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        //const file_size = (try file.stat()).size;
        const file_size = try file.getEndPos();
        const file_buffer: []const u8 = try file.readToEndAllocOptions(allocator, file_size, null, @alignOf(u8), null); // not terminated

        return file_buffer; // must be freed by caller
    }

    pub fn loadDataFileWithSentinel(
        self: *ContentManager,
        allocator: std.mem.Allocator,
        file_type: []const u8,
        file_name: []const u8,
    ) ![:0]const u8 {
        const file_path = try self.getDataFilePath(allocator, file_type, file_name);
        defer allocator.free(file_path);

        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();

        //const file_size = (try file.stat()).size;
        const file_size = try file.getEndPos();
        const file_buffer: [:0]u8 = try file.readToEndAllocOptions(allocator, file_size, null, @alignOf(u8), 0); // 0-terminated

        return file_buffer; // must be freed by caller
    }

    pub fn loadShader(
        self: *ContentManager,
        allocator: std.mem.Allocator,
        vs_name: []const u8,
        fs_name: []const u8,
    ) !Shader {
        const vs_source = try self.loadDataFileWithSentinel(allocator, "shader", vs_name); // anyerror
        defer allocator.free(vs_source);

        const fs_source = try self.loadDataFileWithSentinel(allocator, "shader", fs_name);
        defer allocator.free(fs_source);

        const shader = try Shader.loadFromSource(vs_source, fs_source); // ShaderError

        return shader;
    }
};
