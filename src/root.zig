pub const OpCode = @import("opcode.zig").OpCode;
pub const Chunk = @import("chunk.zig").Chunk;
pub const Value = @import("value.zig").Value;
const std = @import("std");

const expect = std.testing.expect;
test "loxz sanity check" {
    try expect(true);
}
