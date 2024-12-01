const std = @import("std");

pub const SaveManager = struct {
    allocator: std.mem.Allocator,
    save_dir_path: []const u8,

    pub fn create(allocator: std.mem.Allocator) !SaveManager {
        const save_dir_path: []u8 = try std.fs.cwd().realpathAlloc(allocator, "saves");
        //defer allocator.free(save_dir_path);

        std.log.info("save dir: {s}", .{save_dir_path});

        return SaveManager{
            .allocator = allocator,
            .save_dir_path = save_dir_path,
        };
    }

    pub fn free(self: *SaveManager) void {
        self.allocator.free(self.save_dir_path);
    }

    fn getSaveFilePath(
        self: *SaveManager,
        save_name: []const u8,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        const save_file_path = try std.fs.path.join(allocator, &.{ self.save_dir_path, save_name });

        return save_file_path; // must be freed by caller
    }

    pub fn save(
        self: *SaveManager,
        name: []const u8,
        data: []const u8,
        allocator: std.mem.Allocator,
    ) !void {
        const save_file_path = try self.getSaveFilePath(name, allocator);
        std.log.info("writing save to {s}", .{save_file_path});

        var file = try std.fs.createFileAbsolute(save_file_path, .{});
        defer file.close();
        try file.writeAll(data);
    }

    pub fn load(
        self: *SaveManager,
        name: []const u8,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        const save_file_path = try self.getSaveFilePath(name, allocator);
        std.log.info("reading save from {s}", .{save_file_path});

        var file = try std.fs.openFileAbsolute(save_file_path, .{});
        const file_size = try file.getEndPos();
        const data = try file.readToEndAlloc(allocator, file_size);

        return data; // must be freed by caller
    }
};
