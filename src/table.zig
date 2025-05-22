pub const Entry = struct {
    key: Object.ObjString,
    value: Value,
};
pub const Table = struct {
    allocator: std.mem.Allocator,
    count: usize,
    capacity: usize,
    entries: [*]Entry,

    pub fn init(allocator: std.mem.Allocator) Table {
        return Table{
            .allocator = allocator,
            .count = 0,
            .capacity = 0,
            .entries = undefined,
        };
    }
    pub fn deinit(self: *Table) void {
        if (self.capacity > 0) {
            self.allocator.free(self.entries[0..self.capacity]);
        }
        self.* = undefined;
    }
};
test "Table" {
    const allocator = std.testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();
    // try table.grow(10);
    // try table.put("key", Value{});
    // const value = try table.get("key");
    // std.debug.assert(table.entries == null);
}
/// FNV-1a hash function
pub fn loxHash(key: []const u8) u64 {
    var hash: u64 = 2166136261;
    for (0..key.len) |char| {
        hash ^= key[char];
        hash *= 16777619;
    }
    return hash;
}
/// Note: pointer must be 8 byte aligned
pub fn clHash(key: []const u8) u64 {
    return clhash.clhash(RANDOM, key.ptr, key.len);
}
pub fn initClHashRandomKey() void {
    if (RANDOM == null)
        RANDOM = clhash.get_random_key_for_clhash(0x23a23cf5033c3c81, 0xb3816f6a2c68e530).?
    else
        @panic("Not allowed");
}

var RANDOM: ?*anyopaque = null;

const std = @import("std");
const clhash = @cImport({
    @cInclude("clhash.h");
});
const Object = @import("object.zig");
const Value = @import("value.zig");
