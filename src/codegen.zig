const std = @import("std");
const ir = @import("ir.zig");
const backend = @import("backend.zig");

/// Assembly code generator for x86-64
pub const AsmGenerator = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    format: backend.Backend.AssemblyFormat,
    target: backend.Backend.Target,
    label_counter: u32 = 0,
    
    pub fn init(allocator: std.mem.Allocator, fmt: backend.Backend.AssemblyFormat, target: backend.Backend.Target) AsmGenerator {
        return .{
            .allocator = allocator,
            .output = .{ .items = &.{}, .capacity = 0 },
            .format = fmt,
            .target = target,
        };
    }
    
    pub fn deinit(self: *AsmGenerator) void {
        self.output.deinit(self.allocator);
    }
    
    pub fn getOutput(self: *AsmGenerator) []const u8 {
        return self.output.items;
    }
    
    fn print(self: *AsmGenerator, comptime fmt: []const u8, args: anytype) !void {
        const str = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(str);
        try self.output.appendSlice(self.allocator, str);
    }
    
    fn writeAll(self: *AsmGenerator, bytes: []const u8) !void {
        try self.output.appendSlice(self.allocator, bytes);
    }
    
    /// Generate assembly code from IR program
    pub fn generate(self: *AsmGenerator, program: *const ir.Program) !void {
        try self.emitHeader();
        
        for (program.functions.items) |*func| {
            try self.generateFunction(func);
        }
        
        try self.emitFooter();
    }
    
    fn emitHeader(self: *AsmGenerator) !void {
        switch (self.format) {
            .att => {
                try self.writeAll("# KL Compiler - Generated Assembly\n");
                try self.writeAll("# Target: x86-64 AT&T syntax\n\n");
            },
            .intel => {
                try self.writeAll("; KL Compiler - Generated Assembly\n");
                try self.writeAll("; Target: x86-64 Intel syntax\n\n");
            },
        }
    }
    
    fn emitFooter(self: *AsmGenerator) !void {
        switch (self.format) {
            .att => {
                try self.writeAll("\n# End of generated assembly\n");
            },
            .intel => {
                try self.writeAll("\n; End of generated assembly\n");
            },
        }
    }
    
    fn generateFunction(self: *AsmGenerator, func: *const ir.Function) !void {
        // Emit function label
        switch (self.format) {
            .att => {
                try self.print(".globl {s}\n", .{func.name});
                try self.print(".type {s}, @function\n", .{func.name});
                try self.print("{s}:\n", .{func.name});
            },
            .intel => {
                try self.print("global {s}\n", .{func.name});
                try self.print("{s}:\n", .{func.name});
            },
        }
        
        // Function prologue
        try self.emitPrologue(func);
        
        // Generate code for each basic block
        for (func.basic_blocks.items) |*block| {
            try self.generateBasicBlock(block);
        }
        
        // Function epilogue
        try self.emitEpilogue();
    }
    
    fn emitPrologue(self: *AsmGenerator, func: *const ir.Function) !void {
        switch (self.format) {
            .att => {
                try self.writeAll("    pushq %rbp\n");
                try self.writeAll("    movq %rsp, %rbp\n");
                
                // Allocate stack space for locals if needed
                const stack_size = func.locals.items.len * 8;
                if (stack_size > 0) {
                    try self.print("    subq ${d}, %rsp\n", .{stack_size});
                }
            },
            .intel => {
                try self.writeAll("    push rbp\n");
                try self.writeAll("    mov rbp, rsp\n");
                
                const stack_size = func.locals.items.len * 8;
                if (stack_size > 0) {
                    try self.print("    sub rsp, {d}\n", .{stack_size});
                }
            },
        }
    }
    
    fn emitEpilogue(self: *AsmGenerator) !void {
        switch (self.format) {
            .att => {
                try self.writeAll("    movq %rbp, %rsp\n");
                try self.writeAll("    popq %rbp\n");
                try self.writeAll("    ret\n\n");
            },
            .intel => {
                try self.writeAll("    mov rsp, rbp\n");
                try self.writeAll("    pop rbp\n");
                try self.writeAll("    ret\n\n");
            },
        }
    }
    
    fn generateBasicBlock(self: *AsmGenerator, block: *const ir.BasicBlock) !void {
        // Emit block label
        try self.print("{s}:\n", .{block.label});
        
        for (block.instructions.items) |instr| {
            try self.generateInstruction(instr);
        }
    }
    
    fn generateInstruction(self: *AsmGenerator, instr: ir.Instruction) !void {
        switch (instr) {
            .load_const => |op| try self.emitLoadConst(op),
            .load_local => |op| try self.emitLoadLocal(op),
            .store_local => |op| try self.emitStoreLocal(op),
            .add => |op| try self.emitBinaryOp("add", op),
            .sub => |op| try self.emitBinaryOp("sub", op),
            .mul => |op| try self.emitBinaryOp("imul", op),
            .ret => |op| try self.emitReturn(op),
            .jump => |op| try self.emitJump(op),
            .branch => |op| try self.emitBranch(op),
            else => {
                // TODO: Implement remaining instructions
                switch (self.format) {
                    .att => try self.writeAll("    # TODO: Unimplemented instruction\n"),
                    .intel => try self.writeAll("    ; TODO: Unimplemented instruction\n"),
                }
            },
        }
    }
    
    fn emitLoadConst(self: *AsmGenerator, op: anytype) !void {
        const comment = switch (self.format) {
            .att => "# Load constant",
            .intel => "; Load constant",
        };
        
        switch (self.format) {
            .att => {
                switch (op.value) {
                    .int => |val| try self.print("    movq ${d}, %rax  {s}\n", .{val, comment}),
                    .uint => |val| try self.print("    movq ${d}, %rax  {s}\n", .{val, comment}),
                    .bool => |val| try self.print("    movq ${d}, %rax  {s}\n", .{@as(i64, if (val) 1 else 0), comment}),
                    else => {},
                }
            },
            .intel => {
                switch (op.value) {
                    .int => |val| try self.print("    mov rax, {d}  {s}\n", .{val, comment}),
                    .uint => |val| try self.print("    mov rax, {d}  {s}\n", .{val, comment}),
                    .bool => |val| try self.print("    mov rax, {d}  {s}\n", .{@as(i64, if (val) 1 else 0), comment}),
                    else => {},
                }
            },
        }
    }
    
    fn emitLoadLocal(self: *AsmGenerator, op: anytype) !void {
        const offset = (op.local + 1) * 8;
        switch (self.format) {
            .att => try self.print("    movq -{d}(%rbp), %rax\n", .{offset}),
            .intel => try self.print("    mov rax, [rbp - {d}]\n", .{offset}),
        }
    }
    
    fn emitStoreLocal(self: *AsmGenerator, op: anytype) !void {
        const offset = (op.local + 1) * 8;
        switch (self.format) {
            .att => try self.print("    movq %rax, -{d}(%rbp)\n", .{offset}),
            .intel => try self.print("    mov [rbp - {d}], rax\n", .{offset}),
        }
    }
    
    fn emitBinaryOp(self: *AsmGenerator, op_name: []const u8, op: ir.BinaryOp) !void {
        // Simplified: assume operands are in registers
        // Real implementation would handle different value types
        _ = op;
        
        switch (self.format) {
            .att => {
                try self.print("    {s}q %rbx, %rax\n", .{op_name});
            },
            .intel => {
                try self.print("    {s} rax, rbx\n", .{op_name});
            },
        }
    }
    
    fn emitReturn(self: *AsmGenerator, op: anytype) !void {
        _ = op;
        // Return value should already be in rax
        switch (self.format) {
            .att => {
                try self.writeAll("    movq %rbp, %rsp\n");
                try self.writeAll("    popq %rbp\n");
                try self.writeAll("    ret\n");
            },
            .intel => {
                try self.writeAll("    mov rsp, rbp\n");
                try self.writeAll("    pop rbp\n");
                try self.writeAll("    ret\n");
            },
        }
    }
    
    fn emitJump(self: *AsmGenerator, op: anytype) !void {
        switch (self.format) {
            .att => try self.print("    jmp {s}\n", .{op.target}),
            .intel => try self.print("    jmp {s}\n", .{op.target}),
        }
    }
    
    fn emitBranch(self: *AsmGenerator, op: anytype) !void {
        switch (self.format) {
            .att => {
                try self.writeAll("    testq %rax, %rax\n");
                try self.print("    jnz {s}\n", .{op.true_target});
                try self.print("    jmp {s}\n", .{op.false_target});
            },
            .intel => {
                try self.writeAll("    test rax, rax\n");
                try self.print("    jnz {s}\n", .{op.true_target});
                try self.print("    jmp {s}\n", .{op.false_target});
            },
        }
    }
};

test "asm generator init" {
    const allocator = std.testing.allocator;
    
    var gen = AsmGenerator.init(allocator, .att, .x86_64_linux);
    defer gen.deinit();
    
    try std.testing.expectEqual(backend.Backend.AssemblyFormat.att, gen.format);
}

test "emit header" {
    const allocator = std.testing.allocator;
    
    var gen = AsmGenerator.init(allocator, .att, .x86_64_linux);
    defer gen.deinit();
    
    try gen.emitHeader();
    const output = gen.getOutput();
    try std.testing.expect(std.mem.indexOf(u8, output, "KL Compiler") != null);
}
