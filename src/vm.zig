const FRAMES_MAX = 64; // Note, frameCount is u8 so this must be within u8 bounds
const STACK_MAX = FRAMES_MAX * ((1 << 16) + 1024); // u16 max locals + 1024 for temporaries.
const MAX_SWITCH_DEPTH = 64; // Arbitrary limit for switch stack depth

pub const VM = @This();
pub const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

var global_debug_level: u8 = 0;
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
stringTable: *Table,
/// Global variables
globals: *Table,
/// Cache for global variables
globalCache: GlobalCache,
/// Switch stack
switchStack: std.BoundedArray(Value, MAX_SWITCH_DEPTH),
/// Callframe stack
frames: *[FRAMES_MAX]CallFrame,
frameCount: u8, // Ok because frames_max is 64

/// An ongoing function call.
const CallFrame = struct {
    closure: *ObjClosure,
    ip: [*]u8,
    slots: [*]Value,
};

inline fn switchDepth(self: *VM) usize {
    return self.switchStack.len;
}

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
        std.debug.print("Error allocating value stack: {s}\n", .{@errorName(err)});
        std.process.exit(101);
    };
    const framesInit = allocator.create([FRAMES_MAX]CallFrame) catch |err| {
        std.debug.print("Error allocating callframe stack: {s}\n", .{@errorName(err)});
        std.process.exit(101);
    };
    return VM{
        .allocator = allocator,
        .stack = stackInit,
        .stackTop = stackInit,
        .stringTable = Table.init(allocator) catch |err| {
            std.debug.print("Error initializing string table: {s}\n", .{@errorName(err)});
            std.process.exit(101);
        },
        .globals = Table.init(allocator) catch |err| {
            std.debug.print("Error initializing globals table: {s}\n", .{@errorName(err)});
            std.process.exit(101);
        },
        .globalCache = GlobalCache.init(),
        .switchStack = std.BoundedArray(Value, MAX_SWITCH_DEPTH).init(0) catch |err| {
            // We fail silently here, as the switch-case is not a critical lox language feature but an extension.
            std.debug.print("Error initializing switch stack: {any}\nSwitch-cases not avaialble", .{err});
            std.process.exit(101);
        },
        .frames = framesInit,
        .frameCount = 0,
    };
}

/// Set up native functions in the VM
pub fn setupNatives(self: *VM) !void {
    try self.defineNative("clock", clockNative);
    try self.defineNative("sqrt", sqrtNative);
    try self.defineNative("abs", absNative);
    try self.defineNative("pow", powNative);
}

/// Set up native functions in the VM with a specific string table
pub fn setupNativesWithStringTable(self: *VM, string_table: *Table) !void {
    try self.defineNativeWithStringTable("clock", clockNative, string_table);
    try self.defineNativeWithStringTable("sqrt", sqrtNative, string_table);
    try self.defineNativeWithStringTable("abs", absNative, string_table);
    try self.defineNativeWithStringTable("pow", powNative, string_table);
}

