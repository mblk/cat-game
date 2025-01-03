const std = @import("std");

pub const Ref = union(enum) {
    Vehicle: VehicleRef,
    Block: BlockRef,
    Device: DeviceRef,
    Item: ItemRef,
};

pub const VehicleRef = struct {
    vehicle_index: usize,
    //vehicle_version

    pub fn format(self: VehicleRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Vehicle(idx={d})", .{self.vehicle_index});
    }
};

pub const BlockRef = struct {
    block_index: usize,
    //block_version

    pub fn format(self: BlockRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Block(idx={d})", .{self.block_index});
    }

    pub fn equals(self: BlockRef, other: BlockRef) bool {
        return self.block_index == other.block_index;
    }
};

pub const DeviceRef = struct {
    device_index: usize,
    // version

    pub fn format(self: DeviceRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Device(idx={d})", .{self.device_index});
    }
};

pub const ItemRef = struct {
    item_index: usize,
    //item_version

    pub fn format(self: ItemRef, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Item(idx={d})", .{self.item_index});
    }
};
