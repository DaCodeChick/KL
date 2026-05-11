const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("../types.zig");
const SourceLocation = @import("../error.zig").SourceLocation;
const intrinsics = @import("../intrinsics.zig");

/// System Module - Compiler-Side Registry
///
/// The System module is special - it's automatically imported and available globally.
/// Functions like Add, Sub, Mul can be called without the System. prefix.
///
/// This file contains compiler-side registries and detection:
/// - Compiler intrinsics list (Sub, Mul, Div, DivRem, Count, Get) - expanded inline to IR
/// - Native hooks mapping (Add, etc.) - call runtime library functions via system.zig
/// - AST generation and intrinsic detection helpers
///
/// Runtime implementations are in system.zig (the runtime version).
/// List of System compiler intrinsics (none - all moved to native hooks)
pub const compiler_intrinsics = [_][]const u8{};

/// Native hook mapping table for System module
/// These call external C functions via native hooks
/// Legacy mapping for backward compatibility (defaults to i32)
pub const system_hooks = [_]intrinsics.HookMapping{
    .{ .qualified_name = "system.add", .native_hook = "kl_sys_add" },
    .{ .qualified_name = "system.sub", .native_hook = "kl_sys_sub" },
    .{ .qualified_name = "system.mul", .native_hook = "kl_sys_mul" },
    .{ .qualified_name = "system.div", .native_hook = "kl_sys_div" },
    .{ .qualified_name = "system.divrem", .native_hook = "kl_sys_divrem" },
};

