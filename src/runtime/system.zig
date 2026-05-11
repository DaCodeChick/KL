const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const SourceLocation = @import("../error.zig").SourceLocation;
const intrinsics = @import("../intrinsics.zig");

/// System Module Runtime Support
/// 
/// The System module is special - it's automatically imported and available globally.
/// Functions like Add, Sub, Mul can be called without the System. prefix.
/// 
/// System intrinsics come in two flavors:
/// 1. Compiler intrinsics (Add, Sub, Mul, Div, DivRem, Count, Get) - expanded inline to IR
/// 2. Native hooks (future: Exit, Print, etc.) - call external C functions

/// List of System compiler intrinsics (expanded inline, not native calls)
/// Note: Add was converted to a native hook to support variadic number parameters
pub const compiler_intrinsics = [_][]const u8{
    "Sub", 
    "Mul",
    "Div",
    "DivRem",
    "Count",  // Variadic parameter intrinsics
    "Get",
};

/// Native hook mapping table for System module
/// These call external C functions via native hooks
pub const system_hooks = [_]intrinsics.HookMapping{
    .{ .qualified_name = "system.add", .native_hook = "kl_sys_add" },
};

/// Check if a function is a System compiler intrinsic
pub fn isCompilerIntrinsic(func_name: []const u8) bool {
    for (compiler_intrinsics) |name| {
        if (std.mem.eql(u8, func_name, name)) return true;
    }
    return false;
}

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
    try std.testing.expect(isSystemIntrinsic("System.Add"));
    try std.testing.expect(isSystemIntrinsic("system.add"));
    try std.testing.expect(!isSystemIntrinsic("MyModule.Foo"));
    try std.testing.expect(!isSystemIntrinsic("Add"));
}

test "compiler intrinsic detection" {
    try std.testing.expect(!isCompilerIntrinsic("Add"));  // Now a native hook
    try std.testing.expect(isCompilerIntrinsic("Sub"));
    try std.testing.expect(isCompilerIntrinsic("Mul"));
    try std.testing.expect(isCompilerIntrinsic("Div"));
    try std.testing.expect(isCompilerIntrinsic("DivRem"));
    try std.testing.expect(isCompilerIntrinsic("Count"));
    try std.testing.expect(isCompilerIntrinsic("Get"));
    try std.testing.expect(!isCompilerIntrinsic("Exit"));
    try std.testing.expect(!isCompilerIntrinsic("Print"));
}
