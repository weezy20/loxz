pub const OpCode = enum {
    OP_RETURN,
};

/// A bytecode chunk
pub const Chunk = struct {
    count: usize, // Bytes used
    capacity: usize, // Bytes allocated
    code: [*]u8, // Many-pointer to chunk data
};
