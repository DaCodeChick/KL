const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const types = @import("types.zig");
const ErrorReporter = @import("error.zig").ErrorReporter;
const SourceLocation = @import("error.zig").SourceLocation;

const Token = lexer.Token;
const TokenType = lexer.TokenType;
const Lexer = lexer.Lexer;

const ParseError = error{
    OutOfMemory,
    UnexpectedToken,
    InvalidSyntax,
    ExpectedToken,
    InvalidCharacter,
    UnterminatedString,
    UnterminatedComment,
    InvalidNumber,
    Overflow,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: *Lexer,
    error_reporter: *ErrorReporter,
    current_token: Token,
    peek_token: Token,

    pub fn init(allocator: std.mem.Allocator, lex: *Lexer, err_reporter: *ErrorReporter) !Parser {
        var p = Parser{
            .allocator = allocator,
            .lexer = lex,
            .error_reporter = err_reporter,
            .current_token = undefined,
            .peek_token = undefined,
        };
        
        // Initialize with first two tokens
        p.current_token = try p.lexer.nextToken();
        p.peek_token = try p.lexer.nextToken();
        
        return p;
    }

    fn advance(self: *Parser) !void {
        self.current_token = self.peek_token;
        self.peek_token = try self.lexer.nextToken();
    }

    fn expect(self: *Parser, token_type: TokenType) !void {
        if (self.current_token.type != token_type) {
            try self.error_reporter.report(
                self.current_token.location,
                error.ExpectedToken,
                "Expected {s}, but got {s}",
                .{ @tagName(token_type), @tagName(self.current_token.type) }
            );
            return error.UnexpectedToken;
        }
        try self.advance();
    }

    /// Parse a complete KL module
    pub fn parseModule(self: *Parser) !*ast.ModuleNode {
        // Expect "Module" keyword
        try self.expect(.kw_module);
        
        const module_name = self.current_token.lexeme;
        const module_loc = self.current_token.location;
        try self.expect(.identifier);
        
        // Module declaration requires semicolon
        try self.expect(.semicolon);
        
        const module_node = try ast.ModuleNode.init(self.allocator, module_loc, module_name);
        errdefer module_node.deinit(self.allocator);
        
        // Parse commands until EndModule
        while (self.current_token.type != .kw_emodule and 
               self.current_token.type != .eof) {
            // Skip and collect pragmas before command/function
            var pragma: ?[]const u8 = null;
            if (self.current_token.type == .pragma) {
                pragma = self.current_token.lexeme;
                try self.advance();
            }
            
            if (self.current_token.type == .kw_cmd) {
                const cmd = try self.parseCommand();
                // If we had a pragma, parse it and set intrinsic flags
                if (pragma) |pragma_text| {
                    try self.applyPragmaToCommand(cmd, pragma_text);
                }
                try module_node.commands.append(self.allocator, cmd);
            } else if (self.current_token.type == .kw_function) {
                const func = try self.parseFunction();
                // If we had a pragma, parse it and set native hook
                if (pragma) |pragma_text| {
                    try self.applyPragmaToFunction(func, pragma_text);
                }
                try module_node.functions.append(self.allocator, func);
            } else if (self.current_token.type == .pragma) {
                // Pragma without following command/function - just skip it
                try self.advance();
            } else {
                try self.error_reporter.report(
                    self.current_token.location,
                    error.InvalidSyntax,
                    "Expected Command, Function, or EndModule, got {s}",
                    .{ @tagName(self.current_token.type) }
                );
                return error.UnexpectedToken;
            }
        }
        
        try self.expect(.kw_emodule);
        
        // EndModule requires semicolon
        try self.expect(.semicolon);
        
        return module_node;
    }

    /// Parse a command implementation
    fn parseCommand(self: *Parser) !*ast.CommandImplNode {
        // Accept "Command" or "Cmd"
        if (self.current_token.type == .kw_cmd) {
            try self.advance();
        } else {
            return error.UnexpectedToken;
        }
        
        const cmd_name = self.current_token.lexeme;
        const cmd_loc = self.current_token.location;
        try self.expect(.identifier);
        
        const cmd_node = try ast.CommandImplNode.init(self.allocator, cmd_loc, cmd_name);
        errdefer cmd_node.deinit(self.allocator);
        
        // Check for declaration-only syntax: Command Name[params...];
        // vs full body syntax: Command Name; ... EndCommand;
        const is_declaration_only = self.current_token.type == .lbracket;
        
        if (is_declaration_only) {
            // Declaration-only syntax for native commands
            try self.advance(); // consume '['
            
            while (self.current_token.type != .rbracket and 
                   self.current_token.type != .eof) {
                const param = try self.parseParameter();
                try cmd_node.parameters.append(self.allocator, param);
                
                if (self.current_token.type == .comma) {
                    try self.advance();
                } else if (self.current_token.type != .rbracket) {
                    try self.error_reporter.report(
                        self.current_token.location,
                        error.InvalidSyntax,
                        "Expected ',' or ']' in parameter list",
                        .{}
                    );
                    return error.UnexpectedToken;
                }
            }
            
            try self.expect(.rbracket);
            
            // Declaration-only: expect semicolon, no EndCommand
            try self.expect(.semicolon);
            return cmd_node;
        }
        
        // Full body syntax: Command Name; ... EndCommand;
        // Command declaration requires semicolon
        try self.expect(.semicolon);
        
        // Parse command body until EndCommand
        while (self.current_token.type != .kw_ecmd and 
               self.current_token.type != .eof) {
            // Skip extra semicolons (empty statements)
            if (self.current_token.type == .semicolon) {
                try self.advance();
                continue;
            }
            
            const stmt = try self.parseStatement();
            try cmd_node.body.append(self.allocator, stmt);
            
            // Require semicolon after statement
            try self.expect(.semicolon);
        }
        
        try self.expect(.kw_ecmd);
        
        // EndCommand requires semicolon
        try self.expect(.semicolon);
        
        return cmd_node;
    }

    /// Parse a parameter declaration
    fn parseParameter(self: *Parser) !*ast.ParamDeclNode {
        const param_name = self.current_token.lexeme;
        const param_loc = self.current_token.location;
        try self.expect(.identifier);
        
        // Check for variadic marker (...)
        var is_variadic = false;
        if (self.current_token.type == .ellipsis) {
            is_variadic = true;
            try self.advance();
        }
        
        // Parse optional type annotation (: type)
        var param_type = types.KLType{ .sint32 = {} }; // default type
        if (self.current_token.type == .colon) {
            try self.advance(); // consume ':'
            param_type = try self.parseType();
        }
        
        const param_node = try ast.ParamDeclNode.init(
            self.allocator,
            param_loc,
            param_name,
            param_type,
            null
        );
        param_node.is_variadic = is_variadic;
        
        return param_node;
    }

    /// Parse a type expression
    fn parseType(self: *Parser) !types.KLType {
        return switch (self.current_token.type) {
            .kw_uint => blk: {
                try self.advance();
                // For now, default to uint32
                break :blk types.KLType{ .uint32 = {} };
            },
            .kw_sint => blk: {
                try self.advance();
                // For now, default to sint32
                break :blk types.KLType{ .sint32 = {} };
            },
            .kw_bool => blk: {
                try self.advance();
                break :blk types.KLType{ .bool_type = {} };
            },
            .kw_char => blk: {
                try self.advance();
                break :blk types.KLType{ .char = {} };
            },
            .identifier => blk: {
                // Check for type names like "uint32", "text", etc.
                const type_name = self.current_token.lexeme;
                try self.advance();
                
                if (std.mem.eql(u8, type_name, "uint32")) {
                    break :blk types.KLType{ .uint32 = {} };
                } else if (std.mem.eql(u8, type_name, "uint8")) {
                    break :blk types.KLType{ .uint8 = {} };
                } else if (std.mem.eql(u8, type_name, "sint32")) {
                    break :blk types.KLType{ .sint32 = {} };
                } else if (std.mem.eql(u8, type_name, "sint8")) {
                    break :blk types.KLType{ .sint8 = {} };
                } else if (std.mem.eql(u8, type_name, "text")) {
                    break :blk types.KLType{ .text = {} };
                } else {
                    // Unknown type, default to uint32 for now
                    break :blk types.KLType{ .uint32 = {} };
                }
            },
            else => {
                try self.error_reporter.report(
                    self.current_token.location,
                    error.InvalidSyntax,
                    "Expected type, got {s}",
                    .{ @tagName(self.current_token.type) }
                );
                return error.UnexpectedToken;
            },
        };
    }

    /// Parse a statement (commands/control flow)
    fn parseStatement(self: *Parser) ParseError!ast.Node {
        return switch (self.current_token.type) {
            .kw_var => self.parseVarDecl(),
            .kw_set => self.parseSetStatement(),
            .kw_if => self.parseIfStatement(),
            .kw_repeat => self.parseRepeatStatement(),
            .kw_return => self.parseReturnStatement(),
            .kw_goto => self.parseGotoStatement(),
            .kw_loc => self.parseLocationStatement(),
            .identifier => self.parseIdentifierStatement(),
            else => {
                try self.error_reporter.report(
                    self.current_token.location,
                    error.InvalidSyntax,
                    "Unexpected token in statement: {s}",
                    .{ @tagName(self.current_token.type) }
                );
                return error.UnexpectedToken;
            },
        };
    }

    /// Parse variable declaration: var name, type; or var name, type, value;
    fn parseVarDecl(self: *Parser) !ast.Node {
        // Accept both "Var" and "Variable"
        if (self.current_token.type == .kw_var) {
            try self.advance();
        } else {
            return error.UnexpectedToken;
        }
        
        // Parse variable name
        const var_name = self.current_token.lexeme;
        const var_loc = self.current_token.location;
        try self.expect(.identifier);
        
        // Expect comma
        try self.expect(.comma);
        
        // Parse type
        const var_type = try self.parseType();
        
        // Check for optional initial value after comma
        var initial_value: ?ast.Node = null;
        if (self.current_token.type == .comma) {
            try self.advance(); // consume comma
            initial_value = try self.parseExpression();
        }
        
        const var_node = try ast.VarDeclNode.init(
            self.allocator,
            var_loc,
            var_name,
            var_type,
            initial_value
        );
        
        return ast.Node{ .var_decl = var_node };
    }

    /// Parse set statement: set varname, value;
    fn parseSetStatement(self: *Parser) !ast.Node {
        const set_loc = self.current_token.location;
        try self.expect(.kw_set);
        
        // Parse variable name
        const var_name = self.current_token.lexeme;
        try self.expect(.identifier);
        
        // Expect comma
        try self.expect(.comma);
        
        // Parse value expression
        const value = try self.parseExpression();
        
        const assign_node = try ast.AssignmentNode.init(
            self.allocator,
            set_loc,
            var_name,
            value,
            .simple
        );
        
        return ast.Node{ .assignment = assign_node };
    }

    /// Parse if statement
    fn parseIfStatement(self: *Parser) !ast.Node {
        const if_loc = self.current_token.location;
        try self.expect(.kw_if);
        
        const condition = try self.parseExpression();
        
        // If condition requires semicolon
        try self.expect(.semicolon);
        
        const if_node = try ast.IfStmtNode.init(self.allocator, if_loc, condition);
        errdefer if_node.deinit(self.allocator);
        
        // Parse then body
        while (self.current_token.type != .kw_endif and
               self.current_token.type != .kw_elseif and
               self.current_token.type != .kw_else and
               self.current_token.type != .eof) {
            // Skip extra semicolons
            if (self.current_token.type == .semicolon) {
                try self.advance();
                continue;
            }
            
            const stmt = try self.parseStatement();
            try if_node.then_body.append(self.allocator, stmt);
            try self.expect(.semicolon);
        }
        
        // Parse elif clauses
        while (self.current_token.type == .kw_elseif) {
            try self.advance();
            const elif_condition = try self.parseExpression();
            
            // ElseIf condition requires semicolon
            try self.expect(.semicolon);
            
            var elif_body: std.ArrayList(ast.Node) = .{ .items = &.{}, .capacity = 0 };
            while (self.current_token.type != .kw_endif and
                   self.current_token.type != .kw_elseif and
                   self.current_token.type != .kw_else and
                   self.current_token.type != .eof) {
                // Skip extra semicolons
                if (self.current_token.type == .semicolon) {
                    try self.advance();
                    continue;
                }
                
                const stmt = try self.parseStatement();
                try elif_body.append(self.allocator, stmt);
                try self.expect(.semicolon);
            }
            
            try if_node.elif_clauses.append(self.allocator, .{
                .condition = elif_condition,
                .body = elif_body,
            });
        }
        
        // Parse else clause
        if (self.current_token.type == .kw_else) {
            try self.advance();
            
            // Else requires semicolon
            try self.expect(.semicolon);
            
            var else_body: std.ArrayList(ast.Node) = .{ .items = &.{}, .capacity = 0 };
            
            while (self.current_token.type != .kw_endif and
                   self.current_token.type != .eof) {
                // Skip extra semicolons
                if (self.current_token.type == .semicolon) {
                    try self.advance();
                    continue;
                }
                
                const stmt = try self.parseStatement();
                try else_body.append(self.allocator, stmt);
                try self.expect(.semicolon);
            }
            
            if_node.else_body = else_body;
        }
        
        try self.expect(.kw_endif);
        
        return ast.Node{ .if_stmt = if_node };
    }

    /// Parse repeat statement
    fn parseRepeatStatement(self: *Parser) !ast.Node {
        const repeat_loc = self.current_token.location;
        try self.expect(.kw_repeat);
        
        // Check if there's a count expression
        var count: ?ast.Node = null;
        if (self.current_token.type != .semicolon and self.current_token.type != .kw_erepeat) {
            // Try to parse expression - if it fails, assume infinite repeat
            count = self.parseExpression() catch null;
        }
        
        // Repeat declaration requires semicolon
        try self.expect(.semicolon);
        
        const repeat_node = try ast.RepeatStmtNode.init(self.allocator, repeat_loc, count);
        errdefer repeat_node.deinit(self.allocator);
        
        // Parse body
        while (self.current_token.type != .kw_erepeat and
               self.current_token.type != .eof) {
            // Skip extra semicolons
            if (self.current_token.type == .semicolon) {
                try self.advance();
                continue;
            }
            
            const stmt = try self.parseStatement();
            try repeat_node.body.append(self.allocator, stmt);
            try self.expect(.semicolon);
        }
        
        try self.expect(.kw_erepeat);
        
        return ast.Node{ .repeat_stmt = repeat_node };
    }

    // Note: Break and Continue statements removed - tokens don't exist in new TokenType
    // /// Parse break statement
    // fn parseBreakStatement(self: *Parser) !ast.Node {
    //     const break_loc = self.current_token.location;
    //     try self.expect(.kw_break);
    //     
    //     // TODO: Parse optional level count
    //     const break_node = try ast.BreakStmtNode.init(self.allocator, break_loc, 1);
    //     
    //     return ast.Node{ .break_stmt = break_node };
    // }

    // /// Parse continue statement
    // fn parseContinueStatement(self: *Parser) !ast.Node {
    //     const continue_loc = self.current_token.location;
    //     try self.expect(.kw_continue);
    //     
    //     const continue_node = try ast.ContinueStmtNode.init(self.allocator, continue_loc);
    //     
    //     return ast.Node{ .continue_stmt = continue_node };
    // }

    /// Parse return statement
    fn parseReturnStatement(self: *Parser) !ast.Node {
        const return_loc = self.current_token.location;
        try self.expect(.kw_return);
        
        // Parse optional return value expression
        var return_value: ?ast.Node = null;
        // Check if there's an expression (not semicolon or EOF)
        if (self.current_token.type != .semicolon and 
            self.current_token.type != .eof) {
            return_value = try self.parseExpression();
        }
        
        const return_node = try ast.ReturnStmtNode.init(self.allocator, return_loc, return_value);
        
        return ast.Node{ .return_stmt = return_node };
    }

    /// Parse goto statement
    fn parseGotoStatement(self: *Parser) !ast.Node {
        const goto_loc = self.current_token.location;
        try self.expect(.kw_goto);
        
        const label = self.current_token.lexeme;
        try self.expect(.identifier);
        
        const goto_node = try ast.GotoStmtNode.init(self.allocator, goto_loc, label);
        
        return ast.Node{ .goto_stmt = goto_node };
    }

    /// Parse location statement (label)
    fn parseLocationStatement(self: *Parser) !ast.Node {
        const loc_loc = self.current_token.location;
        // Accept "Location" or "Loc"
        if (self.current_token.type == .kw_loc) {
            try self.advance();
        } else {
            return error.UnexpectedToken;
        }
        
        const label = self.current_token.lexeme;
        try self.expect(.identifier);
        
        const loc_node = try ast.LocationStmtNode.init(self.allocator, loc_loc, label);
        
        return ast.Node{ .location_stmt = loc_node };
    }

    /// Parse identifier statement (assignment or command invocation)
    fn parseIdentifierStatement(self: *Parser) !ast.Node {
        var id_name = self.current_token.lexeme;
        const id_loc = self.current_token.location;
        try self.advance();
        
        // Check for qualified name (e.g., System.Exit)
        if (self.current_token.type == .dot) {
            try self.advance();
            if (self.current_token.type != .identifier) {
                try self.error_reporter.report(
                    self.current_token.location,
                    error.InvalidSyntax,
                    "Expected identifier after '.'",
                    .{},
                );
                return error.UnexpectedToken;
            }
            
            // Build qualified name: "Module.Command"
            const qualified_name = try std.fmt.allocPrint(
                self.allocator,
                "{s}.{s}",
                .{ id_name, self.current_token.lexeme },
            );
            id_name = qualified_name;
            try self.advance();
        }
        
        // It's a command invocation (no assignment operators in KL - use Set command)
        const cmd_node = try ast.CommandInvocationNode.init(self.allocator, id_loc, id_name);
        errdefer cmd_node.deinit(self.allocator);
        
        // Parse arguments if present
        if (self.current_token.type == .lbracket) {
            try self.advance();
            
            while (self.current_token.type != .rbracket and
                   self.current_token.type != .eof) {
                const arg = try self.parseExpression();
                try cmd_node.arguments.append(self.allocator, arg);
                
                if (self.current_token.type == .comma) {
                    try self.advance();
                } else if (self.current_token.type != .rbracket) {
                    try self.error_reporter.report(
                        self.current_token.location,
                        error.InvalidSyntax,
                        "Expected ',' or ']' in argument list",
                        .{}
                    );
                    return error.UnexpectedToken;
                }
            }
            
            try self.expect(.rbracket);
        }
        
        return ast.Node{ .command_invocation = cmd_node };
    }

    /// Parse an expression with left-to-right evaluation (no precedence)
    pub fn parseExpression(self: *Parser) ParseError!ast.Node {
        return try self.parseInfixExpression();
    }

    /// Parse infix expression with left-to-right evaluation
    fn parseInfixExpression(self: *Parser) ParseError!ast.Node {
        var left = try self.parsePrimaryExpression();
        
        while (self.isInfixOperator(self.current_token.type)) {
            const op_token = self.current_token;
            try self.advance();
            
            const right = try self.parsePrimaryExpression();
            
            // Convert infix to binary operation
            const bin_op = self.tokenToBinaryOp(op_token.type);
            const bin_node = try ast.BinaryOpNode.init(
                self.allocator,
                op_token.location,
                bin_op,
                left,
                right
            );
            
            left = ast.Node{ .binary_op = bin_node };
        }
        
        return left;
    }

    /// Parse primary expression (literals, identifiers, function calls, unary ops)
    fn parsePrimaryExpression(self: *Parser) ParseError!ast.Node {
        return switch (self.current_token.type) {
            .int_literal => try self.parseIntLiteral(),
            .char_literal => try self.parseCharLiteral(),
            .string_literal => try self.parseStringLiteral(),
            .identifier => try self.parseIdentifierOrFunctionCall(),
            .op_minus => try self.parseUnaryMinus(),
            .op_not => try self.parseUnaryNot(),
            .lparen => try self.parseParenExpression(),
            else => {
                try self.error_reporter.report(
                    self.current_token.location,
                    error.InvalidSyntax,
                    "Unexpected token in expression: {s}",
                    .{ @tagName(self.current_token.type) }
                );
                return error.UnexpectedToken;
            },
        };
    }

    /// Parse integer literal
    fn parseIntLiteral(self: *Parser) !ast.Node {
        const value = try std.fmt.parseInt(i64, self.current_token.lexeme, 0);
        const loc = self.current_token.location;
        try self.advance();
        
        const lit_node = try ast.IntLiteralNode.init(self.allocator, loc, value);
        return ast.Node{ .int_literal = lit_node };
    }

    /// Parse character literal
    fn parseCharLiteral(self: *Parser) !ast.Node {
        // TODO: Properly decode unicode from string
        const value: u32 = if (self.current_token.lexeme.len > 0) 
            self.current_token.lexeme[0] 
        else 
            0;
        const loc = self.current_token.location;
        try self.advance();
        
        const lit_node = try ast.CharLiteralNode.init(self.allocator, loc, value);
        return ast.Node{ .char_literal = lit_node };
    }

    /// Parse string literal
    fn parseStringLiteral(self: *Parser) !ast.Node {
        const value = self.current_token.lexeme;
        const loc = self.current_token.location;
        try self.advance();
        
        const lit_node = try ast.StringLiteralNode.init(self.allocator, loc, value);
        return ast.Node{ .string_literal = lit_node };
    }

    /// Parse identifier or function call (prefix notation)
    fn parseIdentifierOrFunctionCall(self: *Parser) !ast.Node {
        const name = self.current_token.lexeme;
        const loc = self.current_token.location;
        try self.advance();
        
        // Check if followed by '[' for function call
        if (self.current_token.type == .lbracket) {
            try self.advance();
            
            const fn_node = try ast.FunctionCallNode.init(self.allocator, loc, name);
            errdefer fn_node.deinit(self.allocator);
            
            // Parse arguments
            while (self.current_token.type != .rbracket and
                   self.current_token.type != .eof) {
                const arg = try self.parseExpression();
                try fn_node.arguments.append(self.allocator, arg);
                
                if (self.current_token.type == .comma) {
                    try self.advance();
                } else if (self.current_token.type != .rbracket) {
                    try self.error_reporter.report(
                        self.current_token.location,
                        error.InvalidSyntax,
                        "Expected ',' or ']' in function arguments",
                        .{}
                    );
                    return error.UnexpectedToken;
                }
            }
            
            try self.expect(.rbracket);
            
            return ast.Node{ .function_call = fn_node };
        }
        
        // Just an identifier
        const id_node = try ast.IdentifierNode.init(self.allocator, loc, name);
        return ast.Node{ .identifier = id_node };
    }

    /// Parse unary minus
    fn parseUnaryMinus(self: *Parser) !ast.Node {
        const loc = self.current_token.location;
        try self.advance();
        
        const operand = try self.parsePrimaryExpression();
        
        const unary_node = try ast.UnaryOpNode.init(
            self.allocator,
            loc,
            .negate,
            operand
        );
        
        return ast.Node{ .unary_op = unary_node };
    }

    /// Parse unary not
    fn parseUnaryNot(self: *Parser) !ast.Node {
        const loc = self.current_token.location;
        try self.advance();
        
        const operand = try self.parsePrimaryExpression();
        
        const unary_node = try ast.UnaryOpNode.init(
            self.allocator,
            loc,
            .logic_not,
            operand
        );
        
        return ast.Node{ .unary_op = unary_node };
    }

    /// Parse parenthesized expression
    fn parseParenExpression(self: *Parser) !ast.Node {
        try self.expect(.lparen);
        const expr = try self.parseExpression();
        try self.expect(.rparen);
        return expr;
    }

    /// Check if token is an infix operator
    fn isInfixOperator(self: *Parser, token_type: TokenType) bool {
        _ = self;
        return switch (token_type) {
            .op_plus, .op_minus, .op_mult, .op_div, .op_mod,
            .op_eq, .op_neq,
            .op_lt, .op_gt, .op_lte, .op_gte,
            .op_and, .op_or,
            => true,
            else => false,
        };
    }

    /// Convert token type to binary operation
    fn tokenToBinaryOp(self: *Parser, token_type: TokenType) ast.BinaryOpNode.BinaryOp {
        _ = self;
        return switch (token_type) {
            .op_plus => .add,
            .op_minus => .sub,
            .op_mult => .mul,
            .op_div => .div,
            .op_mod => .mod,
            .op_eq => .eq,
            .op_neq => .neq,
            .op_lt => .lt,
            .op_gt => .gt,
            .op_lte => .lte,
            .op_gte => .gte,
            .op_and => .logic_and,
            .op_or => .logic_or,
            else => unreachable,
        };
    }
    
    /// Infer KL type from an expression node (basic type inference)
    fn inferType(self: *Parser, expr: ast.Node) types.KLType {
        _ = self;
        return switch (expr) {
            .int_literal => types.KLType{ .sint32 = {} },
            .char_literal => types.KLType{ .char = {} },
            .string_literal => types.KLType{ .text = {} },
            .binary_op => types.KLType{ .sint32 = {} }, // Assume int for now
            .function_call => types.KLType{ .sint32 = {} }, // Assume int for now
            else => types.KLType{ .sint32 = {} }, // Default
        };
    }
    
    /// Apply pragma annotation to a command
    /// Parse a function implementation
    fn parseFunction(self: *Parser) !*ast.FunctionImplNode {
        try self.expect(.kw_function);
        
        const func_name = self.current_token.lexeme;
        const func_loc = self.current_token.location;
        try self.expect(.identifier);
        
        const func_node = try ast.FunctionImplNode.init(self.allocator, func_loc, func_name);
        errdefer func_node.deinit(self.allocator);
        
        // Check for declaration-only syntax: Function Name[params...] Return expr
        // vs full body syntax: Function Name ... EndFunction
        const is_declaration_only = self.current_token.type == .lbracket;
        
        if (is_declaration_only) {
            // Declaration-only syntax for native functions
            try self.advance(); // consume '['
            
            // Parse parameters
            while (self.current_token.type != .rbracket and 
                   self.current_token.type != .eof) {
                const param_name = self.current_token.lexeme;
                const param_loc = self.current_token.location;
                try self.expect(.identifier);
                
                // Check for variadic marker (...)
                var is_variadic = false;
                if (self.current_token.type == .ellipsis) {
                    is_variadic = true;
                    try self.advance();
                }
                
                // Parse optional type annotation (: type)
                var param_type = types.KLType{ .uint32 = {} }; // default type
                if (self.current_token.type == .colon) {
                    try self.advance(); // consume ':'
                    param_type = try self.parseType();
                }
                
                const param_node = try ast.ParamDeclNode.init(
                    self.allocator,
                    param_loc,
                    param_name,
                    param_type,
                    null
                );
                param_node.is_variadic = is_variadic;
                
                try func_node.parameters.append(self.allocator, param_node);
                
                if (self.current_token.type == .comma) {
                    try self.advance();
                } else if (self.current_token.type != .rbracket) {
                    try self.error_reporter.report(
                        self.current_token.location,
                        error.InvalidSyntax,
                        "Expected ',' or ']' in parameter list",
                        .{}
                    );
                    return error.UnexpectedToken;
                }
            }
            
            try self.expect(.rbracket);
            
            // Expect: Return <type>
            try self.expect(.kw_return);
            const return_type = try self.parseType();
            func_node.return_type = return_type;
            
            // Declaration-only: expect semicolon, no EndFunction
            try self.expect(.semicolon);
            return func_node;
        } else {
            // Full body syntax
            
            // Function declaration requires semicolon
            try self.expect(.semicolon);
            
            // Parse parameters inside body using Parameter keyword
            while (self.current_token.type == .kw_prm) {
                try self.advance(); // consume 'Parameter'
                
                const param_name = self.current_token.lexeme;
                const param_loc = self.current_token.location;
                try self.expect(.identifier);
                
                // Check for variadic marker (...)
                var is_variadic = false;
                if (self.current_token.type == .ellipsis) {
                    is_variadic = true;
                    try self.advance();
                }
                
                // Expect colon and type
                try self.expect(.colon);
                const param_type = try self.parseType();
                
                const param_node = try ast.ParamDeclNode.init(
                    self.allocator,
                    param_loc,
                    param_name,
                    param_type,
                    null
                );
                param_node.is_variadic = is_variadic;
                
                try func_node.parameters.append(self.allocator, param_node);
                
                // Require semicolon after Parameter
                try self.expect(.semicolon);
            }
            
            // Parse function body statements until EndFunction
            while (self.current_token.type != .kw_efunction and 
                   self.current_token.type != .eof) {
                const stmt = try self.parseStatement();
                try func_node.body.append(self.allocator, stmt);
                
                // Require semicolon after each statement
                try self.expect(.semicolon);
            }
            
            // Expect EndFunction
            try self.expect(.kw_efunction);
            
            // EndFunction requires semicolon
            try self.expect(.semicolon);
            
            return func_node;
        }
    }

    fn applyPragmaToFunction(self: *Parser, func: *ast.FunctionImplNode, pragma_text: []const u8) !void {
        _ = self;
        const trimmed = std.mem.trim(u8, pragma_text, " \t\n\r");
        
        if (std.mem.startsWith(u8, trimmed, "native ")) {
            const hook_name = std.mem.trim(u8, trimmed["native ".len..], " \t\n\r");
            func.native_hook = hook_name;
        }
    }

    fn applyPragmaToCommand(self: *Parser, cmd: *ast.CommandImplNode, pragma_text: []const u8) !void {
        _ = self; // Unused for now
        // Parse pragma text: expected format is "native <hook_name>"
        // e.g., "native kl_sys_exit"
        // The slice points directly into the source buffer - zero allocation!
        
        const trimmed = std.mem.trim(u8, pragma_text, " \t\n\r");
        
        if (std.mem.startsWith(u8, trimmed, "native ")) {
            // Extract the hook name (everything after "native ")
            const hook_name = std.mem.trim(u8, trimmed["native ".len..], " \t\n\r");
            
            // Store the slice directly - it points into the source buffer
            // No allocation needed!
            cmd.native_hook = hook_name;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "parse simple integer literal" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source = "42";
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const expr = try parser.parseExpression();
    defer {
        if (expr == .int_literal) {
            expr.int_literal.deinit(allocator);
        }
    }
    
    try testing.expect(expr == .int_literal);
    try testing.expectEqual(@as(i64, 42), expr.int_literal.value);
}

test "parse simple addition with infix" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source = "5 + 3";
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const expr = try parser.parseExpression();
    defer expr.deinit(allocator);
    
    try testing.expect(expr == .binary_op);
    try testing.expectEqual(ast.BinaryOpNode.BinaryOp.add, expr.binary_op.op);
}

test "parse prefix function call Add[56, 89]" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source = "Add[56, 89]";
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const expr = try parser.parseExpression();
    defer expr.deinit(allocator);
    
    try testing.expect(expr == .function_call);
    try testing.expectEqualStrings("Add", expr.function_call.function_name);
    try testing.expectEqual(@as(usize, 2), expr.function_call.arguments.items.len);
}

