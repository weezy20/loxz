const lib = @import("root.zig");
const build_options = @import("build_options");
/// Default hasher for keys in the table
// Conditionally use clhash..
pub const hasher = lib.loxHash;
pub var clhasher: ?*const fn (key: []const u8) u64 = lib.ClHash.hash;
