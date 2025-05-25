const std = @import("std");
const Allocator = std.mem.Allocator;

/// A heap allocated lox object
pub const Object = struct {
    data: Data,
    allocator: Allocator,
    next: ?*Object = null,

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
                .String => |s| try writer.print("Object string: [\"{s}\"]", .{s.chars}),
            }
        }
    };

    pub fn format(self: *const Object, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try self.data.format(fmt, options, writer);
    }

    pub fn newString(allocator: Allocator, strings: []const []const u8, intern_table: ?*Table) !struct {
        obj: *Object,
        interned: bool,
    } {
        var obj_string: *ObjString = undefined;
        var interned: bool = false;
        if (strings.len == 1) top: {
            if (intern_table) |t| {
                if (tableFindString(t, strings[0])) |i| {
                    obj_string = i;
                    interned = true;
                    break :top;
                }
            }
            obj_string = try ObjString.init(allocator, strings[0]);
        } else top: {
            var total_length: usize = 0;
            for (strings) |s| {
                total_length += s.len;
            }
            var buf = try allocator.alignedAlloc(
                u8,
                8,
                total_length,
            );
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
        }
        errdefer if (!interned) {
            obj_string.deinit(allocator);
        };

        const obj = try allocator.create(Object);

        obj.* = .{
            .allocator = allocator,
            .data = .{
                .String = if (interned) b: {
                    obj_string.refcount += 1;
                    break :b obj_string;
                } else obj_string,
            },
        };
        if (intern_table) |t| _ = try t.set(obj.data.String, .Nil);

        return .{ .obj = obj, .interned = interned };
    }

    pub fn asString(self: *const Object) ?[]const u8 {
        return switch (self.data) {
            .String => |s| s.chars,
            // else => null,
        };
    }

    pub fn asObjString(self: *const Object) ?*ObjString {
        return switch (self.data) {
            .String => |s| s,
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
            .String => |s| {
                @constCast(s).deinit(self.allocator);
            },
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
                if (s1 == s2) return true; // Fast path for same string
                std.debug.print("Intern comparison failed", .{});
                return ObjString.eql(s1, s2);
            },
            // else => return false,
        }
    }
};

pub const ObjString = struct {
    chars: []align(8) const u8,
    hash: u64,
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
        if (self.refcount > 1) {
            self.refcount -= 1;
            return;
        }
        allocator.free(self.chars);
        allocator.destroy(self);
    }
};

test "Object" {
    const t = std.testing;
    try t.expect(@sizeOf(Object) == 32);
    try t.expect(@sizeOf(ObjString) == 32);
}

// const hasher = @import("table.zig").loxHash;
const hasher = @import("common.zig").hasher;
const Table = @import("table.zig").Table;
const tableFindString = @import("table.zig").tableFindString;
