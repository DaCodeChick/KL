const std = @import("std");
const intrinsics = @import("../intrinsics.zig");

/// MCLI (Modular Command Line Interface) Runtime Support
/// Stub for future command-line argument parsing intrinsics.

/// Native hook mapping table for MCLI module
/// Currently empty - populate when implementing MCLI intrinsics
pub const mcli_hooks = [_]intrinsics.HookMapping{};

/// Check if a command invocation is calling an MCLI intrinsic
pub fn isMCLIIntrinsic(command_name: []const u8) bool {
    return intrinsics.isIntrinsic(command_name, "MCLI");
}

test "intrinsic detection" {
    try std.testing.expect(isMCLIIntrinsic("MCLI.ArgCount"));
    try std.testing.expect(isMCLIIntrinsic("mcli.getarg"));
    try std.testing.expect(!isMCLIIntrinsic("System.Exit"));
    try std.testing.expect(!isMCLIIntrinsic("ArgCount"));
}
