const std = @import("std");
const ErrorReporter = @import("error.zig").ErrorReporter;
const SourceLocation = @import("error.zig").SourceLocation;
const CompilerError = @import("error.zig").CompilerError;

pub const TokenType = enum {
    // Literals
    int_literal, // Integer literal, e.g. 123, 0x4D2, 0b1010
    string_literal, // String literal, e.g. "hello world"
    char_literal, // Character literal, e.g. 'a', 'z', '<deg>'
    true_literal, // True literal, true or True
    false_literal, // False literal, false or False
    null_literal, // Null literal, null or Null

    // Keywords - control flow
    kw_if, // If keyword for conditional statements
    kw_ifnot, // IfNot keyword for negated conditionals
    kw_elseif, // ElseIf keyword for else-if branches
    kw_else, // Else keyword for else branches
    kw_endif, // EndIf keyword for ending if statements
    kw_repeat, // Repeat keyword for loops
    kw_erepeat, // EndRepeat keyword for ending loops
    kw_switch, // Switch keyword for switch statements
    kw_case, // Case keyword for switch cases
    kw_default, // Default keyword for default case in switch and translate statements
    kw_eswitch, // EndSwitch keyword for ending switch statements
    kw_translate, // Translate keyword for translation blocks
    kw_aso, // Associate keyword for associating values in translation blocks
    kw_etranslate, // EndTranslate keyword for ending translation blocks
    kw_return, // Return keyword for returning from functions

    // Keywords - declarations
    kw_module, // Module keyword for module declarations
    kw_emodule, // EndModule keyword for ending module declarations
    kw_cmd, // Command keyword for command declarations
    kw_ecmd, // EndCommand keyword for ending command declarations
    kw_function, // Function keyword for function declarations
    kw_efunction, // EndFunction keyword for ending function declarations
    kw_tuple, // Tuple keyword for tuple type declarations
    kw_etuple, // EndTuple keyword for ending tuple type declarations
    kw_record, // Record keyword for record type declarations
    kw_erecord, // EndRecord keyword for ending record type declarations
    kw_enum, // Enum keyword for enum type declarations
    kw_eenum, // EndEnum keyword for ending enum type declarations
    kw_var, // Variable keyword for variable declarations
    kw_prm, // Parameter keyword for parameter declarations
    kw_atr, // Attribute keyword for attribute declarations

    // Keywords - commands
    kw_set, // Set keyword for assignment command
    kw_incr, // Incr keyword for increment command
    kw_decr, // Decr keyword for decrement command
    kw_invoke, // Invoke keyword for invoking commands or functions

    // Type keywords
    kw_uint, // uint keyword for unsigned integer types
    kw_uint16, // uint16 keyword for 16-bit unsigned integer type
    kw_sint, // sint keyword for signed integer types
    kw_bool, // bool keyword for boolean types
    kw_char, // char keyword for character types
    kw_nullable, // Nullable keyword for nullable value types
    kw_unnullable, // Unnullable keyword for non-nullable value types
    kw_ptr, // Ptr keyword for pointer types
    kw_ref, // Ref keyword for reference types
    kw_refn, // RefN keyword for nullable references
    kw_signed, // Signed keyword for signed integer types
    kw_unsigned, // Unsigned keyword for unsigned integer types

    // storage modifiers
    kw_out, // Out keyword for output parameters
    kw_inout, // InOut keyword for parameters that are both input and output
    kw_readonly, // ReadOnly keyword for read-only parameters
    kw_modifyonly, // ModifyOnly keyword for write-only parameters
    kw_constantsize, // ConstantSize keyword for fixed-size arrays
    kw_preallocated, // Preallocated keyword for preallocated arrays
    kw_appended, // Appended keyword for dynamically appended arrays
    kw_unchangingsize, // UnchangingSize keyword for arrays that can be resized but not reallocated
    kw_consolidated, // Consolidated keyword for consolidated arrays
    kw_be, // BigEndian keyword for big-endian data types
    kw_le, // LittleEndian keyword for little-endian data types
    kw_aligned, // Aligned keyword for specifying alignment of types or variables
    kw_unaligned, // Unaligned keyword for specifying unaligned types or variables

    kw_goto, // goto keyword for goto statements
    kw_loc, // loc keyword for source code labels

    // Operators - arithmetic
    op_plus, // Add operator +
    op_minus, // Sub operator -
    op_mult, // Mul operator *
    op_div, // Div operator /
    op_mod, // DivRem operator %
    op_pow, // Pow/Power operator **

    // Operators - comparison
    op_eq, // Equal/EQ operator ==
    op_neq, // NotEqual/NEQ operator !=
    op_lt, // Less/LT operator <
    op_gt, // Greater/GT operator >
    op_lte, // LessEqual/LTE operator <=
    op_gte, // GreaterEqual/GTE operator >=

    // Commands and Operators - pointer
    kw_mkp, // MakePtr keyword for creating pointers to values
    kw_sett, // SetTarget keyword for setting the target of a pointer
    kw_setp, // SetPtr keyword for setting a pointer to point to another pointer (pointer assignment)
    kw_setpnull, // SetPtrNull keyword for setting a pointer to null
    kw_targetof, // TargetOf keyword for dereferencing pointers
    kw_gettarget, // GetTarget keyword for getting the target of a pointer without dereferencing
    kw_gettargetsize, // GetTargetSize keyword for getting the size of the target of a pointer
    kw_mvpf, // MovePtrFwd keyword for moving pointers forward by a certain number of bytes
    kw_mvpb, // MovePtrBack keyword for moving pointers backward by a certain number of bytes
    kw_incp, // IncrPtr keyword for incrementing pointers by a certain number of bytes
    kw_decp, // DecrPtr keyword for decrementing pointers by a certain number of bytes
    kw_equaltarget, // EqualTarget keyword for checking if two pointers point to the same target
    kw_equalptr, // EqualPtr keyword for checking if two pointers are equal (point to the same target and have the same offset)
    kw_isnullptr, // IsNullPtr keyword for checking if a pointer is null
    kw_ptrtouint, // PtrToUInt keyword for converting pointers to unsigned integers
    kw_uinttoptr, // UIntToPtr keyword for converting unsigned integers to pointers
    kw_load, // Load keyword for loading a value from a pointer
    kw_store, // Store keyword for storing a value to a pointer
    op_same, // Same operator ==#
    op_notsame, // NotSame operator !=#
    op_lessptr, // LessPtr operator <#
    op_greaterptr, // GreaterPtr operator >#
    op_lesseqptr, // LessEqualPtr operator <=#
    op_greatereqptr, // GreaterEqualPtr operator >=#

    // Operators - logical
    op_and, // And operator &&
    op_or, // Or operator ||
    op_not, // Not operator !
    op_notand, // NotAnd operator !&&
    op_notor, // NotOr operator !||
    op_min, // Minimum operator <?
    op_max, // Maximum operator >?

    // Operators - bitwise
    op_bitor, // BitOr operator |
    op_bitxor, // BitXor operator ^
    op_bitand, // BitAnd operator &
    op_bitclear, // BitClear operator &~ (AND NOT)
    op_bitshiftup, // BitShiftUp operator <<
    op_bitshiftdown, // BitShiftDown operator >>

    // Punctuation
    semicolon, // ;
    comma, // ,
    dot, // .
    range, // .. for ranges
    ellipsis, // ... for variadic parameters
    colon, // :
    lparen, // (
    rparen, // )
    lbracket, // [
    rbracket, // ]

    // Identifiers
    identifier,

    // Pragmas
    pragma,

    // Special
    eof,

    pub fn format(self: TokenType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}", .{@tagName(self)});
    }
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    location: SourceLocation,

    // For literals
    int_value: ?i64 = null,
    char_value: ?u32 = null, // Unicode codepoint

    pub fn format(self: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Token({}, \"{s}\", {})", .{ self.type, self.lexeme, self.location });
    }
};

