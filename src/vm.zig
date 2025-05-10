pub const VM = struct {
    /// Chunk to execute
    chunk: *Chunk,
    /// Bytecode instruction pointer
    ip: *u8,
    /// Optional debug info to print during execution
    debugInfo: ?*DebugInfo,
    /// Allocator for the VM
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, opts: struct {
        debugInfo: ?*DebugInfo,
    }) VM {
        return VM{ .allocator = allocator, .chunk = undefined, .ip = undefined, .debugInfo = opts.debugInfo };
    }
    /// No-op for now
    pub fn deinit(self: *VM) void {
        _ = self;
    }
    pub fn interpret(self: *VM, chunk: *Chunk) InterpretResult {
        self.chunk = chunk;
        self.ip = &chunk.code[0];
        return self.run();
    }
    /// Read a byte from the current instruction pointer and increment it.
    /// SAFETY: Depends on caller to make sure outside of bounds access is not possible
    fn readByte(self: *VM) u8 {
        const byte = self.ip.*;
        self.ip = @ptrFromInt(@intFromPtr(self.ip) + 1);
        return byte;
    }
    fn readConstant(self: *VM, long: bool) usize {
        if (!long) {
            return self.readByte();
        } else {
            const long_idx: usize = @as(usize, self.readByte()) << 16 | @as(usize, self.readByte()) << 8 | @as(usize, self.readByte());
            return long_idx;
        }
    }
    // UNSAFE: no bounds check
    fn run(self: *VM) InterpretResult {
        var debug_offset: usize = 0;
        while (debug_offset < self.chunk.count) {
            // If we have a debug info, print the current instruction before executing
            if (self.debugInfo) |d| {
                debug_offset = lib.disassembleInstruction(self.chunk, debug_offset, self.allocator, .{ .debugInfo = d, .prefix = "VM" });
            }
            const instruction = @as(OpCode, @enumFromInt(self.readByte()));
            switch (instruction) {
                OpCode.RETURN => {
                    return .ok;
                },
                OpCode.CONSTANT, OpCode.CONSTANT_LONG => {
                    const constant_index = self.readConstant(instruction == OpCode.CONSTANT_LONG);
                    const constant_value = self.chunk.constants.get(constant_index) catch |err| {
                        return .{ .runtime_error = @errorName(err) };
                    };
                    std.debug.print("Constant: {d}\n", .{constant_value});
                    // Handle the constant value here
                    // return .ok;
                },
                // else => {
                //     // Handle other opcodes here
                //     // For now, just print the instruction
                //     std.debug.print("Unknown instruction: {d}\n", .{instruction});
                //     return .{ .runtime_error = "Unknown instruction" };
                // },
            }
        }
        return .ok;
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
const DebugInfo = lib.DebugInfo;
