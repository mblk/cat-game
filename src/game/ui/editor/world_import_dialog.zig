const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../../engine/engine.zig");

const World = @import("../../world.zig").World;
const WorldImporter = @import("../../world_export.zig").WorldImporter;

const formatter = @import("../../../utils/formatter.zig");
const ui_utils = @import("../../../utils/ui_utils.zig");

pub const WorldImportDialog = struct {
    const Self = @This();
    const popup_id = "Import world";

    world: *World,
    save_manager: *engine.SaveManager,
    long_term_allocator: std.mem.Allocator,
    per_frame_allocator: std.mem.Allocator,

    should_open: bool = false,

    save_infos: ?engine.SaveManager.SaveInfos = null,
    selected_index: ?usize = null,

    pub fn init(
        self: *Self,
        world: *World,
        save_manager: *engine.SaveManager,
        long_term_allocator: std.mem.Allocator,
        per_frame_allocator: std.mem.Allocator,
    ) void {
        self.* = Self{
            .world = world,
            .save_manager = save_manager,
            .long_term_allocator = long_term_allocator,
            .per_frame_allocator = per_frame_allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn open(self: *Self) !void {
        std.debug.assert(self.save_infos == null);

        const save_infos = try self.save_manager.getSaveInfos(.WorldExport, self.long_term_allocator);

        self.save_infos = save_infos;
        self.should_open = true;
    }

    fn close(self: *Self) void {
        std.debug.assert(self.save_infos != null);

        if (self.save_infos) |infos| {
            infos.deinit();
        }
        self.save_infos = null;
    }

    pub fn drawUi(self: *Self) void {
        if (self.save_infos == null) {
            return;
        }
        const save_infos = self.save_infos.?;

        if (self.should_open) {
            self.should_open = false;
            zgui.openPopup(Self.popup_id, .{});
        }

        ui_utils.setNextWindowToCenterOfScreen();

        if (zgui.beginPopupModal(Self.popup_id, .{
            .flags = .{
                .always_auto_resize = true,
            },
        })) {
            var buffer: [128]u8 = undefined;
            var select_via_doubleclick = false;

            if (zgui.beginListBox("##files", .{ .w = 300, .h = 300 })) {
                for (save_infos.entries, 0..) |entry, i| {
                    const s = std.fmt.bufPrintZ(&buffer, "{s}", .{entry.name}) catch unreachable;

                    if (zgui.selectable(s, .{ .selected = self.selected_index == i })) {
                        self.selected_index = i;
                    }

                    if (zgui.isItemHovered(.{}) and zgui.getMouseClickedCount(.left) > 1) {
                        std.log.info("select via double click {s}", .{s});
                        select_via_doubleclick = true;
                    }
                }

                zgui.endListBox();
            }

            var maybe_selected: ?engine.SaveManager.SaveInfoEntry = null;
            if (self.selected_index) |sel_idx| {
                maybe_selected = save_infos.entries[sel_idx];
            }

            zgui.sameLine(.{});

            zgui.beginGroup();
            {
                if (maybe_selected) |selected| {
                    zgui.text("Selected: {s}", .{selected.name});
                    zgui.text("Size: {s}", .{formatter.formatFileSize(&buffer, selected.size)});
                    zgui.text("Last modification: {s}", .{formatter.formatNanosecondTimestamp(&buffer, selected.mtime)});
                } else {
                    zgui.text("No selection.", .{});
                }
            }
            zgui.endGroup();

            if (maybe_selected) |selected| {
                if (zgui.button("Import", .{ .w = 300, .h = 30 }) or select_via_doubleclick) {
                    var success = true;

                    self.importWorld(selected) catch |e| {
                        std.log.err("import world: {any}", .{e});
                        success = false;
                    };

                    if (success) {
                        zgui.closeCurrentPopup();
                        self.close();
                    }
                }
            } else {
                zgui.beginDisabled(.{ .disabled = true });
                _ = zgui.button("Import", .{ .w = 300, .h = 30 });
                zgui.endDisabled();
            }

            zgui.sameLine(.{});

            if (zgui.button("Cancel", .{ .w = 300, .h = 30 })) {
                zgui.closeCurrentPopup();
                self.close();
            }

            zgui.endPopup();
        }
    }

    fn importWorld(self: *Self, entry: engine.SaveManager.SaveInfoEntry) !void {
        const name = entry.name;
        std.log.info("import: {s}", .{name});

        const data = try self.save_manager.load(.WorldExport, name, self.per_frame_allocator);
        defer self.per_frame_allocator.free(data);
        std.log.info("world data: {s}", .{data});

        try WorldImporter.importWorld(self.world, data, self.per_frame_allocator);
    }
};
