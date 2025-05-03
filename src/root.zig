pub const OpCode = enum {
    OP_RETURN,
};

const std = @import("std");

const expect = std.testing.expect;
test "loxz sanity check" {
    try expect(true);
}
