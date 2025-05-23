const TABLE_MAX_LOAD = 0.75; // 3 / 4 in integer

pub const Entry = struct {
    key: ?ObjString,
    value: ?Value,
};
pub const Table = struct {
    allocator: std.mem.Allocator,
    count: usize,
    capacity: usize,
    entries: []align(8) Entry,

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
            self.allocator.free(@as([]align(8) Entry, self.entries[0..self.capacity]));
        }
        self.* = undefined;
    }
    pub fn set(table: *Table, key: *ObjString, value: Value) !bool {
        // Grow the array at 75% capacity, can't multiply float with int hence..
        if (table.count + 1 > table.capacity * 3 / 4) {
            try table.grow();
        }
        var entry_ptr: *Entry = findEntry(table.entries, table.capacity, key);
        const isNewKey = entry_ptr.*.key == null;
        if (isNewKey) {
            table.count += 1;
        }
        entry_ptr.key = key.*;
        entry_ptr.value = value;
        return isNewKey;
    }
    fn grow(table: *Table) !void {
        const new_capacity = if (table.capacity < 8) 8 else table.capacity * 2;

        if (table.capacity == 0) {
            table.entries = try table.allocator.alignedAlloc(Entry, 8, new_capacity);
            @memset(table.entries[0..new_capacity], .{ .key = null, .value = null });
        } else {
            const new_entries = try table.allocator.alignedAlloc(Entry, 8, new_capacity);
            // Rebuild hash table
            @memset(new_entries[0..new_capacity], .{ .key = null, .value = null });
            for (table.entries[0..table.capacity]) |e| {
                if (e.key == null) continue;
                const dest = findEntry(new_entries, new_capacity, @constCast(&e.key.?));
                dest.key = e.key;
                dest.value = e.value;
            }
            table.allocator.free(table.entries);
            table.entries = new_entries;
        }
        table.capacity = new_capacity;
    }
};
/// Return pointer to Entry which either contains the same key (overwrite) or empty key (empty slot)
fn findEntry(entries: []Entry, capacity: usize, key: *ObjString) *Entry {
    var idx = key.hash % capacity;
    while (true) : (idx = @mod(idx + 1, capacity)) {
        const e = &entries[idx];
        if (e.key) |found| if (ObjString.eql(found, key.*)) return e;
        if (e.key == null) return e;
    }
}
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
    // Manually invoke grow()
    try table.grow();
    try std.testing.expect(table.count == 1);
    try std.testing.expect(table.capacity == 16);
    // Check if the value was set
    const found_entry = findEntry(table.entries, table.capacity, &key);
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
