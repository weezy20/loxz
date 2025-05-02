pub const OpCode = enum {
    OP_RETURN,
};

/// A bytecode chunk
pub const Chunk = struct {
    /// Bytes used
    count: usize,
    /// Bytes allocated
    capacity: usize,
    /// Many-pointer to chunk data
    code: [*]u8,
};

// Alternatively, this suffices as well
// pub const Chunk2 = std.ArrayList(u8);

const std = @import("std");
