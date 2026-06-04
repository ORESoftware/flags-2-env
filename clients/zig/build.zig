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
}
