const std = @import("std");
const ast = @import("ast.zig");
const KLType = @import("types.zig").KLType;
const ErrorReporter = @import("error.zig").ErrorReporter;
const SourceLocation = @import("error.zig").SourceLocation;
const CompilerError = @import("error.zig").CompilerError;
const ghost = @import("ghost.zig");

/// Symbol in the symbol table
pub const Symbol = struct {
    name: []const u8,
    kind: SymbolKind,
    location: SourceLocation,
};

/// Kind of symbol
pub const SymbolKind = union(enum) {
    module: *ast.ModuleNode,
    command: *ast.CommandImplNode,
    function: *ast.FunctionImplNode,
    variable: *ast.VarDeclNode,
    parameter: *ast.ParamDeclNode,
};

/// Scope for symbol resolution
pub const Scope = struct {
    allocator: std.mem.Allocator,
    parent: ?*Scope,
    symbols: std.StringHashMap(*Symbol),
    
    pub fn init(allocator: std.mem.Allocator, parent: ?*Scope) !*Scope {
        const scope = try allocator.create(Scope);
        scope.* = .{
            .allocator = allocator,
            .parent = parent,
            .symbols = std.StringHashMap(*Symbol).init(allocator),
        };
        return scope;
    }
    
    pub fn deinit(self: *Scope) void {
        var iter = self.symbols.valueIterator();
        while (iter.next()) |sym_ptr| {
            self.allocator.destroy(sym_ptr.*);
        }
        self.symbols.deinit();
        self.allocator.destroy(self);
    }
    
    /// Declare a symbol in this scope
    pub fn declare(self: *Scope, name: []const u8, symbol: Symbol) !void {
        const sym = try self.allocator.create(Symbol);
        sym.* = symbol;
        try self.symbols.put(name, sym);
    }
    
    /// Look up a symbol in this scope or parent scopes
    pub fn lookup(self: *Scope, name: []const u8) ?*Symbol {
        if (self.symbols.get(name)) |sym| {
            return sym;
        }
        
        if (self.parent) |parent| {
            return parent.lookup(name);
        }
        
        return null;
    }
};

