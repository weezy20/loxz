const STACK_MAX = 512;
pub const VM = @This();
pub const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

var global_debug_level: u8 = 0;
/// Chunk to execute
chunk: *Chunk,
/// Bytecode instruction pointer
ip: [*]u8,
/// Optional debug info to print during execution
debugInfo: ?*DebugInfo = null,
/// Allocator for the VM
allocator: std.mem.Allocator,
/// Stack
stack: *[STACK_MAX]Value,
/// Stack pointer - points just past the last used element
stackTop: [*]Value,
/// Allocated objects (redundant if using Arena allocator)
objects: ?*Object = null,
/// String HashSet
stringTable: Table,
/// Global variables
globals: Table,
/// Cache for global variables
globalCache: GlobalCache,

const GlobalCache = struct {
    const GlobalCacheEntry = struct {
        name: ?*ObjString = null,
        value: Value = .Nil,
        is_defined: bool = false,
    };
    const GlobalCacheSize: comptime_int = 1 << 8;
    const GlobalCacheMask: comptime_int = GlobalCacheSize - 1; // 0xFF
    entries: [GlobalCacheSize]GlobalCacheEntry,

    fn init() GlobalCache {
        return GlobalCache{
            // @splat essentially is [_]GlobalCacheEntry{.{ .name = null, .value = .Nil, .is_defined = false }} ** GlobalCacheSize,
            .entries = @splat(.{ .name = null, .value = .Nil, .is_defined = false }),
        };
    }
    fn lookup(self: *GlobalCache, name: *ObjString) ?Value {
        const index = @as(usize, name.hash) & GlobalCacheMask;
        const entry = self.entries[index];
        if (entry.name != null and entry.name.? == name and entry.is_defined) {
            if (global_debug_level >= 2) {
                std.debug.print("GlobalCache hit for '{s}' at index {d}\n", .{ name.chars, index });
            }
            return entry.value;
        }
        // In case of a collision we reach here and return null
        return null;
    }
    fn set(self: *GlobalCache, name: *ObjString, value: Value, is_defined: bool) void {
        const index = @as(usize, name.hash) & GlobalCacheMask;
        self.entries[index] = GlobalCacheEntry{
            .name = name,
            .value = value,
            .is_defined = is_defined,
        };
    }
};

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
        .stringTable = Table.init(allocator),
        .globals = Table.init(allocator),
        .globalCache = GlobalCache.init(),
    };
}
pub fn deinitVM(self: *VM) void {
    if (global_debug_level >= 2)
        std.debug.print("Running destructor on VM\n", .{});

    self.stringTable.deinit();
    self.globals.deinit();
    self.freeObjects();
    self.allocator.destroy(self.stack);
}
inline fn stackSize(self: *VM) usize {
    return @divExact((@intFromPtr(self.stackTop) - @intFromPtr(self.stack)), @sizeOf(Value));
}
pub fn freeObjects(self: *VM) void {
    if (self.objects) |obj| {
        if (global_debug_level >= 2) std.debug.print("VM Objects:\n", .{});
        var current: ?*Object = obj;
        var idx: usize = 0;

        while (current) |current_ptr| : (idx += 1) {
            if (global_debug_level >= 2) {
                std.debug.print(" - Destroy Object {} at {p}\n", .{ idx, current_ptr });
                if (current_ptr.asObjString()) |o| {
                    std.debug.print("   String chars ptr: 0x{x}\n", .{@intFromPtr(o.chars.ptr)});
                    std.debug.print("   String chars    : {s}\n", .{o.chars});
                }
            }
            const next = current_ptr.next;
            current_ptr.next = null;
            current_ptr.deinit();
            current = next;
        }
    }
}

pub fn resetStack(self: *VM) void {
    self.stackTop = self.stack;
    self.globalCache = GlobalCache.init();
}
fn printStack(self: *VM) void {
    // ANSI escape for bold red: \x1b[1;31m, reset: \x1b[0m
    std.debug.print("\x1b[1;31mStack [ ", .{});
    var current: [*]Value = self.stack;
    while (@intFromPtr(current) < @intFromPtr(self.stackTop)) : (current += 1) {
        const value = current[0];
        std.debug.print("<{}> ", .{value});
    }
    std.debug.print(" ]\x1b[0m\n", .{});
}

fn push(self: *VM, value: Value) RuntimeError!void {
    if (self.stackSize() >= STACK_MAX) {
        return RuntimeError.StackOverflow;
    }
    self.stackTop[0] = value;
    self.stackTop += 1;
}

