const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = .{
        .shared = b.option(
            bool,
            "shared",
            "Bulid as a shared library",
        ) orelse false,
    };

    const options_step = b.addOptions();
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }

    const options_module = options_step.createModule();

    const module = b.addModule("root", .{
        .root_source_file = b.path("src/zbox.zig"),
        .imports = &.{
            .{ .name = "zbox_options", .module = options_module },
        },
    });

    module.addIncludePath(b.path("libs/box2d/include"));
    module.addIncludePath(b.path("libs/box2d/include/box2d/"));

    const cflags = &.{
        //"-fno-sanitize=undefined",
        //"-Wno-elaborated-enum-base",
        //"-Wno-error=date-time",
        //if (options.use_32bit_draw_idx) "-DIMGUI_USE_32BIT_DRAW_INDEX" else "",
        "",
    };

    const box2d = if (options.shared) blk: {
        const lib = b.addSharedLibrary(.{
            .name = "box2d",
            .target = target,
            .optimize = optimize,
        });

        if (target.result.os.tag == .windows) {
            lib.defineCMacro("BOX2D_API", "__declspec(dllexport)");
        }

        if (target.result.os.tag == .macos) {
            lib.linker_allow_shlib_undefined = true;
        }

        break :blk lib;
    } else b.addStaticLibrary(.{
        .name = "box2d",
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(box2d);

    //box2d.addIncludePath(b.path("libs"));
    box2d.addIncludePath(b.path("libs/box2d/include/"));

    box2d.linkLibC();

    if (target.result.abi != .msvc)
        box2d.linkLibCpp();

    box2d.addCSourceFiles(.{
        .files = &.{
            "libs/box2d/src/aabb.c",
            "libs/box2d/src/array.c",
            "libs/box2d/src/bitset.c",
            "libs/box2d/src/body.c",
            "libs/box2d/src/broad_phase.c",
            "libs/box2d/src/constraint_graph.c",
            "libs/box2d/src/contact.c",
            "libs/box2d/src/contact_solver.c",
            "libs/box2d/src/core.c",
            "libs/box2d/src/distance.c",
            "libs/box2d/src/distance_joint.c",
            "libs/box2d/src/dynamic_tree.c",
            "libs/box2d/src/geometry.c",
            "libs/box2d/src/hull.c",
            "libs/box2d/src/id_pool.c",
            "libs/box2d/src/island.c",
            "libs/box2d/src/joint.c",
            "libs/box2d/src/manifold.c",
            "libs/box2d/src/math_functions.c",
            "libs/box2d/src/motor_joint.c",
            "libs/box2d/src/mouse_joint.c",
            "libs/box2d/src/prismatic_joint.c",
            "libs/box2d/src/revolute_joint.c",
            "libs/box2d/src/shape.c",
            "libs/box2d/src/solver.c",
            "libs/box2d/src/solver_set.c",
            "libs/box2d/src/stack_allocator.c",
            "libs/box2d/src/table.c",
            "libs/box2d/src/timer.c",
            "libs/box2d/src/types.c",
            "libs/box2d/src/weld_joint.c",
            "libs/box2d/src/wheel_joint.c",
            "libs/box2d/src/world.c",
        },
        .flags = cflags,
    });
}
