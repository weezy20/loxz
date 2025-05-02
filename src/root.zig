pub const OpCode = enum {
    OP_RETURN,
};

const std = @import("std");
const chunk = @import("./chunk.zig");
const expect = std.testing.expect;

test "loxz" {
    try expect(true);
}
