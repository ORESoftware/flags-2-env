const std = @import("std");
const flags2env = @import("flags2env");

test "parse JSON argv through the C core" {
    const parsed = try flags2env.parseJsonArgvFromFile(
        std.testing.allocator,
        "../../tests/fixtures/.cli-flags.toml",
        "[\"app\",\"--port\",\"8181\",\"--debug=t\"]",
    );
    defer std.testing.allocator.free(parsed);

    try std.testing.expect(std.mem.indexOf(u8, parsed, "\"PORT\":\"8181\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, parsed, "\"DEBUG\":\"true\"") != null);
}
