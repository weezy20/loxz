/// Disassemble a single instruction and return next offset
pub fn disassembleInstruction(chunk: *const Chunk, byte_offset: usize, debugInfo: ?*DebugInfo, allocator: std.mem.Allocator) usize {
    dbg("0x{0X:0>4}\t", .{chunk.code[byte_offset]});
    const instruction = chunk.code[byte_offset];

    const src_info = if (debugInfo) |d| blk: {
        const offset = switch (@as(OpCode, @enumFromInt(instruction))) {
            // Because for constants, the location info is tied to the constant offset rather than the constant OP offset
            // Check out the implementation of `writeConstant` and especially the Location struct where offset is set to `self.count + 1`
            // +1 for skipping opcode
            .CONSTANT, .CONSTANT_LONG => byte_offset + 1,
            else => byte_offset,
        };
        const location: Location = if (d.getLocation(offset)) |loc| loc else {
            break :blk EMPTY;
        };

        const str = std.fmt.allocPrint(allocator, "(line:{d} col:{d}-{d})", .{ location.line, location.start_column, location.end_column }) catch DEBUG_ALLOC_FAILED;

        break :blk str;
    } else EMPTY;

    defer {
        // Free source if it was allocated
        if (src_info.ptr != EMPTY.ptr and src_info.ptr != DEBUG_ALLOC_FAILED.ptr) {
            allocator.free(src_info);
        }
    }

    switch (@as(OpCode, @enumFromInt(instruction))) {
        .RETURN => return simpleInstruction("OP_RETURN", byte_offset, src_info),
        .CONSTANT => return constantInstruction("OP_CONSTANT", chunk, byte_offset, src_info),
        // TODO: Separate this out to constantLongInstruction
        .CONSTANT_LONG => return constantLongInstruction("OP_CONSTANT_LONG", chunk, byte_offset, src_info),
    }
}

fn simpleInstruction(name: []const u8, offset: usize, src_info: []const u8) usize {
    dbg("{s}\t{1s}\n", .{ name, src_info });
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize, src_info: []const u8) usize {
    const constant_index = chunk.code[offset + 1]; // Skip 1 byte for OP_CONSTANT
    const constant_value = chunk.constants.get(constant_index) catch |err| {
        std.debug.panic("Error getting constant: {}", .{err});
    }; // Look up the constant with bounds check
    const stdout = std.io.getStdErr().writer();
    stdout.print("{0s} (const idx : {1d}) [{2}]\t{3s}\n", .{ name, constant_index, constant_value, src_info }) catch {
        dbg("Failed to print constant", .{});
    };
    return offset + 2;
}

fn constantLongInstruction(name: []const u8, chunk: *const Chunk, offset: usize, src_info: []const u8) usize {
    const constant_index: u24 =
        (@as(u24, chunk.code[offset + 1]) << 16) |
        (@as(u24, chunk.code[offset + 2]) << 8) |
        @as(u24, chunk.code[offset + 3]);

    const constant_value = chunk.constants.get(constant_index) catch |err| {
        std.debug.panic("Error getting constant at index {d}: {}", .{ constant_index, err });
    };

    const stdout = std.io.getStdErr().writer();
    stdout.print("{0s} (const idx : {1d}) [{2}]  {3s}\n", .{
        name, constant_index, constant_value, src_info,
    }) catch {
        dbg("Failed to print constant", .{});
    };

    return offset + 4; // 1 for opcode, 3 for u24 index
}

/// Location for chunk bytecode
/// Used by write functions when creating bytecode for a given chunk
pub const Location = struct {
    /// Offset in the bytecode of a given chunk
    offset: usize,
    /// Source line number generating the bytecode at offset
    line: usize,
    /// Column number generating the bytecode at offset
    start_column: usize,
    /// End column number generating the bytecode at offset
    end_column: usize,
};

/// Represents a run of instructions from the same line
const LineRun = struct {
    /// Starting offset of this run
    start_offset: usize,
    /// Number of instructions in this run
    length: usize,
    /// Source line number
    line: usize,
};

/// Column information for an instruction, part of a `LineRun
const ColumnSpan = struct {
    /// Bytecode offset of the instruction in a chunk
    offset: usize,
    /// Span start
    start_column: usize,
    /// Span end
    end_column: usize,
};

