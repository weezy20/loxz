const STACK_MAX = 256;

pub const VM = struct {
    /// Chunk to execute
    chunk: *Chunk,
    /// Bytecode instruction pointer
    ip: *u8,
    /// Optional debug info to print during execution
    debugInfo: ?*DebugInfo,
    /// Allocator for the VM
    allocator: std.mem.Allocator,
    /// Stack
    stack: *[STACK_MAX]Value,
    /// Stack pointer - points just past the last used element
    stackTop: [*]Value,

    pub fn init(allocator: std.mem.Allocator, opts: struct {
        debugInfo: ?*DebugInfo,
    }) VM {
        var stackInit = [_]Value{.Nil} ** STACK_MAX;
        return VM{
            .chunk = undefined,
            .ip = undefined,
            .debugInfo = opts.debugInfo,
            .allocator = allocator,
            .stack = &stackInit,
            .stackTop = &stackInit,
        };
    }
    inline fn stackSize(self: *VM) usize {
        return @divExact((@intFromPtr(self.stackTop) - @intFromPtr(self.stack)), @sizeOf(Value));
    }

    pub fn resetStack(self: *VM) void {
        self.stackTop = self.stack;
    }
    fn printStack(self: *VM) void {
        std.debug.print("Stack [ ", .{});
        var current: [*]Value = self.stack;
        while (@intFromPtr(current) < @intFromPtr(self.stackTop)) : (current += 1) {
            const value = current[0];
            std.debug.print("<{}> ", .{value});
        }
        std.debug.print(" ]\n", .{});
    }

    fn push(self: *VM, value: Value) !void {
        if (self.stackSize() >= STACK_MAX) {
            return error.StackOverflow;
        }
        self.stackTop[0] = value;
        self.stackTop += 1;
    }

    fn pop(self: *VM) Value {
        self.stackTop -= 1;
        return self.stackTop.*;
    }
    pub fn deinit(self: *VM) void {
        _ = self;
    }

    pub fn interpret(self: *VM, chunk: *Chunk) InterpretResult {
        self.chunk = chunk;
        self.ip = &chunk.code[0];
        return self.run();
    }

    inline fn readByte(self: *VM) u8 {
        const byte = self.ip.*;
        self.ip = @ptrFromInt(@intFromPtr(self.ip) + 1);
        return byte;
    }

    inline fn readConstant(self: *VM, long: bool) usize {
        if (!long) {
            return self.readByte();
        } else {
            return @as(usize, self.readByte()) << 16 |
                @as(usize, self.readByte()) << 8 |
                @as(usize, self.readByte());
        }
    }

    fn run(self: *VM) InterpretResult {
        var debug_offset: usize = 0;
        while (debug_offset < self.chunk.count) {
            if (self.debugInfo) |d| blk: {
                if (debug_offset >= self.chunk.count) break :blk;
                self.printStack();
                debug_offset = lib.disassembleInstruction(self.chunk, debug_offset, self.allocator, .{ .debugInfo = d, .prefix = "VM" });
            }
            const instruction = @as(OpCode, @enumFromInt(self.readByte()));
            switch (instruction) {
                OpCode.RETURN => return .ok,
                OpCode.CONSTANT, OpCode.CONSTANT_LONG => {
                    const constant_index = self.readConstant(instruction == OpCode.CONSTANT_LONG);
                    const constant_value = self.chunk.constants.get(constant_index) catch |err| {
                        return .{ .runtime_error = @errorName(err) };
                    };
                    self.push(constant_value) catch |err| {
                        return .{ .runtime_error = @errorName(err) };
                    };
                },
            }
        }
        return .ok;
    }
};

// pub const ValueStack = struct {
//     stack: [STACK_MAX]Value,
//     top: [*]Value,

//     pub inline fn push(self: *ValueStack, value: Value) void {
//         self.top[0] = value;
//         self.top += 1;
//     }

//     pub inline fn pop(self: *ValueStack) Value {
//         self.top -= 1;
//         return (self.top)[0];
//     }
// };

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
