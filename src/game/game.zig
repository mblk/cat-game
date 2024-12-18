const world = @import("world.zig");
pub const World = world.World;
pub const GroundSegment = world.GroundSegment;
pub const GroundSegmentIndex = world.GroundSegmentIndex;
pub const GroundPointIndex = world.GroundPointIndex;

const vehicle = @import("vehicle.zig");
pub const VehicleDefs = vehicle.VehicleDefs;

pub const Vehicle = vehicle.Vehicle;

pub const Block = vehicle.Block;
pub const BlockDef = vehicle.BlockDef;
pub const BlockRef = vehicle.BlockRef;

pub const Device = vehicle.Device;
pub const DeviceDef = vehicle.DeviceDef;
pub const DeviceRef = vehicle.DeviceRef;

const player = @import("player.zig");
pub const Player = player.Player;
