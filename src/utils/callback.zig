const std = @import("std");

pub fn Callback(comptime T: type) type {
    return struct {
        function: *const fn (arg: T, context: *anyopaque) void,
        context: *anyopaque,
    };
}