/// Get the type-specific native hook name for a System operation
/// operation: "add", "sub", "mul", "div", "divrem"
/// type_name: "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64"
pub fn getNativeHookForType(operation: []const u8, type_name: []const u8) ?[]const u8 {
    // Map operation + type to native hook name
    // Format: kl_sys_{operation}_{type}
    // e.g., "add" + "i32" -> "kl_sys_add_i32"

    // Validate operation
    const valid_operations = [_][]const u8{ "add", "sub", "mul", "div", "divrem" };
    var found = false;
    for (valid_operations) |op| {
        if (std.mem.eql(u8, operation, op)) {
            found = true;
            break;
        }
    }
    if (!found) return null;

    // Validate type
    const valid_types = [_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64" };
    found = false;
    for (valid_types) |t| {
        if (std.mem.eql(u8, type_name, t)) {
            found = true;
            break;
        }
    }
    if (!found) return null;

    // For divrem, integer types only
    if (std.mem.eql(u8, operation, "divrem")) {
        if (std.mem.eql(u8, type_name, "f32") or std.mem.eql(u8, type_name, "f64")) {
            return null;
        }
    }

    // Build hook name: kl_sys_{operation}_{type}
    // Note: This returns a comptime-known string for each combination
    if (std.mem.eql(u8, operation, "add")) {
        if (std.mem.eql(u8, type_name, "i8")) return "kl_sys_add_i8";
        if (std.mem.eql(u8, type_name, "i16")) return "kl_sys_add_i16";
        if (std.mem.eql(u8, type_name, "i32")) return "kl_sys_add_i32";
        if (std.mem.eql(u8, type_name, "i64")) return "kl_sys_add_i64";
        if (std.mem.eql(u8, type_name, "u8")) return "kl_sys_add_u8";
        if (std.mem.eql(u8, type_name, "u16")) return "kl_sys_add_u16";
        if (std.mem.eql(u8, type_name, "u32")) return "kl_sys_add_u32";
        if (std.mem.eql(u8, type_name, "u64")) return "kl_sys_add_u64";
        if (std.mem.eql(u8, type_name, "f32")) return "kl_sys_add_f32";
        if (std.mem.eql(u8, type_name, "f64")) return "kl_sys_add_f64";
    } else if (std.mem.eql(u8, operation, "sub")) {
        if (std.mem.eql(u8, type_name, "i8")) return "kl_sys_sub_i8";
        if (std.mem.eql(u8, type_name, "i16")) return "kl_sys_sub_i16";
        if (std.mem.eql(u8, type_name, "i32")) return "kl_sys_sub_i32";
        if (std.mem.eql(u8, type_name, "i64")) return "kl_sys_sub_i64";
        if (std.mem.eql(u8, type_name, "u8")) return "kl_sys_sub_u8";
        if (std.mem.eql(u8, type_name, "u16")) return "kl_sys_sub_u16";
        if (std.mem.eql(u8, type_name, "u32")) return "kl_sys_sub_u32";
        if (std.mem.eql(u8, type_name, "u64")) return "kl_sys_sub_u64";
        if (std.mem.eql(u8, type_name, "f32")) return "kl_sys_sub_f32";
        if (std.mem.eql(u8, type_name, "f64")) return "kl_sys_sub_f64";
    } else if (std.mem.eql(u8, operation, "mul")) {
        if (std.mem.eql(u8, type_name, "i8")) return "kl_sys_mul_i8";
        if (std.mem.eql(u8, type_name, "i16")) return "kl_sys_mul_i16";
        if (std.mem.eql(u8, type_name, "i32")) return "kl_sys_mul_i32";
        if (std.mem.eql(u8, type_name, "i64")) return "kl_sys_mul_i64";
        if (std.mem.eql(u8, type_name, "u8")) return "kl_sys_mul_u8";
        if (std.mem.eql(u8, type_name, "u16")) return "kl_sys_mul_u16";
        if (std.mem.eql(u8, type_name, "u32")) return "kl_sys_mul_u32";
        if (std.mem.eql(u8, type_name, "u64")) return "kl_sys_mul_u64";
        if (std.mem.eql(u8, type_name, "f32")) return "kl_sys_mul_f32";
        if (std.mem.eql(u8, type_name, "f64")) return "kl_sys_mul_f64";
    } else if (std.mem.eql(u8, operation, "div")) {
        if (std.mem.eql(u8, type_name, "i8")) return "kl_sys_div_i8";
        if (std.mem.eql(u8, type_name, "i16")) return "kl_sys_div_i16";
        if (std.mem.eql(u8, type_name, "i32")) return "kl_sys_div_i32";
        if (std.mem.eql(u8, type_name, "i64")) return "kl_sys_div_i64";
        if (std.mem.eql(u8, type_name, "u8")) return "kl_sys_div_u8";
        if (std.mem.eql(u8, type_name, "u16")) return "kl_sys_div_u16";
        if (std.mem.eql(u8, type_name, "u32")) return "kl_sys_div_u32";
        if (std.mem.eql(u8, type_name, "u64")) return "kl_sys_div_u64";
        if (std.mem.eql(u8, type_name, "f32")) return "kl_sys_div_f32";
        if (std.mem.eql(u8, type_name, "f64")) return "kl_sys_div_f64";
    } else if (std.mem.eql(u8, operation, "divrem")) {
        if (std.mem.eql(u8, type_name, "i8")) return "kl_sys_divrem_i8";
        if (std.mem.eql(u8, type_name, "i16")) return "kl_sys_divrem_i16";
        if (std.mem.eql(u8, type_name, "i32")) return "kl_sys_divrem_i32";
        if (std.mem.eql(u8, type_name, "i64")) return "kl_sys_divrem_i64";
        if (std.mem.eql(u8, type_name, "u8")) return "kl_sys_divrem_u8";
        if (std.mem.eql(u8, type_name, "u16")) return "kl_sys_divrem_u16";
        if (std.mem.eql(u8, type_name, "u32")) return "kl_sys_divrem_u32";
        if (std.mem.eql(u8, type_name, "u64")) return "kl_sys_divrem_u64";
    }

    return null;
}

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
    try std.testing.expect(!isCompilerIntrinsic("Add")); // Now a native hook
    try std.testing.expect(!isCompilerIntrinsic("Sub")); // Now a native hook
    try std.testing.expect(!isCompilerIntrinsic("Mul")); // Now a native hook
    try std.testing.expect(!isCompilerIntrinsic("Div")); // Now a native hook
    try std.testing.expect(!isCompilerIntrinsic("DivRem")); // Now a native hook
}

