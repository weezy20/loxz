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

test "isEqual: Numbers" {
    const num1 = Value{ .Number = 42.0 };
    const num2 = Value{ .Number = 42.0 };
    const num3 = Value{ .Number = 43.0 };
    const nan = Value{ .Number = std.math.nan(f64) };
    const inf = Value{ .Number = std.math.inf(f64) };

    try expect(num1.isEqual(&num2)); // Equal numbers
    try expect(!num1.isEqual(&num3)); // Different numbers
    try expect(!nan.isEqual(&nan)); // NaN != NaN (IEEE 754 rule)
    try expect(inf.isEqual(&inf)); // Inf == Inf
}

test "isEqual: Strings" {
    const str1 = Value{ .String = "hello" };
    const str2 = Value{ .String = "hello" };
    const str3 = Value{ .String = "world" };
    const empty = Value{ .String = "" };
    const upper = Value{ .String = "HELLO" };

    try expect(str1.isEqual(&str2)); // Equal strings
    try expect(!str1.isEqual(&str3)); // Different strings
    try expect(empty.isEqual(&empty)); // Empty strings
    try expect(!str1.isEqual(&upper)); // Case-sensitive
}

test "isEqual: Booleans" {
    const t = Value{ .Bool = true };
    const f = Value{ .Bool = false };

    try expect(t.isEqual(&t)); // true == true
    try expect(f.isEqual(&f)); // false == false
    try expect(!t.isEqual(&f)); // true != false
}

test "isEqual: Nil" {
    const nil1 = Value{ .Nil = undefined };
    const nil2 = Value{ .Nil = undefined };
    const num = Value{ .Number = 0.0 };

    try expect(nil1.isEqual(&nil2)); // Nil == Nil
    try expect(!nil1.isEqual(&num)); // Nil != Number
}

test "isEqual: Mismatched Types" {
    const num = Value{ .Number = 42.0 };
    const str = Value{ .String = "42" };
    const boolean = Value{ .Bool = true };
    const nil = Value{ .Nil = undefined };

    try expect(!num.isEqual(&str)); // Number != String
    try expect(!boolean.isEqual(&num)); // Bool != Number
    try expect(!str.isEqual(&nil)); // String != Nil
}

test "isEqual: Edge Cases" {
    const v1 = Value{ .Number = 42.0 };
    var v2 = Value{ .Number = 42.0 };
    const same = Value{ .Bool = true };

    try expect(v1.isEqual(&v2)); // Same value, different instances
    try expect(same.isEqual(&same)); // Self-comparison
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
