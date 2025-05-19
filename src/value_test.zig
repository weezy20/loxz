test "ValueArray" {
    const allocator = std.testing.allocator;
    var array = try ValueArray.init();
    defer array.deinit(allocator);

    try array.write(Value{ .Number = 1.0 }, allocator);
    try array.write(Value{ .String = "Hello" }, allocator);
    try array.write(Value{ .Bool = true }, allocator);
    try array.write(Value{ .Nil = undefined }, allocator);

    try std.testing.expect(array.count == 4);
    try std.testing.expect(array.capacity == 8);

    try std.testing.expect(@sizeOf(ValueArray) == 4 * @sizeOf(usize)); // 32 bytes size
    try std.testing.expect(@alignOf(ValueArray) == @alignOf(u64)); // 8 byte alignment
}

test "Values" {
    try std.testing.expect(@sizeOf(Value) == 3 * @sizeOf(usize));
}

test "deinit values" {
    const allocator = std.testing.allocator;
    // Init empty .values with non-null pointer and zero length
    var value_array = try ValueArray.init();
    try std.testing.expect(value_array.values.len == 0);
    // Attempt free
    value_array.deinit(allocator);
}

const std = @import("std");
const expect = std.testing.expect;
const Value = @import("value.zig").Value;
const ValueArray = @import("value.zig").ValueArray;
