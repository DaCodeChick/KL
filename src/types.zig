const std = @import("std");

/// KL type system - Phase 1 MVP types
pub const KLType = union(enum) {
    // Integer types
    uint8,
    sint8,
    uint32,
    sint32,
    bool_type,
    
    // Future: uint16, sint16, uint64, sint64, float types, reference types
    
    pub fn format(self: KLType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        
        const name = switch (self) {
            .uint8 => "TUInt8",
            .sint8 => "TSInt8",
            .uint32 => "TUInt32",
            .sint32 => "TSInt32",
            .bool_type => "TBool",
        };
        try writer.writeAll(name);
    }
    
    pub fn sizeBytes(self: KLType) usize {
        return switch (self) {
            .uint8, .sint8, .bool_type => 1,
            .uint32, .sint32 => 4,
        };
    }
    
    pub fn isSigned(self: KLType) bool {
        return switch (self) {
            .sint8, .sint32 => true,
            .uint8, .uint32, .bool_type => false,
        };
    }
    
    pub fn isInteger(self: KLType) bool {
        return switch (self) {
            .uint8, .sint8, .uint32, .sint32 => true,
            .bool_type => false,
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
    if (std.mem.eql(u8, name, "TUInt8")) return .uint8;
    if (std.mem.eql(u8, name, "TSInt8")) return .sint8;
    if (std.mem.eql(u8, name, "TUInt32") or std.mem.eql(u8, name, "TUInt") or std.mem.eql(u8, name, "uint")) return .uint32;
    if (std.mem.eql(u8, name, "TSInt32") or std.mem.eql(u8, name, "TSInt") or std.mem.eql(u8, name, "sint")) return .sint32;
    if (std.mem.eql(u8, name, "TBool") or std.mem.eql(u8, name, "bool")) return .bool_type;
    
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
    
    try testing.expectEqual(KLType.uint8, parseTypeName("TUInt8").?);
    try testing.expectEqual(KLType.sint8, parseTypeName("TSInt8").?);
    try testing.expectEqual(KLType.uint32, parseTypeName("TUInt32").?);
    try testing.expectEqual(KLType.uint32, parseTypeName("TUInt").?);
    try testing.expectEqual(KLType.uint32, parseTypeName("uint").?);  // lowercase alias
    try testing.expectEqual(KLType.sint32, parseTypeName("TSInt32").?);
    try testing.expectEqual(KLType.sint32, parseTypeName("TSInt").?);
    try testing.expectEqual(KLType.sint32, parseTypeName("sint").?);  // lowercase alias
    try testing.expectEqual(KLType.bool_type, parseTypeName("TBool").?);
    try testing.expectEqual(KLType.bool_type, parseTypeName("bool").?);  // lowercase alias
    try testing.expectEqual(@as(?KLType, null), parseTypeName("InvalidType"));
}
