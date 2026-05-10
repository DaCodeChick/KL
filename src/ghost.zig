const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");
const SourceLocation = @import("error.zig").SourceLocation;

/// Ghost Module Generator
/// Creates in-memory AST for the System runtime module without parsing any files.
/// This allows the compiler to provide built-in runtime functions that are
/// resolved at compile-time but implemented with native code or system calls.

/// Generate the System module ghost AST
pub fn generateSystemModule(allocator: std.mem.Allocator) !*ast.ModuleNode {
    // Create a synthetic source location for ghost module
    const ghost_location = SourceLocation{
        .line = 0,
        .column = 0,
        .file = "<System>",
    };
    
    const system_module = try ast.ModuleNode.init(allocator, ghost_location, "System");
    
    // Add System.Print command
    // Signature: Command Print[msg: text]
    const print_cmd = try ast.CommandImplNode.init(
        allocator,
        ghost_location,
        "Print",
    );
    print_cmd.native_hook = "kl_sys_print";  // Static string slice - zero allocation!
    
    const print_param = try ast.ParamDeclNode.init(
        allocator,
        ghost_location,
        "msg",
        types.KLType{ .text = {} },
        null, // no initial value
    );
    try print_cmd.parameters.append(allocator, print_param);
    try system_module.commands.append(allocator, print_cmd);
    
    // Add System.PrintLn command
    // Signature: Command PrintLn[msg: text]
    const println_cmd = try ast.CommandImplNode.init(
        allocator,
        ghost_location,
        "PrintLn",
    );
    println_cmd.native_hook = "kl_sys_println";
    
    const println_param = try ast.ParamDeclNode.init(
        allocator,
        ghost_location,
        "msg",
        types.KLType{ .text = {} },
        null, // no initial value
    );
    try println_cmd.parameters.append(allocator, println_param);
    try system_module.commands.append(allocator, println_cmd);
    
    // Add System.Exit command
    // Signature: Command Exit[code: sint32]
    const exit_cmd = try ast.CommandImplNode.init(
        allocator,
        ghost_location,
        "Exit",
    );
    exit_cmd.native_hook = "kl_sys_exit";
    
    const exit_param = try ast.ParamDeclNode.init(
        allocator,
        ghost_location,
        "code",
        types.KLType{ .sint32 = {} },
        null, // no initial value
    );
    try exit_cmd.parameters.append(allocator, exit_param);
    try system_module.commands.append(allocator, exit_cmd);
    
    return system_module;
}

/// Check if a command invocation is calling a System intrinsic
pub fn isSystemIntrinsic(command_name: []const u8) bool {
    return std.mem.startsWith(u8, command_name, "System.") or
           std.mem.startsWith(u8, command_name, "system.");
}

/// Get the native hook name from a qualified System call name
/// Maps "System.Exit" -> "kl_sys_exit", etc.
/// Returns a static string slice - zero allocation!
pub fn getNativeHook(command_name: []const u8) []const u8 {
    // Handle both System.Print and system.print
    var lower_buf: [256]u8 = undefined;
    if (command_name.len > lower_buf.len) return "unknown";
    
    const lower_name = std.ascii.lowerString(&lower_buf, command_name);
    
    if (std.mem.eql(u8, lower_name, "system.print")) return "kl_sys_print";
    if (std.mem.eql(u8, lower_name, "system.println")) return "kl_sys_println";
    if (std.mem.eql(u8, lower_name, "system.read")) return "kl_sys_read";
    if (std.mem.eql(u8, lower_name, "system.readln")) return "kl_sys_readln";
    if (std.mem.eql(u8, lower_name, "system.exit")) return "kl_sys_exit";
    
    return "unknown";
}

test "generate System module" {
    const allocator = std.testing.allocator;
    
    const system = try generateSystemModule(allocator);
    defer system.deinit(allocator);
    
    try std.testing.expectEqualStrings("System", system.name);
    try std.testing.expect(system.commands.items.len >= 1);
    
    // Check Print command
    const print_cmd = system.commands.items[0];
    try std.testing.expectEqualStrings("Print", print_cmd.name);
    // Ghost module commands still use the old approach - will be removed soon
    try std.testing.expectEqual(@as(usize, 1), print_cmd.parameters.items.len);
}

test "intrinsic detection" {
    try std.testing.expect(isSystemIntrinsic("System.Print"));
    try std.testing.expect(isSystemIntrinsic("system.println"));
    try std.testing.expect(!isSystemIntrinsic("MyModule.Foo"));
    try std.testing.expect(!isSystemIntrinsic("Print"));
}
