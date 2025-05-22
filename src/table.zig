pub const Entry = struct {
    key: ObjString,
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
    pub fn set(table: *Table, key: *ObjString, value: Value) !bool {
        if (table.count + 1 > table.capacity) {
            const new_capacity = if (table.capacity == 0) 16 else table.capacity * 3 / 2;

            if (table.capacity == 0)
                table.entries = (try table.allocator.alignedAlloc(Entry, @alignOf(Entry), new_capacity)).ptr
            else {
                const new_entries = try table.allocator.alignedAlloc(Entry, @alignOf(Entry), new_capacity);
                @memcpy(new_entries[0..table.count], table.entries[0..table.count]);
                table.allocator.free(table.entries[0..table.capacity]);
                table.entries = new_entries.ptr;
            }
            table.capacity = new_capacity;
        }

        // Add the new entry
        table.entries[table.count] = .{
            .key = key.*,
            .value = value,
        };
        table.count += 1;
        return true;
    }
};
test "Table" {
    initClHashRandomKey();
    const allocator = testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();
    var key = try ObjString.init(allocator, "Hello");
    defer key.deinit(allocator);
    const result = try table.set(&key, Value{ .Number = 42 });
    try testing.expect(result);
    try std.testing.expect(table.count == 1);
    try std.testing.expect(table.capacity >= 16);
    // try table.grow(10);
    // try table.put("key", Value{});
    // const value = try table.get("key");
    // std.debug.assert(table.entries == null);
}

/// FNV-1a hash function
// We don't use it in loxz because we chose to go with clhash instead!
pub fn loxHash(key: []const u8) u64 {
    var hash: u64 = 2166136261;
    for (key) |char| {
        hash ^= char;
        hash *%= 16777619;
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
const testing = std.testing;
const clhash = @cImport({
    @cInclude("clhash.h");
});
const Object = @import("object.zig").Object;
const ObjString = @import("object.zig").ObjString;
const Value = @import("value.zig").Value;
