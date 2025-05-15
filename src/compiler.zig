pub fn compile(source: []const u8, chunk: *Chunk, opts: ?struct { debug: bool, stack_tracing: bool }) bool {
    _ = opts;
    chunk.*.code = &[_]u8{};
    var sc = @import("scanner.zig").init(source);
    _ = sc.advance();
    // expression();
    // consume(TokenType.EOF, "Expect end of expression.");
    return true;
}

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
