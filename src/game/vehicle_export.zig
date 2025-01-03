const std = @import("std");

const engine = @import("../engine/engine.zig");
const Transform2 = engine.Transform2;
const vec2 = engine.vec2;

const zbox = @import("zbox");
const b2 = zbox.API;

const World = @import("world.zig").World;

const Vehicle = @import("vehicle.zig").Vehicle;
const Block = @import("vehicle.zig").Block;
const Device = @import("vehicle.zig").Device;

const refs = @import("refs.zig");
const VehicleRef = refs.VehicleRef;
const ItemRef = refs.ItemRef;

pub const VehicleData = struct {
    transform: Transform2,

    blocks: []BlockData,
    devices: []DeviceData,
};

pub const BlockData = struct {
    def_id: []const u8,
    local_position: vec2,
};

pub const DeviceData = struct {
    def_id: []const u8,
    local_position: vec2,

    data: union(enum) {
        Wheel: struct {
            left_key: i32,
            right_key: i32,
        },
        Thruster: struct {
            thrust_key: i32,
        },
    },
};

pub const VehicleExporter = struct {
    pub fn exportVehicle(vehicle: *const Vehicle, allocator: std.mem.Allocator) ![]const u8 {
        // get data
        const vehicle_data = try getVehicleData(vehicle, allocator);
        defer allocator.free(vehicle_data.blocks);
        defer allocator.free(vehicle_data.devices);

        // convert to json
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try std.json.stringify(vehicle_data, .{
            .whitespace = .indent_4,
        }, string.writer());

        // return copy of string, must be freed by caller
        return allocator.dupe(u8, string.items);
    }

    pub fn getVehicleData(vehicle: *const Vehicle, allocator: std.mem.Allocator) !VehicleData {
        var block_data_list = std.ArrayList(BlockData).init(allocator);
        defer block_data_list.deinit();

        var device_data_list = std.ArrayList(DeviceData).init(allocator);
        defer device_data_list.deinit();

        for (vehicle.blocks.items) |*block| {
            if (!block.alive) continue;

            try block_data_list.append(.{
                .def_id = block.def.id, // TODO maybe dupe?
                .local_position = block.local_position,
            });
        }

        for (vehicle.devices.items) |*device| {
            if (!device.alive) continue;

            switch (device.type) {
                .Wheel => {
                    //
                    const wheel = &vehicle.wheels.items[device.data_index];

                    try device_data_list.append(.{
                        .def_id = device.def.id,
                        .local_position = device.local_position,

                        .data = .{
                            .Wheel = .{
                                .left_key = @intFromEnum(wheel.control_left_key),
                                .right_key = @intFromEnum(wheel.control_right_key),
                            },
                        },
                    });
                },
                .Thruster => {
                    //
                    const thruster = &vehicle.thrusters.items[device.data_index];

                    try device_data_list.append(.{
                        .def_id = device.def.id,
                        .local_position = device.local_position,

                        .data = .{
                            .Thruster = .{
                                .thrust_key = @intFromEnum(thruster.control_key),
                            },
                        },
                    });
                },
            }
        }

        const vehicle_data = VehicleData{
            .transform = vehicle.getTransform(),
            .blocks = try block_data_list.toOwnedSlice(),
            .devices = try device_data_list.toOwnedSlice(),
        };

        return vehicle_data;
    }
};

pub const VehicleImporter = struct {
    pub fn importVehicle(world: *World, data: []const u8, allocator: std.mem.Allocator) !VehicleRef {

        // parse json
        const parsed = try std.json.parseFromSlice(
            VehicleData,
            allocator,
            data,
            .{},
        );
        defer parsed.deinit();

        const vehicle_data = parsed.value;

        return createVehicleFromData(world, vehicle_data);
    }

    pub fn createVehicleFromData(world: *World, vehicle_data: VehicleData) VehicleRef {
        //
        const vehicle_ref = world.createVehicle(vehicle_data.transform);
        const vehicle = world.getVehicle(vehicle_ref).?;

        for (vehicle_data.blocks) |block_data| {
            if (world.defs.getBlockDef(block_data.def_id)) |block_def| {
                _ = vehicle.createBlock(block_def, block_data.local_position);
            }
        }

        for (vehicle_data.devices) |device_data| {
            if (world.defs.getDeviceDef(device_data.def_id)) |device_def| {
                const device_ref = vehicle.createDevice(device_def, device_data.local_position).?; // TODO might fail
                const device = vehicle.getDevice(device_ref).?;

                switch (device_data.data) {
                    .Wheel => |wheel_data| {
                        //
                        std.debug.assert(device.type == .Wheel);
                        const wheel = &vehicle.wheels.items[device.data_index];
                        wheel.control_left_key = @enumFromInt(wheel_data.left_key);
                        wheel.control_right_key = @enumFromInt(wheel_data.right_key);
                    },
                    .Thruster => |thruster_data| {
                        //
                        std.debug.assert(device.type == .Thruster);
                        const thruster = &vehicle.thrusters.items[device.data_index];
                        thruster.control_key = @enumFromInt(thruster_data.thrust_key);
                    },
                }
            }
        }

        return vehicle_ref;
    }
};
