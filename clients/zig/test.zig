const std = @import("std");
const flags2env = @import("flags2env");

test "parse JSON argv through the C core" {
    const config_path = "flags2env-zig-smoke.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = config_path, .data =
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
    });
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

test "subcommands, scoped help, coercion, and codegen through the C core" {
    const config_path = "flags2env-zig-subcommands.toml";
    try std.fs.cwd().writeFile(.{ .sub_path = config_path, .data =
        \\[flags.verbose]
        \\env = "GITISH_VERBOSE"
        \\aliases = ["verbose"]
        \\type = "bool"
        \\
        \\[commands.remote]
        \\help = "Manage remotes."
        \\
        \\[commands.remote.commands.add]
        \\help = "Add a remote."
        \\
        \\[commands.remote.commands.add.flags.fetch]
        \\env = "GITISH_REMOTE_ADD_FETCH"
        \\aliases = ["fetch"]
        \\short = "f"
        \\type = "bool"
        \\
    });
    defer std.fs.cwd().deleteFile(config_path) catch {};

    const allocator = std.testing.allocator;

    const parsed = try flags2env.parseJsonArgvFromFile(
        allocator,
        config_path,
        "[\"gitish\",\"remote\",\"add\",\"-f\"]",
    );
    defer allocator.free(parsed);
    try std.testing.expect(std.mem.indexOf(u8, parsed, "\"FLAGS2ENV_COMMAND\":\"remote add\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, parsed, "\"GITISH_REMOTE_ADD_FETCH\":\"true\"") != null);

    try std.testing.expect(flags2env.isHelpRequestedJsonArgv("[\"gitish\",\"add\",\"--help\"]"));
    try std.testing.expect(!flags2env.isHelpRequestedJsonArgv("[\"gitish\",\"add\"]"));

    const scoped_help = try flags2env.helpTableForJsonArgvFromFile(
        allocator,
        config_path,
        "gitish",
        "[\"gitish\",\"remote\",\"add\",\"--help\"]",
        100,
    );
    defer allocator.free(scoped_help);
    try std.testing.expect(std.mem.indexOf(u8, scoped_help, "Command: gitish remote add [OPTIONS]") != null);
    try std.testing.expect(std.mem.indexOf(u8, scoped_help, "--fetch") != null);

    const coerced = try flags2env.coerceJsonFromFile(
        allocator,
        config_path,
        "{\"FLAGS2ENV_COMMAND\":\"remote add\",\"GITISH_REMOTE_ADD_FETCH\":\"true\"}",
    );
    defer allocator.free(coerced);
    try std.testing.expect(std.mem.indexOf(u8, coerced, "\"ok\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, coerced, "\"GITISH_REMOTE_ADD_FETCH\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, coerced, "\"FLAGS2ENV_COMMAND\":\"remote add\"") != null);

    const generated = try flags2env.generateTypesFromFile(allocator, config_path, "typescript", "GitishConfig");
    defer allocator.free(generated);
    try std.testing.expect(std.mem.indexOf(u8, generated, "FLAGS2ENV_COMMAND?: string;") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "GITISH_REMOTE_ADD_FETCH?: boolean;") != null);
}
