const std = @import("std");

/// Backend configuration for the KL compiler
/// Supports multiple assemblers and platforms
pub const Backend = struct {
    assembler: Assembler,
    target: Target,
    allocator: std.mem.Allocator,
    
    pub const Assembler = enum {
        gcc,
        clang,
        msvc,
        nasm,
        fasm,
        auto, // Auto-detect available assembler
        
        pub fn toString(self: Assembler) []const u8 {
            return switch (self) {
                .gcc => "gcc",
                .clang => "clang",
                .msvc => "msvc",
                .nasm => "nasm",
                .fasm => "fasm",
                .auto => "auto",
            };
        }
    };
    
    pub const Target = enum {
        x86_64_linux,
        x86_64_windows,
        x86_64_macos,
        
        pub fn toString(self: Target) []const u8 {
            return switch (self) {
                .x86_64_linux => "x86_64-linux",
                .x86_64_windows => "x86_64-windows",
                .x86_64_macos => "x86_64-macos",
            };
        }
        
        pub fn assemblyFormat(self: Target) AssemblyFormat {
            return switch (self) {
                .x86_64_linux, .x86_64_macos => .att, // GCC/Clang prefer AT&T
                .x86_64_windows => .intel, // MSVC uses Intel syntax
            };
        }
    };
    
    pub const AssemblyFormat = enum {
        att,   // AT&T syntax (GCC/Clang default)
        intel, // Intel syntax (NASM/FASM/MSVC)
    };
    
    pub fn init(allocator: std.mem.Allocator, assembler: Assembler, target: Target) Backend {
        return .{
            .assembler = assembler,
            .target = target,
            .allocator = allocator,
        };
    }
    
    /// Auto-detect the best available assembler
    pub fn autoDetect(allocator: std.mem.Allocator, target: Target) !Backend {
        const assembler = try detectAssembler(allocator);
        return Backend.init(allocator, assembler, target);
    }
    
    /// Detect which assembler is available on the system
    fn detectAssembler(allocator: std.mem.Allocator) !Assembler {
        // Try to find available assemblers
        const assemblers = [_]Assembler{ .gcc, .clang, .nasm };
        
        for (assemblers) |assembler| {
            const cmd = switch (assembler) {
                .gcc => "gcc",
                .clang => "clang",
                .nasm => "nasm",
                else => continue,
            };
            
            // Try to execute with --version flag
            const result = std.process.Child.run(.{
                .allocator = allocator,
                .argv = &[_][]const u8{ cmd, "--version" },
            }) catch continue;
            
            allocator.free(result.stdout);
            allocator.free(result.stderr);
            
            if (result.term.Exited == 0) {
                return assembler;
            }
        }
        
        return error.NoAssemblerFound;
    }
    
    /// Get the assembly file extension for this backend
    pub fn asmExtension(self: Backend) []const u8 {
        return switch (self.assembler) {
            .gcc, .clang => ".s",
            .msvc => ".asm",
            .nasm, .fasm => ".asm",
            .auto => ".s",
        };
    }
    
    /// Get the object file extension for this target
    pub fn objExtension(self: Backend) []const u8 {
        return switch (self.target) {
            .x86_64_linux, .x86_64_macos => ".o",
            .x86_64_windows => ".obj",
        };
    }
    
    /// Get the executable extension for this target
    pub fn exeExtension(self: Backend) []const u8 {
        return switch (self.target) {
            .x86_64_linux, .x86_64_macos => "",
            .x86_64_windows => ".exe",
        };
    }
    
    /// Assemble a source file to an object file
    pub fn assemble(self: Backend, asm_file: []const u8, obj_file: []const u8) !void {
        const argv = try self.buildAssembleCommand(asm_file, obj_file);
        defer self.allocator.free(argv);
        
        std.debug.print("Assembling: {s}\n", .{asm_file});
        std.debug.print("Command: ", .{});
        for (argv) |arg| {
            std.debug.print("{s} ", .{arg});
        }
        std.debug.print("\n", .{});
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            std.debug.print("Assembly failed:\n{s}\n", .{result.stderr});
            return error.AssemblyFailed;
        }
        
        std.debug.print("✓ Assembly successful: {s}\n", .{obj_file});
    }
    
    /// Link object files into an executable
    pub fn link(self: Backend, obj_files: []const []const u8, exe_file: []const u8) !void {
        const argv = try self.buildLinkCommand(obj_files, exe_file);
        defer self.allocator.free(argv);
        
        std.debug.print("Linking: {s}\n", .{exe_file});
        std.debug.print("Command: ", .{});
        for (argv) |arg| {
            std.debug.print("{s} ", .{arg});
        }
        std.debug.print("\n", .{});
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            std.debug.print("Linking failed:\n{s}\n", .{result.stderr});
            return error.LinkingFailed;
        }
        
        std.debug.print("✓ Linking successful: {s}\n", .{exe_file});
    }
    
    fn buildAssembleCommand(self: Backend, asm_file: []const u8, obj_file: []const u8) ![][]const u8 {
        var cmd = std.ArrayList([]const u8).init(self.allocator);
        errdefer cmd.deinit();
        
        switch (self.assembler) {
            .gcc => {
                try cmd.append(self.allocator, "gcc");
                try cmd.append(self.allocator, "-c");
                try cmd.append(self.allocator, asm_file);
                try cmd.append(self.allocator, "-o");
                try cmd.append(self.allocator, obj_file);
            },
            .clang => {
                try cmd.append(self.allocator, "clang");
                try cmd.append(self.allocator, "-c");
                try cmd.append(self.allocator, asm_file);
                try cmd.append(self.allocator, "-o");
                try cmd.append(self.allocator, obj_file);
            },
            .nasm => {
                try cmd.append(self.allocator, "nasm");
                try cmd.append(self.allocator, "-f");
                const fmt = switch (self.target) {
                    .x86_64_linux => "elf64",
                    .x86_64_macos => "macho64",
                    .x86_64_windows => "win64",
                };
                try cmd.append(self.allocator, fmt);
                try cmd.append(self.allocator, asm_file);
                try cmd.append(self.allocator, "-o");
                try cmd.append(self.allocator, obj_file);
            },
            .fasm => {
                try cmd.append(self.allocator, "fasm");
                try cmd.append(self.allocator, asm_file);
                try cmd.append(self.allocator, obj_file);
            },
            .msvc => {
                try cmd.append(self.allocator, "ml64");
                try cmd.append(self.allocator, "/c");
                try cmd.append(self.allocator, asm_file);
                try cmd.append(self.allocator, "/Fo");
                try cmd.append(self.allocator, obj_file);
            },
            .auto => return error.AssemblerNotDetected,
        }
        
        return cmd.toOwnedSlice();
    }
    
    fn buildLinkCommand(self: Backend, obj_files: []const []const u8, exe_file: []const u8) ![][]const u8 {
        var cmd = std.ArrayList([]const u8).init(self.allocator);
        errdefer cmd.deinit();
        
        switch (self.assembler) {
            .gcc => {
                try cmd.append(self.allocator, "gcc");
                for (obj_files) |obj| {
                    try cmd.append(self.allocator, obj);
                }
                try cmd.append(self.allocator, "-o");
                try cmd.append(self.allocator, exe_file);
            },
            .clang => {
                try cmd.append(self.allocator, "clang");
                for (obj_files) |obj| {
                    try cmd.append(self.allocator, obj);
                }
                try cmd.append(self.allocator, "-o");
                try cmd.append(self.allocator, exe_file);
            },
            .nasm, .fasm => {
                // Use system linker
                if (self.target == .x86_64_linux) {
                    try cmd.append(self.allocator, "ld");
                    for (obj_files) |obj| {
                        try cmd.append(self.allocator, obj);
                    }
                    try cmd.append(self.allocator, "-o");
                    try cmd.append(self.allocator, exe_file);
                } else {
                    return error.LinkerNotSupported;
                }
            },
            .msvc => {
                try cmd.append(self.allocator, "link");
                for (obj_files) |obj| {
                    try cmd.append(self.allocator, obj);
                }
                try cmd.append(self.allocator, "/OUT:");
                try cmd.append(self.allocator, exe_file);
            },
            .auto => return error.AssemblerNotDetected,
        }
        
        return cmd.toOwnedSlice();
    }
};

test "backend configuration" {
    const allocator = std.testing.allocator;
    
    const backend = Backend.init(allocator, .gcc, .x86_64_linux);
    try std.testing.expectEqual(Backend.Assembler.gcc, backend.assembler);
    try std.testing.expectEqual(Backend.Target.x86_64_linux, backend.target);
    try std.testing.expectEqualStrings(".s", backend.asmExtension());
    try std.testing.expectEqualStrings(".o", backend.objExtension());
    try std.testing.expectEqualStrings("", backend.exeExtension());
}

test "assembly format" {
    const linux = Backend.Target.x86_64_linux;
    const windows = Backend.Target.x86_64_windows;
    
    try std.testing.expectEqual(Backend.AssemblyFormat.att, linux.assemblyFormat());
    try std.testing.expectEqual(Backend.AssemblyFormat.intel, windows.assemblyFormat());
}
