/// A bytecode chunk
pub const Chunk = struct {
    /// Allocator for managing chunk memory
    allocator: *const Allocator,
    /// Bytes used
    count: usize,
    /// Bytes allocated
    capacity: usize,
    /// Many-pointer to chunk data
    code: [*]u8,
    /// Value Array for the chunk
    constants: ValueArray,

    /// Initialize a Chunk
    pub fn init(allocator: *const Allocator) Chunk {
        return Chunk{
            .allocator = allocator,
            .count = 0,
            .capacity = 0,
            .code = undefined,
            .constants = ValueArray.init() catch @panic("Failed to initialize ValueArray for Chunk"),
        };
    }
    /// Free the Chunk
    pub fn deinit(self: *Chunk) void {
        if (self.capacity > 0) {
            self.allocator.free(self.code[0..self.capacity]);
        }
        self.constants.deinit(self.allocator.*);
        self.* = undefined; // Prevent's use after free during compilation
    }

    /// Write a bytecode to the chunk, with DebugInfo
    pub fn writeWithDebugInfo(self: *Chunk, byte: u8, debugInfo: *DebugInfo, line: usize, span: [2]usize) !void {
        try self.write(byte);
        const location = Location{
            .offset = self.count - 1,
            .line = line,
            .start_column = span[0],
            .end_column = span[1],
        };
        try debugInfo.addLocation(location);
    }

    /// Write a byte to the chunk, growing if necessary
    pub fn write(self: *Chunk, byte: u8) !void {
        if (self.count >= self.capacity) {
            try self.grow();
        }
        self.code[self.count] = byte;
        self.count += 1;
    }

    /// Write a constant to the chunk, uses OP_CONSTANT with 8 bits or OP_CONSTANT_LONG with 24 bits for index
    pub fn writeConstant(self: *Chunk, value: Value, debugInfo: ?*DebugInfo, line: ?usize, span: ?[2]usize) !void {
        if (self.constants.count + 1 >= (1 << 24)) {
            return error.Exceed24BitsIndex;
        }
        // Write the constant to ValueArray
        try self.constants.write(value, self.allocator.*);
        const idx: usize = self.constants.count - 1;
        const const_offset = self.count + 1; // +1 for skipping opcode
        // Write opcode
        if (idx <= 255) {
            try self.write(@intFromEnum(OpCode.CONSTANT));
            try self.write(@as(u8, @intCast(idx))); // Safe: checked <=255
        } else {
            try self.write(@intFromEnum(OpCode.CONSTANT_LONG));
            // Big-endian 24-bit index
            try self.write(@as(u8, @truncate(idx >> 16))); // bits 16-23
            try self.write(@as(u8, @truncate(idx >> 8))); // bits 8-15
            try self.write(@as(u8, @truncate(idx))); // bits 0-7
        }
        // Write debug info if provided
        if (debugInfo) |d| {
            const location = Location{
                .offset = const_offset,
                .line = line orelse 0,
                .start_column = if (span) |s| s[0] else 0,
                .end_column = if (span) |s| s[1] else 0,
            };
            try d.addLocation(location);
        }
    }
    /// Given a `idx` to bytecode OP_CONSTANT or OP_CONSTANT_LONG, return the constant value's index
    /// in the ValueArray. If `idx` doesn't contain a constant opcode, return null.
    pub fn getConstantIdx(self: *const Chunk, idx: usize) ?usize {
        const instruction: OpCode = @enumFromInt(self.code[idx]);
        switch (instruction) {
            .CONSTANT => {
                return @as(usize, self.code[idx + 1]);
            },
            .CONSTANT_LONG => {
                return @as(usize, self.code[idx + 1]) << 16 |
                    @as(usize, self.code[idx + 2]) << 8 |
                    @as(usize, self.code[idx + 3]);
            },
            else => {
                return null;
            },
        }
    }

    /// Grow memory behind the chunk and bump up it's capacity accordingly
    pub fn grow(
        self: *Chunk,
    ) !void {
        const new_capacity = if (self.capacity == 0) 8 else self.capacity * 2;
        const new_mem = try self.allocator.alignedAlloc(u8, @alignOf(u8), new_capacity);

        // Copy existing data if needed
        if (self.count > 0) {
            @memcpy(new_mem[0..self.count], self.code[0..self.count]);
        }

        // Free old memory if it existed
        if (self.capacity > 0) {
            self.allocator.free(self.code[0..self.capacity]);
        }

        self.code = new_mem.ptr;
        self.capacity = new_capacity;
    }

    /// Inspect a chunk
    pub fn disassemble(self: *const Chunk, allocator: std.mem.Allocator, name: ?[]const u8, debugInfo: ?*DebugInfo) !void {
        dbg("=== <{s}> === >>\n", .{name orelse "chunk"});
        var offset: usize = 0;
        while (offset < self.count) : (offset = debug.disassembleInstruction(
            self,
            offset,
            allocator,
            .{ .debugInfo = debugInfo, .prefix = name orelse "CHUNK" },
        )) {}
        if (offset > 0) {
            dbg("=== <{s}> === <<\n", .{name orelse "chunk"});
        }
    }
};

const lib = @import("root.zig");
const std = @import("std");
const dbg = std.debug.print;
const debug = @import("debug.zig");
const ValueArray = @import("value.zig").ValueArray;
const Value = @import("value.zig").Value;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const DebugInfo = debug.DebugInfo;
const Location = debug.Location;
const OpCode = lib.OpCode;
