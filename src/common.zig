/// Common types and exports
const std = @import("std");

pub const Allocator = std.mem.Allocator;

test "common sanity check" {
    try std.testing.expect(true);
}
