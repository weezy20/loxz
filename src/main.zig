pub fn main() !void {
    const x = lib.OpCode.OP_RETURN;
    std.debug.print("Size of [*]u8: {}\n", .{@sizeOf([*]u8)}); // Expected: 8 on 64-bit
    std.debug.print("Size of []u8: {}\n", .{@sizeOf([]u8)}); // Expected: 16 on 64-bit
    std.debug.print("Size of [5]const u8: {}\n", .{@sizeOf(@TypeOf([5]u8{ 1, 2, 3, 4, 5 }))}); // Expected: 16 on 64-bit

    _ = x;
}

const lib = @import("loxz");
const std = @import("std");