pub const Lexer = struct {
    source: []const u8,
    filename: []const u8,
    current: usize,
    line: usize,
    column: usize,
    allocator: std.mem.Allocator,
    error_reporter: *ErrorReporter,

    pub fn init(source: []const u8, filename: []const u8, allocator: std.mem.Allocator, error_reporter: *ErrorReporter) Lexer {
        return .{
            .source = source,
            .filename = filename,
            .current = 0,
            .line = 1,
            .column = 1,
            .allocator = allocator,
            .error_reporter = error_reporter,
        };
    }

    pub fn tokenize(self: *Lexer) !std.ArrayList(Token) {
        var tokens: std.ArrayList(Token) = .{ .items = &.{}, .capacity = 0 };

        while (true) {
            const token = try self.nextToken();
            try tokens.append(self.allocator, token);
            if (token.type == .eof) break;
        }

        return tokens;
    }

    pub fn nextToken(self: *Lexer) !Token {
        self.skipWhitespace();

        if (self.isAtEnd()) {
            return self.makeToken(.eof, "");
        }

        const start_line = self.line;
        const start_column = self.column;
        const start = self.current;
        const c = self.advance();

        // Comments
        if (c == '{') {
            // Check if this is a pragma comment: {@...}
            if (self.peek() == '@') {
                return self.scanPragma(start, start_line, start_column);
            }
            try self.skipBlockComment();
            return self.nextToken();
        }

        if (c == '/' and self.peek() == '/') {
            self.skipLineComment();
            return self.nextToken();
        }

        // String literals
        if (c == '"') {
            return self.scanString(start_line, start_column);
        }

        // Character literals
        if (c == '\'') {
            return self.scanChar(start_line, start_column);
        }

        // Number literals
        if (std.ascii.isDigit(c)) {
            return self.scanNumber(start, start_line, start_column);
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            return self.scanIdentifier(start, start_line, start_column);
        }

        // Operators and punctuation
        return switch (c) {
            ';' => self.makeTokenFrom(.semicolon, start, start_line, start_column),
            ',' => self.makeTokenFrom(.comma, start, start_line, start_column),
            '.' => blk: {
                // Check for ellipsis (...)
                if (self.peek() == '.' and self.peekNext() == '.') {
                    _ = self.advance();
                    _ = self.advance();
                    break :blk self.makeTokenFrom(.ellipsis, start, start_line, start_column);
                }
                break :blk self.makeTokenFrom(.dot, start, start_line, start_column);
            },
            ':' => self.makeTokenFrom(.colon, start, start_line, start_column),
            '(' => self.makeTokenFrom(.lparen, start, start_line, start_column),
            ')' => self.makeTokenFrom(.rparen, start, start_line, start_column),
            '[' => self.makeTokenFrom(.lbracket, start, start_line, start_column),
            ']' => self.makeTokenFrom(.rbracket, start, start_line, start_column),

            '+' => self.makeTokenFrom(.op_plus, start, start_line, start_column),

            '-' => self.makeTokenFrom(.op_minus, start, start_line, start_column),

            '*' => blk: {
                if (self.match('*')) {
                    break :blk self.makeTokenFrom(.op_pow, start, start_line, start_column);
                }
                break :blk self.makeTokenFrom(.op_mult, start, start_line, start_column);
            },

            '/' => self.makeTokenFrom(.op_div, start, start_line, start_column),

            '%' => self.makeTokenFrom(.op_mod, start, start_line, start_column),

            '=' => blk: {
                if (self.match('=')) {
                    if (self.match('#')) {
                        break :blk self.makeTokenFrom(.op_same, start, start_line, start_column);
                    }
                    break :blk self.makeTokenFrom(.op_eq, start, start_line, start_column);
                }
                // Single '=' is not a valid token in KL
                try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.InvalidCharacter, "unexpected character '=' (did you mean '==' for comparison?)", .{});
                return error.InvalidCharacter;
            },

            '!' => blk: {
                if (self.match('=')) {
                    break :blk self.makeTokenFrom(.op_neq, start, start_line, start_column);
                }
                break :blk self.makeTokenFrom(.op_not, start, start_line, start_column);
            },

            '<' => blk: {
                if (self.match('=')) {
                    break :blk self.makeTokenFrom(.op_lte, start, start_line, start_column);
                }
                break :blk self.makeTokenFrom(.op_lt, start, start_line, start_column);
            },

            '>' => blk: {
                if (self.match('=')) {
                    break :blk self.makeTokenFrom(.op_gte, start, start_line, start_column);
                }
                break :blk self.makeTokenFrom(.op_gt, start, start_line, start_column);
            },

            '&' => blk: {
                if (self.match('&')) {
                    break :blk self.makeTokenFrom(.op_and, start, start_line, start_column);
                }
                try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.InvalidCharacter, "unexpected character '&' (did you mean '&&'?)", .{});
                return error.InvalidCharacter;
            },

            '|' => blk: {
                if (self.match('|')) {
                    break :blk self.makeTokenFrom(.op_or, start, start_line, start_column);
                }
                try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.InvalidCharacter, "unexpected character '|' (did you mean '||'?)", .{});
                return error.InvalidCharacter;
            },

            else => {
                try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.InvalidCharacter, "unexpected character '{c}'", .{c});
                return error.InvalidCharacter;
            },
        };
    }

    fn scanString(self: *Lexer, start_line: usize, start_column: usize) !Token {
        const start = self.current;

        while (!self.isAtEnd() and self.peek() != '"') {
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
            }
            _ = self.advance();
        }

        if (self.isAtEnd()) {
            try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.UnterminatedString, "unterminated string literal", .{});
            return error.UnterminatedString;
        }

        _ = self.advance(); // closing "
        const lexeme = self.source[start - 1 .. self.current];
        return Token{
            .type = .string_literal,
            .lexeme = lexeme,
            .location = .{ .line = start_line, .column = start_column, .file = self.filename },
        };
    }

    fn scanChar(self: *Lexer, start_line: usize, start_column: usize) !Token {
        const start = self.current;

        // Handle special escape sequences like <deg>, <quot>, <apos>
        if (self.peek() == '<') {
            _ = self.advance(); // <
            const escape_start = self.current;
            while (!self.isAtEnd() and self.peek() != '>') {
                _ = self.advance();
            }

            if (self.isAtEnd()) {
                try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.UnterminatedString, "unterminated escape sequence in character literal", .{});
                return error.UnterminatedString;
            }

            const escape_name = self.source[escape_start..self.current];
            _ = self.advance(); // >

            if (self.isAtEnd() or self.peek() != '\'') {
                try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.UnterminatedString, "expected closing ' after character escape", .{});
                return error.UnterminatedString;
            }

            _ = self.advance(); // closing '

            // Map escape sequences to Unicode codepoints
            const codepoint: u32 = if (std.mem.eql(u8, escape_name, "deg"))
                0x00B0 // degree symbol °
            else if (std.mem.eql(u8, escape_name, "quot"))
                '"'
            else if (std.mem.eql(u8, escape_name, "apos"))
                '\''
            else
                '?'; // Unknown escape - use '?'

            const lexeme = self.source[start - 1 .. self.current];
            return Token{
                .type = .char_literal,
                .lexeme = lexeme,
                .location = .{ .line = start_line, .column = start_column, .file = self.filename },
                .char_value = codepoint,
            };
        }

        // Regular single character
        if (self.isAtEnd()) {
            try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.UnterminatedString, "unterminated character literal", .{});
            return error.UnterminatedString;
        }

        const char = self.advance();

        if (self.isAtEnd() or self.peek() != '\'') {
            try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.UnterminatedString, "expected closing ' after character", .{});
            return error.UnterminatedString;
        }

        _ = self.advance(); // closing '
        const lexeme = self.source[start - 1 .. self.current];
        return Token{
            .type = .char_literal,
            .lexeme = lexeme,
            .location = .{ .line = start_line, .column = start_column, .file = self.filename },
            .char_value = @as(u32, char),
        };
    }

    fn scanNumber(self: *Lexer, start: usize, start_line: usize, start_column: usize) !Token {
        // Check for hex (0x) or binary (0b) prefix
        var base: u8 = 10;
        var num_start = start;

        if (self.source[start] == '0' and !self.isAtEnd()) {
            const next = self.peek();
            if (next == 'x' or next == 'X') {
                base = 16;
                _ = self.advance(); // consume 'x'
                num_start = self.current;
            } else if (next == 'b' or next == 'B') {
                base = 2;
                _ = self.advance(); // consume 'b'
                num_start = self.current;
            }
        }

        // Scan digits (including underscores)
        while (!self.isAtEnd()) {
            const c = self.peek();
            if (c == '_') {
                _ = self.advance(); // skip underscores
                continue;
            }

            const is_valid_digit = switch (base) {
                2 => c == '0' or c == '1',
                10 => std.ascii.isDigit(c) or c == '.' or c == 'e',
                16 => std.ascii.isHex(c),
                else => false,
            };

            if (!is_valid_digit) break;
            _ = self.advance();
        }

        // Extract lexeme and remove underscores for parsing
        const lexeme = self.source[start..self.current];

        // Build cleaned number string without underscores
        var cleaned: std.ArrayList(u8) = .{ .items = &.{}, .capacity = 0 };
        defer cleaned.deinit(self.allocator);

        for (self.source[num_start..self.current]) |c| {
            if (c != '_') {
                try cleaned.append(self.allocator, c);
            }
        }

        const clean_str = cleaned.items;

        if (clean_str.len == 0) {
            try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.InvalidNumber, "invalid number literal '{s}'", .{lexeme});
            return error.InvalidNumber;
        }

        const value = std.fmt.parseInt(i64, clean_str, base) catch {
            try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.InvalidNumber, "invalid number literal '{s}'", .{lexeme});
            return error.InvalidNumber;
        };

        return Token{
            .type = .int_literal,
            .lexeme = lexeme,
            .location = .{ .line = start_line, .column = start_column, .file = self.filename },
            .int_value = value,
        };
    }

    fn scanIdentifier(self: *Lexer, start: usize, start_line: usize, start_column: usize) Token {
        while (!self.isAtEnd() and (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_')) {
            _ = self.advance();
        }

        const lexeme = self.source[start..self.current];
        const token_type = getKeywordType(lexeme) orelse .identifier;

        return Token{
            .type = token_type,
            .lexeme = lexeme,
            .location = .{ .line = start_line, .column = start_column, .file = self.filename },
        };
    }

    fn skipWhitespace(self: *Lexer) void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            switch (c) {
                ' ', '\t', '\r' => _ = self.advance(),
                '\n' => {
                    self.line += 1;
                    self.column = 1;
                    _ = self.advance();
                },
                else => break,
            }
        }
    }

    fn skipLineComment(self: *Lexer) void {
        while (!self.isAtEnd() and self.peek() != '\n') {
            _ = self.advance();
        }
    }

    fn skipBlockComment(self: *Lexer) !void {
        var depth: usize = 1;
        const start_line = self.line;
        const start_column = self.column;

        while (!self.isAtEnd() and depth > 0) {
            const c = self.peek();
            if (c == '{') {
                depth += 1;
                _ = self.advance();
            } else if (c == '}') {
                depth -= 1;
                _ = self.advance();
            } else if (c == '\n') {
                self.line += 1;
                self.column = 1;
                _ = self.advance();
            } else {
                _ = self.advance();
            }
        }

        if (depth > 0) {
            try self.error_reporter.report(.{ .line = start_line, .column = start_column, .file = self.filename }, CompilerError.UnterminatedComment, "unterminated block comment", .{});
            return error.UnterminatedComment;
        }
    }

    fn scanPragma(self: *Lexer, start: usize, start_line: usize, start_column: usize) !Token {
        // We've seen '{@', now consume the '@'
        _ = self.advance();

        // Scan until we find '}'
        while (!self.isAtEnd() and self.peek() != '}') {
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
            }
            _ = self.advance();
        }

        if (self.isAtEnd()) {
            try self.error_reporter.report(
                .{ .line = start_line, .column = start_column, .file = self.filename },
                CompilerError.UnterminatedComment,
                "unterminated pragma comment",
                .{},
            );
            return error.UnterminatedComment;
        }

        // Consume the closing '}'
        _ = self.advance();

        // Extract pragma text (between {@  and })
        // Skip the leading '{@' and trailing '}'
        const pragma_text = std.mem.trim(u8, self.source[start + 2 .. self.current - 1], " \t\n\r");

        return Token{
            .type = .pragma,
            .lexeme = pragma_text,
            .location = .{
                .line = start_line,
                .column = start_column,
                .file = self.filename,
            },
        };
    }

    fn advance(self: *Lexer) u8 {
        const c = self.source[self.current];
        self.current += 1;
        self.column += 1;
        return c;
    }

    fn peek(self: *const Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *const Lexer) u8 {
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;
        _ = self.advance();
        return true;
    }

    fn isAtEnd(self: *const Lexer) bool {
        return self.current >= self.source.len;
    }

    fn makeToken(self: *const Lexer, token_type: TokenType, lexeme: []const u8) Token {
        return Token{
            .type = token_type,
            .lexeme = lexeme,
            .location = .{ .line = self.line, .column = self.column, .file = self.filename },
        };
    }

    fn makeTokenFrom(self: *const Lexer, token_type: TokenType, start: usize, line: usize, column: usize) Token {
        return Token{
            .type = token_type,
            .lexeme = self.source[start..self.current],
            .location = .{ .line = line, .column = column, .file = self.filename },
        };
    }
};

