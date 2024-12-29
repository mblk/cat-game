const std = @import("std");

pub const TrackingAllocatorStats = struct {
    total_allocs: usize,
    total_resizes: usize,
    total_frees: usize,

    total_allocations: usize,
    total_memory_used: usize,
    max_memory_used: usize,
};

pub const TrackingAllocator = struct {
    const Self = TrackingAllocator;

    name: []const u8,
    verbose: bool,
    inner: std.mem.Allocator,

    total_allocs: usize = 0,
    total_resizes: usize = 0,
    total_frees: usize = 0,

    total_allocations: usize = 0,
    total_memory_used: usize = 0,
    max_memory_used: usize = 0,

    pub fn getAllocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    pub fn getStats(allocator: std.mem.Allocator) TrackingAllocatorStats {
        const self: *Self = @ptrCast(@alignCast(allocator.ptr));

        return TrackingAllocatorStats{
            .total_allocs = self.total_allocs,
            .total_resizes = self.total_resizes,
            .total_frees = self.total_frees,
            .total_allocations = self.total_allocations,
            .total_memory_used = self.total_memory_used,
            .max_memory_used = self.max_memory_used,
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        // self.mutex.lock();
        // defer self.mutex.unlock();

        if (self.verbose) {
            std.debug.print("{s} alloc {d}\n", .{ self.name, len });

            // if (len > 10000) {
            //     std.debug.dumpCurrentStackTrace(@returnAddress());
            // }
        }

        self.total_allocs += 1;
        self.total_allocations += 1;
        self.total_memory_used += len;
        self.max_memory_used = @max(self.max_memory_used, self.total_memory_used);

        return self.inner.vtable.alloc(self.inner.ptr, len, ptr_align, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.verbose) {
            std.debug.print("{s} resize {d} -> {d}\n", .{ self.name, buf.len, new_len });

            //std.debug.dumpCurrentStackTrace(@returnAddress());
        }

        const success = self.inner.vtable.resize(self.inner.ptr, buf, buf_align, new_len, ret_addr);

        if (success) {
            self.total_resizes += 1;
            self.total_memory_used -= buf.len;
            self.total_memory_used += new_len;
        }

        return success;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.verbose) {
            std.debug.print("{s} free {d}\n", .{ self.name, buf.len });
        }

        self.total_frees += 1;
        self.total_allocations -= 1;
        self.total_memory_used -= buf.len;

        self.inner.vtable.free(self.inner.ptr, buf, buf_align, ret_addr);
    }
};
