const std = @import("std");

const b2 = @import("zbox").API;

const refs = @import("refs.zig");

pub const UserData = packed struct(usize) {
    const Self = @This();

    pub const Type = enum(u8) {
        Invalid,

        Vehicle,
        Block,
        Device,
        Item,
        //Player,
    };

    type: Type,
    index: u32,
    padding: u24 = 0,

    comptime {
        std.debug.assert(@sizeOf(Self) == @sizeOf(usize));
        std.debug.assert(@sizeOf(Self) == 8);
    }

    pub fn setToBody(self: Self, body_id: b2.b2BodyId) void {
        std.debug.assert(b2.B2_IS_NON_NULL(body_id));

        const value: usize = @bitCast(self);
        const ptr: *anyopaque = @ptrFromInt(value);

        b2.b2Body_SetUserData(body_id, ptr);
    }

    pub fn getFromBody(body_id: b2.b2BodyId) ?Self {
        std.debug.assert(b2.B2_IS_NON_NULL(body_id));

        const ptr = b2.b2Body_GetUserData(body_id);
        const value: usize = @intFromPtr(ptr);

        if (value == 0) {
            return null;
        }

        const user_data: UserData = @bitCast(value);

        std.debug.assert(user_data.padding == 0);

        return user_data;
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("UserData(type={s}, index={d}, pad={d})", .{ @tagName(self.type), self.index, self.padding });
    }

    pub fn getRef(self: Self) ?refs.Ref {
        switch (self.type) {
            .Vehicle => {
                return refs.Ref{
                    .Vehicle = refs.VehicleRef{
                        .vehicle_index = self.index,
                    },
                };
            },
            .Block => {
                return refs.Ref{
                    .Block = refs.BlockRef{
                        .block_index = self.index,
                    },
                };
            },
            .Device => {
                return refs.Ref{
                    .Device = refs.DeviceRef{
                        .device_index = self.index,
                    },
                };
            },
            .Item => {
                return refs.Ref{
                    .Item = refs.ItemRef{
                        .item_index = self.index,
                    },
                };
            },
            else => {
                return null;
            },
        }
    }
};
