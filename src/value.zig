/// Values in Lox
pub const Value = union(enum) {
    Number: f64,
    String: []const u8,
    Bool: bool,
    Obj: *Object,
    Nil,

    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .Number => try writer.print("Number {d}", .{self.Number}),
            .String => try writer.print("String \"{s}\"", .{self.String}),
            .Bool => |b| try writer.print("Boolean {any}", .{b}),
            .Nil => try writer.writeAll("Nil"),
            .Obj => try writer.print("{s}", .{self.Obj}),
        }
    }
    pub fn asNumber(value: *const Value) ?f64 {
        return switch (value.*) {
            .Number => |num| num,
            else => null,
        };
    }
    pub fn isString(value: *const Value) ?[]const u8 {
        return switch (value.*) {
            .String => |str| str,
            .Obj => |obj| {
                return obj.asString();
            },
            else => null,
        };
    }
    pub fn isBool(value: *const Value) ?bool {
        return switch (value.*) {
            .Bool => |b| b,
            // Dynamic typing, thus:
            .Nil => false,
            else => null,
        };
    }
    pub inline fn isEqual(self: *const Value, other: *const Value) bool {
        // if (self == other) return true; // Warning: f64.NaN == f64.NaN because of this
        return switch (self.*) {
            .Number => |n| switch (other.*) {
                .Number => |m| n == m,
                .Bool => |b| (n == 0 and !b) or (n == 1 and b),
                else => false,
            },
            .Bool => |b| switch (other.*) {
                .Bool => |b2| b == b2,
                .Number => |n| (n == 0 and !b) or (n == 1 and b),
                .Nil => !b,
                else => false,
            },
            .Nil => switch (other.*) {
                .Nil => true,
                .Bool => |b| !b,
                else => false,
            },
            .String => |s| switch (other.*) {
                .String => |other_string| std.mem.eql(u8, s, other_string),
                else => false,
            },
            .Obj => |o| switch (other.*) {
                .Obj => |other_obj| o == other_obj or o.isEqual(other_obj),
                else => false,
            },
        };
    }
    /// Compare value types not values. For values use `isEqual`.
    pub fn isSameType(self: *const Value, other: *const Value) bool {
        switch (.{ self.*, other.* }) {
            // Both are numbers
            .{ .Number, .Number } => return true,
            // Both are strings
            .{ .String, .String } => return true,
            // Both are booleans
            .{ .Bool, .Bool } => return true,
            // Both are nil
            .{ .Nil, .Nil } => return true,
            // Both are objects
            .{ .Obj, .Obj } => self.Obj.objType() == other.Obj.objType(),
            else => return false,
        }
    }
    pub fn isObject(self: *const Value) ?*Object {
        if (self.* == .Obj) {
            return self.Obj;
        }
        return null;
    }
    pub fn asObjString(self: *const Value) ?*ObjString {
        if (self.isObject()) |obj| {
            if (std.meta.activeTag(obj.data) == .String) {
                return obj.data.String;
            }
        }
        return null;
    }
    pub fn isFalsey(self: *const Value) bool {
        return switch (self.*) {
            .Nil => true,
            .Bool => |b| !b,
            .Number => |n| n == 0.0 or std.math.isNaN(n),
            else => false,
        };
    }
};

/// Value Arrays
pub const ValueArray = struct {
    values: []Value,
    count: usize,
    capacity: usize,

    pub fn init() !ValueArray {
        return ValueArray{
            .values = &[_]Value{},
            .count = 0,
            .capacity = 0,
        };
    }

    pub fn deinit(self: *ValueArray, allocator: std.mem.Allocator) void {
        allocator.free(self.values);
        self.* = undefined;
    }

    pub fn write(
        self: *ValueArray,
        value: Value,
        allocator: std.mem.Allocator,
    ) !void {
        if (self.count >= self.capacity) {
            const new_capacity = if (self.capacity == 0) 8 else self.capacity * 2;
            const new_values: []Value = try allocator.realloc(self.values, new_capacity);

            self.values = new_values;
            self.capacity = new_capacity;
        }
        std.debug.assert(self.count < self.capacity);
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn get(self: *const ValueArray, index: usize) !Value {
        if (index >= self.count) {
            return error.ValueIndexOutOfBounds;
        }
        return self.values[index];
    }
};

const std = @import("std");
const lib = @import("root.zig");
const Object = lib.Object;
const ObjString = lib.ObjString;
