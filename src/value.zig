/// Values in Lox
pub const Value = union(enum) {
    Number: f64,
    String: []const u8,
    Bool: bool,
    Nil,
};

/// Value Arrays
pub const ValueArray = struct {
    values: []Value,
    count: usize,
    capacity: usize,

    pub fn init() !ValueArray {
        return ValueArray{
            .values = &[_]Value{},
            .count = 0,
            .capacity = 0,
        };
    }

    pub fn deinit(self: *ValueArray, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        self.* = undefined;
    }

    pub fn write(
        self: *ValueArray,
        value: Value,
        allocator: std.mem.Allocator,
    ) !void {
        if (self.count >= self.capacity) {
            const new_capacity = if (self.capacity == 0) 8 else self.capacity * 2;
            const new_values: []Value = try allocator.realloc(self.values, new_capacity);

            self.values = new_values;
            self.capacity = new_capacity;
        }
        std.debug.assert(self.count < self.capacity);
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn get(self: *const ValueArray, index: usize) !Value {
        if (index >= self.count) {
            return error.ValueIndexOutOfBounds;
        }
        return self.values[index];
    }
};

test "ValueArray" {
    const allocator = std.testing.allocator;
    var array = try ValueArray.init();
    defer array.deinit(allocator);

    try array.write(Value{ .Number = 1.0 }, allocator);
    try array.write(Value{ .String = "Hello" }, allocator);
    try array.write(Value{ .Bool = true }, allocator);
    try array.write(Value{ .Nil = undefined }, allocator);

    std.debug.assert(array.count == 4);
    std.debug.assert(array.capacity == 8);

    std.debug.assert(@sizeOf(ValueArray) == 4 * @sizeOf(usize)); // 32 bytes size
    std.debug.assert(@alignOf(ValueArray) == @alignOf(u64)); // 8 byte alignment
}

const std = @import("std");
const lib = @import("root.zig");
