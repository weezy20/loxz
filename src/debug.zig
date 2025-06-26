const stderr = std.io.getStdErr().writer();

/// Disassemble a single instruction and return next offset
pub fn disassembleInstruction(chunk: *const Chunk, byte_offset: usize, allocator: std.mem.Allocator, opts: struct {
    debugInfo: ?*DebugInfo,
    prefix: []const u8 = "DEBUG INFO",
}) usize {
    dbg("[{0s}]: 0x{1X:0>4}\t", .{ opts.prefix, chunk.code[byte_offset] });
    const instruction = chunk.code[byte_offset];
    const src_info = if (opts.debugInfo) |d| blk: {
        const offset = switch (@as(OpCode, @enumFromInt(instruction))) {
            // Because for constants, the location info is tied to the constant offset rather than the constant OP offset
            // Check out the implementation of `writeConstant` and especially the Location struct where offset is set to `self.count + 1`
            // +1 for skipping opcode
            .CONSTANT, .CONSTANT_LONG => byte_offset + 1,
            else => byte_offset,
        };
        const line = if (d.getLine(offset)) |loc| loc else {
            break :blk EMPTY;
        };

        const str = std.fmt.allocPrint(allocator, "(line:{d})", .{line}) catch DEBUG_ALLOC_FAILED;

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
        .NEGATE => return simpleInstruction("OP_NEGATE", byte_offset, src_info),
        .CONSTANT => return constantInstruction("OP_CONSTANT", chunk, byte_offset, src_info),
        .CONSTANT_LONG => return constantLongInstruction("OP_CONSTANT_LONG", chunk, byte_offset, src_info),
        .ADD => return simpleInstruction("OP_ADD", byte_offset, src_info),
        .SUBTRACT => return simpleInstruction("OP_SUBTRACT", byte_offset, src_info),
        .MULTIPLY => return simpleInstruction("OP_MULTIPLY", byte_offset, src_info),
        .DIVIDE => return simpleInstruction("OP_DIVIDE", byte_offset, src_info),
        .MOD => return simpleInstruction("OP_MOD", byte_offset, src_info),
        .TRUE => return simpleInstruction("OP_TRUE", byte_offset, src_info),
        .FALSE => return simpleInstruction("OP_FALSE", byte_offset, src_info),
        .NIL => return simpleInstruction("OP_NIL", byte_offset, src_info),
        .NOT => return simpleInstruction("OP_NOT", byte_offset, src_info),
        .LESS => return simpleInstruction("OP_LESS", byte_offset, src_info),
        .GREATER => return simpleInstruction("OP_GREATER", byte_offset, src_info),
        .EQUAL => return simpleInstruction("OP_EQUAL", byte_offset, src_info),
        .PRINT => return simpleInstruction("OP_PRINT", byte_offset, src_info),
        .POP => return simpleInstruction("OP_POP", byte_offset, src_info),
        .SWITCH_COMP => return simpleInstruction("OP_SWITCH_COMP", byte_offset, src_info),
        .SWITCH_VAL => return simpleInstruction("OP_SWITCH_VAL", byte_offset, src_info),
        .DEFINE_GLOBAL => return constantU16Instruction("OP_DEFINE_GLOBAL", chunk, byte_offset, src_info),
        .GET_GLOBAL => return constantU16Instruction("OP_GET_GLOBAL", chunk, byte_offset, src_info),
        .SET_GLOBAL => return constantU16Instruction("OP_SET_GLOBAL", chunk, byte_offset, src_info),
        .GET_LOCAL => return U16Instruction("OP_GET_LOCAL", chunk, byte_offset, src_info),
        .SET_LOCAL => return U16Instruction("OP_SET_LOCAL", chunk, byte_offset, src_info),
        .JUMP => return jumpInstruction("OP_JUMP", .POSITIVE, chunk, byte_offset, src_info),
        .JUMP_IF_FALSE => return jumpInstruction("OP_JUMP_IF_FALSE", .POSITIVE, chunk, byte_offset, src_info),
        .LOOP => return jumpInstruction("OP_LOOP", .NEGATIVE, chunk, byte_offset, src_info),
    }
}

fn simpleInstruction(name: []const u8, offset: usize, src_info: []const u8) usize {
    dbg("{s}\t{1s}\n", .{ name, src_info });
    return offset + 1;
}
/// Instruction followed by a u16 constant index
fn constantU16Instruction(name: []const u8, chunk: *const Chunk, offset: usize, src_info: []const u8) usize {
    const constant_index = chunk.getConstantIdx(offset).?; // Skips 1 byte for OP_DEFINE_GLOBAL or OP_GET_GLOBAL
    const constant_val = chunk.constants.get(constant_index) catch |err| {
        std.debug.panic("Error getting constant at index {d}: {}", .{ constant_index, err });
    };
    stderr.print("{0s} (const idx : {1d}_u16) [{2}]\t{3s}\n", .{ name, constant_index, constant_val, src_info }) catch |err| {
        dbg("Failed to print constant: {}", .{err});
    };
    return offset + 3; // 1 for opcode, 2 for u16 index
}

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize, src_info: []const u8) usize {
    const constant_index = chunk.getConstantIdx(offset).?; // Skips 1 byte for OP_CONSTANT
    const constant_value = chunk.constants.get(constant_index) catch |err| {
        std.debug.panic("Error getting constant: {}", .{err});
    }; // Look up the constant with bounds check
    stderr.print("{0s} (const idx : {1d}_u8) [{2}]\t{3s}\n", .{ name, constant_index, constant_value, src_info }) catch {
        dbg("Failed to print constant", .{});
    };
    return offset + 2;
}

