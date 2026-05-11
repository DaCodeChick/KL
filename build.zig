const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // KL Runtime Library
    // This contains native hook implementations that generated code will link against
    const runtime_module = b.createModule(.{
        .root_source_file = b.path("src/runtime_lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const runtime_lib = b.addLibrary(.{
        .name = "klruntime",
        .root_module = runtime_module,
        .linkage = .static,
    });
    
    b.installArtifact(runtime_lib);

    // Main executable
    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    
    const exe = b.addExecutable(.{
        .name = "klc",
        .root_module = exe_module,
    });

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the KL compiler");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    
    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
