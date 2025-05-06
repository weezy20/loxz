pub const OpCode = enum {
    OP_RETURN,
};

pub const Chunk = @import("chunk.zig").Chunk;

const std = @import("std");

const expect = std.testing.expect;
test "loxz sanity check" {
    try expect(true);
}
