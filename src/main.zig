const std = @import("std");

pub const types = @import("types.zig");
pub const error_handling = @import("error.zig");
pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const sema = @import("sema.zig");
pub const ir = @import("ir.zig");
pub const irgen = @import("irgen.zig");
pub const backend = @import("backend.zig");
pub const codegen = @import("codegen.zig");

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
    
    // IR generation
    std.debug.print("Generating intermediate representation...\n", .{});
    var ir_generator = try irgen.IRGenerator.init(allocator);
    // Note: arena allocator will clean this up automatically
    
    try ir_generator.generateModule(module);
    
    std.debug.print("✓ IR generation complete!\n\n", .{});
    
    // Print IR summary
    std.debug.print("Generated IR:\n", .{});
    std.debug.print("=============\n", .{});
    std.debug.print("Functions: {d}\n", .{ir_generator.program.functions.items.len});
    for (ir_generator.program.functions.items) |func| {
        std.debug.print("  - {s} ({d} locals, {d} blocks)\n", .{
            func.name,
            func.locals.items.len,
            func.basic_blocks.items.len,
        });
    }
    std.debug.print("\n", .{});
    
    // Code generation
    std.debug.print("Generating assembly code...\n", .{});
    
    // Determine output filename
    const output_file = try std.mem.concat(allocator, u8, &.{
        std.fs.path.stem(filename),
        ".s",
    });
    
    // Generate assembly
    var asm_gen = codegen.AsmGenerator.init(
        allocator,
        .att,  // AT&T syntax for GCC/Clang
        .x86_64_linux,
    );
    defer asm_gen.deinit();
    
    try asm_gen.generate(ir_generator.program);
    
    // Write assembly to file
    const asm_file = try std.Io.Dir.createFile(
        std.Io.Dir.cwd(),
        io,
        output_file,
        .{},
    );
    defer asm_file.close(io);
    
    const asm_output = asm_gen.getOutput();
    _ = try asm_file.writePositionalAll(io, asm_output, 0);
    
    std.debug.print("✓ Assembly code written to: {s}\n", .{output_file});
    
    // Assemble and link
    std.debug.print("\nAssembling and linking...\n", .{});
    
    const exe_name = std.fs.path.stem(filename);
    
    // Use GCC to assemble and link with runtime library
    // Runtime library location is relative to where klc was built
    const result = try std.process.run(allocator, io, .{
        .argv = &.{
            "gcc",
            "-no-pie",  // Disable position independent executable for simpler assembly
            output_file,
            "-o",
            exe_name,
            // Link against KL runtime library
            // The library path assumes we're running from the project root
            // In production, this should be an installed path
            "zig-out/lib/libklruntime.a",
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    if (result.term == .exited and result.term.exited == 0) {
        std.debug.print("✓ Executable created: {s}\n", .{exe_name});
        std.debug.print("\nCompilation successful!\n", .{});
    } else {
        std.debug.print("✗ Assembly/linking failed\n", .{});
        if (result.stderr.len > 0) {
            std.debug.print("Error output:\n{s}\n", .{result.stderr});
        }
        return error.AssemblyFailed;
    }
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
    
    // IR generation
    std.debug.print("\nGenerating IR...\n", .{});
    var ir_generator = try irgen.IRGenerator.init(allocator);
    // Note: arena allocator will clean this up automatically
    
    try ir_generator.generateModule(module);
    
    std.debug.print("✓ IR generation complete!\n\n", .{});
    
    // Print IR summary
    std.debug.print("Generated IR:\n", .{});
    std.debug.print("=============\n", .{});
    std.debug.print("Functions: {d}\n", .{ir_generator.program.functions.items.len});
    for (ir_generator.program.functions.items) |func| {
        std.debug.print("  - {s} ({d} locals, {d} blocks)\n", .{
            func.name,
            func.locals.items.len,
            func.basic_blocks.items.len,
        });
    }
    std.debug.print("\n", .{});
}

test {
    std.testing.refAllDecls(@This());
}
