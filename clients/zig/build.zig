const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("flags2env", .{
        .root_source_file = b.path("src/flags2env.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addIncludePath(b.path("../../src"));

    const parser = b.addStaticLibrary(.{
        .name = "flags2env_parser",
        .target = target,
        .optimize = optimize,
    });
    parser.addCSourceFile(.{
        .file = b.path("../../src/parser.c"),
        .flags = &.{"-std=c99", "-Wall", "-Wextra"},
    });
    parser.addIncludePath(b.path("../../src"));
    parser.linkLibC();

    const tests = b.addTest(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("flags2env", module);
    tests.linkLibrary(parser);
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run Zig smoke tests");
    test_step.dependOn(&run_tests.step);
}
