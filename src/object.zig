const std = @import("std");
const Allocator = std.mem.Allocator;

/// A heap allocated lox object
pub const Object = struct {
    data: Data,
    allocator: Allocator,
    next: ?*Object = null,

    const Data = union(enum) {
        String: *ObjString,
        Function: *ObjFunction,
        Native: *ObjNative,
        Closure: *ObjClosure,
        Upvalue: *ObjUpvalue,

        pub fn format(self: Data, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = options;
            switch (self) {
                .String => |s| {
                    if (std.mem.eql(u8, fmt, "s")) { // Simple mode: `{s}`
                        try writer.writeAll(s.chars);
                    } else { // Debug mode: `{}`
                        try writer.print("<ObjString: [\"{s}\"]>", .{s.chars});
                    }
                },
                .Function => |f| {
                    if (std.mem.eql(u8, fmt, "s")) { // Simple mode: `{s}`
                        if (f.name) |n|
                            try writer.print("<fn: {s}>", .{n.chars})
                        else
                            try writer.print("<script>", .{});
                    } else { // Debug mode: `{}`
                        try writer.print("<ObjFunction: [name: {s}, arity: {}, chunk: {}]>", .{
                            if (f.name) |n| n.chars else "<script>",
                            f.arity,
                            f.chunk,
                        });
                    }
                },
                .Native => |n| {
                    if (std.mem.eql(u8, fmt, "s")) { // Simple mode: `{s}`
                        try writer.print("<native fn>", .{});
                    } else { // Debug mode: `{}`
                        try writer.print("<ObjNative: [name: {s}]>", .{n.name.chars});
                    }
                },
                .Closure => |c| {
                    if (std.mem.eql(u8, fmt, "s")) { // Simple mode: `{s}`
                        try writer.print("<closure: {}>", .{c.function});
                    } else { // Debug mode: `{}`
                        try writer.print("<ObjClosure: [function: {}]>", .{c.function});
                    }
                },
                .Upvalue => |u| {
                    if (std.mem.eql(u8, fmt, "s")) { // Simple mode: `{s}`
                        try writer.print("<upvalue>", .{});
                    } else { // Debug mode: `{}`
                        try writer.print("<ObjUpvalue: [location: {}]>", .{u.location});
                    }
                },
            }
        }
    };

    pub fn format(self: *const Object, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try self.data.format(fmt, options, writer);
    }
    /// Allocate a new ObjFunction using the VM's allocator and add it to the VM's object list.
    pub fn newFunction(
        vm: *VM,
        name: ?*ObjString,
        arity: ?u32,
    ) !*Object {
        const allocator = vm.allocator;
        const obj_function = try ObjFunction.init(allocator);
        errdefer obj_function.deinit(allocator);

        obj_function.* = .{
            .name = if (name) |n| n.clone() else null,
            .arity = arity orelse 0,
            .upvalue_count = 0,
            .chunk = Chunk.init(&vm.allocator),
        };

        // Create the Object wrapper
        const obj = try allocator.create(Object);
        errdefer allocator.destroy(obj);

        obj.* = .{
            .allocator = allocator,
            .data = .{
                .Function = obj_function,
            },
        };

        vm.addObj(obj);
        return obj;
    }

    pub fn newString(vm: *VM, strings: []const []const u8, intern_table: ?*Table) !struct {
        obj: *Object,
        interned: bool,
    } {
        const allocator = vm.allocator;
        var obj_string: *ObjString = undefined;
        var interned: bool = false;

        // single string
        if (strings.len == 1) top: {
            if (intern_table) |t| {
                if (tableFindString(t, strings[0])) |i| {
                    obj_string = i;
                    interned = true;
                    break :top;
                }
            }
            obj_string = try ObjString.init(allocator, strings[0]);
            errdefer obj_string.deinit(allocator);
        }
        // concatenated strings
        else top: {
            var total_length: usize = 0;
            for (strings) |s| {
                total_length += s.len;
            }

            var buf = try allocator.alignedAlloc(u8, 8, total_length);
            defer allocator.free(buf);

            var offset: usize = 0;
            for (strings) |s| {
                std.mem.copyForwards(u8, buf[offset..], s);
                offset += s.len;
            }

            if (intern_table) |t| {
                if (tableFindString(t, buf)) |i| {
                    obj_string = i;
                    interned = true;
                    break :top;
                }
            }
            obj_string = try ObjString.init(allocator, buf);
            errdefer obj_string.deinit(allocator);
        }

        // Create the Object wrapper
        const obj = try allocator.create(Object);
        errdefer allocator.destroy(obj);

        obj.* = .{
            .allocator = allocator,
            .data = .{
                .String = if (interned) b: {
                    obj_string.refcount += 1;
                    break :b obj_string;
                } else obj_string,
            },
        };

        // Add to intern table if provided
        if (intern_table) |t| {
            if (t.set(obj.data.String, .Nil)) |_| {} else |err| {
                if (!interned) {
                    obj.data.String.deinit(allocator);
                    allocator.destroy(obj);
                }
                return err;
            }
        }
        // Even if the string is interned, the Object object is a heap allocation and must be tracked.
        vm.addObj(obj);
        return .{ .obj = obj, .interned = interned };
    }

    pub fn newNative(vm: *VM, name: *ObjString, function: NativeFn) !*Object {
        const allocator = vm.allocator;

        const obj_native = try allocator.create(ObjNative);
        errdefer allocator.destroy(obj_native);

        obj_native.* = .{
            .name = name,
            .function = function,
        };

        const obj = try allocator.create(Object);
        errdefer allocator.destroy(obj);

        obj.* = .{
            .allocator = allocator,
            .data = .{
                .Native = obj_native,
            },
        };

        vm.addObj(obj);
        return obj;
    }

    /// Allocate a new ObjClosure using the VM's allocator and add it to the VM's object list.
    pub fn newClosure(vm: *VM, function: *ObjFunction) !*Object {
        const allocator = vm.allocator;

        const obj_closure = try newObjClosure(&allocator, function);
        errdefer {
            obj_closure.deinit(allocator);
        }

        const obj = try allocator.create(Object);
        errdefer allocator.destroy(obj);

        obj.* = .{
            .allocator = allocator,
            .data = .{
                .Closure = obj_closure,
            },
        };

        vm.addObj(obj);
        return obj;
    }

    /// Allocate a new ObjUpvalue using the VM's allocator and add it to the VM's object list.
    pub fn newUpvalue(vm: *VM, location: *Value) !*Object {
        const allocator = vm.allocator;

        const obj_upvalue = try allocator.create(ObjUpvalue);
        errdefer allocator.destroy(obj_upvalue);

        obj_upvalue.* = .{
            .location = location,
        };

        const obj = try allocator.create(Object);
        errdefer allocator.destroy(obj);

        obj.* = .{
            .allocator = allocator,
            .data = .{
                .Upvalue = obj_upvalue,
            },
        };

        vm.addObj(obj);
        return obj;
    }

    pub fn asString(self: *const Object) ?[]const u8 {
        return switch (self.data) {
            .String => |s| s.chars,
            else => null,
        };
    }

    pub fn asObjString(self: *const Object) ?*ObjString {
        return switch (self.data) {
            .String => |s| s,
            else => null,
        };
    }

    pub fn asFunction(self: *const Object) ?*ObjFunction {
        return switch (self.data) {
            .Function => |f| f,
            else => null,
        };
    }

    pub fn asNative(self: *const Object) ?*ObjNative {
        return switch (self.data) {
            .Native => |n| n,
            else => null,
        };
    }

    pub fn asClosure(self: *const Object) ?*ObjClosure {
        return switch (self.data) {
            .Closure => |c| c,
            else => null,
        };
    }
    pub fn deinit(self: *Object) void {
        switch (self.data) {
            .String => |s| {
                s.deinit(self.allocator);
            },
            .Function => |f| {
                f.deinit(self.allocator);
            },
            .Native => |n| {
                n.deinit(self.allocator);
            },
            .Closure => |c| {
                c.deinit(self.allocator);
            },
            .Upvalue => |u| {
                u.deinit(self.allocator);
            },
        }
        self.allocator.destroy(self);
    }

    pub fn isEqual(self: *const Object, other: *const Object) bool {
        // Fast path for same object (interned strs)
        if (self == other) return true;
        // Different object types can't be equal
        if (@as(std.meta.Tag(@TypeOf(self.data)), self.data) !=
            @as(std.meta.Tag(@TypeOf(other.data)), other.data))
            return false;

        // Type-specific comparison
        switch (self.data) {
            .String => |s1| {
                const s2 = other.data.String;
                if (s1 == s2) return true; // Fast path for same string
                return ObjString.eql(s1, s2);
            },
            .Function, .Closure => {
                return false;
            },
            .Native => |n1| {
                const n2 = other.data.Native;
                // Compare function pointers for equality
                return n1.function == n2.function;
            },
            .Upvalue => {
                // Upvalues are compared by identity, not value
                return false;
            },
        }
    }
};

