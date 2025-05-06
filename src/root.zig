pub const OpCode = @import("opcode.zig").OpCode;
pub const Chunk = @import("chunk.zig").Chunk;

const std = @import("std");

const expect = std.testing.expect;
test "loxz sanity check" {
    try expect(true);
}
