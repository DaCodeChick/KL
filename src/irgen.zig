const std = @import("std");
const ast = @import("ast.zig");
const ir = @import("ir.zig");
const types = @import("types.zig");
const sema = @import("sema.zig");

/// IR Generator - converts analyzed AST to IR
pub const IRGenerator = struct {
    allocator: std.mem.Allocator,
    program: *ir.Program,
    current_function: ?*ir.Function = null,
    current_block: ?*ir.BasicBlock = null,
    next_temp: u32 = 0,
    next_label: u32 = 0,
    
    /// Map variable names to local indices
    var_map: std.StringHashMap(u32),
    
    pub fn init(allocator: std.mem.Allocator) !IRGenerator {
        const program = try ir.Program.init(allocator);
        return .{
            .allocator = allocator,
            .program = program,
            .var_map = std.StringHashMap(u32).init(allocator),
        };
    }
    
    pub fn deinit(self: *IRGenerator) void {
        self.var_map.deinit();
        self.program.deinit();
    }
    
    /// Generate IR from a module
    pub fn generateModule(self: *IRGenerator, module: *const ast.ModuleNode) !void {
        for (module.commands.items) |cmd| {
            try self.generateCommand(cmd);
        }
    }
    
    /// Generate IR for a command (function)
    fn generateCommand(self: *IRGenerator, cmd: *const ast.CommandImplNode) !void {
        var func = ir.Function.init(self.allocator, cmd.name);
        self.current_function = &func;
        self.var_map.clearRetainingCapacity();
        self.next_temp = 0;
        self.next_label = 0;
        
        // Create entry block
        var entry_block = ir.BasicBlock.init(self.allocator, "entry");
        self.current_block = &entry_block;
        
        // Generate IR for statements
        for (cmd.body.items) |*stmt| {
            try self.generateStatement(stmt.*);
        }
        
        // Add implicit return if no explicit return
        if (self.current_block) |block| {
            if (block.instructions.items.len == 0 or 
                block.instructions.items[block.instructions.items.len - 1] != .ret) {
                try block.addInstruction(.{ .ret = .{ .value = null } });
            }
            try func.addBlock(entry_block);
        }
        
        try self.program.addFunction(func);
        self.current_function = null;
        self.current_block = null;
    }
    
    /// Generate IR for a statement
    fn generateStatement(self: *IRGenerator, stmt: ast.Node) !void {
        switch (stmt) {
            .var_decl => |var_decl| try self.generateVarDecl(var_decl),
            .assignment => |assignment| try self.generateAssign(assignment),
            .if_stmt => |if_stmt| try self.generateIf(if_stmt),
            .repeat_stmt => |repeat| try self.generateRepeat(repeat),
            .command_invocation => |cmd| {
                // Standalone command invocation
                try self.generateCommandInvocation(cmd);
            },
            .function_call => {
                // Standalone function call (for side effects)
                _ = try self.generateExpression(stmt);
            },
            else => {},
        }
    }
    
    /// Generate IR for variable declaration
    fn generateVarDecl(self: *IRGenerator, var_decl: *ast.VarDeclNode) error{OutOfMemory, UndefinedVariable}!void {
        const func = self.current_function.?;
        const block = self.current_block.?;
        
        // Add local variable
        const local_index: u32 = @intCast(func.locals.items.len);
        try func.addLocal(.{
            .name = var_decl.name,
            .ty = var_decl.var_type,
        });
        try self.var_map.put(var_decl.name, local_index);
        
        // Generate initialization if present
        if (var_decl.initial_value) |init_expr| {
            const init_value = try self.generateExpression(init_expr);
            try block.addInstruction(.{
                .store_local = .{
                    .local = local_index,
                    .value = init_value,
                },
            });
        }
    }
    
    /// Generate IR for assignment
    fn generateAssign(self: *IRGenerator, assignment: *ast.AssignmentNode) error{OutOfMemory, UndefinedVariable}!void {
        const block = self.current_block.?;
        
        // Look up variable
        const local_index = self.var_map.get(assignment.target) orelse return error.UndefinedVariable;
        
        // Generate value expression
        const value = try self.generateExpression(assignment.value);
        
        // Store to local
        try block.addInstruction(.{
            .store_local = .{
                .local = local_index,
                .value = value,
            },
        });
    }
    
    /// Generate IR for command invocation
    fn generateCommandInvocation(self: *IRGenerator, cmd: *ast.CommandInvocationNode) error{OutOfMemory, UndefinedVariable}!void {
        const block = self.current_block.?;
        
        // Generate arguments
        var args = try self.allocator.alloc(ir.Value, cmd.arguments.items.len);
        for (cmd.arguments.items, 0..) |arg, i| {
            args[i] = try self.generateExpression(arg);
        }
        
        const dest_temp = self.nextTemp();
        const dest = ir.Value{ .temporary = dest_temp };
        
        try block.addInstruction(.{
            .call = .{
                .dest = dest,
                .function = cmd.command_name,
                .args = args,
            },
        });
    }
    
    /// Generate IR for if statement
    fn generateIf(self: *IRGenerator, if_stmt: *ast.IfStmtNode) error{OutOfMemory, UndefinedVariable}!void {
        const func = self.current_function.?;
        const block = self.current_block.?;
        
        // Generate condition
        const cond_value = try self.generateExpression(if_stmt.condition);
        
        // Create labels
        const then_label = try self.makeLabel("then");
        const else_label = if (if_stmt.else_body) |_| 
            try self.makeLabel("else") 
        else 
            try self.makeLabel("endif");
        const endif_label = try self.makeLabel("endif");
        
        // Branch instruction
        try block.addInstruction(.{
            .branch = .{
                .condition = cond_value,
                .true_target = then_label,
                .false_target = else_label,
            },
        });
        
        // Generate then block
        var then_block = ir.BasicBlock.init(self.allocator, then_label);
        self.current_block = &then_block;
        for (if_stmt.then_body.items) |stmt| {
            try self.generateStatement(stmt);
        }
        try then_block.addInstruction(.{ .jump = .{ .target = endif_label } });
        try func.addBlock(then_block);
        
        // Generate else block if present
        if (if_stmt.else_body) |else_body| {
            var else_block = ir.BasicBlock.init(self.allocator, else_label);
            self.current_block = &else_block;
            for (else_body.items) |stmt| {
                try self.generateStatement(stmt);
            }
            try else_block.addInstruction(.{ .jump = .{ .target = endif_label } });
            try func.addBlock(else_block);
        }
        
        // Create endif block
        var endif_block = ir.BasicBlock.init(self.allocator, endif_label);
        self.current_block = &endif_block;
        try func.addBlock(endif_block);
    }
    
    /// Generate IR for repeat statement
    fn generateRepeat(self: *IRGenerator, repeat: *ast.RepeatStmtNode) error{OutOfMemory, UndefinedVariable}!void {
        const func = self.current_function.?;
        
        // Create loop counter variable
        const counter_index: u32 = @intCast(func.locals.items.len);
        try func.addLocal(.{
            .name = "<repeat_counter>",
            .ty = .{ .uint32 = {} },
        });
        
        // Initialize counter to 0
        const block = self.current_block.?;
        try block.addInstruction(.{
            .store_local = .{
                .local = counter_index,
                .value = .{ .constant = .{ .uint = 0 } },
            },
        });
        
        // Generate iteration count (if specified)
        const count_value = if (repeat.count) |count|
            try self.generateExpression(count)
        else
            ir.Value{ .constant = .{ .uint = 0xFFFFFFFF } }; // Max iterations for infinite loop
        
        // Create labels
        const loop_label = try self.makeLabel("loop");
        const body_label = try self.makeLabel("loop_body");
        const end_label = try self.makeLabel("loop_end");
        
        // Jump to loop check
        try block.addInstruction(.{ .jump = .{ .target = loop_label } });
        try func.addBlock(block.*);
        
        // Loop check block
        var loop_block = ir.BasicBlock.init(self.allocator, loop_label);
        const counter_temp = self.nextTemp();
        try loop_block.addInstruction(.{
            .load_local = .{
                .dest = .{ .temporary = counter_temp },
                .local = counter_index,
            },
        });
        
        const cond_temp = self.nextTemp();
        try loop_block.addInstruction(.{
            .lt = .{
                .dest = .{ .temporary = cond_temp },
                .left = .{ .temporary = counter_temp },
                .right = count_value,
            },
        });
        
        try loop_block.addInstruction(.{
            .branch = .{
                .condition = .{ .temporary = cond_temp },
                .true_target = body_label,
                .false_target = end_label,
            },
        });
        try func.addBlock(loop_block);
        
        // Loop body
        var body_block = ir.BasicBlock.init(self.allocator, body_label);
        self.current_block = &body_block;
        for (repeat.body.items) |stmt| {
            try self.generateStatement(stmt);
        }
        
        // Increment counter
        const counter_temp2 = self.nextTemp();
        try body_block.addInstruction(.{
            .load_local = .{
                .dest = .{ .temporary = counter_temp2 },
                .local = counter_index,
            },
        });
        
        const inc_temp = self.nextTemp();
        try body_block.addInstruction(.{
            .add = .{
                .dest = .{ .temporary = inc_temp },
                .left = .{ .temporary = counter_temp2 },
                .right = .{ .constant = .{ .uint = 1 } },
            },
        });
        
        try body_block.addInstruction(.{
            .store_local = .{
                .local = counter_index,
                .value = .{ .temporary = inc_temp },
            },
        });
        
        try body_block.addInstruction(.{ .jump = .{ .target = loop_label } });
        try func.addBlock(body_block);
        
        // End block
        var end_block = ir.BasicBlock.init(self.allocator, end_label);
        self.current_block = &end_block;
    }
    
    /// Generate IR for an expression
    fn generateExpression(self: *IRGenerator, expr: ast.Node) error{OutOfMemory, UndefinedVariable}!ir.Value {
        const block = self.current_block.?;
        
        switch (expr) {
            .int_literal => |lit| {
                return ir.Value{ .constant = .{ .int = lit.value } };
            },
            
            .char_literal => |lit| {
                return ir.Value{ .constant = .{ .int = @intCast(lit.value) } };
            },
            
            .string_literal => |lit| {
                return ir.Value{ .constant = .{ .string = lit.value } };
            },
            
            .identifier => |ident| {
                const local_index = self.var_map.get(ident.name) orelse return error.UndefinedVariable;
                const temp = self.nextTemp();
                try block.addInstruction(.{
                    .load_local = .{
                        .dest = .{ .temporary = temp },
                        .local = local_index,
                    },
                });
                return ir.Value{ .temporary = temp };
            },
            
            .binary_op => |bin_op| {
                const left = try self.generateExpression(bin_op.left);
                const right = try self.generateExpression(bin_op.right);
                const dest_temp = self.nextTemp();
                const dest = ir.Value{ .temporary = dest_temp };
                
                const instr = switch (bin_op.op) {
                    .add => ir.Instruction{ .add = .{ .dest = dest, .left = left, .right = right } },
                    .sub => ir.Instruction{ .sub = .{ .dest = dest, .left = left, .right = right } },
                    .mul => ir.Instruction{ .mul = .{ .dest = dest, .left = left, .right = right } },
                    .div => ir.Instruction{ .div = .{ .dest = dest, .left = left, .right = right } },
                    .mod => ir.Instruction{ .mod = .{ .dest = dest, .left = left, .right = right } },
                    .eq => ir.Instruction{ .eq = .{ .dest = dest, .left = left, .right = right } },
                    .neq => ir.Instruction{ .ne = .{ .dest = dest, .left = left, .right = right } },
                    .lt => ir.Instruction{ .lt = .{ .dest = dest, .left = left, .right = right } },
                    .lte => ir.Instruction{ .le = .{ .dest = dest, .left = left, .right = right } },
                    .gt => ir.Instruction{ .gt = .{ .dest = dest, .left = left, .right = right } },
                    .gte => ir.Instruction{ .ge = .{ .dest = dest, .left = left, .right = right } },
                    .logic_and => ir.Instruction{ .bool_and = .{ .dest = dest, .left = left, .right = right } },
                    .logic_or => ir.Instruction{ .bool_or = .{ .dest = dest, .left = left, .right = right } },
                };
                
                try block.addInstruction(instr);
                return dest;
            },
            
            .unary_op => |un_op| {
                const operand = try self.generateExpression(un_op.operand);
                const dest_temp = self.nextTemp();
                const dest = ir.Value{ .temporary = dest_temp };
                
                const instr = switch (un_op.op) {
                    .negate => ir.Instruction{ .neg = .{ .dest = dest, .operand = operand } },
                    .logic_not => ir.Instruction{ .bool_not = .{ .dest = dest, .operand = operand } },
                };
                
                try block.addInstruction(instr);
                return dest;
            },
            
            .function_call => |call| {
                // Generate arguments
                var args = try self.allocator.alloc(ir.Value, call.arguments.items.len);
                for (call.arguments.items, 0..) |arg, i| {
                    args[i] = try self.generateExpression(arg);
                }
                
                const dest_temp = self.nextTemp();
                const dest = ir.Value{ .temporary = dest_temp };
                
                try block.addInstruction(.{
                    .call = .{
                        .dest = dest,
                        .function = call.function_name,
                        .args = args,
                    },
                });
                
                return dest;
            },
            
            else => return ir.Value{ .constant = .{ .int = 0 } },
        }
    }
    
    fn nextTemp(self: *IRGenerator) u32 {
        const temp = self.next_temp;
        self.next_temp += 1;
        return temp;
    }
    
    fn makeLabel(self: *IRGenerator, prefix: []const u8) ![]const u8 {
        const label = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{prefix, self.next_label});
        self.next_label += 1;
        return label;
    }
};

test "IR generation" {
    const allocator = std.testing.allocator;
    
    var gen = try IRGenerator.init(allocator);
    defer gen.deinit();
    
    // For now just test that it initializes correctly
    try std.testing.expectEqual(@as(usize, 0), gen.program.functions.items.len);
}
