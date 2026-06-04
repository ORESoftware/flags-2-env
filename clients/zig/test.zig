const std = @import("std");
const flags2env = @import("flags2env");

test "parse JSON argv through the C core" {
    const config_path = "flags2env-zig-smoke.toml";
    var config_file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer config_file.close();
    try config_file.writeAll(
        \\[flags.port]
        \\env = "PORT"
        \\aliases = ["port"]
        \\type = "integer"
        \\
        \\[flags.debug]
        \\env = "DEBUG"
        \\aliases = ["debug"]
        \\type = "bool"
        \\true_aliases = ["t"]
        \\
    );
    defer std.fs.cwd().deleteFile(config_path) catch {};

    const parsed = try flags2env.parseJsonArgvFromFile(
        std.testing.allocator,
        config_path,
        "[\"app\",\"--port\",\"8181\",\"--debug=t\"]",
    );
    defer std.testing.allocator.free(parsed);

    try std.testing.expect(std.mem.indexOf(u8, parsed, "\"PORT\":\"8181\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, parsed, "\"DEBUG\":\"true\"") != null);
}