fn getKeywordType(lexeme: []const u8) ?TokenType {
    const map = std.StaticStringMap(TokenType).initComptime(.{
        // Literals
        .{ "true", .true_literal },
        .{ "True", .true_literal },
        .{ "false", .false_literal },
        .{ "False", .false_literal },
        .{ "null", .null_literal },
        .{ "Null", .null_literal },

        // Control flow
        .{ "if", .kw_if },
        .{ "If", .kw_if },
        .{ "ifnot", .kw_ifnot },
        .{ "IfNot", .kw_ifnot },
        .{ "ElseIf", .kw_elseif },
        .{ "elif", .kw_elseif },
        .{ "else", .kw_else },
        .{ "Else", .kw_else },
        .{ "EndIf", .kw_endif },
        .{ "eif", .kw_endif },
        .{ "repeat", .kw_repeat },
        .{ "Repeat", .kw_repeat },
        .{ "EndRepeat", .kw_erepeat },
        .{ "erepeat", .kw_erepeat },
        .{ "return", .kw_return },
        .{ "Return", .kw_return },
        .{ "switch", .kw_switch },
        .{ "Switch", .kw_switch },
        .{ "case", .kw_case },
        .{ "Case", .kw_case },
        .{ "default", .kw_default },
        .{ "Default", .kw_default },
        .{ "EndSwitch", .kw_eswitch },
        .{ "eswitch", .kw_eswitch },
        .{ "translate", .kw_translate },
        .{ "Translate", .kw_translate },
        .{ "Associate", .kw_aso },
        .{ "aso", .kw_aso },
        .{ "EndTranslate", .kw_etranslate },
        .{ "etranslate", .kw_etranslate },

        // Declarations
        .{ "module", .kw_module },
        .{ "Module", .kw_module },
        .{ "emodule", .kw_emodule },
        .{ "EndModule", .kw_emodule },
        .{ "cmd", .kw_cmd },
        .{ "Command", .kw_cmd },
        .{ "ecmd", .kw_ecmd },
        .{ "EndCommand", .kw_ecmd },
        //.{ "function", .kw_function },
        .{ "Function", .kw_function },
        //.{ "efunction", .kw_efunction },
        .{ "EndFunction", .kw_efunction },
        .{ "tuple", .kw_tuple },
        .{ "Tuple", .kw_tuple },
        .{ "etuple", .kw_etuple },
        .{ "EndTuple", .kw_etuple },
        .{ "record", .kw_record },
        .{ "Record", .kw_record },
        .{ "erecord", .kw_erecord },
        .{ "EndRecord", .kw_erecord },
        .{ "enum", .kw_enum },
        .{ "Enum", .kw_enum },
        .{ "eenum", .kw_eenum },
        .{ "EndEnum", .kw_eenum },
        .{ "var", .kw_var },
        .{ "Variable", .kw_var },
        .{ "prm", .kw_prm },
        .{ "Parameter", .kw_prm },
        .{ "atr", .kw_atr },
        .{ "Attribute", .kw_atr },

        // Commands
        .{ "set", .kw_set },
        .{ "Set", .kw_set },
        .{ "incr", .kw_incr },
        .{ "Incr", .kw_incr },
        .{ "decr", .kw_decr },
        .{ "Decr", .kw_decr },
        .{ "Invoke", .kw_invoke },

        // Types
        .{ "uint", .kw_uint },
        .{ "uint16", .kw_uint16 },
        .{ "sint", .kw_sint },
        .{ "bool", .kw_bool },
        .{ "char", .kw_char },
        .{ "Nullable", .kw_nullable },
        .{ "Unnullable", .kw_unnullable },
        .{ "Ptr", .kw_ptr },
        .{ "Ref", .kw_ref },
        .{ "RefN", .kw_refn },
        .{ "Signed", .kw_signed },
        .{ "Unsigned", .kw_unsigned },

        // Storage modifiers
        .{ "Out", .kw_out },
        .{ "InOut", .kw_inout },
        .{ "ReadOnly", .kw_readonly },
        .{ "ModifyOnly", .kw_modifyonly },

        // Control
        .{ "goto", .kw_goto },
        .{ "Goto", .kw_goto },
        .{ "loc", .kw_loc },
        .{ "Location", .kw_loc },
    });

    return map.get(lexeme);
}

