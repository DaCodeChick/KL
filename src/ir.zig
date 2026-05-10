const std = @import("std");
const types = @import("types.zig");
const ast = @import("ast.zig");

/// Intermediate Representation for KL compiler
/// This represents a low-level, platform-independent representation
/// of the program that can be easily translated to machine code.

pub const Program = struct {
    functions: std.ArrayList(Function),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !*Program {
        const program = try allocator.create(Program);
        program.* = .{
            .functions = .{ .items = &.{}, .capacity = 0 },
            .allocator = allocator,
        };
        return program;
    }
    
    pub fn deinit(self: *Program) void {
        for (self.functions.items) |*func| {
            func.deinit();
        }
        self.functions.deinit(self.allocator);
        self.allocator.destroy(self);
    }
    
    pub fn addFunction(self: *Program, func: Function) !void {
        try self.functions.append(self.allocator, func);
    }
};

pub const Function = struct {
    name: []const u8,
    basic_blocks: std.ArrayList(BasicBlock),
    locals: std.ArrayList(Local),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) Function {
        return .{
            .name = name,
            .basic_blocks = .{ .items = &.{}, .capacity = 0 },
            .locals = .{ .items = &.{}, .capacity = 0 },
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Function) void {
        for (self.basic_blocks.items) |*bb| {
            bb.deinit();
        }
        self.basic_blocks.deinit(self.allocator);
        self.locals.deinit(self.allocator);
    }
    
    pub fn addBlock(self: *Function, block: BasicBlock) !void {
        try self.basic_blocks.append(self.allocator, block);
    }
    
    pub fn addLocal(self: *Function, local: Local) !void {
        try self.locals.append(self.allocator, local);
    }
};

pub const BasicBlock = struct {
    label: []const u8,
    instructions: std.ArrayList(Instruction),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, label: []const u8) BasicBlock {
        return .{
            .label = label,
            .instructions = .{ .items = &.{}, .capacity = 0 },
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *BasicBlock) void {
        self.instructions.deinit(self.allocator);
    }
    
    pub fn addInstruction(self: *BasicBlock, instr: Instruction) !void {
        try self.instructions.append(self.allocator, instr);
    }
};

pub const Local = struct {
    name: []const u8,
    ty: types.KLType,
    /// Stack offset in bytes (set during register allocation/stack layout)
    stack_offset: ?i32 = null,
};

pub const Value = union(enum) {
    local: u32,         // Index into function locals
    constant: Constant,
    temporary: u32,     // Temporary value (SSA register)
};

pub const Constant = union(enum) {
    int: i64,
    uint: u64,
    bool: bool,
    string: []const u8,
};

pub const Instruction = union(enum) {
    /// Load a constant value
    load_const: struct {
        dest: Value,
        value: Constant,
    },
    
    /// Load a local variable
    load_local: struct {
        dest: Value,
        local: u32,
    },
    
    /// Store to a local variable
    store_local: struct {
        local: u32,
        value: Value,
    },
    
    /// Binary arithmetic operations
    add: BinaryOp,
    sub: BinaryOp,
    mul: BinaryOp,
    div: BinaryOp,
    mod: BinaryOp,
    
    /// Binary comparison operations
    eq: BinaryOp,
    ne: BinaryOp,
    lt: BinaryOp,
    le: BinaryOp,
    gt: BinaryOp,
    ge: BinaryOp,
    
    /// Binary logical operations
    bool_and: BinaryOp,
    bool_or: BinaryOp,
    
    /// Unary operations
    neg: UnaryOp,
    bool_not: UnaryOp,
    
    /// Control flow
    jump: struct {
        target: []const u8,  // Basic block label
    },
    
    branch: struct {
        condition: Value,
        true_target: []const u8,
        false_target: []const u8,
    },
    
    /// Function call
    call: struct {
        dest: ?Value,  // null for void functions
        function: []const u8,
        args: []Value,
    },
    
    /// Intrinsic/native call (System runtime functions)
    // Uses string-based native hooks for bootstrappability
    // The hook name (e.g., "kl_sys_exit") maps to backend implementation
    intrinsic: struct {
        dest: ?Value,  // null for void intrinsics
        native_hook: []const u8,  // Zero-allocation slice from source
        args: []Value,
    },
    
    /// Return from function
    ret: struct {
        value: ?Value,
    },
};

pub const BinaryOp = struct {
    dest: Value,
    left: Value,
    right: Value,
};

pub const UnaryOp = struct {
    dest: Value,
    operand: Value,
};

/// Pretty-print IR for debugging
pub fn printProgram(program: *const Program, writer: anytype) !void {
    for (program.functions.items) |func| {
        try writer.print("\nfunction {s}:\n", .{func.name});
        
        // Print locals
        if (func.locals.items.len > 0) {
            try writer.writeAll("  locals:\n");
            for (func.locals.items, 0..) |local, i| {
                try writer.print("    %{d}: {s} {any}\n", .{i, local.name, local.ty});
            }
            try writer.writeAll("\n");
        }
        
        // Print basic blocks
        for (func.basic_blocks.items) |block| {
            try writer.print("  {s}:\n", .{block.label});
            for (block.instructions.items) |instr| {
                try writer.writeAll("    ");
                try printInstruction(instr, writer);
                try writer.writeAll("\n");
            }
        }
    }
}

fn printInstruction(instr: Instruction, writer: anytype) !void {
    switch (instr) {
        .load_const => |op| try writer.print("load_const {any}, {any}", .{op.dest, op.value}),
        .load_local => |op| try writer.print("load_local {any}, %{d}", .{op.dest, op.local}),
        .store_local => |op| try writer.print("store_local %{d}, {any}", .{op.local, op.value}),
        .add => |op| try writer.print("add {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .sub => |op| try writer.print("sub {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .mul => |op| try writer.print("mul {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .div => |op| try writer.print("div {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .mod => |op| try writer.print("mod {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .eq => |op| try writer.print("eq {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .ne => |op| try writer.print("ne {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .lt => |op| try writer.print("lt {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .le => |op| try writer.print("le {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .gt => |op| try writer.print("gt {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .ge => |op| try writer.print("ge {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .bool_and => |op| try writer.print("and {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .bool_or => |op| try writer.print("or {any}, {any}, {any}", .{op.dest, op.left, op.right}),
        .neg => |op| try writer.print("neg {any}, {any}", .{op.dest, op.operand}),
        .bool_not => |op| try writer.print("not {any}, {any}", .{op.dest, op.operand}),
        .jump => |op| try writer.print("jump {s}", .{op.target}),
        .branch => |op| try writer.print("branch {any}, {s}, {s}", .{op.condition, op.true_target, op.false_target}),
        .call => |op| {
            if (op.dest) |dest| {
                try writer.print("{any} = call {s}(", .{dest, op.function});
            } else {
                try writer.print("call {s}(", .{op.function});
            }
            for (op.args, 0..) |arg, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{any}", .{arg});
            }
            try writer.writeAll(")");
        },
        .intrinsic => |op| {
            if (op.dest) |dest| {
                try writer.print("{any} = intrinsic {any}(", .{dest, op.intrinsic_id});
            } else {
                try writer.print("intrinsic {any}(", .{op.intrinsic_id});
            }
            for (op.args, 0..) |arg, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{any}", .{arg});
            }
            try writer.writeAll(")");
        },
        .ret => |op| {
            if (op.value) |val| {
                try writer.print("ret {any}", .{val});
            } else {
                try writer.writeAll("ret");
            }
        },
    }
}

test {
    std.testing.refAllDecls(@This());
}