fn constantLongInstruction(name: []const u8, chunk: *const Chunk, offset: usize, src_info: []const u8) usize {
    const constant_index = chunk.getConstantIdx(offset).?; // Skips 3 byte for OP_CONSTANT_LONG
    const constant_value = chunk.constants.get(constant_index) catch |err| {
        std.debug.panic("Error getting constant at index {d}: {}", .{ constant_index, err });
    };

    stderr.print("{0s} (const idx : {1d}_u24) [{2}]  {3s}\n", .{
        name, constant_index, constant_value, src_info,
    }) catch {
        dbg("Failed to print constant", .{});
    };

    return offset + 4; // 1 for opcode, 3 for u24 index
}

fn byteInstruction(name: []const u8, chunk: *const Chunk, offset: usize, src_info: []const u8) usize {
    const slot: u8 = chunk.code[offset + 1];
    stderr.print("{0s} (local idx : {1d}_u8)\t{2s}\n", .{ name, slot, src_info }) catch {
        dbg("Failed to print local index", .{});
    };
    return offset + 2;
}

fn U16Instruction(name: []const u8, chunk: *const Chunk, offset: usize, src_info: []const u8) usize {
    const slot: u16 = @as(u16, chunk.code[offset + 1]) << 8 | @as(u16, chunk.code[offset + 2]);
    stderr.print("{0s} (slot: {1d}_u16)\t{2s}\n", .{ name, slot, src_info }) catch {
        dbg("Failed to print local index", .{});
    };
    return offset + 3;
}

fn jumpInstruction(name: []const u8, sign: Sign, chunk: *const Chunk, offset: usize, src_info: []const u8) usize {
    const jump_offset = @as(usize, chunk.code[offset + 1]) << 8 | @as(usize, chunk.code[offset + 2]);
    var offset_after_jump = offset + 3;
    if (sign == .NEGATIVE) {
        // Negative jump
        offset_after_jump -= jump_offset;
    } else {
        // Positive jump
        offset_after_jump += jump_offset;
    }
    stderr.print("{0s} (jump offset: {1d} -> {2d})\t{3s}\n", .{ name, offset, offset_after_jump, src_info }) catch {
        dbg("Failed to print jump offset", .{});
    };
    return offset + 3;
}

const Sign = enum {
    /// Positive jump
    POSITIVE,
    /// Negative jump
    NEGATIVE,
};

/// Location for chunk bytecode
/// Used by write functions when creating bytecode for a given chunk
pub const Location = struct {
    /// Bytecode offset of a given chunk
    offset: usize,
    /// Source line number generating the bytecode at offset
    line: usize,
    /// Column number generating the bytecode at offset
    start_column: ?usize = null,
    /// End column number generating the bytecode at offset
    end_column: ?usize = null,
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

/// Column information for an instruction, part of a `LineRun`
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
    col_spans: ?std.ArrayList(ColumnSpan) = null,

    pub const InitCapacity = struct {
        /// Initial capacity for line runs
        line_capacity: ?usize = null,
        /// Initial capacity for column spans
        col_capacity: ?usize = null,
        /// Enable column spans, defaults to false
        enable_column_spans: bool = false,
    };

    /// Initialize `DebugInfo` for a chunk. `line_capacity` and `col_capacity` are optional parameters to
    /// initialize the corresponding arrays based on expected chunk size.
    /// Defaults to 8 bytes if not provided
    pub fn init(allocator: std.mem.Allocator, options: InitCapacity) !DebugInfo {
        const lc = options.line_capacity orelse 8;
        const cc = options.col_capacity orelse 8;
        const line_runs = try std.ArrayList(LineRun).initCapacity(allocator, lc);
        if (options.enable_column_spans) {
            return DebugInfo{
                .line_runs = line_runs,
                .col_spans = try std.ArrayList(ColumnSpan).initCapacity(allocator, cc),
            };
        }
        return DebugInfo{
            .line_runs = line_runs,
            .col_spans = null, // No column spans by default
        };
    }
    /// Free the DebugInfo
    pub fn deinit(self: *DebugInfo) void {
        self.line_runs.deinit();
        if (self.col_spans) |cols| {
            cols.deinit();
        }
    }

    /// Get location for a given bytecode offset
    pub fn getLocation(self: *DebugInfo, offset: usize) ?Location {
        if (self.col_spans == null) {
            // No column spans, return only line information
            const line = self.getLine(offset) orelse return null;
            return Location{
                .offset = offset,
                .line = line,
            };
        }
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
    /// If colspan is not provided it defaults to 0 for both start and end columns
    pub fn addLocation(self: *DebugInfo, location: Location) !void {
        if (self.col_spans) |*cols| {
            try cols.append(.{
                .offset = location.offset,
                .start_column = location.start_column orelse 0,
                .end_column = location.end_column orelse 0,
            });
        }

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
const lib = @import("root.zig");
const Chunk = lib.Chunk;
const OpCode = lib.OpCode;
const dbg = std.debug.print;
const EMPTY = "";
const DEBUG_ALLOC_FAILED = "Debug Allocation Failed";
