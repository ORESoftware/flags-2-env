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

fn copyOwned(allocator: std.mem.Allocator, ptr: [*c]u8) ![]u8 {
    if (ptr == null) {
        return allocator.dupe(u8, "{}");
    }
    defer c.f2e_free(ptr);
    const cstr: [*:0]u8 = @ptrCast(ptr);
    return allocator.dupe(u8, std.mem.span(cstr));
}