test "parse left-to-right evaluation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // In KL: 2 + 3 * 4 = (2 + 3) * 4 = 20 (left-to-right, no precedence)
    const source = "2 + 3 * 4";
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const expr = try parser.parseExpression();
    defer expr.deinit(allocator);
    
    // Should be: Mul[Add[2, 3], 4]
    try testing.expect(expr == .binary_op);
    try testing.expectEqual(ast.BinaryOpNode.BinaryOp.mul, expr.binary_op.op);
    
    // Left side should be Add[2, 3]
    const left = expr.binary_op.left;
    try testing.expect(left == .binary_op);
    try testing.expectEqual(ast.BinaryOpNode.BinaryOp.add, left.binary_op.op);
}

test "parse simple module" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source =
        \\Module TestModule
        \\Command Hello
        \\EndCommand
        \\EndModule
    ;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const module = try parser.parseModule();
    defer module.deinit(allocator);
    
    try testing.expectEqualStrings("TestModule", module.name);
    try testing.expectEqual(@as(usize, 1), module.commands.items.len);
    try testing.expectEqualStrings("Hello", module.commands.items[0].name);
}

test "parse command with parameters" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source =
        \\Module TestModule
        \\Command Add[a, b]
        \\EndCommand
        \\EndModule
    ;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const module = try parser.parseModule();
    defer module.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 1), module.commands.items.len);
    const cmd = module.commands.items[0];
    try testing.expectEqualStrings("Add", cmd.name);
    try testing.expectEqual(@as(usize, 2), cmd.parameters.items.len);
    try testing.expectEqualStrings("a", cmd.parameters.items[0].name);
    try testing.expectEqualStrings("b", cmd.parameters.items[1].name);
}

