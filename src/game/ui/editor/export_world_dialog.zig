const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../../engine/engine.zig");

const World = @import("../../world.zig").World;
const WorldExporter = @import("../../world_export.zig").WorldExporter;

const formatter = @import("../../../utils/formatter.zig");

pub const ExportWorldDialog = struct {
    const Self = @This();
    const popup_id = "Export world";
    const file_name_max_len = 16;

    world: *World,
    save_manager: *engine.SaveManager,
    long_term_allocator: std.mem.Allocator,
    per_frame_allocator: std.mem.Allocator,

    save_infos: ?engine.SaveManager.SaveInfos = null,
    selected_index: ?usize = null,

    file_name_buffer: [file_name_max_len:0]u8 = [_:0]u8{0} ** file_name_max_len,

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
        self.save_infos = try self.save_manager.getSaveInfos(.WorldExport, self.long_term_allocator);
        @memset(&self.file_name_buffer, 0);

        zgui.openPopup(Self.popup_id, .{});
    }

    fn close(self: *Self) void {
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

        // center on screen
        const display_size = zgui.io.getDisplaySize();
        zgui.setNextWindowPos(.{
            .cond = .appearing,
            .pivot_x = 0.5,
            .pivot_y = 0.5,
            .x = display_size[0] * 0.5,
            .y = display_size[1] * 0.5,
        });

        if (zgui.beginPopupModal(Self.popup_id, .{
            .flags = .{
                .always_auto_resize = true,
            },
        })) {
            zgui.text("Enter new file name or select existing file to overwrite.", .{});

            _ = zgui.inputText("File name", .{
                .buf = &self.file_name_buffer,
            });

            var buffer: [128]u8 = undefined;
            var select_via_doubleclick = false;

            zgui.text("Existing files:", .{});

            if (zgui.beginListBox("##world_files", .{ .w = 300, .h = 300 })) {
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

            const ptr: [*:0]const u8 = &self.file_name_buffer;
            const buffer_content_len = std.mem.len(ptr);
            const buffer_content_slice: []const u8 = self.file_name_buffer[0..buffer_content_len];
            const trimmed_file_name = std.mem.trim(u8, buffer_content_slice, &[_]u8{ ' ', '\t', '.' });

            const can_export = isValidFileName(trimmed_file_name);

            if (can_export) {
                if (zgui.button("Export", .{ .w = 300, .h = 30 }) or select_via_doubleclick) {
                    var success = true;

                    // TODO ask before overwriting existing file?

                    self.exportWorld(trimmed_file_name) catch |e| {
                        std.log.err("export world: {any}", .{e});
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

    fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\t', '\n', '\r' => true,
            else => false,
        };
    }

    fn isValidFileName(s: []const u8) bool {
        if (s.len < 1) return false;

        for (s) |c| {
            if (!isWhitespace(c)) {
                return true;
            }
        }

        return false;
    }

    fn exportWorld(self: *Self, name: []const u8) !void {
        std.log.info("export {s}", .{name});

        const data = try WorldExporter.exportWorld(self.world, self.per_frame_allocator);
        defer self.per_frame_allocator.free(data);
        std.log.info("world data: {s}", .{data});

        try self.save_manager.save(.WorldExport, name, data, self.per_frame_allocator);
    }
};
