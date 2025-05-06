const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("opcode.zig").OpCode;
const dbg = std.debug.print;

/// Disassemble a single instruction and return next offset
pub fn disassembleInstruction(chunk: *const Chunk, offset: usize) usize {
    dbg("{d:0>4}\t", .{chunk.code[offset]});
    const instruction = chunk.code[offset];
    // enumFromInt forces enum exhaustiveness check
    switch (@as(OpCode, @enumFromInt(instruction))) {
        .RETURN => {
            return simpleInstruction("OP_RETURN", offset);
        },
    }
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    dbg("{s}\n", .{name});
    return offset + 1;
}