pub const ObjString = struct {
    chars: []align(8) const u8,
    hash: u64,
    // U32 could've been used here but 4 bytes would've been added as padding anyway
    // due to `chars` being 8-byte aligned
    refcount: usize = 0,

    pub fn eql(a: *const ObjString, b: *const ObjString) bool {
        // On the rare chance that two strings are different but have the same hash,
        // At least we can shortcircuit the comparison using the hashcode check first
        return a.hash == b.hash and std.mem.eql(u8, a.chars, b.chars);
    }

    pub fn init(allocator: Allocator, from: []const u8) !*ObjString {
        // const string_chars = try allocator.dupe(u8, chars);
        // u8 alignment is required for clhash
        const obj_str_chars = try allocator.alignedAlloc(u8, 8, from.len);
        errdefer allocator.free(obj_str_chars);
        @memcpy(obj_str_chars, from);
        const obj_str = try allocator.create(ObjString);
        obj_str.* = ObjString{
            .chars = obj_str_chars,
            .hash = hasher(obj_str_chars),
            .refcount = 1,
        };
        return obj_str;
    }
    /// Deallocate the backing array
    pub fn deinit(self: *ObjString, allocator: Allocator) void {
        std.debug.assert(self.refcount != 0);
        if (self.refcount > 1) {
            self.refcount -= 1;
            return;
        }
        allocator.free(self.chars);
        allocator.destroy(self);
    }
    /// Clone the string object. Cheap, just bumps the refcount.
    pub fn clone(self: *ObjString) *ObjString {
        self.refcount += 1; // Increment refcount
        return self;
    }
};
pub const ObjFunction = struct {
    name: ?*ObjString = null,
    arity: u32,
    upvalue_count: u16,
    chunk: Chunk,

    /// Create and return an undefined function object.
    pub inline fn init(allocator: Allocator) !*ObjFunction {
        return allocator.create(ObjFunction);
    }
    /// Deallocate the function object and its chunk
    pub fn deinit(self: *ObjFunction, allocator: Allocator) void {
        self.chunk.deinit();
        if (self.name) |n| n.deinit(allocator);
        allocator.destroy(self);
    }
};

