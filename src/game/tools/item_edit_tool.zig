const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Transform2 = engine.Transform2;
const Color = engine.Color;

const zbox = @import("zbox");
const b2 = zbox.API;

const World = @import("../world.zig").World;
const Item = @import("../item.zig").Item;
const ItemDef = @import("../item.zig").ItemDef;

const tools = @import("tools.zig");
const ToolVTable = tools.ToolVTable;
const ToolDeps = tools.ToolDeps;
const ToolUpdateContext = tools.ToolUpdateContext;
const ToolRenderContext = tools.ToolRenderContext;
const ToolDrawUiContext = tools.ToolDrawUiContext;

const Mode = union(enum) {
    Idle: void,
    CreateItem: *const ItemDef,
};

pub const ItemEditTool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    world: *World,
    renderer2D: *engine.Renderer2D,

    mode: Mode = .Idle,

    pub fn getVTable() ToolVTable {
        return ToolVTable{
            .name = "Item edit",
            .shortcut = .F4,
            .create = Self.create,
            .destroy = Self.destroy,
            .update = Self.update,
            .render = Self.render,
            .drawUi = Self.drawUi,
        };
    }

    fn create(allocator: std.mem.Allocator, deps: ToolDeps) !*anyopaque {
        const self = try allocator.create(Self);

        self.* = Self{
            .allocator = allocator,
            .world = deps.world,
            .renderer2D = deps.renderer2D,
        };

        return self;
    }

    fn destroy(self_ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        self.allocator.destroy(self);
    }

    fn update(self_ptr: *anyopaque, context: ToolUpdateContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        const input = context.input;
        const mouse_position = context.mouse_position;

        switch (self.mode) {
            .Idle => {
                //
            },
            .CreateItem => |item_def| {
                //
                var spawn = false;

                if (input.getKeyState(.left_shift)) {
                    spawn = input.getMouseButtonState(.left);
                } else {
                    spawn = input.consumeMouseButtonDownEvent(.left);
                }

                if (spawn) {
                    const t = Transform2.from_pos(mouse_position);
                    _ = self.world.createItem(item_def, t) catch unreachable;
                }
            },
        }

        // cancel?
        if (self.mode != .Idle and input.consumeMouseButtonDownEvent(.right)) {
            self.mode = .Idle;
        }
    }

    fn render(self_ptr: *anyopaque, context: ToolRenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = self;
        _ = context;
    }

    fn drawUi(self_ptr: *anyopaque, context: ToolDrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));

        _ = context;

        zgui.setNextWindowPos(.{ .x = 10.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 300, .h = 600 });

        if (zgui.begin("Item list", .{})) {
            self.drawListWindowContent();
        }
        zgui.end();

        zgui.setNextWindowPos(.{ .x = 320.0, .y = 300.0, .cond = .appearing });
        zgui.setNextWindowSize(.{ .w = 300, .h = 300 });

        if (zgui.begin("Item edit", .{})) {
            self.drawEditWindowContent();
        }
        zgui.end();
    }

    fn drawEditWindowContent(self: *Self) void {
        var buffer: [128]u8 = undefined;

        switch (self.mode) {
            .Idle => {
                zgui.text("Available items:", .{});

                for (self.world.defs.item_defs) |*item_def| {
                    const s = std.fmt.bufPrintZ(&buffer, "{s}", .{item_def.id}) catch unreachable;

                    if (zgui.button(s, .{})) {
                        self.mode = .{ .CreateItem = item_def };
                    }
                }
            },

            .CreateItem => |item_def| {
                zgui.text("Creating item {s}", .{item_def.id});
            },
        }
    }

    fn drawListWindowContent(self: *Self) void {
        //var buffer: [128]u8 = undefined;

        zgui.text("total (incl dead): {d}", .{self.world.items.items.len});

        if (zgui.button("destroy all", .{})) {
            for (self.world.items.items, 0..) |*item, item_index| {
                if (!item.alive) continue;

                _ = self.world.destroyItem(.{
                    .item_index = item_index,
                });
            }
        }

        zgui.separator();

        for (self.world.items.items, 0..) |*item, item_index| {
            //const s = std.fmt.bufPrint(&buffer, "Item {d} alive={any}", .{ item_index, item.alive }) catch unreachable;

            zgui.text("Item {d} alive={any}", .{ item_index, item.alive });

            if (item.alive) {
                //
                if (zgui.button("destroy", .{})) {
                    _ = self.world.destroyItem(.{
                        .item_index = item_index,
                    });
                }
            }
        }
    }
};
