const std = @import("std");

pub fn main() !void {
    std.log.info("hello!", .{});
    defer std.log.info("bye!", .{});

    std.log.info("bubu", .{});
}
