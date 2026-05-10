const std = @import("std");
const ir = @import("ir.zig");
const backend = @import("backend.zig");
const ast = @import("ast.zig");

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
        
        // Generate all KL functions
        for (program.functions.items) |*func| {
            try self.generateFunction(func);
        }
        
        // Generate main entry point
        // If there's a function called "Main", call it
        // Otherwise, call the first function
        if (program.functions.items.len > 0) {
            var main_func_name: []const u8 = program.functions.items[0].name;
            for (program.functions.items) |*func| {
                if (std.mem.eql(u8, func.name, "Main")) {
                    main_func_name = "Main";
                    break;
                }
            }
            try self.generateMainWrapper(main_func_name);
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
                
                // Allocate stack space for locals (first 128 slots) and temporaries (next 128 slots)
                // This is simplified - a real compiler would calculate exact needs
                const stack_size = 2048; // 256 * 8 bytes
                _ = func; // We'll use a fixed size for now
                if (stack_size > 0) {
                    try self.print("    subq ${d}, %rsp\n", .{stack_size});
                }
            },
            .intel => {
                try self.writeAll("    push rbp\n");
                try self.writeAll("    mov rbp, rsp\n");
                
                const stack_size = 2048;
                _ = func;
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
    
    fn generateMainWrapper(self: *AsmGenerator, kl_func_name: []const u8) !void {
        // Generate a C-compatible main function that calls the specified KL function
        switch (self.format) {
            .att => {
                try self.writeAll(".globl main\n");
                try self.writeAll(".type main, @function\n");
                try self.writeAll("main:\n");
                try self.writeAll("    pushq %rbp\n");
                try self.writeAll("    movq %rsp, %rbp\n");
                try self.print("    call {s}\n", .{kl_func_name});
                try self.writeAll("    xorq %rax, %rax  # Return 0\n");
                try self.writeAll("    popq %rbp\n");
                try self.writeAll("    ret\n\n");
            },
            .intel => {
                try self.writeAll("global main\n");
                try self.writeAll("main:\n");
                try self.writeAll("    push rbp\n");
                try self.writeAll("    mov rbp, rsp\n");
                try self.print("    call {s}\n", .{kl_func_name});
                try self.writeAll("    xor rax, rax  ; Return 0\n");
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
            .eq => |op| try self.emitComparison("e", op),
            .ne => |op| try self.emitComparison("ne", op),
            .lt => |op| try self.emitComparison("l", op),
            .le => |op| try self.emitComparison("le", op),
            .gt => |op| try self.emitComparison("g", op),
            .ge => |op| try self.emitComparison("ge", op),
            .call => |op| try self.emitCall(op),
            .intrinsic => |op| try self.emitIntrinsic(op),
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
        
        // Store the loaded value to the destination
        try self.emitStoreValue(op.dest);
    }
    
    fn emitStoreLocal(self: *AsmGenerator, op: anytype) !void {
        const offset = (op.local + 1) * 8;
        
        // First, load the value into rax
        try self.emitLoadValue(op.value);
        
        // Then store rax to local
        switch (self.format) {
            .att => try self.print("    movq %rax, -{d}(%rbp)\n", .{offset}),
            .intel => try self.print("    mov [rbp - {d}], rax\n", .{offset}),
        }
    }
    
    fn emitLoadValue(self: *AsmGenerator, value: ir.Value) !void {
        switch (value) {
            .constant => |c| {
                switch (self.format) {
                    .att => {
                        switch (c) {
                            .int => |val| try self.print("    movq ${d}, %rax\n", .{val}),
                            .uint => |val| try self.print("    movq ${d}, %rax\n", .{val}),
                            .bool => |val| try self.print("    movq ${d}, %rax\n", .{@as(i64, if (val) 1 else 0)}),
                            .string => try self.writeAll("    # TODO: Load string address\n"),
                        }
                    },
                    .intel => {
                        switch (c) {
                            .int => |val| try self.print("    mov rax, {d}\n", .{val}),
                            .uint => |val| try self.print("    mov rax, {d}\n", .{val}),
                            .bool => |val| try self.print("    mov rax, {d}\n", .{@as(i64, if (val) 1 else 0)}),
                            .string => try self.writeAll("    ; TODO: Load string address\n"),
                        }
                    },
                }
            },
            .local => |local_idx| {
                const local_offset = (local_idx + 1) * 8;
                switch (self.format) {
                    .att => try self.print("    movq -{d}(%rbp), %rax\n", .{local_offset}),
                    .intel => try self.print("    mov rax, [rbp - {d}]\n", .{local_offset}),
                }
            },
            .temporary => |temp_idx| {
                // For now, assume temporaries are spilled to stack at a fixed location
                // This is a simplification - a real compiler would do register allocation
                const temp_offset = 1024 + (temp_idx * 8);
                switch (self.format) {
                    .att => try self.print("    movq -{d}(%rbp), %rax\n", .{temp_offset}),
                    .intel => try self.print("    mov rax, [rbp - {d}]\n", .{temp_offset}),
                }
            },
        }
    }
    
    fn emitStoreValue(self: *AsmGenerator, value: ir.Value) !void {
        switch (value) {
            .constant => {
                // Can't store to a constant
                switch (self.format) {
                    .att => try self.writeAll("    # ERROR: Cannot store to constant\n"),
                    .intel => try self.writeAll("    ; ERROR: Cannot store to constant\n"),
                }
            },
            .local => |local_idx| {
                const local_offset = (local_idx + 1) * 8;
                switch (self.format) {
                    .att => try self.print("    movq %rax, -{d}(%rbp)\n", .{local_offset}),
                    .intel => try self.print("    mov [rbp - {d}], rax\n", .{local_offset}),
                }
            },
            .temporary => |temp_idx| {
                const temp_offset = 1024 + (temp_idx * 8);
                switch (self.format) {
                    .att => try self.print("    movq %rax, -{d}(%rbp)\n", .{temp_offset}),
                    .intel => try self.print("    mov [rbp - {d}], rax\n", .{temp_offset}),
                }
            },
        }
    }
    
    fn emitBinaryOp(self: *AsmGenerator, op_name: []const u8, op: ir.BinaryOp) !void {
        // Load left operand into rax
        try self.emitLoadValue(op.left);
        
        // Save left operand to a temporary location (push onto stack)
        switch (self.format) {
            .att => try self.writeAll("    pushq %rax\n"),
            .intel => try self.writeAll("    push rax\n"),
        }
        
        // Load right operand into rax
        try self.emitLoadValue(op.right);
        
        // Move right operand to rbx
        switch (self.format) {
            .att => try self.writeAll("    movq %rax, %rbx\n"),
            .intel => try self.writeAll("    mov rbx, rax\n"),
        }
        
        // Pop left operand back into rax
        switch (self.format) {
            .att => try self.writeAll("    popq %rax\n"),
            .intel => try self.writeAll("    pop rax\n"),
        }
        
        // Perform operation
        switch (self.format) {
            .att => {
                try self.print("    {s}q %rbx, %rax\n", .{op_name});
            },
            .intel => {
                try self.print("    {s} rax, rbx\n", .{op_name});
            },
        }
        
        // Store result to destination if it's a temporary
        switch (op.dest) {
            .temporary => |temp_idx| {
                const temp_offset = 1024 + (temp_idx * 8);
                switch (self.format) {
                    .att => try self.print("    movq %rax, -{d}(%rbp)\n", .{temp_offset}),
                    .intel => try self.print("    mov [rbp - {d}], rax\n", .{temp_offset}),
                }
            },
            else => {},
        }
    }
    
    fn emitComparison(self: *AsmGenerator, cond_code: []const u8, op: ir.BinaryOp) !void {
        // Load left operand into rax
        try self.emitLoadValue(op.left);
        
        // Save left operand to a temporary location (push onto stack)
        switch (self.format) {
            .att => try self.writeAll("    pushq %rax\n"),
            .intel => try self.writeAll("    push rax\n"),
        }
        
        // Load right operand into rax
        try self.emitLoadValue(op.right);
        
        // Move right operand to rbx
        switch (self.format) {
            .att => try self.writeAll("    movq %rax, %rbx\n"),
            .intel => try self.writeAll("    mov rbx, rax\n"),
        }
        
        // Pop left operand back into rax
        switch (self.format) {
            .att => try self.writeAll("    popq %rax\n"),
            .intel => try self.writeAll("    pop rax\n"),
        }
        
        // Compare
        switch (self.format) {
            .att => {
                try self.writeAll("    cmpq %rbx, %rax\n");
                // Set result based on comparison
                try self.print("    set{s} %al\n", .{cond_code});
                try self.writeAll("    movzbq %al, %rax\n"); // Zero-extend to 64-bit
            },
            .intel => {
                try self.writeAll("    cmp rax, rbx\n");
                try self.print("    set{s} al\n", .{cond_code});
                try self.writeAll("    movzx rax, al\n");
            },
        }
        
        // Store result to destination if it's a temporary
        switch (op.dest) {
            .temporary => |temp_idx| {
                const temp_offset = 1024 + (temp_idx * 8);
                switch (self.format) {
                    .att => try self.print("    movq %rax, -{d}(%rbp)\n", .{temp_offset}),
                    .intel => try self.print("    mov [rbp - {d}], rax\n", .{temp_offset}),
                }
            },
            else => {},
        }
    }
    
    fn emitCall(self: *AsmGenerator, op: anytype) !void {
        // For x86-64 System V ABI (Linux):
        // Arguments go in: rdi, rsi, rdx, rcx, r8, r9, then stack
        // For simplicity, we'll use a basic calling convention:
        // - Load all arguments onto the stack in reverse order
        // - Call the function
        // - Result is in rax
        
        const arg_regs_att = [_][]const u8{ "%rdi", "%rsi", "%rdx", "%rcx", "%r8", "%r9" };
        const arg_regs_intel = [_][]const u8{ "rdi", "rsi", "rdx", "rcx", "r8", "r9" };
        
        // Load arguments into registers (up to 6 args)
        for (op.args, 0..) |arg, i| {
            if (i >= 6) break; // Only handle first 6 args for now
            
            // Load argument value into rax
            try self.emitLoadValue(arg);
            
            // Move to appropriate register
            switch (self.format) {
                .att => try self.print("    movq %rax, {s}\n", .{arg_regs_att[i]}),
                .intel => try self.print("    mov {s}, rax\n", .{arg_regs_intel[i]}),
            }
        }
        
        // Call the function
        switch (self.format) {
            .att => try self.print("    call {s}\n", .{op.function}),
            .intel => try self.print("    call {s}\n", .{op.function}),
        }
        
        // Store result if destination is specified
        if (op.dest) |dest| {
            switch (dest) {
                .temporary => |temp_idx| {
                    const temp_offset = 1024 + (temp_idx * 8);
                    switch (self.format) {
                        .att => try self.print("    movq %rax, -{d}(%rbp)\n", .{temp_offset}),
                        .intel => try self.print("    mov [rbp - {d}], rax\n", .{temp_offset}),
                    }
                },
                .local => |local_idx| {
                    const local_offset = (local_idx + 1) * 8;
                    switch (self.format) {
                        .att => try self.print("    movq %rax, -{d}(%rbp)\n", .{local_offset}),
                        .intel => try self.print("    mov [rbp - {d}], rax\n", .{local_offset}),
                    }
                },
                else => {},
            }
        }
    }
    
    fn emitIntrinsic(self: *AsmGenerator, op: anytype) !void {
        // Emit code for System runtime intrinsics
        switch (op.intrinsic_id) {
            .system_print, .system_println => {
                // For now, emit a comment
                // In a real implementation, this would call libc printf or write syscall
                const intrinsic_name = if (op.intrinsic_id == .system_print) "Print" else "PrintLn";
                
                switch (self.format) {
                    .att => {
                        try self.print("    # Intrinsic: System.{s}\n", .{intrinsic_name});
                        // TODO: Implement actual print functionality
                        // For MVP, we'll skip this for now
                        // A real implementation would:
                        // 1. Load string pointer from args[0]
                        // 2. Call libc printf or use write syscall
                        // 3. For PrintLn, add a newline
                    },
                    .intel => {
                        try self.print("    ; Intrinsic: System.{s}\n", .{intrinsic_name});
                    },
                }
            },
            .system_exit => {
                // Exit syscall: exit(code)
                // Load exit code into rdi (first argument register)
                if (op.args.len > 0) {
                    try self.emitLoadValue(op.args[0]);
                    switch (self.format) {
                        .att => {
                            try self.writeAll("    movq %rax, %rdi\n");
                            try self.writeAll("    movq $60, %rax  # sys_exit\n");
                            try self.writeAll("    syscall\n");
                        },
                        .intel => {
                            try self.writeAll("    mov rdi, rax\n");
                            try self.writeAll("    mov rax, 60  ; sys_exit\n");
                            try self.writeAll("    syscall\n");
                        },
                    }
                }
            },
            .none => {
                switch (self.format) {
                    .att => try self.writeAll("    # Unknown intrinsic\n"),
                    .intel => try self.writeAll("    ; Unknown intrinsic\n"),
                }
            },
            else => {
                switch (self.format) {
                    .att => try self.writeAll("    # TODO: Unimplemented intrinsic\n"),
                    .intel => try self.writeAll("    ; TODO: Unimplemented intrinsic\n"),
                }
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