// Because our chunk writes instructions as a byte, each byte in chunk.code is at an index which can be traced back to a location
// So we can use the byte-location as an index and thus locations[idx] points to each bytecode instruction or constant from source file
/// DebugInfo created for a chunk tracks source code locations corresponding to bytecode instructions
pub const DebugInfo = struct {
    /// Compressed line information
    line_runs: std.ArrayList(LineRun),
    /// Source line location indexed by bytecode offset
    col_spans: std.ArrayList(ColumnSpan),

    pub const InitCapacity = struct {
        /// Initial capacity for line runs
        line_capacity: ?usize = null,
        /// Initial capacity for column spans
        col_capacity: ?usize = null,
    };

    /// Initialize `DebugInfo` for a chunk. `line_capacity` and `col_capacity` are optional parameters to
    /// initialize the corresponding arrays based on expected chunk size.
    /// Defaults to 8 bytes if not provided
    pub fn init(allocator: std.mem.Allocator, options: InitCapacity) !DebugInfo {
        const lc = options.line_capacity orelse 8;
        const cc = options.col_capacity orelse 8;
        const line_runs = try std.ArrayList(LineRun).initCapacity(allocator, lc);
        const col_spans = try std.ArrayList(ColumnSpan).initCapacity(allocator, cc);
        return DebugInfo{
            .line_runs = line_runs,
            .col_spans = col_spans,
        };
    }
    /// Free the DebugInfo
    pub fn deinit(self: *DebugInfo) void {
        self.line_runs.deinit();
        self.col_spans.deinit();
    }

    /// Get location for a given bytecode offset
    pub fn getLocation(self: *DebugInfo, offset: usize) ?Location {
        const BIN_SEARCH_THRESHOLD = 50;
        const line_runs = self.line_runs.items;

        // Find line run for containing this offset
        var low: usize = 0;
        var high: usize = line_runs.len;
        var found_run: ?LineRun = null;

        while (low < high) {
            const mid = low + (high - low) / 2;
            const run = line_runs[mid];

            if (offset < run.start_offset) {
                high = mid;
            } else if (offset >= run.start_offset + run.length) {
                low = mid + 1;
            } else {
                found_run = run;
                break;
            }
        }

        const run = found_run orelse return null;

        // Find column info
        const col_spans = self.col_spans.items;

        if (col_spans.len < BIN_SEARCH_THRESHOLD) {
            // Linear search for column info
            for (col_spans) |col| {
                if (col.offset == offset) {
                    return Location{
                        .offset = offset,
                        .line = run.line,
                        .start_column = col.start_column,
                        .end_column = col.end_column,
                    };
                }
            }
        } else {
            // Binary search for column info
            low = 0;
            high = col_spans.len;

            while (low < high) {
                const mid = low + (high - low) / 2;
                const col = col_spans[mid];

                if (offset < col.offset) {
                    high = mid;
                } else if (offset > col.offset) {
                    low = mid + 1;
                } else {
                    return Location{
                        .offset = offset,
                        .line = run.line,
                        .start_column = col.start_column,
                        .end_column = col.end_column,
                    };
                }
            }
        }

        return null;
    }

    /// Get line of source code given a bytecode offset. This is a simpler version of `getLocation`
    pub fn getLine(self: *DebugInfo, offset: usize) ?usize {
        const line_runs = self.line_runs.items;

        // Find line run for containing this offset
        var low: usize = 0;
        var high: usize = line_runs.len;

        while (low < high) {
            const mid = low + (high - low) / 2;
            const run = line_runs[mid];

            if (offset < run.start_offset) {
                high = mid;
            } else if (offset >= run.start_offset + run.length) {
                low = mid + 1;
            } else {
                return run.line;
            }
        }

        return null;
    }

    /// Add a location to DebugInfo (now using compressed format)
    pub fn addLocation(self: *DebugInfo, location: Location) !void {
        // Always add column information
        try self.col_spans.append(.{
            .offset = location.offset,
            .start_column = location.start_column,
            .end_column = location.end_column,
        });

        // Handle line runs compression
        const line_runs = &self.line_runs;
        if (line_runs.items.len > 0) {
            const last_run = &line_runs.items[line_runs.items.len - 1];
            if (last_run.line == location.line) {
                // Extend the current run
                last_run.length += 1;
                return;
            }
        }

        // Start a new run
        try line_runs.append(.{
            .start_offset = location.offset,
            .length = 1,
            .line = location.line,
        });
    }
};

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("opcode.zig").OpCode;
const dbg = std.debug.print;
const EMPTY = "";
const DEBUG_ALLOC_FAILED = "Debug Allocation Failed";
