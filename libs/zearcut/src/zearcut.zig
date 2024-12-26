const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

const API = @cImport({
    @cInclude("earcut_impl.h");
});

pub fn init(allocator: std.mem.Allocator) void {
    assert(mem_allocator == null);
    assert(mem_allocations == null);

    mem_allocator = allocator;
    mem_allocations = .init(allocator);

    API.earcut_set_allocator(zearcutMalloc, zearcutFree);
}

pub fn deinit() void {
    assert(mem_allocator != null);
    assert(mem_allocations != null);

    const leak_count = mem_allocations.?.count();
    if (leak_count > 0) {
        std.log.err("zearcut deinit: leaked {d} allocations!\n", .{leak_count});
    }

    mem_allocations.?.deinit();
    mem_allocations = null;
    mem_allocator = null;

    API.earcut_set_allocator(null, null);
}

//
// allocator
//

var mem_allocator: ?std.mem.Allocator = null;
var mem_allocations: ?std.AutoHashMap(usize, usize) = null;
var mem_mutex: std.Thread.Mutex = .{};
const mem_alignment = 16;

fn zearcutMalloc(size: usize) callconv(.C) ?*anyopaque {
    //std.debug.print("zearcutMalloc {d}\n", .{size});

    assert(mem_allocator != null);
    assert(mem_allocations != null);

    mem_mutex.lock();
    defer mem_mutex.unlock();

    const mem = mem_allocator.?.alignedAlloc(u8, mem_alignment, size) catch @panic("zearcut: out of memory");

    // the size is required for the free-call
    mem_allocations.?.put(@intFromPtr(mem.ptr), size) catch @panic("zearcut: out of memory");

    return mem.ptr;
}

fn zearcutFree(maybe_ptr: ?*anyopaque) callconv(.C) void {
    //std.debug.print("zearcutFree {any}\n", .{maybe_ptr});

    assert(mem_allocator != null);
    assert(mem_allocations != null);

    if (maybe_ptr) |ptr| {
        mem_mutex.lock();
        defer mem_mutex.unlock();

        const size = mem_allocations.?.fetchRemove(@intFromPtr(ptr)).?.value;
        const mem = @as([*]align(mem_alignment) u8, @ptrCast(@alignCast(ptr)))[0..size];
        mem_allocator.?.free(mem);
    }
}

//
// create
//

pub const vec2 = packed struct {
    x: f32,
    y: f32,
};

pub const Result = struct {
    indices: []u32,

    inner_result: API.earcut_result_t,

    pub fn deinit(self: *Result) void {
        API.earcut_free(@constCast(@ptrCast(&self.inner_result)));
    }
};

pub const EarcutError = error{
    NotEnoughPoints,
    Unknown,
};

pub fn create(points: []const vec2) EarcutError!Result {
    if (points.len < 3) {
        return EarcutError.NotEnoughPoints;
    }

    const points_count: usize = points.len;
    const points_data: [*c]const API.vec2_t = @ptrCast(points.ptr);
    var result: API.earcut_result_t = .{
        .num_indices = 0,
        .indices = null,
    };

    API.earcut_create(points_count, points_data, &result);

    // if (!success) {
    //     return EarcutError.Unknown;
    // }

    const indices_slice: []u32 = result.indices[0..result.num_indices];

    return Result{
        .indices = indices_slice,
        .inner_result = result,
    };
}

//
// tests
//

test "init deinit" {
    init(std.testing.allocator);
    defer deinit();
}

test "split empty" {
    init(std.testing.allocator);
    defer deinit();

    const points = [0]vec2{};
    const result = create(&points);

    //std.debug.print("result: {any}\n", .{result});
    try expect(result == EarcutError.NotEnoughPoints);
}

test "split 1 point" {
    init(std.testing.allocator);
    defer deinit();

    const points = [_]vec2{
        vec2{ .x = 0, .y = 0 },
    };
    const result = create(&points);
    //std.debug.print("result: {any}\n", .{result});

    try expect(result == EarcutError.NotEnoughPoints);
}

