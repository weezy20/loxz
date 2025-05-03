/// Commonly used types and exports
const std = @import("std");
pub const expect = std.testing.expect;

pub const Allocator = std.mem.Allocator;

test "common sanity check" {
    try expect(true);
}
