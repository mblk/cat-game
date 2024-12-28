const std = @import("std");
const zgui = @import("zgui");

pub fn setNextWindowToCenterOfScreen() void {
    const display_size = zgui.io.getDisplaySize();
    zgui.setNextWindowPos(.{
        .cond = .appearing,
        .pivot_x = 0.5,
        .pivot_y = 0.5,
        .x = display_size[0] * 0.5,
        .y = display_size[1] * 0.5,
    });
}

fn getSliceFromSentinelArray(a: [*:0]const u8) []const u8 {
    //const ptr_to_string: [*:0]const u8 = a;
    const len = std.mem.len(a);
    const s: []const u8 = a[0..len];
    std.debug.assert(std.mem.indexOfScalar(u8, s, 0) == null); // no 0 character in string
    return s;
}

pub fn getTrimmedTextEditString(a: [*:0]const u8) []const u8 {
    const full = getSliceFromSentinelArray(a);

    const trimmed = std.mem.trim(u8, full, &[_]u8{ ' ', '\t', '.' });

    return trimmed;
}

fn isWhitespace(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\n', '\r' => true,
        else => false,
    };
}

pub fn isValidFileName(s: []const u8) bool {
    if (s.len < 1) return false;

    for (s) |c| {
        if (!isWhitespace(c)) {
            return true;
        }
    }

    return false;
}
