const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "game",
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const zglfw = b.dependency("zglfw", .{
        .x11 = false,
        .wayland = true,
    });
    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));

    const zopengl = b.dependency("zopengl", .{});
    exe.root_module.addImport("zopengl", zopengl.module("root"));

    const zmath = b.dependency("zmath", .{});
    exe.root_module.addImport("zmath", zmath.module("root"));

    const zgui = b.dependency("zgui", .{
        //.target = exe.target, // ?
        .backend = .glfw_opengl3,
    });
    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

    // const box2d = b.dependency("box2d", .{});
    // exe.root_module.addImport("box2d", box2d.module("root"));
    // exe.linkLibrary(box2d.artifact("box2d"));

    const zbox = b.dependency("zbox", .{});
    exe.root_module.addImport("zbox", zbox.module("root"));
    exe.linkLibrary(zbox.artifact("box2d"));

    b.installArtifact(exe);

    // const exe_check = b.addExecutable(.{
    //     .name = "hello",
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = b.standardTargetOptions(.{}),
    //     .optimize = b.standardOptimizeOption(.{}),
    // });

    //const check = b.step("check", "Check if foo compiles");
    //check.dependOn(&exe.step);

    // b.addTest()

    // const main_tests = b.addTest("src/root.zig");
    // //main_tests.set

    // const test_step = b.step("test", "Run tests");
    // test_step.dependOn(&main_tests.step);

    const test_step = b.step("test", "Run unit tests");

    //for (test_targets) |target| {
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        //.target = b.resolveTargetQuery(),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
    //}
}
