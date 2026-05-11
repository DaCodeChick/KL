const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const SourceLocation = @import("../error.zig").SourceLocation;
const intrinsics = @import("../intrinsics.zig");

/// System Module Runtime Support
/// Provides built-in System module commands that map to native implementations.

/// Native hook mapping table for System module
/// Currently empty - System module uses stdlib/System.kl for now
pub const system_hooks = [_]intrinsics.HookMapping{};

/// Generate the System module AST with native intrinsics
/// Currently returns an empty module - System is loaded from stdlib/System.kl
pub fn generateSystemModule(allocator: std.mem.Allocator) !*ast.ModuleNode {
    const builtin_location = SourceLocation{
        .line = 0,
        .column = 0,
        .file = "<System>",
    };
    
    const system_module = try ast.ModuleNode.init(allocator, builtin_location, "System");
    return system_module;
}

/// Check if a command invocation is calling a System intrinsic
pub fn isSystemIntrinsic(command_name: []const u8) bool {
    return intrinsics.isIntrinsic(command_name, "System");
}

test "generate System module" {
    const allocator = std.testing.allocator;
    
    const system = try generateSystemModule(allocator);
    defer system.deinit(allocator);
    
    try std.testing.expectEqualStrings("System", system.name);
    try std.testing.expect(system.commands.items.len == 0);
    try std.testing.expect(system.functions.items.len == 0);
}

test "intrinsic detection" {
    try std.testing.expect(isSystemIntrinsic("System.Exit"));
    try std.testing.expect(isSystemIntrinsic("system.add"));
    try std.testing.expect(!isSystemIntrinsic("MyModule.Foo"));
    try std.testing.expect(!isSystemIntrinsic("Exit"));
}
