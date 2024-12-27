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
        const save_dir_path: []u8 = try std.fs.cwd().realpathAlloc(allocator, "saves"); // TODO not working correctly i think (at least on windows)
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

    fn getSaveBaseDirPath(self: *SaveManager, save_type: SaveType) []const u8 {
        return switch (save_type) {
            .WorldExport => self.worlds_dir_path,
            .VehicleExport => self.vehicles_dir_path,
        };
    }

    fn getSaveFilePath(
        self: *SaveManager,
        save_type: SaveType,
        save_name: []const u8,
        allocator: std.mem.Allocator,
    ) ![]const u8 {
        const base_path = self.getSaveBaseDirPath(save_type);

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

    pub const SaveInfos = struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        entries: []const SaveInfoEntry,

        pub fn deinit(self: Self) void {
            for (self.entries) |entry| {
                self.allocator.free(entry.name);
            }
            self.allocator.free(self.entries);
        }
    };

    pub const SaveInfoEntry = struct {
        name: []const u8,
        size: u64,

        // nanoseconds, relative to UTC 1970-01-01.
        atime: i128, // last access
        mtime: i128, // last modification
        ctime: i128, // last status/metadata change
    };

    pub fn getSaveInfos(
        self: *SaveManager,
        save_type: SaveType,
        allocator: std.mem.Allocator,
    ) !SaveInfos {
        const base_path = self.getSaveBaseDirPath(save_type);
        std.log.info("getting save infos from {s}", .{base_path});

        const dir = try std.fs.openDirAbsolute(base_path, .{ .iterate = true });
        var iter = dir.iterate();

        var entries = std.ArrayList(SaveInfoEntry).init(allocator);
        defer entries.deinit();

        while (try iter.next()) |file| {
            std.log.info("iter {any} {s}", .{ file.kind, file.name });

            if (file.kind != .file) continue;

            const file_stat = try dir.statFile(file.name);

            try entries.append(SaveInfoEntry{
                .name = try allocator.dupe(u8, file.name),
                .size = file_stat.size,
                .atime = file_stat.atime,
                .mtime = file_stat.mtime,
                .ctime = file_stat.ctime,
            });
        }

        return SaveInfos{
            .allocator = allocator,
            .entries = try entries.toOwnedSlice(),
        };
    }
};
