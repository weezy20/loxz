pub const VM = struct {
    chunks: std.ArrayList(Chunk),

    pub fn init(allocator: std.mem.Allocator) !VM {
        return VM{
            .chunks = try std.ArrayList(Chunk).initCapacity(allocator, 1),
        };
    }
    pub fn deinit(self: *VM) void {
        self.chunks.deinit();
    }
    pub fn interpret(self: *VM, chunk: *Chunk) InterpretResult {
        if (chunk.count == 0) {
            return .{ .compile_error = "Very big error" };
        }
        _ = self;
        return InterpretResult.ok;
    }
};

pub const InterpretResult = union(enum) {
    ok,
    compile_error: ?[]const u8,
    runtime_error: ?[]const u8,
};

const std = @import("std");
const lib = @import("root.zig");
const Chunk = lib.Chunk;
const OpCode = lib.OpCode;
const Value = lib.Value;