test "lexer - simple tokens" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var error_reporter = ErrorReporter.init(allocator);
    defer error_reporter.deinit();

    var lexer = Lexer.init("module Test; ecmd;", "test.kl", allocator, &error_reporter);
    var tokens = try lexer.tokenize();
    defer tokens.deinit(allocator);

    // module, Test, ;, ecmd, ;, eof = 6 tokens
    try testing.expectEqual(@as(usize, 6), tokens.items.len);
    try testing.expectEqual(TokenType.kw_module, tokens.items[0].type);
    try testing.expectEqual(TokenType.identifier, tokens.items[1].type);
    try testing.expectEqual(TokenType.semicolon, tokens.items[2].type);
    try testing.expectEqual(TokenType.kw_ecmd, tokens.items[3].type);
    try testing.expectEqual(TokenType.semicolon, tokens.items[4].type);
    try testing.expectEqual(TokenType.eof, tokens.items[5].type);
}

test "lexer - numbers and strings" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var error_reporter = ErrorReporter.init(allocator);
    defer error_reporter.deinit();

    var lexer = Lexer.init("123 \"hello world\"", "test.kl", allocator, &error_reporter);
    var tokens = try lexer.tokenize();
    defer tokens.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), tokens.items.len);
    try testing.expectEqual(TokenType.int_literal, tokens.items[0].type);
    try testing.expectEqual(@as(i64, 123), tokens.items[0].int_value.?);
    try testing.expectEqual(TokenType.string_literal, tokens.items[1].type);
}