/// Semantic analyzer for KL
pub const SemanticAnalyzer = struct {
    allocator: std.mem.Allocator,
    err_reporter: *ErrorReporter,
    global_scope: *Scope,
    current_scope: *Scope,
    system_module: ?*ast.ModuleNode = null,
    qualified_names: std.array_list.AlignedManaged([]const u8, null),
    
    pub fn init(allocator: std.mem.Allocator, err_reporter: *ErrorReporter) !*SemanticAnalyzer {
        const analyzer = try allocator.create(SemanticAnalyzer);
        const global_scope = try Scope.init(allocator, null);
        
        analyzer.* = .{
            .allocator = allocator,
            .err_reporter = err_reporter,
            .global_scope = global_scope,
            .current_scope = global_scope,
            .system_module = null,
            .qualified_names = std.array_list.AlignedManaged([]const u8, null).init(allocator),
        };
        
        // Generate and register the System ghost module
        try analyzer.loadSystemModule();
        
        return analyzer;
    }
    
    pub fn deinit(self: *SemanticAnalyzer) void {
        // Free allocated qualified names
        for (self.qualified_names.items) |name| {
            self.allocator.free(name);
        }
        self.qualified_names.deinit();
        
        if (self.system_module) |sys_mod| {
            sys_mod.deinit(self.allocator);
        }
        self.global_scope.deinit();
        self.allocator.destroy(self);
    }
    
    /// Load the System ghost module into the global scope
    fn loadSystemModule(self: *SemanticAnalyzer) !void {
        self.system_module = try ghost.generateSystemModule(self.allocator);
        const sys_mod = self.system_module.?;
        
        // Register System module
        try self.declareSymbol(sys_mod.name, .{ .module = sys_mod }, sys_mod.location);
        
        // Register all System commands with qualified names (System.Print, etc.)
        for (sys_mod.commands.items) |cmd| {
            const qualified_name = try std.fmt.allocPrint(
                self.allocator,
                "{s}.{s}",
                .{ sys_mod.name, cmd.name },
            );
            // Track the allocated name for cleanup
            try self.qualified_names.append(qualified_name);
            try self.declareSymbol(qualified_name, .{ .command = cmd }, cmd.location);
        }
    }
    
    /// Analyze a module
    pub fn analyzeModule(self: *SemanticAnalyzer, module: *ast.ModuleNode) CompilerError!void {
        // Register module in global scope
        try self.declareSymbol(module.name, .{ .module = module }, module.location);
        
        // First pass: register all commands and functions
        for (module.commands.items) |cmd| {
            try self.declareSymbol(cmd.name, .{ .command = cmd }, cmd.location);
        }
        for (module.functions.items) |func| {
            try self.declareSymbol(func.name, .{ .function = func }, func.location);
        }
        
        // Second pass: analyze command and function bodies
        for (module.commands.items) |cmd| {
            try self.analyzeCommand(cmd);
        }
        for (module.functions.items) |func| {
            try self.analyzeFunction(func);
        }
    }
    
    /// Analyze a command implementation
    fn analyzeCommand(self: *SemanticAnalyzer, cmd: *ast.CommandImplNode) CompilerError!void {
        // Create new scope for command body
        const cmd_scope = try Scope.init(self.allocator, self.current_scope);
        const prev_scope = self.current_scope;
        self.current_scope = cmd_scope;
        defer {
            self.current_scope = prev_scope;
            cmd_scope.deinit();
        }
        
        // Register parameters in command scope
        for (cmd.parameters.items) |param| {
            try self.declareSymbol(param.name, .{ .parameter = param }, param.location);
        }
        
        // Analyze command body
        for (cmd.body.items) |stmt| {
            try self.analyzeStatement(stmt);
        }
    }
    
    /// Analyze a function implementation
    fn analyzeFunction(self: *SemanticAnalyzer, func: *ast.FunctionImplNode) CompilerError!void {
        // For native functions (with native_hook), skip body analysis
        if (func.native_hook != null) {
            return;
        }
        
        // Create new scope for function body
        const func_scope = try Scope.init(self.allocator, self.current_scope);
        const prev_scope = self.current_scope;
        self.current_scope = func_scope;
        defer {
            self.current_scope = prev_scope;
            func_scope.deinit();
        }
        
        // Register parameters in function scope
        for (func.parameters.items) |param| {
            try self.declareSymbol(param.name, .{ .parameter = param }, param.location);
        }
        
        // Analyze function body statements
        for (func.body.items) |stmt| {
            try self.analyzeStatement(stmt);
        }
    }
    
    /// Analyze a statement
    fn analyzeStatement(self: *SemanticAnalyzer, stmt: ast.Node) CompilerError!void {
        switch (stmt) {
            .var_decl => |decl| try self.analyzeVarDecl(decl),
            .assignment => |assign| try self.analyzeAssignment(assign),
            .if_stmt => |if_stmt| try self.analyzeIfStatement(if_stmt),
            .repeat_stmt => |repeat| try self.analyzeRepeatStatement(repeat),
            else => {
                // For MVP, just skip other statement types
            },
        }
    }
    
    /// Analyze variable declaration
    fn analyzeVarDecl(self: *SemanticAnalyzer, decl: *ast.VarDeclNode) CompilerError!void {
        // Check for redeclaration in current scope only
        if (self.current_scope.symbols.get(decl.name)) |_| {
            try self.err_reporter.report(
                decl.location,
                CompilerError.DuplicateVariable,
                "Variable '{s}' is already declared in this scope",
                .{decl.name},
            );
            return CompilerError.DuplicateVariable;
        }
        
        // If there's an initial value, analyze it and check type compatibility
        if (decl.initial_value) |val| {
            const val_type = try self.analyzeExpression(val);
            
            // Check type compatibility
            if (!decl.var_type.isCompatible(val_type)) {
                try self.err_reporter.report(
                    decl.location,
                    CompilerError.TypeMismatch,
                    "Type mismatch: variable '{s}' declared as {} but initialized with {}",
                    .{ decl.name, decl.var_type, val_type },
                );
                return CompilerError.TypeMismatch;
            }
        }
        
        // Register variable in current scope
        try self.declareSymbol(decl.name, .{ .variable = decl }, decl.location);
    }
    
    /// Analyze assignment statement
    fn analyzeAssignment(self: *SemanticAnalyzer, assign: *ast.AssignmentNode) CompilerError!void {
        // Look up the target variable
        const symbol = self.lookupSymbol(assign.target) orelse {
            try self.err_reporter.report(
                assign.location,
                CompilerError.UndefinedVariable,
                "Undefined variable '{s}'",
                .{assign.target},
            );
            return CompilerError.UndefinedVariable;
        };
        
        // Ensure it's a variable or parameter
        const var_type = switch (symbol.kind) {
            .variable => |decl| decl.var_type,
            .parameter => |param| param.param_type,
            else => {
                try self.err_reporter.report(
                    assign.location,
                    CompilerError.TypeMismatch,
                    "'{s}' is not a variable",
                    .{assign.target},
                );
                return CompilerError.TypeMismatch;
            },
        };
        
        // Analyze the value expression
        const val_type = try self.analyzeExpression(assign.value);
        
        // Check type compatibility
        if (!var_type.isCompatible(val_type)) {
            try self.err_reporter.report(
                assign.location,
                CompilerError.TypeMismatch,
                "Type mismatch: cannot assign {} to variable of type {}",
                .{ val_type, var_type },
            );
            return CompilerError.TypeMismatch;
        }
    }
    
    /// Analyze if statement
    fn analyzeIfStatement(self: *SemanticAnalyzer, if_stmt: *ast.IfStmtNode) CompilerError!void {
        // Check condition is boolean
        const cond_type = try self.analyzeExpression(if_stmt.condition);
        if (cond_type != .bool_type) {
            try self.err_reporter.report(
                if_stmt.location,
                CompilerError.TypeMismatch,
                "If condition must be boolean, got {}",
                .{cond_type},
            );
            return CompilerError.TypeMismatch;
        }
        
        // Analyze then body
        for (if_stmt.then_body.items) |stmt| {
            try self.analyzeStatement(stmt);
        }
        
        // Analyze elif clauses
        for (if_stmt.elif_clauses.items) |*elif| {
            const elif_cond_type = try self.analyzeExpression(elif.condition);
            if (elif_cond_type != .bool_type) {
                try self.err_reporter.report(
                    if_stmt.location,
                    CompilerError.TypeMismatch,
                    "Elif condition must be boolean, got {}",
                    .{elif_cond_type},
                );
                return CompilerError.TypeMismatch;
            }
            
            for (elif.body.items) |stmt| {
                try self.analyzeStatement(stmt);
            }
        }
        
        // Analyze else body
        if (if_stmt.else_body) |*else_body| {
            for (else_body.items) |stmt| {
                try self.analyzeStatement(stmt);
            }
        }
    }
    
    /// Analyze repeat statement
    fn analyzeRepeatStatement(self: *SemanticAnalyzer, repeat: *ast.RepeatStmtNode) CompilerError!void {
        // If count is specified, check it's an integer
        if (repeat.count) |count| {
            const count_type = try self.analyzeExpression(count);
            if (!count_type.isInteger()) {
                try self.err_reporter.report(
                    repeat.location,
                    CompilerError.TypeMismatch,
                    "Repeat count must be an integer, got {}",
                    .{count_type},
                );
                return CompilerError.TypeMismatch;
            }
        }
        
        // Analyze body
        for (repeat.body.items) |stmt| {
            try self.analyzeStatement(stmt);
        }
    }
    
    /// Analyze an expression and return its type
    fn analyzeExpression(self: *SemanticAnalyzer, expr: ast.Node) CompilerError!KLType {
        return switch (expr) {
            .int_literal => .sint32, // Default to sint32
            .char_literal => .char,
            .string_literal => .text,
            .identifier => |id| try self.analyzeIdentifier(id),
            .binary_op => |bin| try self.analyzeBinaryOp(bin),
            .function_call => |call| try self.analyzeFunctionCall(call),
            else => CompilerError.TypeMismatch,
        };
    }
    
    /// Analyze identifier reference
    fn analyzeIdentifier(self: *SemanticAnalyzer, id: *ast.IdentifierNode) CompilerError!KLType {
        const symbol = self.lookupSymbol(id.name) orelse {
            try self.err_reporter.report(
                id.location,
                CompilerError.UndefinedVariable,
                "Undefined identifier '{s}'",
                .{id.name},
            );
            return CompilerError.UndefinedVariable;
        };
        
        return switch (symbol.kind) {
            .variable => |decl| decl.var_type,
            .parameter => |param| param.param_type,
            else => {
                try self.err_reporter.report(
                    id.location,
                    CompilerError.TypeMismatch,
                    "'{s}' is not a variable or parameter",
                    .{id.name},
                );
                return CompilerError.TypeMismatch;
            },
        };
    }
    
    /// Analyze binary operation
    fn analyzeBinaryOp(self: *SemanticAnalyzer, bin: *ast.BinaryOpNode) CompilerError!KLType {
        const left_type = try self.analyzeExpression(bin.left);
        const right_type = try self.analyzeExpression(bin.right);
        
        // For MVP: both operands must have the same type
        if (!left_type.isCompatible(right_type)) {
            try self.err_reporter.report(
                bin.location,
                CompilerError.TypeMismatch,
                "Binary operation requires matching types, got {} and {}",
                .{ left_type, right_type },
            );
            return CompilerError.TypeMismatch;
        }
        
        // Determine result type based on operator
        return switch (bin.op) {
            // Arithmetic: return same type as operands
            .add, .sub, .mul, .div, .mod => left_type,
            
            // Comparison: return bool
            .eq, .neq, .lt, .gt, .lte, .gte => .bool_type,
            
            // Logical: require bool, return bool
            .logic_and, .logic_or => blk: {
                if (left_type != .bool_type) {
                    try self.err_reporter.report(
                        bin.location,
                        CompilerError.TypeMismatch,
                        "Logical operation requires boolean operands, got {}",
                        .{left_type},
                    );
                    return CompilerError.TypeMismatch;
                }
                break :blk .bool_type;
            },
        };
    }
    
    /// Analyze function call (basic arithmetic functions for MVP)
    fn analyzeFunctionCall(self: *SemanticAnalyzer, call: *ast.FunctionCallNode) CompilerError!KLType {
        // For MVP, support basic arithmetic functions
        const func_name = call.function_name;
        
        // Variadic intrinsics
        if (std.mem.eql(u8, func_name, "Count")) {
            // Count[variadic_param] - returns sint32 count of elements
            if (call.arguments.items.len != 1) {
                try self.err_reporter.report(
                    call.location,
                    CompilerError.InvalidSyntax,
                    "Count expects exactly 1 argument (variadic parameter)",
                    .{},
                );
                return CompilerError.InvalidSyntax;
            }
            
            // Verify argument is an identifier (the variadic parameter name)
            const arg = call.arguments.items[0];
            if (arg != .identifier) {
                try self.err_reporter.report(
                    call.location,
                    CompilerError.InvalidSyntax,
                    "Count argument must be a variadic parameter name",
                    .{},
                );
                return CompilerError.InvalidSyntax;
            }
            
            // Return sint32 for count
            return .{ .sint32 = {} };
        }
        
        if (std.mem.eql(u8, func_name, "Get")) {
            // Get[variadic_param, index] - returns element type
            if (call.arguments.items.len != 2) {
                try self.err_reporter.report(
                    call.location,
                    CompilerError.InvalidSyntax,
                    "Get expects exactly 2 arguments (variadic parameter, index)",
                    .{},
                );
                return CompilerError.InvalidSyntax;
            }
            
            // Verify first argument is an identifier (the variadic parameter name)
            const param_arg = call.arguments.items[0];
            if (param_arg != .identifier) {
                try self.err_reporter.report(
                    call.location,
                    CompilerError.InvalidSyntax,
                    "Get first argument must be a variadic parameter name",
                    .{},
                );
                return CompilerError.InvalidSyntax;
            }
            
            // Verify second argument is an integer index
            const index_arg = call.arguments.items[1];
            const index_type = try self.analyzeExpression(index_arg);
            if (!index_type.isInteger()) {
                try self.err_reporter.report(
                    call.location,
                    CompilerError.TypeMismatch,
                    "Get index must be an integer",
                    .{},
                );
                return CompilerError.TypeMismatch;
            }
            
            // For MVP, assume uint32 element type (matches variadic param type in System.kl)
            // In a full implementation, we'd look up the actual variadic parameter type
            return .{ .uint32 = {} };
        }
        
        // Arithmetic functions
        if (std.mem.eql(u8, func_name, "Add") or
            std.mem.eql(u8, func_name, "Sub") or
            std.mem.eql(u8, func_name, "Mul") or
            std.mem.eql(u8, func_name, "Div") or
            std.mem.eql(u8, func_name, "Mod") or
            std.mem.eql(u8, func_name, "Subtract") or
            std.mem.eql(u8, func_name, "Multiply") or
            std.mem.eql(u8, func_name, "Divide") or
            std.mem.eql(u8, func_name, "Modulo"))
        {
            // Variadic arithmetic: require at least 1 argument
            if (call.arguments.items.len == 0) {
                try self.err_reporter.report(
                    call.location,
                    CompilerError.InvalidSyntax,
                    "Function '{s}' requires at least 1 argument",
                    .{ func_name },
                );
                return CompilerError.InvalidSyntax;
            }
            
            // Check all arguments are integers and compatible types
            var result_type: KLType = undefined;
            for (call.arguments.items, 0..) |arg, i| {
                const arg_type = try self.analyzeExpression(arg);
                
                if (!arg_type.isInteger()) {
                    try self.err_reporter.report(
                        call.location,
                        CompilerError.TypeMismatch,
                        "Arithmetic function requires integer arguments",
                        .{},
                    );
                    return CompilerError.TypeMismatch;
                }
                
                if (i == 0) {
                    result_type = arg_type;
                } else {
                    if (!result_type.isCompatible(arg_type)) {
                        try self.err_reporter.report(
                            call.location,
                            CompilerError.TypeMismatch,
                            "Arithmetic function requires matching argument types",
                            .{},
                        );
                        return CompilerError.TypeMismatch;
                    }
                }
            }
            
            return result_type;
        }
        
        // Comparison functions
        if (std.mem.eql(u8, func_name, "Equal") or
            std.mem.eql(u8, func_name, "NotEqual") or
            std.mem.eql(u8, func_name, "LessThan") or
            std.mem.eql(u8, func_name, "GreaterThan") or
            std.mem.eql(u8, func_name, "LessOrEqual") or
            std.mem.eql(u8, func_name, "GreaterOrEqual") or
            std.mem.eql(u8, func_name, "Equals") or
            std.mem.eql(u8, func_name, "Less") or
            std.mem.eql(u8, func_name, "Greater"))
        {
            // Require 2 arguments
            if (call.arguments.items.len != 2) {
                try self.err_reporter.report(
                    call.location,
                    CompilerError.InvalidSyntax,
                    "Function '{s}' expects 2 arguments, got {d}",
                    .{ func_name, call.arguments.items.len },
                );
                return CompilerError.InvalidSyntax;
            }
            
            const arg1_type = try self.analyzeExpression(call.arguments.items[0]);
            const arg2_type = try self.analyzeExpression(call.arguments.items[1]);
            
            if (!arg1_type.isCompatible(arg2_type)) {
                try self.err_reporter.report(
                    call.location,
                    CompilerError.TypeMismatch,
                    "Comparison function requires compatible argument types",
                    .{},
                );
                return CompilerError.TypeMismatch;
            }
            
            return KLType{ .bool_type = {} };
        }
        
        // Unknown function
        try self.err_reporter.report(
            call.location,
            CompilerError.UndefinedCommand,
            "Undefined function '{s}'",
            .{func_name},
        );
        return CompilerError.UndefinedCommand;
    }
    
    /// Declare a symbol in the current scope
    fn declareSymbol(self: *SemanticAnalyzer, name: []const u8, kind: SymbolKind, location: SourceLocation) CompilerError!void {
        try self.current_scope.declare(name, .{
            .name = name,
            .kind = kind,
            .location = location,
        });
    }
    
    /// Look up a symbol in the current scope chain
    fn lookupSymbol(self: *SemanticAnalyzer, name: []const u8) ?*Symbol {
        return self.current_scope.lookup(name);
    }
};

