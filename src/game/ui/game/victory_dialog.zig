const std = @import("std");
const zgui = @import("zgui");

const formatter = @import("../../../utils/formatter.zig");
const ui_utils = @import("../../../utils/ui_utils.zig");
const Callback = @import("../../../utils/callback.zig").Callback;

pub const VictoryDialog = struct {
    const Self = @This();
    const popup_id = "Victory";

    should_open: bool = false,
    is_open: bool = false,

    continue_cb: ?Callback(void) = null,
    reset_cb: ?Callback(void) = null,
    finish_cb: ?Callback(void) = null,

    pub fn init(self: *Self) void {
        //
        self.* = .{};
    }

    pub fn deinit(self: *Self) void {
        //
        _ = self;
    }

    pub fn open(self: *Self) void {
        //
        self.should_open = true;
    }

    fn close(self: *Self) void {
        self.is_open = false;
    }

    pub fn drawUi(self: *Self) void {
        //
        if (self.should_open) {
            self.should_open = false;
            zgui.openPopup(Self.popup_id, .{});
        }

        ui_utils.setNextWindowToCenterOfScreen();

        self.is_open = zgui.beginPopupModal(Self.popup_id, .{
            .flags = .{
                .always_auto_resize = true,
            },
        });

        if (self.is_open) {
            zgui.text("Congratulations, you finished the level!", .{});

            _ = zgui.invisibleButton("foo", .{ .w = 20, .h = 20 });

            zgui.text("Calories burned: -1234 kcal", .{});
            zgui.text("Calories eaten: +5000 kcal", .{});
            zgui.text("Calories left in level: 100 kcal ", .{});

            _ = zgui.invisibleButton("foo", .{ .w = 20, .h = 20 });

            zgui.text("Score: 3456", .{});
            zgui.text("Stars: XXX__ (3/5)", .{});
            zgui.text("XP gained: 34", .{});

            _ = zgui.invisibleButton("foo", .{ .w = 20, .h = 20 });

            if (zgui.button("Continue playing", .{ .w = 200, .h = 30 })) {
                if (self.continue_cb) |cb| {
                    cb.function({}, cb.context);
                }
                zgui.closeCurrentPopup();
                self.close();
            }
            zgui.sameLine(.{});
            if (zgui.button("Reset level", .{ .w = 200, .h = 30 })) {
                if (self.reset_cb) |cb| {
                    cb.function({}, cb.context);
                }
                zgui.closeCurrentPopup();
                self.close();
            }
            zgui.sameLine(.{});
            if (zgui.button("Finish level", .{ .w = 200, .h = 30 })) {
                if (self.finish_cb) |cb| {
                    cb.function({}, cb.context);
                }
                zgui.closeCurrentPopup();
                self.close();
            }

            zgui.endPopup();
        }
    }
};
