pub const OpCode = enum {
    OP_RETURN,
};

const std = @import("std");
const chunk = @import("./chunk.zig");
const expect = std.testing;

test "loxz" {
    try expect(true);
}
