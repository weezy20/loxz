pub const VM = struct {
    chunk: *Chunk,
    ip: *u8,

    pub fn init(allocator: std.mem.Allocator) VM {
        _ = allocator;
        return VM{ .chunk = undefined, .ip = undefined };
    }
    pub fn deinit(self: *VM) void {
        _ = self;
        // self.chunks.deinit();
    }
    pub fn interpret(self: *VM, chunk: *Chunk) InterpretResult {
        if (chunk.count == 0) {
            return .ok;
        }
        // Load the chunk into the VM
        self.chunk = chunk;
        self.ip = &chunk.code[0];
        return self.run();
    }
    /// Read a byte from the current instruction pointer and increment it.
    /// SAFETY: Depends on caller to make sure outside of bounds access is not possible
    pub fn readByte(self: *VM) u8 {
        const byte = self.ip.*;
        self.ip = @ptrFromInt(@intFromPtr(self.ip) + 1);
        return byte;
    }
    pub fn run(self: *VM) InterpretResult {
        while (true) {
            const instruction = self.readByte();
            switch (@as(OpCode, @enumFromInt(instruction))) {
                OpCode.RETURN => {
                    return .ok;
                },
                else => {
                    // Handle other opcodes here
                    // For now, just print the instruction
                    std.debug.print("Unknown instruction: {d}\n", .{instruction});
                    return .{ .runtime_error = "Unknown instruction" };
                },
            }
        }
    }
};

pub const InterpretResult = union(enum) {
    ok,
    compile_error: ?[]const u8,
    runtime_error: ?[]const u8,
};

const std = @import("std");
const lib = @import("root.zig");
const Chunk = lib.Chunk;
const OpCode = lib.OpCode;
const Value = lib.Value;
