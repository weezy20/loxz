/// Values in Lox
pub const Value = union(enum) {
    Number: f64,
    String: []const u8,
    Bool: bool,
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
            .Bool => try writer.print("Boolean {s}", .{if (self.Bool) "true" else "false"}),
            .Nil => try writer.writeAll("Nil"),
        }
    }
    pub fn isNumber(value: *const Value) ?f64 {
        return switch (value.*) {
            .Number => |num| num,
            else => null,
        };
    }
    pub fn isString(value: *const Value) ?[]const u8 {
        return switch (value.*) {
            .String => |str| str,
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
    // pub fn isEqual(self: *const Value, other: *const Value) bool {
    //     if (@intFromEnum(self.*) != @intFromEnum(other.*)) {
    //         return false;
    //     }
    //     return switch (self.*) {
    //         .Number => self.Number == other.Number,
    //         .String => std.mem.eql(u8, self.String, other.String),
    //         .Bool => self.Bool == other.Bool,
    //         .Nil => true, // Nil == Nil is true
    //     };
    // }
    pub fn isEqual(self: *const Value, other: *const Value) bool {
        return std.meta.eql(self.*, other.*);
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
