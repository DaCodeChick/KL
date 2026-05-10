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
    const print_cmd = try ast.CommandImplNode.initIntrinsic(
        allocator,
        ghost_location,
        "Print",
        .system_print,
    );
    
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
    const println_cmd = try ast.CommandImplNode.initIntrinsic(
        allocator,
        ghost_location,
        "PrintLn",
        .system_println,
    );
    
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
    const exit_cmd = try ast.CommandImplNode.initIntrinsic(
        allocator,
        ghost_location,
        "Exit",
        .system_exit,
    );
    
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

/// Get the intrinsic ID from a qualified System call name
pub fn getIntrinsicId(command_name: []const u8) ast.IntrinsicId {
    // Handle both System.Print and system.print
    var lower_buf: [256]u8 = undefined;
    if (command_name.len > lower_buf.len) return .none;
    
    const lower_name = std.ascii.lowerString(&lower_buf, command_name);
    
    if (std.mem.eql(u8, lower_name, "system.print")) return .system_print;
    if (std.mem.eql(u8, lower_name, "system.println")) return .system_println;
    if (std.mem.eql(u8, lower_name, "system.read")) return .system_read;
    if (std.mem.eql(u8, lower_name, "system.readln")) return .system_readln;
    if (std.mem.eql(u8, lower_name, "system.exit")) return .system_exit;
    
    return .none;
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
    try std.testing.expect(print_cmd.is_intrinsic);
    try std.testing.expectEqual(ast.IntrinsicId.system_print, print_cmd.intrinsic_id);
    try std.testing.expectEqual(@as(usize, 1), print_cmd.parameters.items.len);
}

test "intrinsic detection" {
    try std.testing.expect(isSystemIntrinsic("System.Print"));
    try std.testing.expect(isSystemIntrinsic("system.println"));
    try std.testing.expect(!isSystemIntrinsic("MyModule.Foo"));
    try std.testing.expect(!isSystemIntrinsic("Print"));
}