// ============================================================================
// Runtime-Side: Native Hook Implementations for All Types
// ============================================================================

// Generic implementations
fn GenericAdd(comptime T: type) type {
    return struct {
        pub fn call(args_ptr: [*]const T, count: usize) T {
            if (count == 0) return 0;
            var sum: T = 0;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                sum += args_ptr[i];
            }
            return sum;
        }
    };
}

fn GenericSub(comptime T: type) type {
    return struct {
        pub fn call(args_ptr: [*]const T, count: usize) T {
            if (count == 0) return 0;
            if (count == 1) return args_ptr[0];
            var result: T = args_ptr[0];
            var i: usize = 1;
            while (i < count) : (i += 1) {
                result -= args_ptr[i];
            }
            return result;
        }
    };
}

fn GenericMul(comptime T: type) type {
    return struct {
        pub fn call(args_ptr: [*]const T, count: usize) T {
            if (count == 0) return 1;
            var result: T = 1;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                result *= args_ptr[i];
            }
            return result;
        }
    };
}

fn GenericDiv(comptime T: type) type {
    const is_float = (T == f32 or T == f64);
    return struct {
        pub fn call(args_ptr: [*]const T, count: usize) T {
            if (count == 0) return 1;
            if (count == 1) return args_ptr[0];
            var result: T = args_ptr[0];
            var i: usize = 1;
            while (i < count) : (i += 1) {
                if (is_float) {
                    result /= args_ptr[i];
                } else {
                    result = @divTrunc(result, args_ptr[i]);
                }
            }
            return result;
        }
    };
}

fn GenericDivRem(comptime T: type) type {
    return struct {
        pub fn call(args_ptr: [*]const T, count: usize) T {
            if (count != 2) return 0;
            return @rem(args_ptr[0], args_ptr[1]);
        }
    };
}

// Signed integers
pub export fn kl_sys_add_i8(args_ptr: [*]const i8, count: usize) callconv(.c) i8 {
    return GenericAdd(i8).call(args_ptr, count);
}
pub export fn kl_sys_add_i16(args_ptr: [*]const i16, count: usize) callconv(.c) i16 {
    return GenericAdd(i16).call(args_ptr, count);
}
pub export fn kl_sys_add_i32(args_ptr: [*]const i32, count: usize) callconv(.c) i32 {
    return GenericAdd(i32).call(args_ptr, count);
}
pub export fn kl_sys_add_i64(args_ptr: [*]const i64, count: usize) callconv(.c) i64 {
    return GenericAdd(i64).call(args_ptr, count);
}

pub export fn kl_sys_sub_i8(args_ptr: [*]const i8, count: usize) callconv(.c) i8 {
    return GenericSub(i8).call(args_ptr, count);
}
pub export fn kl_sys_sub_i16(args_ptr: [*]const i16, count: usize) callconv(.c) i16 {
    return GenericSub(i16).call(args_ptr, count);
}
pub export fn kl_sys_sub_i32(args_ptr: [*]const i32, count: usize) callconv(.c) i32 {
    return GenericSub(i32).call(args_ptr, count);
}
pub export fn kl_sys_sub_i64(args_ptr: [*]const i64, count: usize) callconv(.c) i64 {
    return GenericSub(i64).call(args_ptr, count);
}

