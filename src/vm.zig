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
        debugInfo: ?*DebugInfo = null,
    }) VM {
        const stackInit = allocator.create([STACK_MAX]Value) catch |err| {
            std.debug.print("Error allocating stack: {s}\n", .{@errorName(err)});
            std.process.exit(101);
        };
        return VM{
            .chunk = undefined,
            .ip = undefined,
            .debugInfo = opts.debugInfo,
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

    fn push(self: *VM, value: Value) !void {
        if (self.stackSize() >= STACK_MAX) {
            return error.StackOverflow;
        }
        self.stackTop[0] = value;
        self.stackTop += 1;
    }

    fn pop(self: *VM) Value {
        self.stackTop -= 1;
        return self.stackTop[0];
    }
    pub fn deinit(self: *VM) void {
        _ = self.allocator.destroy(self.stack);
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
                .RETURN => {
                    const val = self.pop();
                    std.debug.print("Return Value: {s}\n", .{val});
                    return .ok;
                },
                .CONSTANT, .CONSTANT_LONG => {
                    const constant_index = self.readConstant(instruction == OpCode.CONSTANT_LONG);
                    const constant_value = self.chunk.constants.get(constant_index) catch |err| {
                        return .{ .runtime_error = @errorName(err) };
                    };
                    self.push(constant_value) catch |err| {
                        return .{ .runtime_error = @errorName(err) };
                    };
                },
                .NEGATE => {
                    const value = self.pop();
                    if (value.isNumber()) |num| {
                        self.push(Value{ .Number = -num }) catch |err| {
                            return .{ .runtime_error = @errorName(err) };
                        };
                    } else {
                        return .{ .runtime_error = "Operand must be a number." };
                    }
                },
                .ADD => {
                    const rhs = self.popNumber();
                    const lhs = self.popNumber();
                    self.pushNumber(add(lhs, rhs)) catch |err| {
                        return .{ .runtime_error = @errorName(err) };
                    };
                },
                .SUBTRACT => {
                    const rhs = self.popNumber();
                    const lhs = self.popNumber();
                    self.pushNumber(sub(lhs, rhs)) catch |err| {
                        return .{ .runtime_error = @errorName(err) };
                    };
                },
                .MULTIPLY => {
                    const rhs = self.popNumber();
                    const lhs = self.popNumber();
                    self.pushNumber(mul(lhs, rhs)) catch |err| {
                        return .{ .runtime_error = @errorName(err) };
                    };
                },
                .DIVIDE => {
                    const rhs = self.popNumber();
                    const lhs = self.popNumber();
                    if (rhs == 0.0) {
                        return .{ .runtime_error = "Division by zero." };
                    }
                    self.pushNumber(div(lhs, rhs)) catch |err| {
                        return .{ .runtime_error = @errorName(err) };
                    };
                },
            }
        }
        return .ok;
    }
    inline fn popNumber(self: *VM) f64 {
        const value = self.pop();
        if (value.isNumber()) |num| {
            return num;
        } else {
            std.debug.print("Error: Expected number, got {s}\n", .{value});
            return 0.0;
        }
    }
    inline fn pushNumber(self: *VM, value: f64) !void {
        try self.push(Value{ .Number = value });
    }
};

pub const InterpretResult = union(enum) {
    ok,
    compile_error: ?[]const u8,
    runtime_error: ?[]const u8,
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
