pub const Table = struct {
    allocator: *std.mem.Allocator,
    count: usize,
    capacity: usize,
    entries: []Entry,
};
pub const Entry = struct {
    key : []const u8, value: []const u8
}

const std = @import("std");