pub export fn kl_sys_mul_i8(args_ptr: [*]const i8, count: usize) callconv(.c) i8 {
    return GenericMul(i8).call(args_ptr, count);
}
pub export fn kl_sys_mul_i16(args_ptr: [*]const i16, count: usize) callconv(.c) i16 {
    return GenericMul(i16).call(args_ptr, count);
}
pub export fn kl_sys_mul_i32(args_ptr: [*]const i32, count: usize) callconv(.c) i32 {
    return GenericMul(i32).call(args_ptr, count);
}
pub export fn kl_sys_mul_i64(args_ptr: [*]const i64, count: usize) callconv(.c) i64 {
    return GenericMul(i64).call(args_ptr, count);
}

pub export fn kl_sys_div_i8(args_ptr: [*]const i8, count: usize) callconv(.c) i8 {
    return GenericDiv(i8).call(args_ptr, count);
}
pub export fn kl_sys_div_i16(args_ptr: [*]const i16, count: usize) callconv(.c) i16 {
    return GenericDiv(i16).call(args_ptr, count);
}
pub export fn kl_sys_div_i32(args_ptr: [*]const i32, count: usize) callconv(.c) i32 {
    return GenericDiv(i32).call(args_ptr, count);
}
pub export fn kl_sys_div_i64(args_ptr: [*]const i64, count: usize) callconv(.c) i64 {
    return GenericDiv(i64).call(args_ptr, count);
}

pub export fn kl_sys_divrem_i8(args_ptr: [*]const i8, count: usize) callconv(.c) i8 {
    return GenericDivRem(i8).call(args_ptr, count);
}
pub export fn kl_sys_divrem_i16(args_ptr: [*]const i16, count: usize) callconv(.c) i16 {
    return GenericDivRem(i16).call(args_ptr, count);
}
pub export fn kl_sys_divrem_i32(args_ptr: [*]const i32, count: usize) callconv(.c) i32 {
    return GenericDivRem(i32).call(args_ptr, count);
}
pub export fn kl_sys_divrem_i64(args_ptr: [*]const i64, count: usize) callconv(.c) i64 {
    return GenericDivRem(i64).call(args_ptr, count);
}

// Unsigned integers
pub export fn kl_sys_add_u8(args_ptr: [*]const u8, count: usize) callconv(.c) u8 {
    return GenericAdd(u8).call(args_ptr, count);
}
pub export fn kl_sys_add_u16(args_ptr: [*]const u16, count: usize) callconv(.c) u16 {
    return GenericAdd(u16).call(args_ptr, count);
}
pub export fn kl_sys_add_u32(args_ptr: [*]const u32, count: usize) callconv(.c) u32 {
    return GenericAdd(u32).call(args_ptr, count);
}
pub export fn kl_sys_add_u64(args_ptr: [*]const u64, count: usize) callconv(.c) u64 {
    return GenericAdd(u64).call(args_ptr, count);
}

pub export fn kl_sys_sub_u8(args_ptr: [*]const u8, count: usize) callconv(.c) u8 {
    return GenericSub(u8).call(args_ptr, count);
}
pub export fn kl_sys_sub_u16(args_ptr: [*]const u16, count: usize) callconv(.c) u16 {
    return GenericSub(u16).call(args_ptr, count);
}
pub export fn kl_sys_sub_u32(args_ptr: [*]const u32, count: usize) callconv(.c) u32 {
    return GenericSub(u32).call(args_ptr, count);
}
pub export fn kl_sys_sub_u64(args_ptr: [*]const u64, count: usize) callconv(.c) u64 {
    return GenericSub(u64).call(args_ptr, count);
}

pub export fn kl_sys_mul_u8(args_ptr: [*]const u8, count: usize) callconv(.c) u8 {
    return GenericMul(u8).call(args_ptr, count);
}
pub export fn kl_sys_mul_u16(args_ptr: [*]const u16, count: usize) callconv(.c) u16 {
    return GenericMul(u16).call(args_ptr, count);
}
pub export fn kl_sys_mul_u32(args_ptr: [*]const u32, count: usize) callconv(.c) u32 {
    return GenericMul(u32).call(args_ptr, count);
}
pub export fn kl_sys_mul_u64(args_ptr: [*]const u64, count: usize) callconv(.c) u64 {
    return GenericMul(u64).call(args_ptr, count);
}

