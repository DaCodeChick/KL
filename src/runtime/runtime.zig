// KL Runtime Library
// This module exports native hook implementations that can be called from
// generated KL assembly code. All functions use C calling convention for
// compatibility with generated code.

const std = @import("std");

// Import and force compilation of runtime modules
// The _ = comptime ensures the modules are analyzed and their exports are retained
const system_runtime = @import("system_runtime.zig");
comptime {
    _ = system_runtime;
}

// Future: Export other module native hooks
// const mcli_runtime = @import("mcli_runtime.zig");
// comptime { _ = mcli_runtime; }
