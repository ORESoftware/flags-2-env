const std = @import("std");

const c = @cImport({
    @cInclude("parser.h");
});

pub fn parseJsonArgv(allocator: std.mem.Allocator, argv_json: [:0]const u8) ![]u8 {
    return copyOwned(allocator, c.f2e_parse_json_argv(argv_json.ptr));
}

pub fn parseJsonArgvFromFile(allocator: std.mem.Allocator, config_path: [:0]const u8, argv_json: [:0]const u8) ![]u8 {
    return copyOwned(allocator, c.f2e_parse_json_argv_from_file(config_path.ptr, argv_json.ptr));
}

pub fn parseProcess(allocator: std.mem.Allocator) ![]u8 {
    return copyOwned(allocator, c.f2e_parse_process());
}

pub fn parseProcessFromFile(allocator: std.mem.Allocator, config_path: [:0]const u8) ![]u8 {
    return copyOwned(allocator, c.f2e_parse_process_from_file(config_path.ptr));
}

pub fn isHelpRequestedJsonArgv(argv_json: [:0]const u8) bool {
    return c.f2e_is_help_requested_json_argv(argv_json.ptr) != 0;
}

/// Renders the help table for the [commands.*] path selected by argv_json;
/// with no matching command this renders the top-level menu including the
/// Commands section when subcommands are declared.
pub fn helpTableForJsonArgv(allocator: std.mem.Allocator, command: [:0]const u8, argv_json: [:0]const u8, terminal_columns: c_int) ![]u8 {
    return copyOwnedOr(allocator, c.f2e_help_table_for_json_argv(command.ptr, argv_json.ptr, terminal_columns), "");
}

pub fn helpTableForJsonArgvFromFile(allocator: std.mem.Allocator, config_path: [:0]const u8, command: [:0]const u8, argv_json: [:0]const u8, terminal_columns: c_int) ![]u8 {
    return copyOwnedOr(allocator, c.f2e_help_table_for_json_argv_from_file(config_path.ptr, command.ptr, argv_json.ptr, terminal_columns), "");
}

/// Returns the raw coercion report JSON: {"ok":true,"value":{...}} or
/// {"ok":false,"errors":[...]}. Subcommand flag envs, command marker envs,
/// and the command path env are all coerced.
pub fn coerceJson(allocator: std.mem.Allocator, values_json: [:0]const u8) ![]u8 {
    return copyOwnedOr(allocator, c.f2e_coerce_json(values_json.ptr), "{\"ok\":false,\"errors\":[\"coercion failed\"]}");
}

pub fn coerceJsonFromFile(allocator: std.mem.Allocator, config_path: [:0]const u8, values_json: [:0]const u8) ![]u8 {
    return copyOwnedOr(allocator, c.f2e_coerce_json_from_file(config_path.ptr, values_json.ptr), "{\"ok\":false,\"errors\":[\"coercion failed\"]}");
}

/// Generates importable types; subcommand flag envs and command envs are
/// included as optional fields. Returns "" when generation fails.
pub fn generateTypes(allocator: std.mem.Allocator, language: [:0]const u8, type_name: ?[:0]const u8) ![]u8 {
    return copyOwnedOr(allocator, c.f2e_generate_types(language.ptr, if (type_name) |name| name.ptr else null), "");
}

pub fn generateTypesFromFile(allocator: std.mem.Allocator, config_path: [:0]const u8, language: [:0]const u8, type_name: ?[:0]const u8) ![]u8 {
    return copyOwnedOr(allocator, c.f2e_generate_types_from_file(config_path.ptr, language.ptr, if (type_name) |name| name.ptr else null), "");
}

fn copyOwned(allocator: std.mem.Allocator, ptr: [*c]u8) ![]u8 {
    return copyOwnedOr(allocator, ptr, "{}");
}

fn copyOwnedOr(allocator: std.mem.Allocator, ptr: [*c]u8, fallback: []const u8) ![]u8 {
    if (ptr == null) {
        return allocator.dupe(u8, fallback);
    }
    defer c.f2e_free(ptr);
    const cstr: [*:0]u8 = @ptrCast(ptr);
    return allocator.dupe(u8, std.mem.span(cstr));
}
