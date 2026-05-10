const std = @import("std");

/// KL type system - Phase 1 MVP types
pub const KLType = union(enum) {
    // Integer types
    uint8,
    sint8,
    uint32,
    sint32,
    bool_type,
    
    // Character and text types
    char,
    text,

    // Future: uint16, sint16, uint64, sint64, float types, reference types

    pub fn format(self: KLType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        const name = switch (self) {
            .uint8 => "uint8",
            .sint8 => "sint8",
            .uint32 => "uint32",
            .sint32 => "sint32",
            .bool_type => "bool",
            .char => "char",
            .text => "text",
        };
        try writer.writeAll(name);
    }

    pub fn sizeBytes(self: KLType) usize {
        return switch (self) {
            .uint8, .sint8, .bool_type, .char => 1,
            .uint32, .sint32 => 4,
            .text => 0, // Text is a reference type, size varies
        };
    }

    pub fn isSigned(self: KLType) bool {
        return switch (self) {
            .sint8, .sint32 => true,
            .uint8, .uint32, .bool_type, .char, .text => false,
        };
    }

    pub fn isInteger(self: KLType) bool {
        return switch (self) {
            .uint8, .sint8, .uint32, .sint32 => true,
            .bool_type, .char, .text => false,
        };
    }

    pub fn isBool(self: KLType) bool {
        return self == .bool_type;
    }

    /// Check if two types are compatible for assignment
    pub fn isCompatible(self: KLType, other: KLType) bool {
        // For Phase 1: exact match only
        return std.meta.eql(self, other);
    }
};

/// Parse a type name from a string
pub fn parseTypeName(name: []const u8) ?KLType {
    if (std.mem.eql(u8, name, "uint8")) return .uint8;
    if (std.mem.eql(u8, name, "sint8")) return .sint8;
    if (std.mem.eql(u8, name, "uint32") or std.mem.eql(u8, name, "uint")) return .uint32;
    if (std.mem.eql(u8, name, "sint32") or std.mem.eql(u8, name, "sint")) return .sint32;
    if (std.mem.eql(u8, name, "bool")) return .bool_type;
    if (std.mem.eql(u8, name, "char")) return .char;
    if (std.mem.eql(u8, name, "text")) return .text;

    return null;
}

test "type system - size bytes" {
    const testing = std.testing;

    try testing.expectEqual(@as(usize, 1), (KLType{ .uint8 = {} }).sizeBytes());
    try testing.expectEqual(@as(usize, 1), (KLType{ .sint8 = {} }).sizeBytes());
    try testing.expectEqual(@as(usize, 4), (KLType{ .uint32 = {} }).sizeBytes());
    try testing.expectEqual(@as(usize, 4), (KLType{ .sint32 = {} }).sizeBytes());
    try testing.expectEqual(@as(usize, 1), (KLType{ .bool_type = {} }).sizeBytes());
}

test "type system - signedness" {
    const testing = std.testing;

    try testing.expect(!(KLType{ .uint8 = {} }).isSigned());
    try testing.expect((KLType{ .sint8 = {} }).isSigned());
    try testing.expect(!(KLType{ .uint32 = {} }).isSigned());
    try testing.expect((KLType{ .sint32 = {} }).isSigned());
    try testing.expect(!(KLType{ .bool_type = {} }).isSigned());
}

test "type system - parse type names" {
    const testing = std.testing;

    try testing.expectEqual(KLType.uint8, parseTypeName("uint8").?);
    try testing.expectEqual(KLType.sint8, parseTypeName("sint8").?);
    try testing.expectEqual(KLType.uint32, parseTypeName("uint32").?);
    try testing.expectEqual(KLType.uint32, parseTypeName("uint").?);
    try testing.expectEqual(KLType.uint32, parseTypeName("uint").?); // lowercase alias
    try testing.expectEqual(KLType.sint32, parseTypeName("sint32").?);
    try testing.expectEqual(KLType.sint32, parseTypeName("sint").?);
    try testing.expectEqual(KLType.sint32, parseTypeName("sint").?); // lowercase alias
    try testing.expectEqual(KLType.bool_type, parseTypeName("bool").?);
    try testing.expectEqual(KLType.bool_type, parseTypeName("bool").?); // lowercase alias
    try testing.expectEqual(@as(?KLType, null), parseTypeName("InvalidType"));
}
