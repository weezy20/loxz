pub const Table = struct {
    allocator: *std.mem.Allocator,
    count: usize,
    capacity: usize,
    entries: []Entry,
};
pub const Entry = struct { key: []const u8, value: []const u8 };

pub fn fastHash(key: []const u8) u64 {
    const random = clhash.get_random_key_for_clhash(0x23a23cf5033c3c81, 0xb3816f6a2c68e530).?;
    return clhash.clhash(random, key.ptr, key.len);
}

const std = @import("std");
const clhash = @cImport({
    @cInclude("clhash.h");
});
