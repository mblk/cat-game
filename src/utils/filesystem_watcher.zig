const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.watcher);

const Callback = @import("callback.zig").Callback;

const Impl = switch (builtin.os.tag) {
    .linux => LinuxFilesystemWatcher,
    .windows => WindowsFilesystemWatcher,
    else => EmptyFilesystemWatcher,
};

pub const FilesystemWatcher = struct {
    const Self = @This();

    impl: Impl,

    pub fn init(
        self: *Self,
        allocator: std.mem.Allocator,
        path: []const u8,
        file_modified_cb: Callback([]const u8),
    ) !void {
        try self.impl.init(allocator, path, file_modified_cb);
    }

    pub fn deinit(self: *Self) void {
        self.impl.deinit();
    }
};

const EmptyFilesystemWatcher = struct {
    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator, path: []const u8, file_modified_cb: Callback([]const u8)) !void {
        _ = self;
        _ = allocator;
        _ = path;
        _ = file_modified_cb;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

const WindowsFilesystemWatcher = struct {
    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator, path: []const u8, file_modified_cb: Callback([]const u8)) !void {
        _ = self;
        _ = allocator;
        _ = path;
        _ = file_modified_cb;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

const LinuxFilesystemWatcher = struct {
    const Self = @This();

    // c-import some constants
    const c = @cImport({
        @cInclude("sys/epoll.h");
        @cInclude("sys/inotify.h");
    });

    const WatchedDirectory = struct {
        path: []const u8,
    };

    allocator: std.mem.Allocator,
    file_modified_cb: ?Callback([]const u8),

    event_fd: i32 = -1,
    inotify_fd: i32 = -1,
    epoll_fd: i32 = -1,
    watched_dirs: std.AutoArrayHashMap(i32, WatchedDirectory),
    thread: std.Thread = undefined,

    pub fn init(
        self: *Self,
        allocator: std.mem.Allocator,
        path: []const u8,
        file_modified_cb: Callback([]const u8),
    ) !void {
        log.info("init start '{s}'", .{path});

        // TODO error handling (correctly free resources)

        self.* = .{
            .allocator = allocator,
            .file_modified_cb = file_modified_cb,
            .watched_dirs = .init(allocator),
        };

        // create event-fd
        self.event_fd = try std.posix.eventfd(0, 0);

        // create inotify-fd
        self.inotify_fd = try std.posix.inotify_init1(0);

        try self.addDirectoryRecursive(path);

        // create epoll-fd
        self.epoll_fd = try std.posix.epoll_create1(0);
        var event1 = std.os.linux.epoll_event{
            .events = c.EPOLLIN,
            .data = .{
                .fd = self.event_fd,
            },
        };
        var event2 = std.os.linux.epoll_event{
            .events = c.EPOLLIN,
            .data = .{
                .fd = self.inotify_fd,
            },
        };
        try std.posix.epoll_ctl(self.epoll_fd, c.EPOLL_CTL_ADD, self.event_fd, &event1);
        try std.posix.epoll_ctl(self.epoll_fd, c.EPOLL_CTL_ADD, self.inotify_fd, &event2);

        // start worker thread
        self.thread = try std.Thread.spawn(.{ .allocator = allocator }, threadFunc, .{self});

        log.info("init end", .{});
    }

    pub fn deinit(self: *Self) void {
        log.info("deinit start", .{});

        // tell worker thread to exit
        // add value 1 to the event-fd
        const value: u64 = 1;
        const p: [*]const u8 = @ptrCast(&value);
        const s: []const u8 = p[0..8];
        _ = std.posix.write(self.event_fd, s) catch unreachable;

        // wait for thread to exit
        std.Thread.join(self.thread);

        // close fds
        std.posix.close(self.epoll_fd);
        std.posix.close(self.event_fd);
        std.posix.close(self.inotify_fd);

        // free memory
        var iter = self.watched_dirs.iterator();
        while (iter.next()) |curr| {
            self.allocator.free(curr.value_ptr.*.path);
        }
        self.watched_dirs.deinit();

        log.info("deinit end", .{});
    }

    fn addDirectoryRecursive(self: *Self, path: []const u8) !void {

        // add the directory
        try self.addDirectory(path);

        // add child directories
        var dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |file| {
            if (file.kind == .directory) {
                const child_dir_path = try std.fs.path.join(self.allocator, &.{ path, file.name });
                defer self.allocator.free(child_dir_path);

                try self.addDirectoryRecursive(child_dir_path);
            }
        }
    }

    fn addDirectory(self: *Self, path: []const u8) !void {
        log.info("watching directory: '{s}'", .{path});

        const mask: u32 = c.IN_CLOSE_WRITE | c.IN_MOVED_TO;
        const watch_fd = try std.posix.inotify_add_watch(self.inotify_fd, path, mask);

        try self.watched_dirs.put(watch_fd, WatchedDirectory{
            .path = try self.allocator.dupe(u8, path),
        });
    }

    fn threadFunc(self: *Self) void {
        log.info("worker thread start", .{});

        var running = true;
        while (running) {
            var events: [10]std.os.linux.epoll_event = undefined;

            const event_count = std.posix.epoll_wait(self.epoll_fd, &events, -1); // -1 = wait indefinitely

            // epoll_wait() can return multiple events
            for (events[0..event_count]) |event| {
                if (event.data.fd == self.event_fd) {
                    log.info("exiting ...", .{});
                    running = false;
                } else if (event.data.fd == self.inotify_fd) {
                    //log.info("got inotify event", .{});

                    self.processInotifyEvent() catch |e| {
                        log.err("failed to process inotify event: {any}, exiting", .{e});
                        running = false; // exit thread
                    };
                } else {
                    log.warn("unknown event: {any}", .{event});
                }
            }
        }

        log.info("worker thread end", .{});
    }

    fn processInotifyEvent(self: *Self) !void {
        const Event = std.os.linux.inotify_event;
        const event_size: usize = @sizeOf(Event);

        var buffer: [1024]u8 = undefined;
        const read_bytes = try std.posix.read(self.inotify_fd, &buffer);

        var alloc_buffer: [1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&alloc_buffer);
        var fba_alloc = fba.allocator();

        // read() can return multiple events
        var remaining_data = buffer[0..read_bytes];
        while (remaining_data.len >= event_size) {
            const event: *const Event = @ptrCast(@alignCast(remaining_data.ptr));
            remaining_data = remaining_data[event_size + event.len ..];

            // std.log.info("event wd={d} cookie={d} mask={d} len={d}", .{
            //     event.wd,
            //     event.cookie,
            //     event.mask,
            //     event.len,
            // });

            // Note: No need for a mutex (yet) because the worker thread is started after
            //       all structures have been filled and stopped before anything if cleaned up.

            if (event.mask & (c.IN_CLOSE_WRITE | c.IN_MOVED_TO) != 0) {
                if (self.watched_dirs.get(event.wd)) |watched_dir| {
                    if (event.getName()) |name| {
                        //std.log.info("name: '{s}'", .{name});

                        const changed_file_path = try std.fs.path.join(fba_alloc, &.{ watched_dir.path, name });
                        defer fba_alloc.free(changed_file_path);

                        //std.log.info("full path: '{s}'", .{changed_file_path});

                        if (self.file_modified_cb) |cb| {
                            cb.function(changed_file_path, cb.context);
                        }
                    }
                }
            }
        }
    }
};