// Tests
const testing = std.testing;

test "sema - simple variable declaration" {
    const allocator = testing.allocator;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &err_reporter);
    defer analyzer.deinit();
    
    // Create a simple var decl: var x: sint32 = 42
    const var_decl = try ast.VarDeclNode.init(
        allocator,
        .{ .line = 1, .column = 1, .file = "<test>" },
        "x",
        .sint32,
        .{ .int_literal = try ast.IntLiteralNode.init(
            allocator,
            .{ .line = 1, .column = 10, .file = "<test>" },
            42,
        ) },
    );
    defer var_decl.deinit(allocator);
    
    // Should succeed
    try analyzer.analyzeVarDecl(var_decl);
    
    // Verify symbol was registered
    const symbol = analyzer.lookupSymbol("x");
    try testing.expect(symbol != null);
    try testing.expectEqualStrings("x", symbol.?.name);
}

test "sema - duplicate variable error" {
    const allocator = testing.allocator;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &err_reporter);
    defer analyzer.deinit();
    
    // Create first var decl
    const var_decl1 = try ast.VarDeclNode.init(
        allocator,
        .{ .line = 1, .column = 1, .file = "<test>" },
        "x",
        .sint32,
        null,
    );
    defer var_decl1.deinit(allocator);
    
    // Create duplicate var decl
    const var_decl2 = try ast.VarDeclNode.init(
        allocator,
        .{ .line = 2, .column = 1, .file = "<test>" },
        "x",
        .sint32,
        null,
    );
    defer var_decl2.deinit(allocator);
    
    // First should succeed
    try analyzer.analyzeVarDecl(var_decl1);
    
    // Second should fail
    const result = analyzer.analyzeVarDecl(var_decl2);
    try testing.expectError(CompilerError.DuplicateVariable, result);
    try testing.expect(err_reporter.hasErrors());
}

