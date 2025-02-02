const std = @import("std");
const zgui = @import("zgui");

pub const AntiWindupStrategy = enum {
    None,
    ResetOnZero,
};

pub fn PIDController(comptime T: type) type {
    return struct {
        const Self = @This();

        const HistoryLength = 120;

        // pid settings
        kp: T,
        ki: T = 0,
        kd: T = 0,
        integral_min: ?T = null,
        integral_max: ?T = null,
        anti_windup: AntiWindupStrategy = .None,

        // pid state
        previous_error: T = 0,
        integral: T = 0,

        // history
        setpoint_history: [HistoryLength]T = [1]T{0} ** HistoryLength,
        measured_history: [HistoryLength]T = [1]T{0} ** HistoryLength,
        history_insert_index: usize = 0,
        history_value_min: T = -1,
        history_value_max: T = 1,

        pub fn new(kp: T, ki: T, kd: T) Self {
            return Self{
                .kp = kp,
                .ki = ki,
                .kd = kd,
                .previous_error = 0,
                .integral = 0,
                .integral_min = null,
                .integral_max = null,
            };
        }

        pub fn reset(self: *Self) void {
            self.integral = 0;
            self.previous_error = 0;
        }

        pub fn update(self: *Self, dt: T, setpoint: T, measured_value: T) T {

            //xxx
            self.addHistory(setpoint, measured_value);
            //xxx

            const err = setpoint - measured_value;

            self.integral += err * dt;

            if (self.integral_min) |min| {
                self.integral = @max(self.integral, min);
            }
            if (self.integral_max) |max| {
                self.integral = @min(self.integral, max);
            }

            if (self.anti_windup == .ResetOnZero) {
                if (std.math.sign(err) != std.math.sign(self.previous_error)) {
                    //std.log.info("PID-AntiWindup: setting integral to 0", .{});
                    self.integral = 0;
                }
            }

            const derivative = (err - self.previous_error) / dt;
            self.previous_error = err;

            const output = self.kp * err + self.ki * self.integral + self.kd * derivative;

            return output;
        }

        fn addHistory(self: *Self, setpoint: T, measured_value: T) void {
            self.setpoint_history[self.history_insert_index] = setpoint;
            self.measured_history[self.history_insert_index] = measured_value;

            self.history_insert_index = (self.history_insert_index + 1) % HistoryLength;

            self.history_value_min = @min(self.history_value_min, setpoint);
            self.history_value_max = @max(self.history_value_max, setpoint);

            self.history_value_min = @min(self.history_value_min, measured_value);
            self.history_value_max = @max(self.history_value_max, measured_value);
        }

        pub fn showUi(self: *Self) void {
            //zgui.setNextWindowPos(.{ .x = 1600.0, .y = 400.0, .cond = .appearing });
            //zgui.setNextWindowSize(.{ .w = 200, .h = 200 });

            if (zgui.begin("PID", .{})) {
                if (zgui.collapsingHeader("Settings", .{ .default_open = true })) {
                    _ = zgui.dragFloat("P", .{
                        .v = &self.kp,
                        .speed = 0.1,
                        .min = 0,
                        .max = 100,
                    });

                    _ = zgui.dragFloat("I", .{
                        .v = &self.ki,
                        .speed = 0.1,
                        .min = 0,
                        .max = 100,
                    });

                    _ = zgui.dragFloat("D", .{
                        .v = &self.kd,
                        .speed = 0.1,
                        .min = 0,
                        .max = 100,
                    });

                    // I_min
                    var has_integral_min: bool = self.integral_min != null;
                    _ = zgui.checkbox("has I_min", .{ .v = &has_integral_min });
                    if (has_integral_min) {
                        var value: T = self.integral_min orelse -1;
                        _ = zgui.dragFloat("I_min", .{
                            .v = &value,
                            .speed = 0.1,
                            .min = -100,
                            .max = 100,
                        });
                        self.integral_min = value;
                    } else {
                        self.integral_min = null;
                    }

                    // I_max
                    var has_integral_max: bool = self.integral_max != null;
                    _ = zgui.checkbox("has I_max", .{ .v = &has_integral_max });
                    if (has_integral_max) {
                        var value: T = self.integral_max orelse 1;
                        _ = zgui.dragFloat("I_max", .{
                            .v = &value,
                            .speed = 0.1,
                            .min = -100,
                            .max = 100,
                        });
                        self.integral_max = value;
                    } else {
                        self.integral_max = null;
                    }

                    // anti windup
                    zgui.text("anti windup: {s}", .{@tagName(self.anti_windup)});
                    inline for (@typeInfo(AntiWindupStrategy).@"enum".fields) |field| {
                        const enumValue = @field(AntiWindupStrategy, field.name);
                        if (zgui.radioButton(field.name, .{ .active = self.anti_windup == enumValue })) {
                            self.anti_windup = enumValue;
                        }
                    }
                }

                if (zgui.collapsingHeader("State", .{ .default_open = true })) {
                    zgui.text("integral: {d:.3}", .{self.integral});
                    zgui.text("prev_err: {d:.3}", .{self.previous_error});
                }

                if (zgui.collapsingHeader("Graph", .{ .default_open = true })) {
                    if (zgui.button("reset min/max", .{})) {
                        self.history_value_min = 0;
                        self.history_value_max = 0;
                    }

                    if (zgui.plot.beginPlot("Values", .{
                        .h = -1,

                        //.flags = .canvas_only,

                        .flags = .{
                            .no_frame = true,
                            .no_title = true,
                            .no_box_select = true,
                            .no_mouse_text = true,
                            .no_menus = true,
                            .no_inputs = true,
                        },
                    })) {
                        //
                        zgui.plot.setupLegend(.{
                            .south = true,
                            .west = true,
                        }, .{
                            //.outside = true,
                        });

                        zgui.plot.setupAxis(.x1, .{
                            .flags = .{
                                //.auto_fit = true,
                            },
                            //.label = "T",
                        });

                        zgui.plot.setupAxis(.y1, .{
                            .flags = .{
                                //.auto_fit = true,
                                //.range_fit = true,
                            },
                            //.label = "value",
                        });

                        zgui.plot.setupAxisLimits(.x1, .{
                            .cond = .always,
                            .min = 0,
                            .max = HistoryLength,
                        });

                        const y_range = @max(1.0, self.history_value_max - self.history_value_min);
                        const y_extra = y_range * 0.1;

                        zgui.plot.setupAxisLimits(.y1, .{
                            .cond = .always,
                            .min = self.history_value_min - y_extra,
                            .max = self.history_value_max + y_extra,
                        });

                        zgui.plot.setupFinish();

                        zgui.plot.plotLineValues("SP", T, .{ .v = &self.setpoint_history });
                        zgui.plot.plotLineValues("M", T, .{ .v = &self.measured_history });

                        // const x_curr: f32 = @floatFromInt(self.history_insert_index);
                        // zgui.plot.plotLine("", f32, .{
                        //     .xv = &.{ x_curr, x_curr },
                        //     .yv = &.{ self.history_value_min, self.history_value_max },
                        // });

                        zgui.plot.endPlot();
                    }
                }
            }
            zgui.end();
        }
    };
}
