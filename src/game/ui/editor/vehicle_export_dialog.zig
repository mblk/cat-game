const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../../engine/engine.zig");

const Vehicle = @import("../../vehicle.zig").Vehicle;
const VehicleExporter = @import("../../vehicle_export.zig").VehicleExporter;

const formatter = @import("../../../utils/formatter.zig");
const ui_utils = @import("../../../utils/ui_utils.zig");

pub const VehicleExportDialog = struct {
    const Self = @This();
    const popup_id = "Export vehicle";
    const file_name_max_len = 16;

    save_manager: *engine.SaveManager,
    long_term_allocator: std.mem.Allocator,
    per_frame_allocator: std.mem.Allocator,

    should_open: bool = false,

    vehicle: ?*const Vehicle = null,
    save_infos: ?engine.SaveManager.SaveInfos = null,
    selected_index: ?usize = null,

    file_name_buffer: [file_name_max_len:0]u8 = undefined,

    pub fn init(
        self: *Self,
        save_manager: *engine.SaveManager,
        long_term_allocator: std.mem.Allocator,
        per_frame_allocator: std.mem.Allocator,
    ) void {
        self.* = Self{
            .save_manager = save_manager,
            .long_term_allocator = long_term_allocator,
            .per_frame_allocator = per_frame_allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn open(self: *Self, vehicle: *const Vehicle) !void {
        std.debug.assert(self.vehicle == null);
        std.debug.assert(self.save_infos == null);
        std.debug.assert(vehicle.alive); // TODO might change while dialog is open?

        const save_infos = try self.save_manager.getSaveInfos(.VehicleExport, self.long_term_allocator);

        self.vehicle = vehicle;
        self.save_infos = save_infos;
        @memset(&self.file_name_buffer, 0);
        self.should_open = true;
    }

    fn close(self: *Self) void {
        std.debug.assert(self.vehicle != null);
        std.debug.assert(self.save_infos != null);

        if (self.save_infos) |infos| {
            infos.deinit();
        }
        self.save_infos = null;
        self.vehicle = null;
    }

    pub fn drawUi(self: *Self) void {
        if (self.vehicle == null) {
            return;
        }
        if (self.save_infos == null) {
            return;
        }
        const save_infos = self.save_infos.?;
        const vehicle = self.vehicle.?;

        if (self.should_open) {
            self.should_open = false;
            zgui.openPopup(Self.popup_id, .{});
        }

        ui_utils.setNextWindowToCenterOfScreen();

        if (zgui.beginPopupModal(Self.popup_id, .{ .flags = .{ .always_auto_resize = true } })) {
            zgui.text("Enter new file name or select existing file to overwrite.", .{});

            _ = zgui.inputText("File name", .{
                .buf = &self.file_name_buffer,
            });

            var buffer: [128]u8 = undefined;
            var select_via_doubleclick = false;

            zgui.text("Existing files:", .{});

            if (zgui.beginListBox("##files", .{ .w = 300, .h = 300 })) {
                for (save_infos.entries, 0..) |entry, i| {
                    const s = std.fmt.bufPrintZ(&buffer, "{s}", .{entry.name}) catch unreachable;

                    if (zgui.selectable(s, .{ .selected = self.selected_index == i })) {
                        self.selected_index = i;

                        @memset(&self.file_name_buffer, 0);
                        const to_copy = @min(self.file_name_buffer.len, entry.name.len);
                        @memcpy(self.file_name_buffer[0..to_copy], entry.name[0..to_copy]);
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

            const trimmed_file_name = ui_utils.getTrimmedTextEditString(&self.file_name_buffer);
            const can_export = ui_utils.isValidFileName(trimmed_file_name);

            if (can_export) {
                if (zgui.button("Export", .{ .w = 300, .h = 30 }) or select_via_doubleclick) {
                    var success = true;

                    // TODO ask before overwriting existing file?

                    self.exportVehicle(vehicle, trimmed_file_name) catch |e| {
                        std.log.err("export vehicle: {any}", .{e});
                        success = false;
                    };

                    if (success) {
                        zgui.closeCurrentPopup();
                        self.close();
                    }
                }
            } else {
                zgui.beginDisabled(.{ .disabled = true });
                _ = zgui.button("Export", .{ .w = 300, .h = 30 });
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

    fn exportVehicle(self: *Self, vehicle: *const Vehicle, name: []const u8) !void {
        std.log.info("export {s}", .{name});

        const data = try VehicleExporter.exportVehicle(vehicle, self.per_frame_allocator);
        defer self.per_frame_allocator.free(data);
        std.log.info("vehicle data: {s}", .{data});

        try self.save_manager.save(.VehicleExport, name, data, self.per_frame_allocator);
    }
};
