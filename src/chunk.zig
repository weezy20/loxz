const std = @import("std");
const Allocator = std.mem.Allocator;

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
    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
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

    try std.testing.expect(chunk.count == 0);
    try std.testing.expect(chunk.capacity == 0);
    try std.testing.expect(chunk.code[0] == undefined);

    // Test Chunk type size - 24 bytes
    try std.testing.expect(@sizeOf(Chunk) == 3 * @sizeOf(usize));
}
