const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ==========================================================================
    // Library module
    // ==========================================================================
    const utf8_index_mod = b.addModule("utf8_index", .{
        .root_source_file = b.path("src/utf8_index.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ==========================================================================
    // Executable
    // ==========================================================================
    const exe = b.addExecutable(.{
        .name = "utf8-index",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "utf8_index", .module = utf8_index_mod },
            },
        }),
    });

    b.installArtifact(exe);

    // ==========================================================================
    // Run command
    // ==========================================================================
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the UTF-8 index tool");
    run_step.dependOn(&run_cmd.step);

    // ==========================================================================
    // Tests
    // ==========================================================================
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/utf8_index.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
}
