const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("opcode.zig").OpCode;
const dbg = std.debug.print;

/// Disassemble a single instruction and return next offset
pub fn disassembleInstruction(chunk: *const Chunk, offset: usize) usize {
    dbg("0x{0X:0>4}\t", .{chunk.code[offset]});
    const instruction = chunk.code[offset];
    // enumFromInt forces enum exhaustiveness check
    switch (@as(OpCode, @enumFromInt(instruction))) {
        .RETURN => {
            return simpleInstruction("OP_RETURN", offset);
        },
        .CONSTANT => {
            return constantInstruction("OP_CONSTANT", chunk, offset);
        },
    }
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    dbg("{s}\n", .{name});
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const constant_index = chunk.code[offset + 1]; // Skip 1 byte for OP_CONSTANT
    const constant_value = chunk.constants.get(constant_index) catch |err| {
        std.debug.panic("Error getting constant: {}", .{err});
    }; // Look up the constant with bounds check
    const stdout = std.io.getStdOut().writer();
    stdout.print("{0s} idx : {1d: >4} [{2}]\n", .{ name, constant_index, constant_value }) catch {
        dbg("Failed to print constant", .{});
    };
    return offset + 2;
}
