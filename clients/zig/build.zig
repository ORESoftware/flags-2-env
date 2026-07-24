const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("flags2env", .{
        .root_source_file = b.path("src/flags2env.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addIncludePath(b.path("native"));

    const parser_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    parser_module.addCSourceFile(.{
        .file = b.path("native/parser.c"),
        .flags = &.{ "-std=c99", "-Wall", "-Wextra" },
    });
    parser_module.addIncludePath(b.path("native"));

    const parser = b.addLibrary(.{
        .name = "flags2env_parser",
        .linkage = .static,
        .root_module = parser_module,
    });

    const tests_module = b.createModule(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tests_module.addImport("flags2env", module);
    tests_module.linkLibrary(parser);

    const tests = b.addTest(.{
        .root_module = tests_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run Zig smoke tests");
    test_step.dependOn(&run_tests.step);
}