pub fn deinitVM(self: *VM) void {
    if (global_debug_level >= 2)
        std.debug.print("Running destructor on VM\n", .{});

    self.stringTable.deinit();
    self.globals.deinit();
    self.freeObjects();
    self.allocator.destroy(self.stack);
    self.allocator.destroy(self.frames);
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

inline fn push(self: *VM, value: Value) void {
    self.stackTop[0] = value;
    self.stackTop += 1;
}

pub fn addObj(self: *VM, obj: *Object) void {
    if (global_debug_level > 0)
        std.debug.print("Adding object ref {s} to VM\n", .{obj.*});
    obj.next = self.objects;
    self.objects = obj;
}

pub fn addObjFunction(self: *VM, function: *ObjFunction) !*Object {
    const obj_wrapper = try self.allocator.create(Object);
    errdefer self.allocator.destroy(obj_wrapper);
    obj_wrapper.* = Object{
        .allocator = self.allocator,
        .data = .{ .Function = function },
    };
    if (global_debug_level > 0)
        std.debug.print("Adding function ref {s} to VM\n", .{obj_wrapper});
    obj_wrapper.next = self.objects;
    self.objects = obj_wrapper;
    return obj_wrapper;
}

/// Define a native function in the global scope
pub fn defineNative(self: *VM, name: []const u8, function: lib.NativeFn) !void {
    // Create the string for the native function name
    const name_str = try Object.newString(self, &[_][]const u8{name}, self.stringTable);

    // Create the native object
    const native_obj = try Object.newNative(self, name_str.obj.data.String, function);

    // Add to globals
    _ = try self.globals.set(name_str.obj.data.String, Value{ .Obj = native_obj });
}

/// Define a native function in the global scope with a specific string table
pub fn defineNativeWithStringTable(self: *VM, name: []const u8, function: lib.NativeFn, string_table: *Table) !void {
    // Create the string for the native function name using the provided string table
    const name_str = try Object.newString(self, &[_][]const u8{name}, string_table);

    // Create the native object
    const native_obj = try Object.newNative(self, name_str.obj.data.String, function);

    // Add to globals
    _ = try self.globals.set(name_str.obj.data.String, Value{ .Obj = native_obj });
}

inline fn pop(self: *VM) Value {
    self.stackTop -= 1;
    return self.stackTop[0];
}

pub fn interpret(self: *VM, source: []const u8, opts: lib.InterpreterOpts) InterpretResult {
    global_debug_level = opts.debug_level;
    var compiler = lib.Compiler.init(self.allocator, self, .Script, null) catch |err| {
        std.debug.print("Compiler init error : {s}", .{@errorName(err)});
        return .compile_error;
    };

    // Set up native functions after compiler is created but before compilation
    self.setupNativesWithStringTable(compiler.stringTable) catch |err| {
        std.debug.print("Error setting up natives: {s}\n", .{@errorName(err)});
        return .compile_error;
    };

    const compilerStringTable = compiler.stringTable;
    const compile_result = lib.compile(&compiler, source, self, self.allocator, opts.intoCompilerOpts());
    if (!compile_result.success) {
        return .compile_error;
    }
    const function = compile_result.function.?;

    // TODO: We avoid the ObjFunction creation, ObjClosure creation, pop, push dance because we don't require it
    // It only becomes relevant when a GC is in place.
    //
    // const obj = self.addObjFunction(function) catch return .compile_error;
    // self.push(Value{ .Obj = obj });
    // const closure_obj = Object.newClosure(self, function) catch return .compile_error;
    // _ = self.pop();  // Remove function object
    // self.push(Value{ .Obj = closure_obj });
    // self.callClosure(closure_obj.asClosure().?, 0) catch |err| return .{ .runtime_error = err };

    const closure_obj = Object.newClosure(self, function) catch return .compile_error;
    const closure = closure_obj.asClosure().?;
    self.push(Value{ .Obj = closure_obj });

    self.callClosure(closure, 0) catch |err| return .{ .runtime_error = err };

    lib.tableAddAll(compilerStringTable, self.stringTable) catch |err| {
        std.debug.print("Warning: Error initializing string table: {s}\n", .{@errorName(err)});
    };

    if (compile_result.debugInfo) |d| {
        self.debugInfo = d;
    }
    defer {
        if (compile_result.debugInfo) |d| {
            d.deinit();
            self.allocator.destroy(d);
        }
        compiler.deinit();
    }
    // Enable stack-tracing here
    if (self.run(opts.stack_tracing)) {
        return .ok;
    } else |err| {
        return .{ .runtime_error = err };
    }
}

inline fn readByte(self: *VM) u8 {
    var frame = self.currentFrame();
    const byte = frame.ip[0];
    frame.ip += 1;
    return byte;
}
/// Interpret u16 as big-endian, return as usize
inline fn readU16(self: *VM) usize {
    var frame = self.currentFrame();
    const bytes: [2]u8 = .{ frame.ip[0], frame.ip[1] };
    frame.ip += 2;
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

inline fn currentFrame(self: *VM) *CallFrame {
    return &self.frames[self.frameCount - 1];
}
inline fn currentChunk(self: *VM) *Chunk {
    return &self.currentFrame().closure.function.chunk;
}

fn run(self: *VM, stack_tracing: bool) RuntimeError!void {
    var frame = &self.frames[self.frameCount - 1];
    var ip = frame.ip;

    while (true) {
        if (stack_tracing) self.printStack();

        // Only do debug work if debugging is enabled
        if (global_debug_level > 0) {
            const debug_offset = @intFromPtr(ip) - @intFromPtr(frame.closure.function.chunk.code);
            if (self.debugInfo) |d| blk: {
                if (debug_offset >= frame.closure.function.chunk.count) break :blk;
                _ = lib.disassembleInstruction(
                    &frame.closure.function.chunk,
                    debug_offset,
                    self.allocator,
                    .{ .debugInfo = d, .prefix = "\x1b[1;32mVM Executing\x1b[0m" },
                );
            } else {
                _ = lib.disassembleInstruction(
                    &frame.closure.function.chunk,
                    debug_offset,
                    self.allocator,
                    .{ .debugInfo = null, .prefix = "\x1b[1;32mVM Executing\x1b[0m" },
                );
            }
        }

        const instruction = @as(OpCode, @enumFromInt(ip[0]));
        ip += 1;
        switch (instruction) {
            .RETURN => {
                const ret_val = self.pop();
                self.frameCount -= 1;
                if (self.frameCount == 0) {
                    _ = self.pop();
                    return;
                }
                self.stackTop = frame.slots;
                self.push(ret_val);
                frame = &self.frames[self.frameCount - 1];
                ip = frame.ip;
            },
            .CONSTANT => {
                const constant_index = ip[0];
                ip += 1;
                const constant_value = frame.closure.function.chunk.constants.values[constant_index];
                self.push(constant_value);
            },
            .CONSTANT_LONG => {
                const constant_index = (@as(usize, ip[0]) << 16) | (@as(usize, ip[1]) << 8) | @as(usize, ip[2]);
                ip += 3;
                const constant_value = frame.closure.function.chunk.constants.values[constant_index];
                self.push(constant_value);
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
                    _ = self.pop();
                    _ = self.pop();
                    const o = try Object.newString(
                        self,
                        &[_][]const u8{ lhstr, rhstr },
                        self.stringTable,
                    );
                    self.push(Value{ .Obj = o.obj });
                    break :add;
                };
                if (self.peek(0).asNumber()) |rhs| if (self.peek(1).asNumber()) |lhs| {
                    _ = self.pop();
                    _ = self.pop();
                    self.push(Value{ .Number = lhs + rhs });
                    break :add;
                };
                return RuntimeError.CannotAddDifferentTypes;
            },
            .SUBTRACT => {
                const rhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                const lhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                self.push(Value{ .Number = lhs - rhs });
            },
            .MULTIPLY => {
                const rhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                const lhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                self.push(Value{ .Number = lhs * rhs });
            },
            .DIVIDE => {
                const rhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                const lhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                if (rhs == 0.0) {
                    return RuntimeError.DivisionByZero;
                }
                self.push(Value{ .Number = lhs / rhs });
            },
            .MOD => {
                const rhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                const lhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                if (rhs == 0.0) {
                    return RuntimeError.DivisionByZero;
                }
                self.push(Value{ .Number = @mod(lhs, rhs) });
            },
            .TRUE => {
                self.push(Value{ .Bool = true });
            },
            .FALSE => {
                self.push(Value{ .Bool = false });
            },
            .NIL => {
                self.push(Value.Nil);
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
                const b, const a = .{ self.pop(), self.pop() };
                self.push(Value{ .Bool = a.isEqual(&b) });
            },
            .GREATER => {
                const rhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                const lhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                self.push(Value{ .Bool = lhs > rhs });
            },
            .LESS => {
                const rhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                const lhs = self.pop().asNumber() orelse return RuntimeError.NaN;
                self.push(Value{ .Bool = lhs < rhs });
            },
            .PRINT => {
                printValue(self.pop());
            },
            .POP => {
                _ = self.pop();
            },
            .DEFINE_GLOBAL => {
                const name_idx = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                const name_val = frame.closure.function.chunk.constants.values[name_idx];
                const name = name_val.asObjString().?; // Safe because we never emit this bytecode without a valid string name
                _ = try self.globals.set(name, self.peek(0));
                const val = self.pop();
                self.globalCache.set(name, val, true);
            },
            .GET_GLOBAL => {
                const name_idx = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                const name_val = frame.closure.function.chunk.constants.values[name_idx];
                const name = name_val.asObjString().?; // Safe because we never emit this bytecode without a valid string name
                if (self.globalCache.lookup(name)) |value| {
                    self.push(value);
                } else {
                    if (self.globals.get(name)) |value| {
                        self.push(value);
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
                const name_idx = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                const name = frame.closure.function.chunk.constants.values[name_idx].asObjString().?;
                if (try self.globals.set(name, self.peek(0))) {
                    std.debug.assert(self.globals.delete(name));
                    // Call runtimeError with format string and args
                    self.runtimeError("Assignment of undefined global variable: '{s}'", .{name.chars});
                    return RuntimeError.GlobalNotFound;
                }
                self.globalCache.set(name, self.peek(0), true);
            },
            .GET_LOCAL => {
                const slot = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                self.push(frame.slots[slot]);
            },
            .SET_LOCAL => {
                const slot = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                frame.slots[slot] = self.peek(0);
            },
            .JUMP => {
                const offset = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                ip += offset;
            },
            .JUMP_IF_FALSE => {
                const offset = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                if (self.peek(0).isFalsey()) {
                    ip += offset;
                }
            },
            .LOOP => {
                const offset = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                ip -= offset;
            },
            .SWITCH_VAL => {
                const depth = ip[0];
                ip += 1;
                if (depth >= MAX_SWITCH_DEPTH) {
                    self.runtimeError("Switch value with invalid depth 0x{x:0>2} (max: {d})", .{ depth, MAX_SWITCH_DEPTH });
                    return RuntimeError.SwitchDepthExceeded;
                }
                if (depth == self.switchStack.len) {
                    self.switchStack.append(self.pop()) catch {};
                } else self.switchStack.set(depth, self.pop()); // Pops the switch value and store in vm.switchStack
            },
            .SWITCH_COMP => {
                if (self.switchDepth() == 0) {
                    const depth_byte = ip[0];
                    ip += 1;
                    self.runtimeError("Switch comparison without a switch value, [invalid depth: 0x{x:0>2}]", .{depth_byte});
                    return RuntimeError.SwitchStackEmpty;
                }
                const depth = ip[0];
                ip += 1;
                if (depth >= MAX_SWITCH_DEPTH) {
                    self.runtimeError("Switch value with invalid depth 0x{x:0>2} (max: {d})", .{ depth, MAX_SWITCH_DEPTH });
                    return RuntimeError.SwitchDepthExceeded;
                }
                const switch_value: Value = self.switchStack.get(depth);
                const case_value = self.pop();
                self.push(Value{ .Bool = switch_value.isEqual(&case_value) });
            },
            .CALL => {
                const arg_count = ip[0];
                ip += 1;
                frame.ip = ip; // Save current IP before function call
                try self.callValue(self.peek(arg_count), arg_count);
                frame = &self.frames[self.frameCount - 1];
                ip = frame.ip;
            },
            .CLOSURE => {
                const constant_idx = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                // Safe to unwrap: Compiler guarantee.
                const function = frame.closure.function.chunk.constants.values[constant_idx].asFunction().?;
                const closure_obj = Object.newClosure(self, function) catch |err| {
                    self.runtimeError("Failed to create closure: {s}", .{@errorName(err)});
                    return RuntimeError.InvalidCall;
                };
                self.push(Value{ .Obj = closure_obj });
                const closure = closure_obj.asClosure().?;

                // Read upvalue data following the closure creation
                for (0..closure.upvalue_count) |_| {
                    const packed_byte = ip[0];
                    ip += 1;

                    const is_local = (packed_byte & lib.UPVALUE_IS_LOCAL_FLAG) != 0;
                    const is_wide_index = (packed_byte & lib.UPVALUE_WIDE_INDEX_FLAG) != 0;

                    const upvalue_index: usize = if (is_wide_index) blk: {
                        // Read 2-byte index
                        const msb = @as(usize, ip[0]);
                        const lsb = @as(usize, ip[1]);
                        ip += 2;
                        break :blk (msb << 8) | lsb;
                    } else blk: {
                        // Read 1-byte index
                        const index = @as(usize, ip[0]);
                        ip += 1;
                        break :blk index;
                    };

                    // Capture upvalue
                    const captured_upvalue: *ObjUpvalue = if (is_local) b: {
                        const local_slot = frame.slots + upvalue_index;
                        const upvalue = self.captureUpvalue(&local_slot[0]) catch |err| {
                            self.runtimeError("Failed to capture local upvalue: {s}", .{@errorName(err)});
                            return RuntimeError.InvalidCall;
                        };
                        break :b upvalue;
                    } else b: {
                        if (upvalue_index >= frame.closure.upvalues.items.len) {
                            self.runtimeError("Upvalue index {} out of bounds", .{upvalue_index});
                            return RuntimeError.InvalidCall;
                        }
                        break :b frame.closure.upvalues.items[upvalue_index];
                    };
                    // Store captured upvalue in closure (equivalent to closure->upvalues[i] = ...)
                    try closure.upvalues.append(captured_upvalue);
                }
            },
            .GET_UPVALUE => {
                const slot = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                self.push(frame.closure.upvalues.items[slot].location.*);
            },
            .SET_UPVALUE => {
                const slot = (@as(usize, ip[0]) << 8) | @as(usize, ip[1]);
                ip += 2;
                frame.closure.upvalues.items[slot].location.* = self.peek(0);
            },

            // else => {
            //     self.runtimeError("Unknown opcode: {d}", .{@intFromEnum(instruction)});
            //     return RuntimeError.UnknownOpCode;
            // },
        }

        // Update frame.ip for debugging and error handling
        frame.ip = ip;
    }
}

fn callValue(self: *VM, callee: Value, arg_count: u8) RuntimeError!void {
    // Since every ObjFunction is now treated as a ObjClosure
    if (callee.isClosure()) |closure| {
        return self.callClosure(closure, arg_count);
    }
    if (callee.isNative()) |native| {
        return self.callNative(native, arg_count);
    }
    self.runtimeError("Can only call functions and classes.", .{});
    return RuntimeError.InvalidCall;
}

/// Setup callframe for closure
fn callClosure(self: *VM, closure: *ObjClosure, arg_count: u8) RuntimeError!void {
    if (closure.function.arity != arg_count) {
        self.runtimeError("Expected {d} arguments but got {d}", .{ closure.function.arity, arg_count });
        return RuntimeError.InvalidCall;
    }
    return self.call(closure, arg_count);
}

/// Setup callframe
fn call(self: *VM, closure: *ObjClosure, arg_count: u8) RuntimeError!void {
    if (self.frameCount == FRAMES_MAX) {
        self.runtimeError("Stack overflow", .{});
        return RuntimeError.InvalidCall;
    }
    var frame = &self.frames[self.frameCount];
    self.frameCount += 1;
    frame.closure = closure;
    frame.ip = closure.function.chunk.code;
    frame.slots = self.stackTop - arg_count - 1;
}

/// Call a native function
fn callNative(self: *VM, native: *ObjNative, arg_count: u8) RuntimeError!void {
    const args = self.stackTop - arg_count;
    const result = native.function(arg_count, args);

    switch (result) {
        .ok => |value| {
            self.stackTop -= arg_count + 1;
            self.push(value);
        },
        .runtime_error => |error_msg| {
            self.runtimeError("{s}", .{error_msg});
            return RuntimeError.NativeFunctionError;
        },
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

inline fn peek(self: *VM, distance: usize) Value {
    return (self.stackTop - 1 - distance)[0];
}

fn clockNative(arg_count: u8, args: [*]Value) lib.NativeResult {
    _ = arg_count; // clock() takes no arguments
    _ = args;

    // Get current time in seconds since epoch
    const timestamp = std.time.timestamp();
    return lib.NativeResult{ .ok = Value{ .Number = @floatFromInt(timestamp) } };
}

fn sqrtNative(arg_count: u8, args: [*]Value) lib.NativeResult {
    if (arg_count != 1) {
        return lib.NativeResult{ .runtime_error = "sqrt() takes exactly 1 argument" };
    }

    const arg = args[0];
    const num = arg.asNumber() orelse {
        return lib.NativeResult{ .runtime_error = "sqrt() argument must be a number" };
    };

    if (num < 0.0) {
        return lib.NativeResult{ .runtime_error = "sqrt() argument must be non-negative" };
    }

    const result = @sqrt(num);
    return lib.NativeResult{ .ok = Value{ .Number = result } };
}

fn absNative(arg_count: u8, args: [*]Value) lib.NativeResult {
    if (arg_count != 1) {
        return lib.NativeResult{ .runtime_error = "abs() takes exactly 1 argument" };
    }

    const arg = args[0];
    const num = arg.asNumber() orelse {
        return lib.NativeResult{ .runtime_error = "abs() argument must be a number" };
    };

    const result = @abs(num);
    return lib.NativeResult{ .ok = Value{ .Number = result } };
}

fn powNative(arg_count: u8, args: [*]Value) lib.NativeResult {
    if (arg_count != 2) {
        return lib.NativeResult{ .runtime_error = "pow() takes exactly 2 arguments" };
    }

    const base_arg = args[0];
    const base = base_arg.asNumber() orelse {
        return lib.NativeResult{ .runtime_error = "pow() base argument must be a number" };
    };

    const exponent_arg = args[1];
    const exponent = exponent_arg.asNumber() orelse {
        return lib.NativeResult{ .runtime_error = "pow() exponent argument must be a number" };
    };

    const result = std.math.pow(f64, base, exponent);
    return lib.NativeResult{ .ok = Value{ .Number = result } };
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
const ObjFunction = lib.ObjFunction;
const ObjClosure = lib.ObjClosure;
const ObjUpvalue = lib.ObjUpvalue;
const ObjNative = lib.ObjNative;
const Table = lib.Table;

fn runtimeError(self: *VM, comptime fmt_str: []const u8, args: anytype) void {
    if (self.debugInfo) |d| {
        // Calculate current instruction offset
        // self.ip points to the NEXT instruction, so subtract 1 for the current opcode
        // If the error is due to an operand, this might need adjustment or more info from the caller.
        const ip_addr = @intFromPtr(self.currentFrame().ip);
        const code_addr = @intFromPtr(self.currentChunk().code);
        const offset = if (ip_addr > code_addr) ip_addr - code_addr - 1 else 0;
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

    // Print stack trace
    var i = self.frameCount - 1;
    stderr.print("== Stack trace ==\n", .{}) catch {};
    while (i >= 0) : (i -= 1) {
        const frame = &self.frames[i];
        const function = frame.closure.function;
        const ip_addr = @intFromPtr(frame.ip);
        const code_addr = @intFromPtr(function.chunk.code);
        const instruction = if (ip_addr > code_addr) ip_addr - code_addr - 1 else 0;

        if (self.debugInfo) |d| {
            if (d.getLine(instruction)) |line| {
                stderr.print("[line {d}] in ", .{line}) catch {};
            } else {
                stderr.print("[line ?] in ", .{}) catch {};
            }
        } else {
            stderr.print("[line ?] in ", .{}) catch {};
        }

        if (function.name) |name| {
            stderr.print("{s}()\n", .{name.chars}) catch {};
        } else {
            stderr.print("script\n", .{}) catch {};
        }
        if (i == 0) break;
    }

    self.resetStack();
}

/// Capture an upvalue pointing to the given stack slot
fn captureUpvalue(self: *VM, local: *Value) !*ObjUpvalue {
    // TODO: In a complete implementation, we would maintain a list of open upvalues
    // to avoid creating duplicates for the same stack slot. For now, we create a new one each time.

    // TODO: For GC implementation later the unmanaged memory version
    return lib.newUpvalue(&self.allocator, local);
}
