const std = @import("std");

const zbox = @import("zbox");
const b2 = zbox.API;

pub const Categories = struct {
    // https://box2d.org/documentation/group__shape.html#structb2_filter
    pub const Ground: u64 = 1;
    pub const Vehicle: u64 = 2;
    pub const Item: u64 = 4;
    pub const Player: u64 = 8;

    pub const None: u64 = 0;
    pub const All: u64 = 0xFFFF_FFFF_FFFF_FFFF;
};

pub const Masks = struct {
    //
    pub const Ground: u64 = Categories.All;
    pub const Vehicle: u64 = Categories.All;
    pub const Item: u64 = Categories.All;
    pub const Player: u64 = Categories.All;
};

pub const Filters = struct {
    pub fn getGroundFilter() b2.b2Filter {
        return b2.b2Filter{
            .categoryBits = Categories.Ground,
            .maskBits = Masks.Ground,
            .groupIndex = 0,
        };
    }

    pub fn getVehicleFilter() b2.b2Filter {
        return b2.b2Filter{
            .categoryBits = Categories.Vehicle,
            .maskBits = Masks.Vehicle,
            .groupIndex = 0,
        };
    }

    pub fn getItemFilter() b2.b2Filter {
        return b2.b2Filter{
            .categoryBits = Categories.Item,
            .maskBits = Masks.Item,
            .groupIndex = 0,
        };
    }

    pub fn getPlayerFilter() b2.b2Filter {
        return b2.b2Filter{
            .categoryBits = Categories.Player,
            .maskBits = Masks.Player,
            .groupIndex = 0,
        };
    }
};
