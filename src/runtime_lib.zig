// KL Runtime Library
// This module exports native hook implementations that can be called from
// generated KL assembly code. All functions use C calling convention for
// compatibility with generated code.

const std = @import("std");

// Import and force compilation of runtime modules
// The _ = comptime ensures the modules are analyzed and their exports are retained
const system = @import("runtime/system.zig");
comptime {
    _ = system;
}

// Future: Export other module native hooks
// const mcli = @import("runtime/mcli.zig");
// comptime { _ = mcli; }
