pub const VM = struct {
    chunk: *Chunk,

    pub fn init(allocator: std.mem.Allocator) !VM {
        var chunk = Chunk.init(&allocator);
        return VM{
            .chunk = &chunk,
        };
    }
    pub fn deinit(self: *VM) void {
        self.chunk.deinit();
    }
    pub fn interpret(self: *VM, chunk: *Chunk) InterpretResult {
        _ = self;
        _ = chunk;
        return InterpretResult.OK;
    }
};

pub const InterpretResult = union(enum) {
    OK: void,
    COMPILE_ERROR: ?[]const u8,
    RUNTIME_ERROR: ?[]const u8,
};

const std = @import("std");
const lib = @import("root.zig");
const Chunk = lib.Chunk;
const OpCode = lib.OpCode;
const Value = lib.Value;
