const std = @import("std");
const common = @import("common.zig");
const Allocator = common.Allocator;
const expect = common.expect;

/// A bytecode chunk
pub const Chunk = struct {
    /// Bytes used
    count: usize,
    /// Bytes allocated
    capacity: usize,
    /// Many-pointer to chunk data
    code: [*]u8,

    /// Initialize a Chunk
    pub fn init() Chunk {
        return Chunk{
            .count = 0,
            .capacity = 0,
            .code = undefined,
        };
    }
    /// Free the Chunk
    pub fn deinit(self: *Chunk, allocator: Allocator) void {
        if (self.capacity > 0) {
            allocator.free(self.code[0..self.capacity]);
        }
        self.* = init();
    }

    /// Write a byte to the chunk, growing if necessary
    pub fn write(self: *Chunk, byte: u8, allocator: Allocator) !void {
        if (self.count >= self.capacity) {
            try self.grow(allocator);
        }
        self.code[self.count] = byte;
        self.count += 1;
    }

    // All operations require explicit allocator
    pub fn grow(self: *Chunk, allocator: Allocator) !void {
        const new_capacity = if (self.capacity == 0) 8 else self.capacity * 2;
        const new_mem = try allocator.alloc(u8, new_capacity);

        // Copy existing data if needed
        if (self.count > 0) {
            @memcpy(new_mem[0..self.count], self.code[0..self.count]);
        }

        // Free old memory if it existed
        if (self.capacity > 0) {
            allocator.free(self.code[0..self.capacity]);
        }

        self.code = new_mem.ptr;
        self.capacity = new_capacity;
    }
};

test "Chunk initialization" {
    // Test Chunk initialization
    var chunk = Chunk.init();
    const allocator = std.testing.allocator;
    defer chunk.deinit(allocator);

    try expect(chunk.count == 0);
    try expect(chunk.capacity == 0);
    try expect(chunk.code[0] == undefined);

    // Test Chunk type size - 24 bytes
    try expect(@sizeOf(Chunk) == 3 * @sizeOf(usize));
}

test "Chunk grow and deinit" {
    var chunk = Chunk.init();
    const allocator = std.testing.allocator;

    // Initial state checks
    try expect(chunk.count == 0);
    try expect(chunk.capacity == 0);

    // Grow the chunk
    try chunk.grow(allocator);

    // Check after growing
    try expect(chunk.capacity == 8);
    try expect(chunk.count == 0);

    // Write some bytes
    try chunk.write(42, allocator);
    try chunk.write(84, allocator);

    // Check after writing
    try expect(chunk.count == 2);
    try expect(chunk.code[0] == 42);
    try expect(chunk.code[1] == 84);

    // Grow again
    try chunk.grow(allocator);

    // Check after second grow
    try expect(chunk.capacity == 16);
    try expect(chunk.count == 2);
    try expect(chunk.code[0] == 42);
    try expect(chunk.code[1] == 84);

    chunk.deinit(allocator);
    // Check state after deinitialization
    try expect(chunk.count == 0);
    try expect(chunk.capacity == 0);
    try expect(chunk.code == undefined);
}

test "chunk sanity check" {
    try expect(true);
}
