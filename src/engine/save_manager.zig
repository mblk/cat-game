const std = @import("std");

pub const SaveType = enum {
    WorldExport,
    VehicleExport,
};

pub const SaveManager = struct {
    allocator: std.mem.Allocator,
    save_dir_path: []const u8,
    worlds_dir_path: []const u8,
    vehicles_dir_path: []const u8,

    pub fn create(allocator: std.mem.Allocator) !SaveManager {
        const save_dir_path: []u8 = try std.fs.cwd().realpathAlloc(allocator, "saves");
        std.log.info("save dir: {s}", .{save_dir_path});
        try createDirIfItDoesNotExist(save_dir_path);

        const worlds_dir_path = try std.fs.path.join(allocator, &.{ save_dir_path, "worlds" });
        std.log.info("worlds dir: {s}", .{worlds_dir_path});
        try createDirIfItDoesNotExist(worlds_dir_path);

        const vehicles_dir_path = try std.fs.path.join(allocator, &.{ save_dir_path, "vehicles" });
        std.log.info("vehicles dir: {s}", .{vehicles_dir_path});
        try createDirIfItDoesNotExist(vehicles_dir_path);

        return SaveManager{
            .allocator = allocator,
            .save_dir_path = save_dir_path,
            .worlds_dir_path = worlds_dir_path,
            .vehicles_dir_path = vehicles_dir_path,
        };
    }

    pub fn free(self: *SaveManager) void {
        self.allocator.free(self.vehicles_dir_path);
        self.allocator.free(self.worlds_dir_path);
        self.allocator.free(self.save_dir_path);
    }

    fn createDirIfItDoesNotExist(dir_path: []const u8) !void {
        var dir = std.fs.openDirAbsolute(dir_path, .{}) catch |e| {
            std.log.info("checking dir '{s}': {any}", .{ dir_path, e });

            if (e == error.FileNotFound) {
                std.log.info("creating dir '{s}' ...", .{dir_path});
                std.fs.makeDirAbsolute(dir_path) catch |e2| {
                    std.log.err("failed to create dir '{s}': {any}", .{ dir_path, e2 });
                    return e2;
                };

                std.log.info("trying to open new dir ...", .{});
                var dir2 = try std.fs.openDirAbsolute(dir_path, .{});
                std.log.info("success", .{});
                dir2.close();

                return {}; // success
            } else {
                return e;
            }
        };

        std.log.info("checking dir '{s}': exists", .{dir_path});
        dir.close();
    }

    fn getSaveFilePath(
        self: *SaveManager,
        save_type: SaveType,
        save_name: []const u8,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        const base_path: []const u8 = switch (save_type) {
            .WorldExport => self.worlds_dir_path,
            .VehicleExport => self.vehicles_dir_path,
        };

        const save_file_path = try std.fs.path.join(allocator, &.{ base_path, save_name });

        return save_file_path; // must be freed by caller
    }

    pub fn save(
        self: *SaveManager,
        save_type: SaveType,
        save_name: []const u8,
        data: []const u8,
        allocator: std.mem.Allocator,
    ) !void {
        const save_file_path = try self.getSaveFilePath(save_type, save_name, allocator);
        defer allocator.free(save_file_path);

        std.log.info("writing save to {s}", .{save_file_path});

        var file = try std.fs.createFileAbsolute(save_file_path, .{});
        defer file.close();
        try file.writeAll(data);
    }

    pub fn load(
        self: *SaveManager,
        save_type: SaveType,
        save_name: []const u8,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        const save_file_path = try self.getSaveFilePath(save_type, save_name, allocator);
        defer allocator.free(save_file_path);

        std.log.info("reading save from {s}", .{save_file_path});

        var file = try std.fs.openFileAbsolute(save_file_path, .{});
        const file_size = try file.getEndPos();
        const data = try file.readToEndAlloc(allocator, file_size);

        return data; // must be freed by caller
    }
};