test "parse if statement" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source =
        \\Module TestModule
        \\Command Test
        \\If x
        \\EndIf
        \\EndCommand
        \\EndModule
    ;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const module = try parser.parseModule();
    defer module.deinit(allocator);
    
    const cmd = module.commands.items[0];
    try testing.expectEqual(@as(usize, 1), cmd.body.items.len);
    try testing.expect(cmd.body.items[0] == .if_stmt);
}

test "parse repeat statement" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source =
        \\Module TestModule
        \\Command Test
        \\Repeat 10
        \\EndRepeat
        \\EndCommand
        \\EndModule
    ;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const module = try parser.parseModule();
    defer module.deinit(allocator);
    
    const cmd = module.commands.items[0];
    try testing.expectEqual(@as(usize, 1), cmd.body.items.len);
    try testing.expect(cmd.body.items[0] == .repeat_stmt);
}

test "parse variable declaration with assignment" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source =
        \\Module TestModule
        \\Command Test
        \\var x = 42
        \\EndCommand
        \\EndModule
    ;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const module = try parser.parseModule();
    defer module.deinit(allocator);
    
    const cmd = module.commands.items[0];
    try testing.expectEqual(@as(usize, 1), cmd.body.items.len);
    try testing.expect(cmd.body.items[0] == .var_decl);
    try testing.expectEqualStrings("x", cmd.body.items[0].var_decl.name);
}

