const std = @import("std");
const SourceLocation = @import("error.zig").SourceLocation;
const KLType = @import("types.zig").KLType;

/// AST node types - separate expressions from statements
pub const Node = union(enum) {
    // Top-level declarations
    module: *ModuleNode,
    command_impl: *CommandImplNode,
    function_impl: *FunctionImplNode,
    
    // Statements (commands)
    var_decl: *VarDeclNode,
    param_decl: *ParamDeclNode,
    assignment: *AssignmentNode,
    command_invocation: *CommandInvocationNode,
    if_stmt: *IfStmtNode,
    repeat_stmt: *RepeatStmtNode,
    break_stmt: *BreakStmtNode,
    continue_stmt: *ContinueStmtNode,
    return_stmt: *ReturnStmtNode,
    goto_stmt: *GotoStmtNode,
    location_stmt: *LocationStmtNode,
    
    // Expressions (functions)
    binary_op: *BinaryOpNode,
    unary_op: *UnaryOpNode,
    function_call: *FunctionCallNode,
    int_literal: *IntLiteralNode,
    char_literal: *CharLiteralNode,
    string_literal: *StringLiteralNode,
    bool_literal: *BoolLiteralNode,
    identifier: *IdentifierNode,
    
    /// Recursively free a node and all its children
    pub fn deinit(self: Node, allocator: std.mem.Allocator) void {
        switch (self) {
            .module => |n| n.deinit(allocator),
            .command_impl => |n| n.deinit(allocator),
            .function_impl => |n| n.deinit(allocator),
            .var_decl => |n| n.deinit(allocator),
            .param_decl => |n| n.deinit(allocator),
            .assignment => |n| n.deinit(allocator),
            .command_invocation => |n| n.deinit(allocator),
            .if_stmt => |n| n.deinit(allocator),
            .repeat_stmt => |n| n.deinit(allocator),
            .break_stmt => |n| n.deinit(allocator),
            .continue_stmt => |n| n.deinit(allocator),
            .return_stmt => |n| n.deinit(allocator),
            .goto_stmt => |n| n.deinit(allocator),
            .location_stmt => |n| n.deinit(allocator),
            .binary_op => |n| n.deinit(allocator),
            .unary_op => |n| n.deinit(allocator),
            .function_call => |n| n.deinit(allocator),
            .int_literal => |n| n.deinit(allocator),
            .char_literal => |n| n.deinit(allocator),
            .string_literal => |n| n.deinit(allocator),
            .bool_literal => |n| n.deinit(allocator),
            .identifier => |n| n.deinit(allocator),
        }
    }
};

