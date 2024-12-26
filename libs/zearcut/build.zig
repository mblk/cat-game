const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const cflags = &.{
        //"-fno-sanitize=undefined",
        //"-Wno-elaborated-enum-base",
        //"-Wno-error=date-time",
        //if (options.use_32bit_draw_idx) "-DIMGUI_USE_32BIT_DRAW_INDEX" else "",
        "",
    };

    const module = b.addModule("root", .{
        .root_source_file = b.path("src/zearcut.zig"),
    });

    module.addIncludePath(b.path("src/")); // for cImport

    const earcut_lib = b.addStaticLibrary(.{
        .name = "earcut",
        .target = target,
        .optimize = optimize,
    });

    earcut_lib.addIncludePath(b.path("libs/earcut.hpp/include"));

    earcut_lib.linkLibC();

    if (target.result.abi != .msvc) {
        earcut_lib.linkLibCpp();
    }

    earcut_lib.addCSourceFiles(.{
        .files = &.{
            "src/earcut_impl.cc",
        },
        .flags = cflags,
    });

    b.installArtifact(earcut_lib);

    // ---

    const test_step = b.step("test", "Run zearcut tests");

    const tests = b.addTest(.{
        .name = "zearcut-tests",
        .root_source_file = b.path("src/zearcut.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.addIncludePath(b.path("src/")); // for cImport
    tests.linkLibrary(earcut_lib);
    b.installArtifact(tests);

    test_step.dependOn(&b.addRunArtifact(tests).step);
}
