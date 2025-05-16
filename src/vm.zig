const STACK_MAX = 512;
pub const VM = @This();

/// Chunk to execute
chunk: *Chunk,
/// Bytecode instruction pointer
ip: *u8,
/// Optional debug info to print during execution
debugInfo: ?*DebugInfo = null,
/// Allocator for the VM
allocator: std.mem.Allocator,
/// Stack
stack: *[STACK_MAX]Value,
/// Stack pointer - points just past the last used element
stackTop: [*]Value,

pub fn initVM(allocator: std.mem.Allocator) VM {
    const stackInit = allocator.create([STACK_MAX]Value) catch |err| {
        std.debug.print("Error allocating stack: {s}\n", .{@errorName(err)});
        std.process.exit(101);
    };
    return VM{
        .chunk = undefined,
        .ip = undefined,
        .allocator = allocator,
        .stack = stackInit,
        .stackTop = stackInit,
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

fn push(self: *VM, value: Value) RuntimeError!void {
    if (self.stackSize() >= STACK_MAX) {
        return RuntimeError.StackOverflow;
    }
    self.stackTop[0] = value;
    self.stackTop += 1;
}

fn pop(self: *VM) RuntimeError!Value {
    if (@intFromPtr(self.stackTop) < @intFromPtr(self.stack)) {
        return RuntimeError.StackUnderflow;
    }
    self.stackTop -= 1;
    return self.stackTop[0];
}

pub fn deinitVM(self: *VM) void {
    _ = self.allocator.destroy(self.stack);
    // TODO: Check if this is the right place to free DebugInfo
    // if (self.debugInfo) |d| {
    //     self.allocator.destroy(d);
    // }
}

pub fn interpret(self: *VM, chunk: *Chunk, opts: struct { stack_tracing: bool = false, debugInfo: ?*DebugInfo = null }) InterpretResult {
    self.chunk = chunk;
    self.ip = &chunk.code[0];
    if (opts.debugInfo) |d| {
        self.debugInfo = d;
    }
    // Enable stack-tracing here
    if (self.run(opts.stack_tracing)) {
        return .ok;
    } else |err| {
        return .{ .runtime_error = err };
    }
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

fn run(self: *VM, stack_tracing: bool) RuntimeError!void {
    var debug_offset: usize = 0;
    while (debug_offset < self.chunk.count) {
        if (self.debugInfo) |d| blk: {
            if (debug_offset >= self.chunk.count) break :blk;
            if (stack_tracing) self.printStack();
            debug_offset = lib.disassembleInstruction(
                self.chunk,
                debug_offset,
                self.allocator,
                .{ .debugInfo = d, .prefix = "VM Executing" },
            );
        }
        const instruction = @as(OpCode, @enumFromInt(self.readByte()));
        switch (instruction) {
            .RETURN => {
                const val = try self.pop();
                std.debug.print("Return Value: {s}\n", .{val});
                return;
            },
            .CONSTANT, .CONSTANT_LONG => {
                const constant_index = self.readConstant(instruction == OpCode.CONSTANT_LONG);
                const constant_value = self.chunk.constants.get(constant_index) catch |err| {
                    return err;
                };
                try self.push(constant_value);
            },
            .NEGATE => {
                const value: [*]Value = self.stackTop - 1; // Autoscales ptr arithmetic based on @sizeOf(T) for [*]T
                if (value[0].isNumber()) |num| {
                    value[0] = Value{ .Number = -num };
                } else {
                    return RuntimeError.NaN;
                }
            },
            .ADD => {
                const rhs = try self.popNumber();
                const lhs = try self.popNumber();
                try self.pushNumber(add(lhs, rhs));
            },
            .SUBTRACT => {
                const rhs = try self.popNumber();
                const lhs = try self.popNumber();
                try self.pushNumber(sub(lhs, rhs));
            },
            .MULTIPLY => {
                const rhs = try self.popNumber();
                const lhs = try self.popNumber();
                try self.pushNumber(mul(lhs, rhs));
            },
            .DIVIDE => {
                const rhs = try self.popNumber();
                const lhs = try self.popNumber();
                if (rhs == 0.0) {
                    return RuntimeError.DivisionByZero;
                }
                try self.pushNumber(div(lhs, rhs));
            },
        }
    }
}

inline fn popNumber(self: *VM) RuntimeError!f64 {
    const value = try self.pop();
    if (value.isNumber()) |num| {
        return num;
    } else {
        return RuntimeError.NaN;
    }
}
inline fn pushNumber(self: *VM, value: f64) RuntimeError!void {
    try self.push(Value{ .Number = value });
}

pub const InterpretResult = union(enum) {
    ok,
    compile_error,
    runtime_error: RuntimeError,
};

// const CompileError = error{
//     Oops,
// };

const RuntimeError = error{
    StackOverflow,
    NaN,
    DivisionByZero,
    ValueIndexOutOfBounds,
    OutOfMemory,
    StackUnderflow,
};

fn div(x: f64, y: f64) f64 {
    return x / y;
}
fn mul(x: f64, y: f64) f64 {
    return x * y;
}
fn add(x: f64, y: f64) f64 {
    return x + y;
}
fn sub(x: f64, y: f64) f64 {
    return x - y;
}

const std = @import("std");
const lib = @import("root.zig");
const Chunk = lib.Chunk;
const OpCode = lib.OpCode;
const Value = lib.Value;
const DebugInfo = lib.DebugInfo;