/// Module declaration
pub const ModuleNode = struct {
    location: SourceLocation,
    name: []const u8,
    commands: std.ArrayList(*CommandImplNode),
    functions: std.ArrayList(*FunctionImplNode),
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, name: []const u8) !*ModuleNode {
        const node = try allocator.create(ModuleNode);
        node.* = .{
            .location = location,
            .name = name,
            .commands = .{ .items = &.{}, .capacity = 0 },
            .functions = .{ .items = &.{}, .capacity = 0 },
        };
        return node;
    }
    
    pub fn deinit(self: *ModuleNode, allocator: std.mem.Allocator) void {
        for (self.commands.items) |cmd| {
            cmd.deinit(allocator);
        }
        self.commands.deinit(allocator);
        for (self.functions.items) |func| {
            func.deinit(allocator);
        }
        self.functions.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Intrinsic function identifiers for runtime support
pub const IntrinsicId = enum {
    none,
    system_print,
    system_println,
    system_read,
    system_readln,
    system_exit,
    system_allocate,
    system_deallocate,
    
    pub fn fromString(name: []const u8) ?IntrinsicId {
        if (std.mem.eql(u8, name, "system_print")) return .system_print;
        if (std.mem.eql(u8, name, "system_println")) return .system_println;
        if (std.mem.eql(u8, name, "system_read")) return .system_read;
        if (std.mem.eql(u8, name, "system_readln")) return .system_readln;
        if (std.mem.eql(u8, name, "system_exit")) return .system_exit;
        if (std.mem.eql(u8, name, "system_allocate")) return .system_allocate;
        if (std.mem.eql(u8, name, "system_deallocate")) return .system_deallocate;
        return null;
    }
};

/// Command implementation
pub const CommandImplNode = struct {
    location: SourceLocation,
    name: []const u8,
    parameters: std.ArrayList(*ParamDeclNode),
    body: std.ArrayList(Node),
    options: CommandOptions,
    // Native hook: if present, this command has a native implementation
    // The slice points directly into the source buffer (zero-allocation)
    native_hook: ?[]const u8 = null,
    // Generic type parameter for native hooks (e.g., "T" for @native["T"])
    // For now, only single generic parameter is supported
    generic_param: ?[]const u8 = null,
    
    pub const CommandOptions = struct {
        unchecked: bool = false,
        inline_hint: bool = false,
    };
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, name: []const u8) !*CommandImplNode {
        const node = try allocator.create(CommandImplNode);
        node.* = .{
            .location = location,
            .name = name,
            .parameters = .{ .items = &.{}, .capacity = 0 },
            .body = .{ .items = &.{}, .capacity = 0 },
            .options = .{},
            .native_hook = null,
            .generic_param = null,
        };
        return node;
    }
    
    pub fn deinit(self: *CommandImplNode, allocator: std.mem.Allocator) void {
        for (self.parameters.items) |param| {
            param.deinit(allocator);
        }
        self.parameters.deinit(allocator);
        for (self.body.items) |stmt| {
            stmt.deinit(allocator);
        }
        self.body.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Function implementation (returns a value, unlike commands)
pub const FunctionImplNode = struct {
    location: SourceLocation,
    name: []const u8,
    parameters: std.ArrayList(*ParamDeclNode),
    body: std.ArrayList(Node), // Function body statements
    return_type: ?KLType, // For now, inferred from return statements
    options: FunctionOptions,
    // Native hook: if present, this function has a native implementation
    // The slice points directly into the source buffer (zero-allocation)
    native_hook: ?[]const u8 = null,
    // Generic type parameter for native hooks (e.g., "T" for @native["T"])
    // For now, only single generic parameter is supported
    generic_param: ?[]const u8 = null,
    
    pub const FunctionOptions = struct {
        unchecked: bool = false,
        inline_hint: bool = false,
    };
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, name: []const u8) !*FunctionImplNode {
        const node = try allocator.create(FunctionImplNode);
        node.* = .{
            .location = location,
            .name = name,
            .parameters = .{ .items = &.{}, .capacity = 0 },
            .body = .{ .items = &.{}, .capacity = 0 },
            .return_type = null,
            .options = .{},
            .native_hook = null,
            .generic_param = null,
        };
        return node;
    }
    
    pub fn deinit(self: *FunctionImplNode, allocator: std.mem.Allocator) void {
        for (self.parameters.items) |param| {
            param.deinit(allocator);
        }
        self.parameters.deinit(allocator);
        for (self.body.items) |stmt| {
            stmt.deinit(allocator);
        }
        self.body.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Variable declaration
pub const VarDeclNode = struct {
    location: SourceLocation,
    name: []const u8,
    var_type: KLType,
    initial_value: ?Node,
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, name: []const u8, var_type: KLType, initial_value: ?Node) !*VarDeclNode {
        const node = try allocator.create(VarDeclNode);
        node.* = .{
            .location = location,
            .name = name,
            .var_type = var_type,
            .initial_value = initial_value,
        };
        return node;
    }
    
    pub fn deinit(self: *VarDeclNode, allocator: std.mem.Allocator) void {
        if (self.initial_value) |val| {
            val.deinit(allocator);
        }
        allocator.destroy(self);
    }
};

/// Parameter declaration
pub const ParamDeclNode = struct {
    location: SourceLocation,
    name: []const u8,
    param_type: KLType,
    initial_value: ?Node,
    direction: ParamDirection,
    is_variadic: bool = false, // true if parameter has ... suffix
    
    pub const ParamDirection = enum {
        input,
        output,
        inout,
    };
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, name: []const u8, param_type: KLType, initial_value: ?Node) !*ParamDeclNode {
        const node = try allocator.create(ParamDeclNode);
        node.* = .{
            .location = location,
            .name = name,
            .param_type = param_type,
            .initial_value = initial_value,
            .direction = .input, // Default for MVP
            .is_variadic = false,
        };
        return node;
    }
    
    pub fn deinit(self: *ParamDeclNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// Assignment statement
pub const AssignmentNode = struct {
    location: SourceLocation,
    target: []const u8,
    value: Node,
    op: AssignOp,
    
    pub const AssignOp = enum {
        simple,      // =
        add,         // +=
        sub,         // -=
        mul,         // *=
        div,         // /=
        mod,         // %=
        increment,   // ++
        decrement,   // --
    };
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, target: []const u8, value: Node, op: AssignOp) !*AssignmentNode {
        const node = try allocator.create(AssignmentNode);
        node.* = .{
            .location = location,
            .target = target,
            .value = value,
            .op = op,
        };
        return node;
    }
    
    pub fn deinit(self: *AssignmentNode, allocator: std.mem.Allocator) void {
        self.value.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Command invocation (statement)
pub const CommandInvocationNode = struct {
    location: SourceLocation,
    command_name: []const u8,  // May include module prefix: "MCLI.Output"
    arguments: std.ArrayList(Node),
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, command_name: []const u8) !*CommandInvocationNode {
        const node = try allocator.create(CommandInvocationNode);
        node.* = .{
            .location = location,
            .command_name = command_name,
            .arguments = .{ .items = &.{}, .capacity = 0 },
        };
        return node;
    }
    
    pub fn deinit(self: *CommandInvocationNode, allocator: std.mem.Allocator) void {
        for (self.arguments.items) |arg| {
            arg.deinit(allocator);
        }
        self.arguments.deinit(allocator);
        allocator.destroy(self);
    }
};

/// If statement
pub const IfStmtNode = struct {
    location: SourceLocation,
    condition: Node,
    then_body: std.ArrayList(Node),
    elif_clauses: std.ArrayList(ElifClause),
    else_body: ?std.ArrayList(Node),
    
    pub const ElifClause = struct {
        condition: Node,
        body: std.ArrayList(Node),
    };
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, condition: Node) !*IfStmtNode {
        const node = try allocator.create(IfStmtNode);
        node.* = .{
            .location = location,
            .condition = condition,
            .then_body = .{ .items = &.{}, .capacity = 0 },
            .elif_clauses = .{ .items = &.{}, .capacity = 0 },
            .else_body = null,
        };
        return node;
    }
    
    pub fn deinit(self: *IfStmtNode, allocator: std.mem.Allocator) void {
        self.condition.deinit(allocator);
        for (self.then_body.items) |stmt| {
            stmt.deinit(allocator);
        }
        self.then_body.deinit(allocator);
        for (self.elif_clauses.items) |*elif| {
            elif.condition.deinit(allocator);
            for (elif.body.items) |stmt| {
                stmt.deinit(allocator);
            }
            elif.body.deinit(allocator);
        }
        self.elif_clauses.deinit(allocator);
        if (self.else_body) |*else_b| {
            for (else_b.items) |stmt| {
                stmt.deinit(allocator);
            }
            else_b.deinit(allocator);
        }
        allocator.destroy(self);
    }
};

/// Repeat statement
pub const RepeatStmtNode = struct {
    location: SourceLocation,
    count: ?Node,  // null means infinite
    body: std.ArrayList(Node),
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, count: ?Node) !*RepeatStmtNode {
        const node = try allocator.create(RepeatStmtNode);
        node.* = .{
            .location = location,
            .count = count,
            .body = .{ .items = &.{}, .capacity = 0 },
        };
        return node;
    }
    
    pub fn deinit(self: *RepeatStmtNode, allocator: std.mem.Allocator) void {
        if (self.count) |cnt| {
            cnt.deinit(allocator);
        }
        for (self.body.items) |stmt| {
            stmt.deinit(allocator);
        }
        self.body.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Break statement
pub const BreakStmtNode = struct {
    location: SourceLocation,
    levels: u32,  // Number of loop levels to break (default 1)
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, levels: u32) !*BreakStmtNode {
        const node = try allocator.create(BreakStmtNode);
        node.* = .{
            .location = location,
            .levels = levels,
        };
        return node;
    }
    
    pub fn deinit(self: *BreakStmtNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// Continue statement
pub const ContinueStmtNode = struct {
    location: SourceLocation,
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation) !*ContinueStmtNode {
        const node = try allocator.create(ContinueStmtNode);
        node.* = .{
            .location = location,
        };
        return node;
    }
    
    pub fn deinit(self: *ContinueStmtNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// Return statement
pub const ReturnStmtNode = struct {
    location: SourceLocation,
    value: ?Node,  // For functions only
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, value: ?Node) !*ReturnStmtNode {
        const node = try allocator.create(ReturnStmtNode);
        node.* = .{
            .location = location,
            .value = value,
        };
        return node;
    }
    
    pub fn deinit(self: *ReturnStmtNode, allocator: std.mem.Allocator) void {
        if (self.value) |val| {
            val.deinit(allocator);
        }
        allocator.destroy(self);
    }
};

/// Goto statement
pub const GotoStmtNode = struct {
    location: SourceLocation,
    label: []const u8,
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, label: []const u8) !*GotoStmtNode {
        const node = try allocator.create(GotoStmtNode);
        node.* = .{
            .location = location,
            .label = label,
        };
        return node;
    }
    
    pub fn deinit(self: *GotoStmtNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// Location statement (label)
pub const LocationStmtNode = struct {
    location: SourceLocation,
    label: []const u8,
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, label: []const u8) !*LocationStmtNode {
        const node = try allocator.create(LocationStmtNode);
        node.* = .{
            .location = location,
            .label = label,
        };
        return node;
    }
    
    pub fn deinit(self: *LocationStmtNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// Binary operation (expression)
pub const BinaryOpNode = struct {
    location: SourceLocation,
    op: BinaryOp,
    left: Node,
    right: Node,
    
    pub const BinaryOp = enum {
        // Arithmetic
        add,
        sub,
        mul,
        div,
        mod,
        
        // Comparison
        eq,
        neq,
        lt,
        gt,
        lte,
        gte,
        
        // Logical
        logic_and,
        logic_or,
    };
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, op: BinaryOp, left: Node, right: Node) !*BinaryOpNode {
        const node = try allocator.create(BinaryOpNode);
        node.* = .{
            .location = location,
            .op = op,
            .left = left,
            .right = right,
        };
        return node;
    }
    
    pub fn deinit(self: *BinaryOpNode, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        self.right.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Unary operation (expression)
pub const UnaryOpNode = struct {
    location: SourceLocation,
    op: UnaryOp,
    operand: Node,
    
    pub const UnaryOp = enum {
        negate,
        logic_not,
    };
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, op: UnaryOp, operand: Node) !*UnaryOpNode {
        const node = try allocator.create(UnaryOpNode);
        node.* = .{
            .location = location,
            .op = op,
            .operand = operand,
        };
        return node;
    }
    
    pub fn deinit(self: *UnaryOpNode, allocator: std.mem.Allocator) void {
        self.operand.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Function call (expression with prefix notation: Add[x, y])
pub const FunctionCallNode = struct {
    location: SourceLocation,
    function_name: []const u8,
    arguments: std.ArrayList(Node),
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, function_name: []const u8) !*FunctionCallNode {
        const node = try allocator.create(FunctionCallNode);
        node.* = .{
            .location = location,
            .function_name = function_name,
            .arguments = .{ .items = &.{}, .capacity = 0 },
        };
        return node;
    }
    
    pub fn deinit(self: *FunctionCallNode, allocator: std.mem.Allocator) void {
        for (self.arguments.items) |arg| {
            arg.deinit(allocator);
        }
        self.arguments.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Integer literal
pub const IntLiteralNode = struct {
    location: SourceLocation,
    value: i64,
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, value: i64) !*IntLiteralNode {
        const node = try allocator.create(IntLiteralNode);
        node.* = .{
            .location = location,
            .value = value,
        };
        return node;
    }
    
    pub fn deinit(self: *IntLiteralNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// Character literal
pub const CharLiteralNode = struct {
    location: SourceLocation,
    value: u32,  // Unicode codepoint
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, value: u32) !*CharLiteralNode {
        const node = try allocator.create(CharLiteralNode);
        node.* = .{
            .location = location,
            .value = value,
        };
        return node;
    }
    
    pub fn deinit(self: *CharLiteralNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// String literal
pub const StringLiteralNode = struct {
    location: SourceLocation,
    value: []const u8,
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, value: []const u8) !*StringLiteralNode {
        const node = try allocator.create(StringLiteralNode);
        node.* = .{
            .location = location,
            .value = value,
        };
        return node;
    }
    
    pub fn deinit(self: *StringLiteralNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// Boolean literal
pub const BoolLiteralNode = struct {
    location: SourceLocation,
    value: bool,
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, value: bool) !*BoolLiteralNode {
        const node = try allocator.create(BoolLiteralNode);
        node.* = .{
            .location = location,
            .value = value,
        };
        return node;
    }
    
    pub fn deinit(self: *BoolLiteralNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// Identifier (variable reference)
pub const IdentifierNode = struct {
    location: SourceLocation,
    name: []const u8,
    
    pub fn init(allocator: std.mem.Allocator, location: SourceLocation, name: []const u8) !*IdentifierNode {
        const node = try allocator.create(IdentifierNode);
        node.* = .{
            .location = location,
            .name = name,
        };
        return node;
    }
    
    pub fn deinit(self: *IdentifierNode, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};
