const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const SourceLocation = @import("../error.zig").SourceLocation;
const intrinsics = @import("../intrinsics.zig");

/// System Module Runtime Support
/// Provides built-in System module commands that map to native implementations.

/// Native hook mapping table for System module
pub const system_hooks = [_]intrinsics.HookMapping{
    .{ .qualified_name = "system.exit", .native_hook = "kl_sys_exit" },
};

/// Generate the System module AST with native intrinsics
pub fn generateSystemModule(allocator: std.mem.Allocator) !*ast.ModuleNode {
    const builtin_location = SourceLocation{
        .line = 0,
        .column = 0,
        .file = "<System>",
    };
    
    const system_module = try ast.ModuleNode.init(allocator, builtin_location, "System");
    
    // Add System.Exit command
    // Signature: Command Exit[code: sint32]
    const exit_cmd = try ast.CommandImplNode.init(
        allocator,
        builtin_location,
        "Exit",
    );
    exit_cmd.native_hook = "kl_sys_exit";
    
    const exit_param = try ast.ParamDeclNode.init(
        allocator,
        builtin_location,
        "code",
        types.KLType{ .sint32 = {} },
        null,
    );
    try exit_cmd.parameters.append(allocator, exit_param);
    try system_module.commands.append(allocator, exit_cmd);
    
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
    try std.testing.expect(system.commands.items.len == 1);
    try std.testing.expectEqualStrings("Exit", system.commands.items[0].name);
}

test "intrinsic detection" {
    try std.testing.expect(isSystemIntrinsic("System.Exit"));
    try std.testing.expect(isSystemIntrinsic("system.exit"));
    try std.testing.expect(!isSystemIntrinsic("MyModule.Foo"));
    try std.testing.expect(!isSystemIntrinsic("Exit"));
}