test "sema - type mismatch on initialization" {
    const allocator = testing.allocator;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &err_reporter);
    defer analyzer.deinit();
    
    // Create var decl with wrong type: var x: bool_type = 42
    const var_decl = try ast.VarDeclNode.init(
        allocator,
        .{ .line = 1, .column = 1, .file = "<test>" },
        "x",
        .bool_type,
        .{ .int_literal = try ast.IntLiteralNode.init(
            allocator,
            .{ .line = 1, .column = 10, .file = "<test>" },
            42,
        ) },
    );
    defer var_decl.deinit(allocator);
    
    // Should fail
    const result = analyzer.analyzeVarDecl(var_decl);
    try testing.expectError(CompilerError.TypeMismatch, result);
    try testing.expect(err_reporter.hasErrors());
}

test "sema - analyze simple module" {
    const allocator = testing.allocator;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &err_reporter);
    defer analyzer.deinit();
    
    // Create a simple module with one command
    const module = try ast.ModuleNode.init(
        allocator,
        .{ .line = 1, .column = 1, .file = "<test>" },
        "TestModule",
    );
    defer module.deinit(allocator);
    
    // Create a command
    const cmd = try ast.CommandImplNode.init(
        allocator,
        .{ .line = 2, .column = 1, .file = "<test>" },
        "Main",
    );
    try module.commands.append(allocator, cmd);
    
    // Add a variable declaration to the command
    const var_decl = try ast.VarDeclNode.init(
        allocator,
        .{ .line = 3, .column = 1, .file = "<test>" },
        "x",
        .sint32,
        .{ .int_literal = try ast.IntLiteralNode.init(
            allocator,
            .{ .line = 3, .column = 10, .file = "<test>" },
            42,
        ) },
    );
    try cmd.body.append(allocator, .{ .var_decl = var_decl });
    
    // Should succeed
    try analyzer.analyzeModule(module);
    
    // Verify no errors
    try testing.expect(!err_reporter.hasErrors());
}

test "sema - binary operation type checking" {
    const allocator = testing.allocator;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &err_reporter);
    defer analyzer.deinit();
    
    // Create: 5 + 3
    const left = ast.Node{ .int_literal = try ast.IntLiteralNode.init(
        allocator,
        .{ .line = 1, .column = 1, .file = "<test>" },
        5,
    ) };
    const right = ast.Node{ .int_literal = try ast.IntLiteralNode.init(
        allocator,
        .{ .line = 1, .column = 5, .file = "<test>" },
        3,
    ) };
    const bin_op = try ast.BinaryOpNode.init(
        allocator,
        .{ .line = 1, .column = 3, .file = "<test>" },
        .add,
        left,
        right,
    );
    defer bin_op.deinit(allocator);
    
    // Analyze the binary operation
    const result_type = try analyzer.analyzeBinaryOp(bin_op);
    
    // Should return sint32 (the type of the operands)
    try testing.expectEqual(KLType.sint32, result_type);
    try testing.expect(!err_reporter.hasErrors());
}