pub export fn kl_sys_div_u8(args_ptr: [*]const u8, count: usize) callconv(.c) u8 {
    return GenericDiv(u8).call(args_ptr, count);
}
pub export fn kl_sys_div_u16(args_ptr: [*]const u16, count: usize) callconv(.c) u16 {
    return GenericDiv(u16).call(args_ptr, count);
}
pub export fn kl_sys_div_u32(args_ptr: [*]const u32, count: usize) callconv(.c) u32 {
    return GenericDiv(u32).call(args_ptr, count);
}
pub export fn kl_sys_div_u64(args_ptr: [*]const u64, count: usize) callconv(.c) u64 {
    return GenericDiv(u64).call(args_ptr, count);
}

pub export fn kl_sys_divrem_u8(args_ptr: [*]const u8, count: usize) callconv(.c) u8 {
    return GenericDivRem(u8).call(args_ptr, count);
}
pub export fn kl_sys_divrem_u16(args_ptr: [*]const u16, count: usize) callconv(.c) u16 {
    return GenericDivRem(u16).call(args_ptr, count);
}
pub export fn kl_sys_divrem_u32(args_ptr: [*]const u32, count: usize) callconv(.c) u32 {
    return GenericDivRem(u32).call(args_ptr, count);
}
pub export fn kl_sys_divrem_u64(args_ptr: [*]const u64, count: usize) callconv(.c) u64 {
    return GenericDivRem(u64).call(args_ptr, count);
}

// Floats
pub export fn kl_sys_add_f32(args_ptr: [*]const f32, count: usize) callconv(.c) f32 {
    return GenericAdd(f32).call(args_ptr, count);
}
pub export fn kl_sys_add_f64(args_ptr: [*]const f64, count: usize) callconv(.c) f64 {
    return GenericAdd(f64).call(args_ptr, count);
}

pub export fn kl_sys_sub_f32(args_ptr: [*]const f32, count: usize) callconv(.c) f32 {
    return GenericSub(f32).call(args_ptr, count);
}
pub export fn kl_sys_sub_f64(args_ptr: [*]const f64, count: usize) callconv(.c) f64 {
    return GenericSub(f64).call(args_ptr, count);
}

pub export fn kl_sys_mul_f32(args_ptr: [*]const f32, count: usize) callconv(.c) f32 {
    return GenericMul(f32).call(args_ptr, count);
}
pub export fn kl_sys_mul_f64(args_ptr: [*]const f64, count: usize) callconv(.c) f64 {
    return GenericMul(f64).call(args_ptr, count);
}

pub export fn kl_sys_div_f32(args_ptr: [*]const f32, count: usize) callconv(.c) f32 {
    return GenericDiv(f32).call(args_ptr, count);
}
pub export fn kl_sys_div_f64(args_ptr: [*]const f64, count: usize) callconv(.c) f64 {
    return GenericDiv(f64).call(args_ptr, count);
}

// Tests
test "i32 operations" {
    const add_args = [_]i32{ 10, 20, 30 };
    try std.testing.expectEqual(@as(i32, 60), kl_sys_add_i32(&add_args, 3));

    const sub_args = [_]i32{ 100, 30, 20 };
    try std.testing.expectEqual(@as(i32, 50), kl_sys_sub_i32(&sub_args, 3));
}

test "f32 operations" {
    const add_args = [_]f32{ 1.5, 2.5, 3.0 };
    try std.testing.expectEqual(@as(f32, 7.0), kl_sys_add_f32(&add_args, 3));
}

test "u64 operations" {
    const sub_args = [_]u64{ 1000, 200, 50 };
    try std.testing.expectEqual(@as(u64, 750), kl_sys_sub_u64(&sub_args, 3));
}
