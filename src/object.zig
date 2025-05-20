const std = @import("std");
const Allocator = std.mem.Allocator;

/// A heap allocated lox object
pub const Object = union(enum) {
    /// A lox string
    String: ObjString,
    // /// A lox function
    // Function: *Function,
    // /// A lox class
    // Class: *Class,
    // /// A lox instance
    // Instance: *Instance,
    // /// A lox array
    // Array: *Array,

    pub fn format(self: *const Object, writer: anytype) !void {
        switch (self.*) {
            .String => |s| try writer.print("\"Object [string: {s}]\"", .{s.chars}),
        }
    }

    pub fn newString(allocator: Allocator, init: []const u8) !*Object {
        const obj = try allocator.create(Object);
        obj.* = Object{ .String = try ObjString.new(allocator, init) };
        return obj;
    }

    pub fn deinit(self: *Object) void {
        switch (self.*) {
            .String => |s| s.deinit(),
        }
    }
};

pub const ObjString = struct {
    /// The heap allocated string slice
    chars: []const u8,
    allocator: Allocator,

    pub fn new(allocator: Allocator, init: []const u8) !ObjString {
        const chars = try allocator.alloc(u8, init.len);
        std.mem.copyForwards(u8, chars, init);
        return ObjString{
            .chars = chars,
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *ObjString) void {
        self.allocator.free(self.chars);
        self.* = undefined; // Prevent's use after free during compilation
    }
};
