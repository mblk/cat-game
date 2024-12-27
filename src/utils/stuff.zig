const std = @import("std");

// Imgui notes:
// - "End and EndChild are special and must be called even if Begin{,Child} returns false."
//
// all others:
// if (zgui.BeginFoo()) {
//     ...
//     zgui.EndFoo();
// }

// automatic enum selector:
// inline for (@typeInfo(MasterMode).@"enum".fields) |field| {
//     const enumValue = @field(MasterMode, field.name);
//     if (zgui.radioButton(field.name, .{ .active = self.master_mode == enumValue })) {
//         self.master_mode = enumValue;
//     }
// }

fn getSliceFromSentinelArray(a: [*:0]const u8) []const u8 {
    //const ptr_to_string: [*:0]const u8 = a;
    const len = std.mem.len(a);
    const s: []const u8 = a[0..len];
    std.debug.assert(std.mem.indexOfScalar(u8, s, 0) == null); // no 0 character in string

    return s;
}
