const lib = @import("root.zig");
const build_options = @import("build_options");
/// Default hasher for keys in the table
pub const hasher = lib.loxHash;
/// Use lib.hasClhash to determine if CLHash is available
pub const clhasher = lib.ClHash.hash;
