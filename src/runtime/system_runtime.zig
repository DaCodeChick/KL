// System Module Runtime Implementation
// Native hook functions exported with C calling convention
// These are called from generated KL assembly code

const std = @import("std");

/// Add - Variadic addition
/// Takes a pointer to an array of i32 values and returns their sum
/// Calling convention: args in rdi (pointer), rsi (count); result in rax
pub export fn kl_sys_add(args_ptr: [*]const i32, count: usize) callconv(.c) i32 {
    if (count == 0) return 0;
    
    var sum: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        sum += args_ptr[i];
    }
    return sum;
}

// ============================================================================
// Tests for runtime functions
// ============================================================================

test "kl_sys_add runtime function" {
    // Test 0 arguments
    const result0 = kl_sys_add(undefined, 0);
    try std.testing.expectEqual(@as(i32, 0), result0);
    
    // Test 1 argument
    const args1 = [_]i32{5};
    const result1 = kl_sys_add(&args1, 1);
    try std.testing.expectEqual(@as(i32, 5), result1);
    
    // Test 2 arguments
    const args2 = [_]i32{10, 20};
    const result2 = kl_sys_add(&args2, 2);
    try std.testing.expectEqual(@as(i32, 30), result2);
    
    // Test 3 arguments
    const args3 = [_]i32{1, 2, 3};
    const result3 = kl_sys_add(&args3, 3);
    try std.testing.expectEqual(@as(i32, 6), result3);
    
    // Test many arguments
    const args_many = [_]i32{100, 200, 300, 400};
    const result_many = kl_sys_add(&args_many, 4);
    try std.testing.expectEqual(@as(i32, 1000), result_many);
}