test "lexer - operators" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var error_reporter = ErrorReporter.init(allocator);
    defer error_reporter.deinit();

    var lexer = Lexer.init("+ - * / == != <= >= && ||", "test.kl", allocator, &error_reporter);
    var tokens = try lexer.tokenize();
    defer tokens.deinit(allocator);

    try testing.expectEqual(TokenType.op_plus, tokens.items[0].type);
    try testing.expectEqual(TokenType.op_minus, tokens.items[1].type);
    try testing.expectEqual(TokenType.op_mult, tokens.items[2].type);
    try testing.expectEqual(TokenType.op_div, tokens.items[3].type);
    try testing.expectEqual(TokenType.op_eq, tokens.items[4].type);
    try testing.expectEqual(TokenType.op_neq, tokens.items[5].type);
    try testing.expectEqual(TokenType.op_lte, tokens.items[6].type);
    try testing.expectEqual(TokenType.op_gte, tokens.items[7].type);
    try testing.expectEqual(TokenType.op_and, tokens.items[8].type);
    try testing.expectEqual(TokenType.op_or, tokens.items[9].type);
}

test "lexer - comments" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var error_reporter = ErrorReporter.init(allocator);
    defer error_reporter.deinit();

    var lexer = Lexer.init(
        \\module Test; { this is a comment }
        \\// line comment
        \\cmd Foo;
    , "test.kl", allocator, &error_reporter);
    var tokens = try lexer.tokenize();
    defer tokens.deinit(allocator);

    // module, Test, ;, cmd, Foo, ;, eof = 7 tokens
    try testing.expectEqual(@as(usize, 7), tokens.items.len);
    try testing.expectEqual(TokenType.kw_module, tokens.items[0].type);
    try testing.expectEqual(TokenType.identifier, tokens.items[1].type);
    try testing.expectEqual(TokenType.semicolon, tokens.items[2].type);
    try testing.expectEqual(TokenType.kw_cmd, tokens.items[3].type);
    try testing.expectEqual(TokenType.identifier, tokens.items[4].type);
    try testing.expectEqual(TokenType.semicolon, tokens.items[5].type);
}

