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
