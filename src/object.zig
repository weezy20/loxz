const std = @import("std");
const Allocator = std.mem.Allocator;

/// A heap allocated lox object
pub const Object = struct {
    data: Data,
    allocator: Allocator,

    const Data = union(enum) {
        String: *ObjString,
        // Function: *Function,
        // Class: *Class,
        // Instance: *Instance,
        // Array: *Array,

        pub fn format(self: Data, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            switch (self) {
                .String => |s| try writer.print("Object string: [{s}]", .{s.chars}),
            }
        }
    };

    pub fn format(self: *const Object, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try self.data.format(fmt, options, writer);
    }

    pub fn newString(allocator: Allocator, chars: []const u8) !*Object {
        const obj_string = try ObjString.new(allocator, chars);
        errdefer obj_string.deinit();

        const obj = try allocator.create(Object);
        obj.* = .{
            .allocator = allocator,
            .data = .{ .String = obj_string },
        };
        return obj;
    }
    pub fn newConcatenatedString(allocator: Allocator, strings: []const []const u8) !*Object {
        var total_length: usize = 0;
        for (strings) |s| {
            total_length += s.len;
        }
        const concatenated = try allocator.alloc(u8, total_length);
        errdefer allocator.free(concatenated);

        var offset: usize = 0;
        for (strings) |s| {
            std.mem.copyForwards(u8, concatenated[offset..], s);
            offset += s.len;
        }

        const obj_string = try ObjString.new(allocator, concatenated);
        errdefer obj_string.deinit();

        const obj = try allocator.create(Object);
        obj.* = .{
            .allocator = allocator,
            .data = .{ .String = obj_string },
        };
        return obj;
    }

    pub fn asString(self: *const Object) ?[]const u8 {
        return switch (self.data) {
            .String => |s| s.chars,
            // else => null,
        };
    }
    pub fn objType(self: *const Object) ?[]const u8 {
        return switch (self.data) {
            .String => "string",
            // else => null,
        };
    }

    pub fn deinit(self: *Object) void {
        switch (self.data) {
            .String => |s| s.deinit(),
        }
        self.allocator.destroy(self);
    }
    pub fn isEqual(self: *const Object, other: *const Object) bool {
        // Fast path for same object
        if (self == other) return true;

        // Different object types can't be equal
        if (@as(std.meta.Tag(@TypeOf(self.data)), self.data) !=
            @as(std.meta.Tag(@TypeOf(other.data)), other.data))
            return false;

        // Type-specific comparison
        switch (self.data) {
            .String => |s1| {
                const s2 = other.data.String;
                return std.mem.eql(u8, s1.chars, s2.chars);
            },
            // else => return false,
        }
    }
};
pub const ObjString = struct {
    chars: []const u8,
    allocator: Allocator,

    pub fn new(allocator: Allocator, init: []const u8) !*ObjString {
        const self = try allocator.create(ObjString);
        self.* = .{
            .allocator = allocator,
            .chars = try allocator.dupe(u8, init),
        };
        return self;
    }

    pub fn deinit(self: *ObjString) void {
        self.allocator.free(self.chars);
        self.allocator.destroy(self);
    }
};
