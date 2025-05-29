const lib = @import("root.zig");
const build_options = @import("build_options");
/// Default hasher for keys in the table
// Conditionally use clhash..
pub const hasher = lib.loxHash;
pub const clhasher = lib.ClHash.hash;
