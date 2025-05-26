const TABLE_MAX_LOAD = 0.75; // 3 / 4 in integer
const TOMBSTONE_VAL: Value = Value{ .Bool = true };
pub const Entry = struct {
    key: ?*ObjString,
    value: ?Value,
};

/// A hash table for key (ObjString) to value (Value) mapping.
pub const Table = struct {
    allocator: std.mem.Allocator,
    count: usize, // entries + tombstones
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
    pub fn set(table: *Table, key: *const ObjString, value: Value) !bool {
        // Grow the array at 75% capacity, can't multiply float with int hence..
        if (table.count + 1 > table.capacity * 3 / 4) {
            try table.grow();
        }
        var entry_ptr: *Entry = findEntry(table.entries, table.capacity, key);
        const isNewKey = entry_ptr.*.key == null;
        if (isNewKey and entry_ptr.*.value == null) {
            table.count += 1;
        }
        entry_ptr.key = @constCast(key);
        entry_ptr.value = value;
        return isNewKey;
    }
    pub fn get(table: *const Table, key: *const ObjString) ?Value {
        if (table.count == 0) return null;
        const found = findEntry(table.entries, table.capacity, key);
        if (found.*.key != null) return found.*.value;
        return null;
    }
    pub fn delete(table: *Table, key: *const ObjString) bool {
        if (table.count == 0) return false;
        const found = findEntry(table.entries, table.capacity, key);
        if (found.*.key == null) return false;
        // Set tombstone, in this case key = null, value = bool(true)
        found.*.key = null;
        found.*.value = TOMBSTONE_VAL;
        return true;
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
            table.count = 0;
            for (table.entries[0..table.capacity]) |e| {
                if (e.key == null) continue;
                const dest = findEntry(new_entries, new_capacity, e.key.?);
                dest.key = e.key;
                dest.value = e.value;
                table.count += 1;
            }
            table.allocator.free(table.entries);
            table.entries = new_entries;
        }
        table.capacity = new_capacity;
    }
    pub fn printTable(self: *const Table, name: []const u8) void {
        if (self.capacity == 0) return;
        std.debug.print("Table {s} (count: {}, capacity: {}):\n", .{ name, self.count, self.capacity });
        for (self.entries, 0..) |entry, index| {
            if (entry.key) |k| {
                std.debug.print("{}  Key ptr: {*} (chars: {s}), Value: {any}\n", .{ index, k, k.chars, entry.value.? });
            } else if (entry.value) |v| {
                std.debug.print("{}  Tombstone with value: {any}\n", .{ index, v });
            } else {
                // std.debug.print("  Empty slot\n", .{});
            }
        }
    }
};
/// Return pointer to Entry which either contains the same or empty key (empty slot)
fn findEntry(entries: []Entry, capacity: usize, key: *const ObjString) *Entry {
    var idx = key.hash % capacity;
    var tombstone: ?*Entry = null;
    while (true) : (idx = @mod(idx + 1, capacity)) {
        const e = &entries[idx];
        if (e.key) |found| {
            // Note: this compares pointer not the string, which is fast and requires string interning
            if (found == key) return e;
        } else {
            // Empty slot: check if it's a tombstone (value == true)
            if (e.value) |v| {
                if (v.isEqual(&TOMBSTONE_VAL)) {
                    if (tombstone == null) tombstone = e; // First tombstone in the probing sequence
                } else {
                    // Real empty slot
                    return if (tombstone) |t| t else e;
                }
            } else {
                // Real empty slot
                return if (tombstone) |t| t else e;
            }
        }
    }
}
pub fn tableAddAll(from: *Table, to: *Table) !void {
    for (from.entries) |src_entry| {
        if (src_entry.key != null) {
            _ = try to.set(src_entry.key.?, src_entry.value.?);
        }
    }
}
pub fn tableFindString(table: *Table, chars: []const u8) ?*ObjString {
    if (table.count == 0) return null;
    const hashcode = hasher(chars); // Switch to loxHash because chars is not guaranteed to be 8 byte aligned
    var idx = hashcode % table.capacity;
    while (true) : (idx = @mod(idx + 1, table.capacity)) {
        const e = &table.entries[idx];
        if (e.key) |found| {
            if (found.hash == hashcode and std.mem.eql(u8, found.chars, chars)) {
                // Found the string
                return @constCast(found);
            }
        } else {
            // Check for tombstone
            if (e.value) |v| {
                if (v.isEqual(&TOMBSTONE_VAL)) {
                    // Tombstone found, continue probing
                    continue;
                }
            } else {
                // Real empty slot
                return null;
            }
        }
    }
    return null;
}

test "Table" {
    initClHashRandomKey();
    const allocator = testing.allocator;
    var table = Table.init(allocator);
    defer table.deinit();
    var key = try ObjString.init(allocator, "Hello");
    defer key.deinit(allocator);
    const result = try table.set(key, Value{ .Number = 42 });
    try testing.expect(result);
    try std.testing.expect(table.count == 1);
    try std.testing.expect(table.capacity == 8);
    // Manually invoke grow()
    try table.grow();
    try std.testing.expect(table.count == 1);
    try std.testing.expect(table.capacity == 16);
    // Check if the value was set
    const found_entry = findEntry(table.entries, table.capacity, key);
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
const hasher = @import("common.zig").hasher;
