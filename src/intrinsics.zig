const std = @import("std");

/// Common intrinsics API for runtime modules
/// Provides utilities for checking and resolving native hooks for built-in modules.

/// Check if a qualified name belongs to a specific module
pub fn isIntrinsic(command_name: []const u8, module_prefix: []const u8) bool {
    // Build lowercase version for case-insensitive comparison
    var lower_buf: [256]u8 = undefined;
    if (command_name.len > lower_buf.len) return false;
    
    const lower_name = std.ascii.lowerString(&lower_buf, command_name);
    
    // Build lowercase module prefix with dot
    var prefix_buf: [128]u8 = undefined;
    if (module_prefix.len + 1 > prefix_buf.len) return false;
    
    _ = std.ascii.lowerString(prefix_buf[0..module_prefix.len], module_prefix);
    prefix_buf[module_prefix.len] = '.';
    const prefix_with_dot = prefix_buf[0..module_prefix.len + 1];
    
    return std.mem.startsWith(u8, lower_name, prefix_with_dot);
}

/// Get native hook name from a mapping table
/// Returns "unknown" if the command is not found in the table
pub fn getNativeHook(command_name: []const u8, hook_map: []const HookMapping) []const u8 {
    // Convert to lowercase for case-insensitive lookup
    var lower_buf: [256]u8 = undefined;
    if (command_name.len > lower_buf.len) return "unknown";
    
    const lower_name = std.ascii.lowerString(&lower_buf, command_name);
    
    // Search through the hook mapping table
    for (hook_map) |mapping| {
        if (std.mem.eql(u8, lower_name, mapping.qualified_name)) {
            return mapping.native_hook;
        }
    }
    
    return "unknown";
}

/// Hook mapping entry: qualified name -> native hook
pub const HookMapping = struct {
    qualified_name: []const u8,  // e.g. "system.print"
    native_hook: []const u8,     // e.g. "kl_sys_print"
};

test "isIntrinsic detection" {
    try std.testing.expect(isIntrinsic("System.Print", "System"));
    try std.testing.expect(isIntrinsic("system.print", "System"));
    try std.testing.expect(isIntrinsic("SYSTEM.PRINT", "System"));
    try std.testing.expect(!isIntrinsic("MyModule.Foo", "System"));
    try std.testing.expect(!isIntrinsic("Print", "System"));
    
    try std.testing.expect(isIntrinsic("MCLI.ArgCount", "MCLI"));
    try std.testing.expect(isIntrinsic("mcli.argcount", "MCLI"));
    try std.testing.expect(!isIntrinsic("System.Print", "MCLI"));
}

test "getNativeHook lookup" {
    const test_hooks = [_]HookMapping{
        .{ .qualified_name = "system.print", .native_hook = "kl_sys_print" },
        .{ .qualified_name = "system.exit", .native_hook = "kl_sys_exit" },
        .{ .qualified_name = "mcli.argcount", .native_hook = "kl_mcli_argcount" },
    };
    
    try std.testing.expectEqualStrings("kl_sys_print", getNativeHook("system.print", &test_hooks));
    try std.testing.expectEqualStrings("kl_sys_print", getNativeHook("System.Print", &test_hooks));
    try std.testing.expectEqualStrings("kl_sys_exit", getNativeHook("SYSTEM.EXIT", &test_hooks));
    try std.testing.expectEqualStrings("kl_mcli_argcount", getNativeHook("MCLI.ArgCount", &test_hooks));
    try std.testing.expectEqualStrings("unknown", getNativeHook("system.unknown", &test_hooks));
    try std.testing.expectEqualStrings("unknown", getNativeHook("Print", &test_hooks));
}