test "lexer - character literals" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var error_reporter = ErrorReporter.init(allocator);
    defer error_reporter.deinit();

    var lexer = Lexer.init("'z' 'C' '<deg>'", "test.kl", allocator, &error_reporter);
    var tokens = try lexer.tokenize();
    defer tokens.deinit(allocator);

    try testing.expectEqual(@as(usize, 4), tokens.items.len);
    try testing.expectEqual(TokenType.char_literal, tokens.items[0].type);
    try testing.expectEqual(@as(u32, 'z'), tokens.items[0].char_value.?);
    try testing.expectEqual(TokenType.char_literal, tokens.items[1].type);
    try testing.expectEqual(@as(u32, 'C'), tokens.items[1].char_value.?);
    try testing.expectEqual(TokenType.char_literal, tokens.items[2].type);
    try testing.expectEqual(@as(u32, 0x00B0), tokens.items[2].char_value.?); // degree symbol
}

test "lexer - hex and binary literals" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var error_reporter = ErrorReporter.init(allocator);
    defer error_reporter.deinit();

    var lexer = Lexer.init("0x4D2 0b1010 1_315_000", "test.kl", allocator, &error_reporter);
    var tokens = try lexer.tokenize();
    defer tokens.deinit(allocator);

    try testing.expectEqual(@as(usize, 4), tokens.items.len);
    try testing.expectEqual(TokenType.int_literal, tokens.items[0].type);
    try testing.expectEqual(@as(i64, 1234), tokens.items[0].int_value.?); // 0x4D2
    try testing.expectEqual(TokenType.int_literal, tokens.items[1].type);
    try testing.expectEqual(@as(i64, 10), tokens.items[1].int_value.?); // 0b1010
    try testing.expectEqual(TokenType.int_literal, tokens.items[2].type);
    try testing.expectEqual(@as(i64, 1315000), tokens.items[2].int_value.?); // 1_315_000
}

test "lexer - keyword synonyms" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var error_reporter = ErrorReporter.init(allocator);
    defer error_reporter.deinit();

    var lexer = Lexer.init("EndCommand EndModule EndIf EndRepeat", "test.kl", allocator, &error_reporter);
    var tokens = try lexer.tokenize();
    defer tokens.deinit(allocator);

    try testing.expectEqual(@as(usize, 5), tokens.items.len);
    try testing.expectEqual(TokenType.kw_ecmd, tokens.items[0].type);
    try testing.expectEqual(TokenType.kw_emodule, tokens.items[1].type);
    try testing.expectEqual(TokenType.kw_endif, tokens.items[2].type);
    try testing.expectEqual(TokenType.kw_endrepeat, tokens.items[3].type);
}
