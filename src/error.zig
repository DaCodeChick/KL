const std = @import("std");

/// Source location for error reporting
pub const SourceLocation = struct {
    line: usize,
    column: usize,
    file: []const u8,
    
    pub fn format(self: SourceLocation, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}:{}:{}", .{ self.file, self.line, self.column });
    }
};

/// Compiler error types
pub const CompilerError = error{
    // Lexer errors
    InvalidCharacter,
    UnterminatedString,
    UnterminatedComment,
    InvalidNumber,
    
    // Parser errors
    UnexpectedToken,
    ExpectedToken,
    InvalidSyntax,
    
    // Semantic errors
    UndefinedVariable,
    DuplicateVariable,
    TypeMismatch,
    UndefinedCommand,
    DuplicateCommand,
    InvalidModule,
    BreakOutsideLoop,
    InvalidEntryPoint,
    
    // Codegen errors
    UnsupportedFeature,
    InternalError,
    
    // IO errors
    OutOfMemory,
    FileNotFound,
    CannotWriteFile,
};

/// Diagnostic message
pub const Diagnostic = struct {
    location: SourceLocation,
    message: []const u8,
    err_type: CompilerError,
    
    pub fn format(self: Diagnostic, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("error: {}: {s}\n", .{ self.location, self.message });
    }
};

/// Error reporter - accumulates diagnostics
pub const ErrorReporter = struct {
    diagnostics: std.ArrayList(Diagnostic),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ErrorReporter {
        return .{
            .diagnostics = .{ .items = &.{}, .capacity = 0 },
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ErrorReporter) void {
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.diagnostics.deinit(self.allocator);
    }
    
    pub fn report(self: *ErrorReporter, location: SourceLocation, err_type: CompilerError, comptime format_str: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, format_str, args);
        try self.diagnostics.append(self.allocator, .{
            .location = location,
            .message = message,
            .err_type = err_type,
        });
    }
    
    pub fn hasErrors(self: *const ErrorReporter) bool {
        return self.diagnostics.items.len > 0;
    }
    
    pub fn printAll(self: *const ErrorReporter, writer: anytype) !void {
        for (self.diagnostics.items) |diag| {
            try writer.print("{}", .{diag});
        }
    }
};

test "error reporter - basic usage" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var reporter = ErrorReporter.init(allocator);
    defer reporter.deinit();
    
    try reporter.report(
        .{ .line = 1, .column = 5, .file = "test.kl" },
        CompilerError.UndefinedVariable,
        "undefined variable '{s}'",
        .{"foo"}
    );
    
    try testing.expect(reporter.hasErrors());
    try testing.expectEqual(@as(usize, 1), reporter.diagnostics.items.len);
}
