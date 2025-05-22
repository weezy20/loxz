const TABLE_MAX_LOAD = 0.75; // 3 / 4 in integer

pub const Entry = struct {
    key: ?ObjString,
    value: ?Value,
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
        // Grow the array at 75% capacity, can't multiply float with int hence..
        if (table.count + 1 > table.capacity * 3 / 4) {
            const new_capacity = if (table.capacity < 8) 8 else table.capacity * 2;

            if (table.capacity == 0)
                table.entries = (try table.allocator.alignedAlloc(Entry, @alignOf(Entry), new_capacity)).ptr
            else {
                const new_entries = try table.allocator.alignedAlloc(Entry, @alignOf(Entry), new_capacity);
                @memcpy(new_entries[0..table.count], table.entries[0..table.count]);
                table.allocator.free(table.entries[0..table.capacity]);
                table.entries = new_entries.ptr;
            }
            @memset(table.entries[0..new_capacity], .{ .key = null, .value = null });
            table.capacity = new_capacity;
        }
        var entry_ptr: *Entry = table.findEntry(key);
        entry_ptr.key = key.*;
        entry_ptr.value = value;
        //TODO
        table.count += 1;
        return true;
    }
    /// Return pointer to Entry which either contains the same key (overwrite) or empty key (empty slot)
    fn findEntry(table: *const Table, key: *ObjString) *Entry {
        var idx = key.hash % table.capacity;
        while (true) : (idx = @mod(idx + 1, table.capacity)) {
            const e = &table.entries[idx];
            if (e.key) |found| if (ObjString.eql(found, key.*)) return e;
            if (e.key == null) return e;
        }
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
    try std.testing.expect(table.capacity == 8);
    // Check if the value was set
    const found_entry = table.findEntry(&key);
    try testing.expect(found_entry.value.?.Number == 42);
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
test "loxHash" {
    const expected_hash = 10461433681597188260;
    try testing.expect(expected_hash == loxHash("Zig is amazing"));
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
