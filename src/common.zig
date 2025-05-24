const lib = @import("root.zig");
/// Default hasher for keys in the table
// pub const hasher = lib.clHash;
pub const hasher = lib.loxHash;
