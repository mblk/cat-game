const std = @import("std");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const World = @import("../world.zig").World;

const Vehicle = @import("../world.zig").Vehicle;

const ToolVTable = @import("tool.zig").ToolVTable;

pub const VehicleEditTool = struct {
    const Self = VehicleEditTool;

    allocator: std.mem.Allocator,
    world: *World,
    renderer2D: *engine.Renderer2D,

    pub fn getVTable() ToolVTable {
        return ToolVTable{
            .name = "Vehicle edit",
            .create = Self.create,
            .destroy = Self.destroy,
            .update = Self.update,
            .render = Self.render,
            .drawUi = Self.drawUi,
        };
    }

    fn create(allocator: std.mem.Allocator, world: *World, renderer2D: *engine.Renderer2D) !*anyopaque {
        const self = try allocator.create(Self);

        self.* = Self{
            .allocator = allocator,
            .world = world,
            .renderer2D = renderer2D,
        };

        return self;
    }

    fn destroy(context: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context));

        self.allocator.destroy(self);
    }

    fn update(context: *anyopaque, input: *engine.InputState, mouse_position: vec2) void {
        const self: *Self = @ptrCast(@alignCast(context));

        if (self.world.getClosestVehicle(mouse_position, 10.0)) |closest_vehicle| {
            self.renderer2D.addLine(mouse_position, closest_vehicle.getPosition(), Color.red);

            const local_position = closest_vehicle.transformWorldToLocal(mouse_position);

            if (input.consumeMouseButtonDownEvent(.left)) {
                closest_vehicle.createBlock(local_position);
            } else if (input.consumeMouseButtonDownEvent(.right)) {
                closest_vehicle.destroyBlock(mouse_position);
            }
        } else {
            if (input.consumeMouseButtonDownEvent(.left)) {
                self.world.createVehicle(mouse_position);
            }
        }
    }

    fn render(context: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context));
        _ = self;
    }

    fn drawUi(context: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context));
        _ = self;
    }
};