/// Create a new ObjFunction without Object wrapper - used by compiler
/// The allocator should be the same one used to deinit this objfunction which means it accepts the VM.allocator
pub fn newFunction(allocator: *const Allocator, name: ?*ObjString, arity: ?u32) !*ObjFunction {
    const function = try allocator.create(ObjFunction);
    errdefer allocator.destroy(function);

    function.* = .{
        .name = if (name) |n| n.clone() else null,
        .arity = arity orelse 0,
        .upvalue_count = 0,
        .chunk = Chunk.init(allocator),
    };

    return function;
}

/// Create a new ObjClosure without Object wrapper - used by compiler and VM
/// The allocator should be the same one used to deinit this objclosure which means it accepts the VM.allocator
pub fn newObjClosure(allocator: *const Allocator, function: *ObjFunction) !*ObjClosure {
    const upvalues = try allocator.create(Upvalues);
    errdefer allocator.destroy(upvalues);

    upvalues.* = Upvalues.init(allocator.*);

    const closure = try allocator.create(ObjClosure);

    closure.* = .{
        .function = function,
        .upvalues = upvalues,
        .upvalue_count = function.upvalue_count,
    };

    return closure;
}

pub const ObjNative = struct {
    name: *ObjString,
    function: NativeFn,

    /// Deallocate the native object (currently just destroys the struct itself)
    pub fn deinit(self: *ObjNative, allocator: Allocator) void {
        // Note: We don't deinit the name since it's owned by the string intern table
        allocator.destroy(self);
    }
};

/// Native function result type - allows native functions to signal errors
pub const NativeResult = union(enum) {
    ok: Value,
    runtime_error: []const u8, // Error message
};

pub const NativeFn = *const fn (arg_count: u8, args: [*]Value) NativeResult;

pub const ObjClosure = struct {
    function: *ObjFunction,
    upvalues: *Upvalues,
    // Capped to u16 but u16 can't represent u16 max + 1.
    upvalue_count: u32,

    /// Deallocate the closure object (doesn't destroy the underlying function)
    pub fn deinit(self: *ObjClosure, allocator: Allocator) void {
        self.upvalues.deinit();
        allocator.destroy(self.upvalues);
        allocator.destroy(self);
    }
};

pub const ObjUpvalue = struct {
    location: *Value,

    /// Deallocate the upvalue object
    pub fn deinit(self: *ObjUpvalue, allocator: Allocator) void {
        allocator.destroy(self);
    }
};

// const hasher = @import("table.zig").loxHash;
const hasher = @import("common.zig").hasher;
const Table = @import("table.zig").Table;
const tableFindString = @import("table.zig").tableFindString;
const VM = @import("vm.zig").VM;
const Chunk = @import("chunk.zig").Chunk;
const Value = @import("value.zig").Value;
const Upvalues = @import("compiler.zig").Upvalues;