pub fn addObj(self: *VM, obj: *Object) void {
    if (global_debug_level > 0)
        std.debug.print("Adding object ref {s} to VM\n", .{obj.*});
    obj.next = self.objects;
    self.objects = obj;
}

fn pop(self: *VM) RuntimeError!Value {
    if (self.stackSize() == 0) {
        return RuntimeError.StackUnderflow;
    }
    self.stackTop -= 1;
    return self.stackTop[0];
}

pub fn interpret(self: *VM, chunk: *Chunk, opts: struct {
    stack_tracing: bool = false,
    debug_level: u8,
    debugInfo: ?*DebugInfo = null,
    init_string_table: ?*Table,
}) InterpretResult {
    global_debug_level = opts.debug_level;
    self.chunk = chunk;
    if (global_debug_level >= 2) {
        chunk.print("Loaded chunk on VM");
    }
    self.ip = chunk.code;
    if (opts.init_string_table) |t| {
        lib.tableAddAll(@constCast(t), &self.stringTable) catch |err| {
            std.debug.print("Warning: Error initializing string table: {s}\n", .{@errorName(err)});
        };
        t.deinit();
    }
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
    const byte = self.ip[0];
    self.ip += 1;
    return byte;
}
/// Interpret u16 as big-endian, return as usize
inline fn readU16(self: *VM) usize {
    const bytes: [2]u8 = .{ self.ip[0], self.ip[1] };
    self.ip += 2;
    return @as(usize, std.mem.readInt(u16, bytes[0..], .big));
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
    var global_count: usize = 0;
    var string_count: usize = 0;
    while (debug_offset < self.chunk.count) {
        if (stack_tracing) self.printStack();
        if (global_debug_level > 0) {
            if (self.debugInfo) |d| blk: {
                if (debug_offset >= self.chunk.count) break :blk;
                debug_offset = lib.disassembleInstruction(
                    self.chunk,
                    debug_offset,
                    self.allocator,
                    .{ .debugInfo = d, .prefix = "\x1b[1;32mVM Executing\x1b[0m" },
                );
            } else {
                debug_offset = lib.disassembleInstruction(
                    self.chunk,
                    debug_offset,
                    self.allocator,
                    .{ .debugInfo = null, .prefix = "\x1b[1;32mVM Executing\x1b[0m" },
                );
            }
            if (global_debug_level >= 2) {
                if (self.stringTable.count != string_count) {
                    string_count = self.stringTable.count;
                    self.stringTable.printTable("string intern");
                }
                if (self.globals.count != global_count) {
                    global_count = self.globals.count;
                    self.globals.printTable("globals");
                }
            }
        }
        const instruction = @as(OpCode, @enumFromInt(self.readByte()));
        switch (instruction) {
            .RETURN => {
                // const val = try self.pop();
                // std.debug.print("{s}\n", .{val});
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
                if (value[0].asNumber()) |num| {
                    value[0] = Value{ .Number = -num };
                } else {
                    return RuntimeError.NaN;
                }
            },
            .ADD => add: {
                if (self.peek(0).isString()) |rhstr| if (self.peek(1).isString()) |lhstr| {
                    _ = try self.pop();
                    _ = try self.pop();
                    const o = try Object.newString(
                        self,
                        &[_][]const u8{ lhstr, rhstr },
                        &self.stringTable,
                    );
                    try self.push(Value{ .Obj = o.obj });
                    break :add;
                };
                if (self.peek(0).asNumber()) |rhs| if (self.peek(1).asNumber()) |lhs| {
                    _ = try self.pop();
                    _ = try self.pop();
                    try self.pushNumber(add(lhs, rhs));
                    break :add;
                };
                return RuntimeError.CannotAddDifferentTypes;
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
            .TRUE => {
                try self.push(Value{ .Bool = true });
            },
            .FALSE => {
                try self.push(Value{ .Bool = false });
            },
            .NIL => {
                try self.push(Value.Nil);
            },
            .NOT => {
                const val: Value = (self.stackTop - 1)[0];
                if (val.isBool()) |b| {
                    (self.stackTop - 1)[0] = Value{ .Bool = !b };
                } else {
                    return RuntimeError.InvalidNot;
                }
            },
            .EQUAL => {
                const b, const a = .{ try self.pop(), try self.pop() };
                try self.push(Value{ .Bool = a.isEqual(&b) });
            },
            .GREATER => {
                const rhs = try self.popNumber();
                const lhs = try self.popNumber();
                try self.push(Value{ .Bool = lhs > rhs });
            },
            .LESS => {
                const rhs = try self.popNumber();
                const lhs = try self.popNumber();
                try self.push(Value{ .Bool = lhs < rhs });
            },
            .PRINT => {
                printValue(try self.pop());
            },
            .POP => {
                _ = try self.pop();
            },
            .DEFINE_GLOBAL => {
                const name_idx = self.readU16();
                const name_val = try self.chunk.constants.get(name_idx);
                const name = name_val.asObjString().?; // Safe because we never emit this bytecode without a valid string name
                _ = try self.globals.set(name, self.peek(0));
                const val = try self.pop();
                self.globalCache.set(name, val, true);
            },
            .GET_GLOBAL => {
                const name_idx = self.readU16();
                const name_val = try self.chunk.constants.get(name_idx);
                const name = name_val.asObjString().?; // Safe because we never emit this bytecode without a valid string name
                if (self.globalCache.lookup(name)) |value| {
                    try self.push(value);
                } else {
                    if (self.globals.get(name)) |value| {
                        try self.push(value);
                        self.globalCache.set(name, value, true);
                    } else {
                        // Call runtimeError with format string and args
                        self.runtimeError("Undefined global variable: '{s}'", .{name.chars});
                        //TODO: Switch to error with context for runtime errors
                        return RuntimeError.GlobalNotFound;
                    }
                }
            },
            .SET_GLOBAL => {
                const name_idx = self.readU16();
                const name = (try self.chunk.constants.get(name_idx)).asObjString().?;
                if (try self.globals.set(name, self.peek(0))) {
                    std.debug.assert(self.globals.delete(name));
                    // Call runtimeError with format string and args
                    self.runtimeError("Assignment of undefined global variable: '{s}'", .{name.chars});
                    return RuntimeError.GlobalNotFound;
                }
                self.globalCache.set(name, self.peek(0), true);
            },
        }
    }
}

fn printValue(value: Value) void {
    switch (value) {
        .Number => |num| stdout.print("{d}\n", .{num}) catch {},
        .String => |str| stdout.print("{s}\n", .{str}) catch {},
        .Bool => |b| stdout.print("{s}\n", .{if (b) "true" else "false"}) catch {},
        .Nil => stdout.print("nil\n", .{}) catch {},
        .Obj => |obj| stdout.print("{s}\n", .{obj.*}) catch {},
    }
}

fn peek(self: *VM, distance: usize) Value {
    return self.stack[self.stackSize() - 1 - distance];
}

inline fn popNumber(self: *VM) RuntimeError!f64 {
    const value = try self.pop();
    if (value.asNumber()) |num| {
        return num;
    } else {
        return RuntimeError.NaN;
    }
}
inline fn pushNumber(self: *VM, value: f64) RuntimeError!void {
    try self.push(Value{ .Number = value });
}

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
const InterpretResult = lib.InterpretResult;
const RuntimeError = lib.RuntimeError;
const Object = lib.Object;
const ObjString = lib.ObjString;
const Table = lib.Table;

fn runtimeError(self: *VM, comptime fmt_str: []const u8, args: anytype) void {
    if (self.debugInfo) |d| {
        // Calculate current instruction offset
        // self.ip points to the NEXT instruction, so subtract 1 for the current opcode
        // If the error is due to an operand, this might need adjustment or more info from the caller.
        const offset = @intFromPtr(self.ip) - @intFromPtr(self.chunk.code) - 1;
        const line = d.getLine(offset);
        // ANSI escape for yellow gold: \x1b[1;33m, reset: \x1b[0m
        if (line) |l| {
            stderr.print("\x1b[1;33mRuntime error at line {}:\x1b[0m ", .{l}) catch {};
            stderr.print(fmt_str, args) catch {};
            stderr.print("\n", .{}) catch {};
        } else {
            stderr.print("\x1b[1;33mRuntime error:\x1b[0m ", .{}) catch {};
            stderr.print(fmt_str, args) catch {};
            stderr.print("\n", .{}) catch {};
        }
    } else {
        stderr.print("\x1b[1;33mRuntime error:\x1b[0m ", .{}) catch {};
        stderr.print(fmt_str, args) catch {};
        stderr.print("\n", .{}) catch {};
    }
}
