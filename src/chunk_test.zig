test "Chunk initialization" {
    // Test Chunk initialization
    const allocator = std.testing.allocator;
    var chunk = Chunk.init(&allocator);
    defer chunk.deinit();
    try expect(chunk.count == 0);
    try expect(chunk.capacity == 0);
    try expect(chunk.code[0] == undefined);

    // Test Chunk type size - 64 bytes
    try expect(@sizeOf(Chunk) == 64);
}

test "Chunk grow and deinit" {
    const allocator = std.testing.allocator;
    var chunk = Chunk.init(&allocator);

    // Initial state checks
    try expect(chunk.count == 0);
    try expect(chunk.capacity == 0);

    // Grow the chunk
    try chunk.grow();

    // Check after growing
    try expect(chunk.capacity == 8);
    try expect(chunk.count == 0);

    // Write some bytes
    try chunk.write(42);
    try chunk.write(84);

    // Check after writing
    try expect(chunk.count == 2);
    try expect(chunk.code[0] == 42);
    try expect(chunk.code[1] == 84);

    // Grow again
    try chunk.grow();

    // Check after second grow
    try expect(chunk.capacity == 16);
    try expect(chunk.count == 2);
    try expect(chunk.code[0] == 42);
    try expect(chunk.code[1] == 84);

    chunk.deinit();
    // Check state after deinitialization,
    // should fail now that zig runtime can see that deinit sets Chunk = undefined
    // try expect(chunk.count == 0);
    // try expect(chunk.capacity == 0);
    // try expect(chunk.code == undefined);
}

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const expect = std.testing.expect;
