/// Disassemble a single instruction and return next offset
pub fn disassembleInstruction(chunk: *const Chunk, offset: usize, debugInfo: ?*DebugInfo) usize {
    const allocator = std.heap.page_allocator;
    dbg("0x{0X:0>4}\t", .{chunk.code[offset]});
    const instruction = chunk.code[offset];

    const source = if (debugInfo) |d| blk: {
        const location = d.getLocation(offset) catch |err| {
            std.debug.print("Error getting location: {}\n", .{err});
            break :blk EMPTY;
        };

        const str = std.fmt.allocPrint(allocator, "(line:{d} col:{d})", .{ location.line, location.column }) catch DEBUG_ALLOC_FAILED;

        break :blk str;
    } else EMPTY;

    defer {
        // Free source if it was allocated
        if (source.ptr != EMPTY.ptr and source.ptr != DEBUG_ALLOC_FAILED.ptr) {
            allocator.free(source);
        }
    }

    switch (@as(OpCode, @enumFromInt(instruction))) {
        .RETURN => return simpleInstruction("OP_RETURN", offset, source),
        .CONSTANT => return constantInstruction("OP_CONSTANT", chunk, offset, source),
    }
}

fn simpleInstruction(name: []const u8, offset: usize, source: []const u8) usize {
    dbg("{s}\t{1s}\n", .{ name, source });
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize, source: []const u8) usize {
    const constant_index = chunk.code[offset + 1]; // Skip 1 byte for OP_CONSTANT
    const constant_value = chunk.constants.get(constant_index) catch |err| {
        std.debug.panic("Error getting constant: {}", .{err});
    }; // Look up the constant with bounds check
    const stdout = std.io.getStdErr().writer();
    stdout.print("{0s} (const idx : {1d}) [{2}]\t{3s}\n", .{ name, constant_index, constant_value, source }) catch {
        dbg("Failed to print constant", .{});
    };
    return offset + 2;
}

/// DebugInfo for chunk bytecode
pub const Location = struct {
    /// Offset in the bytecode of a given chunk
    offset: usize,
    /// Source line number generating the bytecode at offset
    line: usize,
    /// Column number generating the bytecode at offset
    column: usize,
};

// Because our chunk writes instructions as a byte, each byte in chunk.code is at an index which can be traced back to a location
// So we can use the byte-location as an index and thus locations[idx] points to each bytecode instruction or constant from source file
/// DebugInfo created for a chunk tracks source code locations corresponding to bytecode instructions
pub const DebugInfo = struct {
    /// Source line location indexed by bytecode offset
    locations: std.ArrayList(Location),
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !DebugInfo {
        const locations = try std.ArrayList(Location).initCapacity(allocator, capacity);
        return DebugInfo{
            .locations = locations,
        };
    }

    /// Get location for a given bytecode offset
    pub fn getLocation(self: *DebugInfo, offset: usize) !Location {
        if (offset >= self.locations.items.len) {
            return error.OutOfBounds;
        }
        std.debug.assert(offset == self.locations.items[offset].offset);
        return self.locations.items[offset];
    }

    pub fn deinit(self: *DebugInfo) void {
        self.locations.deinit();
    }
};
// If chunk.write() succeeds, we update the DebugInfo.locations[chunk.count] with the recently consumed location

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("opcode.zig").OpCode;
const dbg = std.debug.print;
const EMPTY = "";
const DEBUG_ALLOC_FAILED = "Debug Allocation Failed";
