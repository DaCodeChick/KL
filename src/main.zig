const std = @import("std");

pub const types = @import("types.zig");
pub const error_handling = @import("error.zig");
pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const sema = @import("sema.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    
    std.debug.print("KL Compiler - Phase 1 MVP\n", .{});
    std.debug.print("Lexer, Parser, and Semantic Analyzer complete!\n", .{});
    std.debug.print("Run 'zig build test' to see all tests\n", .{});
    
    // Demo: parse a simple inline program
    const source =
        \\Module TestProgram
        \\Command Main
        \\Var x = 42
        \\Var y = Add[x, 10]
        \\EndCommand
        \\EndModule
    ;
    
    std.debug.print("\nParsing demo program...\n", .{});
    
    // Initialize error reporter
    var err_reporter = error_handling.ErrorReporter.init(allocator);
    defer err_reporter.deinit();
    
    // Lexical analysis
    var lex = lexer.Lexer.init(source, "<demo>", allocator, &err_reporter);
    
    // Parse the module
    var parse = try parser.Parser.init(allocator, &lex, &err_reporter);
    const module = parse.parseModule() catch |err| {
        std.debug.print("Parse error: {any}\n", .{err});
        if (err_reporter.diagnostics.items.len > 0) {
            for (err_reporter.diagnostics.items) |e| {
                std.debug.print("  {}: {s}\n", .{e.location, e.message});
            }
        }
        return err;
    };
    defer module.deinit(allocator);
    
    std.debug.print("✓ Successfully parsed module: {s}\n", .{module.name});
    std.debug.print("✓ Commands: {d}\n", .{module.commands.items.len});
    for (module.commands.items) |cmd| {
        std.debug.print("  - {s} ({d} statements)\n", .{cmd.name, cmd.body.items.len});
    }
    
    // Semantic analysis
    std.debug.print("\nRunning semantic analysis...\n", .{});
    var analyzer = try sema.SemanticAnalyzer.init(allocator, &err_reporter);
    defer analyzer.deinit();
    
    analyzer.analyzeModule(module) catch |err| {
        std.debug.print("Semantic error: {any}\n", .{err});
        if (err_reporter.diagnostics.items.len > 0) {
            for (err_reporter.diagnostics.items) |e| {
                std.debug.print("  {}: {s}\n", .{e.location, e.message});
            }
        }
        return err;
    };
    
    std.debug.print("✓ Semantic analysis passed!\n", .{});
    
    std.debug.print("\nNext steps:\n", .{});
    std.debug.print("  - Code generation (x86-64 native)\n", .{});
}

test {
    std.testing.refAllDecls(@This());
}
