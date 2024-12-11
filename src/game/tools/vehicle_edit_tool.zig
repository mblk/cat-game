const std = @import("std");
const zgui = @import("zgui");

const engine = @import("../../engine/engine.zig");
const vec2 = engine.vec2;
const Color = engine.Color;

const World = @import("../world.zig").World;

const Vehicle = @import("../world.zig").Vehicle;

const tools = @import("tools.zig");
const ToolVTable = tools.ToolVTable;
const ToolDeps = tools.ToolDeps;
const ToolUpdateContext = tools.ToolUpdateContext;
const ToolRenderContext = tools.ToolRenderContext;
const ToolDrawUiContext = tools.ToolDrawUiContext;

pub const VehicleEditTool = struct {
    const Self = VehicleEditTool;

    allocator: std.mem.Allocator,
    world: *World,
    renderer2D: *engine.Renderer2D,

    local_position: vec2 = vec2.zero,

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

        if (self.world.getClosestVehicle(mouse_position, 10.0)) |result| {
            const closest_vehicle = result.vehicle;

            const local_position = closest_vehicle.transformWorldToLocal(mouse_position);
            const world_position = closest_vehicle.transformLocalToWorld(local_position);

            self.local_position = local_position;

            self.renderer2D.addLine(mouse_position, result.block_world, Color.red);
            self.renderer2D.addPointWithPixelSize(world_position, 20.0, Color.blue);

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

    fn render(self_ptr: *anyopaque, context: ToolRenderContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));
        _ = self;
        _ = context;
    }

    fn drawUi(self_ptr: *anyopaque, context: ToolDrawUiContext) void {
        const self: *Self = @ptrCast(@alignCast(self_ptr));
        //_ = self;
        _ = context;

        zgui.text("local: {d:.1} {d:.1}", .{ self.local_position.x, self.local_position.y });
    }
};