test "parse assignment statement" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source =
        \\Module TestModule
        \\Command Test
        \\x = 42
        \\EndCommand
        \\EndModule
    ;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const module = try parser.parseModule();
    defer module.deinit(allocator);
    
    const cmd = module.commands.items[0];
    try testing.expectEqual(@as(usize, 1), cmd.body.items.len);
    try testing.expect(cmd.body.items[0] == .assignment);
    try testing.expectEqualStrings("x", cmd.body.items[0].assignment.target);
}

test "parse command invocation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const source =
        \\Module TestModule
        \\Command Test
        \\DoSomething[42, 99]
        \\EndCommand
        \\EndModule
    ;
    
    var err_reporter = ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    var lex = Lexer.init(source, "<test>", allocator, &err_reporter);
    var parser = try Parser.init(allocator, &lex, &err_reporter);
    
    const module = try parser.parseModule();
    defer module.deinit(allocator);
    
    const cmd = module.commands.items[0];
    try testing.expectEqual(@as(usize, 1), cmd.body.items.len);
    try testing.expect(cmd.body.items[0] == .command_invocation);
    try testing.expectEqualStrings("DoSomething", cmd.body.items[0].command_invocation.command_name);
    try testing.expectEqual(@as(usize, 2), cmd.body.items[0].command_invocation.arguments.items.len);
}
