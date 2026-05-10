const std = @import("std");

pub const types = @import("types.zig");
pub const error_handling = @import("error.zig");
pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const sema = @import("sema.zig");
pub const ir = @import("ir.zig");
pub const irgen = @import("irgen.zig");

pub fn main(init: std.process.Init) !void {
    // Create arena allocator for automatic memory cleanup
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const io = init.io;
    
    std.debug.print("KL Compiler - Phase 1 MVP\n", .{});
    
    // Get command line arguments
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    
    // Skip program name
    _ = args.next();
    
    // Check if a file was provided
    const maybe_filename = args.next();
    
    if (maybe_filename) |input_file| {
        // Compile from file
        try compileFile(allocator, io, input_file);
    } else {
        // Run demo mode
        std.debug.print("No input file provided. Running built-in demo...\n", .{});
        std.debug.print("Usage: klc <input.kl>\n\n", .{});
        try runDemo(allocator);
    }
}

fn compileFile(allocator: std.mem.Allocator, io: std.Io, filename: []const u8) !void {
    std.debug.print("Compiling: {s}\n", .{filename});
    
    // Read the source file
    const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, filename, .{});
    defer file.close(io);
    
    // Get file size
    const file_stat = try file.stat(io);
    const size = file_stat.size;
    const source = try allocator.alloc(u8, size);
    // Note: arena allocator will free this automatically
    
    // Read entire file
    const read_amt = try file.readPositionalAll(io, source, 0);
    if (read_amt != size) return error.UnexpectedEof;
    
    // Initialize error reporter
    var err_reporter = error_handling.ErrorReporter.init(allocator);
    // Note: arena allocator will clean this up automatically
    
    // Lexical analysis
    var lex = lexer.Lexer.init(source, filename, allocator, &err_reporter);
    
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
    // Note: arena allocator will clean this up automatically
    
    std.debug.print("✓ Successfully parsed module: {s}\n", .{module.name});
    
    // Semantic analysis
    std.debug.print("Running semantic analysis...\n", .{});
    var analyzer = try sema.SemanticAnalyzer.init(allocator, &err_reporter);
    // Note: arena allocator will clean this up automatically
    
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
    
    // IR generation (TODO: Fix AST node name mismatches)
    // std.debug.print("Generating intermediate representation...\n", .{});
    // var ir_generator = try irgen.IRGenerator.init(allocator);
    // Note: arena allocator will clean this up automatically
    
    // try ir_generator.generateModule(module);
    
    // std.debug.print("✓ IR generation complete!\n\n", .{});
    
    // Print IR for inspection
    // std.debug.print("Generated IR:\n", .{});
    // std.debug.print("=============\n", .{});
    // try ir.printProgram(ir_generator.program, std.io.getStdErr().writer());
    // std.debug.print("\n", .{});
    
    std.debug.print("\nNext: Code generation (not yet implemented)\n", .{});
}

fn runDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("Lexer, Parser, and Semantic Analyzer complete!\n", .{});
    std.debug.print("Run 'zig build test' to see all tests\n\n", .{});
    
    // Demo: parse a simple inline program
    const source =
        \\Module TestProgram
        \\Command Main
        \\Variable x = 42
        \\Variable y = Add[x, 10]
        \\EndCommand
        \\EndModule
    ;
    
    const filename = "<demo>";
    
    std.debug.print("Parsing demo program...\n", .{});
    
    // Initialize error reporter
    var err_reporter = error_handling.ErrorReporter.init(allocator);
    // Note: arena allocator will clean this up automatically
    
    // Lexical analysis
    var lex = lexer.Lexer.init(source, filename, allocator, &err_reporter);
    
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
    // Note: arena allocator will clean this up automatically
    
    std.debug.print("✓ Successfully parsed module: {s}\n", .{module.name});
    std.debug.print("✓ Commands: {d}\n", .{module.commands.items.len});
    for (module.commands.items) |cmd| {
        std.debug.print("  - {s} ({d} statements)\n", .{cmd.name, cmd.body.items.len});
    }
    
    // Semantic analysis
    std.debug.print("\nRunning semantic analysis...\n", .{});
    var analyzer = try sema.SemanticAnalyzer.init(allocator, &err_reporter);
    // Note: arena allocator will clean this up automatically
    
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
    
    // IR generation (TODO: Fix AST node name mismatches)
    // std.debug.print("\nGenerating IR...\n", .{});
    // var ir_generator = try irgen.IRGenerator.init(allocator);
    // Note: arena allocator will clean this up automatically
    
    // try ir_generator.generateModule(module);
    
    // std.debug.print("✓ IR generation complete!\n\n", .{});
    
    // Print IR
    // try ir.printProgram(ir_generator.program, std.io.getStdErr().writer());
}

test {
    std.testing.refAllDecls(@This());
}