test "split 2 points" {
    init(std.testing.allocator);
    defer deinit();

    const points = [_]vec2{
        vec2{ .x = 0, .y = 0 },
        vec2{ .x = 1, .y = 0 },
    };
    const result = create(&points);
    //std.debug.print("result: {any}\n", .{result});

    try expect(result == EarcutError.NotEnoughPoints);
}

test "split ccw tri" {
    init(std.testing.allocator);
    defer deinit();

    // ccw tri
    const points = [_]vec2{
        vec2{ .x = 0, .y = 0 },
        vec2{ .x = 1, .y = 0 },
        vec2{ .x = 1, .y = 1 },
    };

    const result = try create(&points);
    defer result.deinit();
    //std.debug.print("indices: {any}\n", .{result.indices});

    try expect(result.indices.len == 3);
    // Output triangles are clockwise.
    try expect(result.indices[0] == 1);
    try expect(result.indices[1] == 2);
    try expect(result.indices[2] == 0);
}

test "split cw tri" {
    init(std.testing.allocator);
    defer deinit();

    // ccw tri
    const points = [_]vec2{
        vec2{ .x = 0, .y = 0 },
        vec2{ .x = 1, .y = 1 },
        vec2{ .x = 1, .y = 0 },
    };

    const result = try create(&points);
    defer result.deinit();
    //std.debug.print("indices: {any}\n", .{result.indices});

    try expect(result.indices.len == 3);
    // Output triangles are clockwise.
    try expect(result.indices[0] == 1);
    try expect(result.indices[1] == 0);
    try expect(result.indices[2] == 2);
}

test "split ccw quad" {
    init(std.testing.allocator);
    defer deinit();

    // ccw quad
    const points = [_]vec2{
        vec2{ .x = 0, .y = 0 },
        vec2{ .x = 1, .y = 0 },
        vec2{ .x = 1, .y = 1 },
        vec2{ .x = 0, .y = 1 },
    };

    const result = try create(&points);
    defer result.deinit();
    //std.debug.print("indices: {any}\n", .{result.indices});

    try expect(result.indices.len == 6);
}

test "split cw quad" {
    init(std.testing.allocator);
    defer deinit();

    // cw quad
    const points = [_]vec2{
        vec2{ .x = 0, .y = 0 },
        vec2{ .x = 0, .y = 1 },
        vec2{ .x = 1, .y = 1 },
        vec2{ .x = 1, .y = 0 },
    };

    const result = try create(&points);
    defer result.deinit();
    //std.debug.print("indices: {any}\n", .{result.indices});

    try expect(result.indices.len == 6);
}

test "split ccw big poly" {
    init(std.testing.allocator);
    defer deinit();

    // ccw big poly
    const num_points = 12;
    const points = [num_points]vec2{
        vec2{ .x = 0, .y = 0 },
        vec2{ .x = 1, .y = 0 },
        vec2{ .x = 2, .y = 0 },
        vec2{ .x = 3, .y = 0 },
        vec2{ .x = 3, .y = 1 },
        vec2{ .x = 3, .y = 2 },
        vec2{ .x = 3, .y = 3 },
        vec2{ .x = 2, .y = 3 },
        vec2{ .x = 1, .y = 3 },
        vec2{ .x = 0, .y = 3 },
        vec2{ .x = 0, .y = 2 },
        vec2{ .x = 0, .y = 1 },
    };

    const result = try create(&points);
    defer result.deinit();
    //std.debug.print("indices: {any}\n", .{result.indices});

    //
    try expect(result.indices.len > num_points);

    // make sure all indices are used at least once
    var index_used: [num_points]bool = [_]bool{false} ** num_points;
    for (0..num_points) |i| {
        const index = result.indices[i];
        try expect(index < 12);
        index_used[index] = true;
    }
    //std.debug.print("index_used: {any}", .{index_used});
    for (0..num_points) |i| {
        try expect(index_used[i]);
    }
}
