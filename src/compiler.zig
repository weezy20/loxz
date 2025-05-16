var parser: Parser = Parser{
    // This will get overwritten by advance() and pushed into .previous
    // For first byte, the line is fetched as parser.previous.line, so we need this
    .current = Token{
        .tokenType = TokenType.Error,
        .line = 0,
        .lexeme = "",
    },
    .previous = undefined,
    .had_error = false,
    .panic_mode = false,
    .scanner = undefined,
    .debugInfo = null,
    .currentSpan = 0,
};
var compilingChunk: *Chunk = undefined;
const stderr = std.io.getStdErr().writer();
const Parser = struct {
    previous: Token,
    current: Token,
    had_error: bool,
    /// Suppresses all error reporting until a synchronization point is reached.
    panic_mode: bool,
    scanner: Scanner,
    /// Generate debugInfo when emitting bytecode
    debugInfo: ?*DebugInfo,
    /// For spans, we store the starting offset of the previous lexeme
    currentSpan: usize, // TODO: downgrade to u32
};
fn spanInfo() [2]usize {
    std.debug.print("Previous lexeme:  >> {s} <<  (len {})\n", .{ parser.previous.lexeme, parser.previous.lexeme.len });
    std.debug.print("Current lexeme:  >> {s} <<  (len {})\n", .{ parser.current.lexeme, parser.current.lexeme.len });
    std.debug.print("Span: {} - {}\n", .{
        parser.currentSpan,
        parser.currentSpan + parser.current.lexeme.len,
    });
    // Safe: we know that programmers are not going to write a lexeme longer than 2^32
    // const len = std.math.cast(u32, parser.previous.lexeme.len) catch unreachable;
    return [2]usize{
        parser.currentSpan - parser.previous.lexeme.len,
        parser.currentSpan,
    };
}
fn emitByte(byte: u8) CompilerError!void {
    if (parser.debugInfo) |d| {
        currentChunk().writeWithDebugInfo(
            byte,
            d,
            parser.previous.line,
            spanInfo(),
        ) catch {
            return CompilerError.OutOfMemory;
        };
    } else {
        currentChunk().write(byte) catch {
            return CompilerError.OutOfMemory;
        };
    }
}
fn emitConstant(value: Value) !void {
    try currentChunk().writeConstant(
        value,
        parser.debugInfo,
        parser.previous.line,
        spanInfo(),
    );
}
fn emitBytes(bytes: []const u8) !void {
    for (bytes) |byte| {
        try emitByte(byte);
    }
}
/// Advance parser by one token, reporting a token error if found.
fn advance() void {
    parser.previous = parser.current;
    parser.currentSpan += parser.previous.lexeme.len;
    while (true) {
        parser.current = parser.scanner.scanToken();
        if (parser.current.tokenType != TokenType.Error) break;

        // Use ErrorAtCurrent since we're reporting the current token
        ErrorAtCurrent(parser.current.lexeme);
        parser.had_error = true;
    }
}
fn expression() void {
    // currentChunk().writeConstant(
    //     Value{ .Number = 1 },
    //     parser.debugInfo,
    //     0,
    //     .{ 0, 1 },
    // ) catch {};
    // currentChunk().writeConstant(
    //     Value{ .Number = 1 },
    //     parser.debugInfo,
    //     0,
    //     .{ 2, 1 },
    // ) catch {};
    // currentChunk().write(@intFromEnum(op.ADD)) catch {};
}
fn consume(@"type": TokenType, message: []const u8) void {
    if (parser.current.tokenType == @"type") {
        advance();
        return;
    }
    ErrorAtCurrent(message);
}
inline fn currentChunk() *Chunk {
    return compilingChunk;
}
/// Report error at current token
fn ErrorAtCurrent(msg: []const u8) void {
    errorAt(&parser.current, msg) catch {};
}
/// Report error at previous token
fn Error(msg: []const u8) void {
    errorAt(&parser.previous, msg) catch {};
}
fn errorAt(token: *Token, msg: []const u8) !void {
    if (parser.panic_mode) return;
    parser.panic_mode = true;
    try stderr.print("[line {}] Error: {s}", .{ token.line, msg });

    switch (token.tokenType) {
        .Eof => try stderr.writeAll(" at end"),
        .Error => {}, // No location info captured for error lexeme
        else => {
            try stderr.writeAll(" (at \"");
            try stderr.writeAll(token.lexeme);
            try stderr.writeAll("\")");
        },
    }
    try stderr.writeAll("\n");
}

pub fn compile(
    source: []const u8,
    chunk: *Chunk,
    allocator: std.mem.Allocator,
    opts: ?struct { debug: bool },
) struct {
    bool,
    ?*DebugInfo,
    ?CompilerError,
} {
    compilingChunk = chunk;
    if (opts) |o| if (o.debug) {
        // Allocate DebugInfo on the heap
        const di_ptr = allocator.create(DebugInfo) catch {
            @panic("Failed to allocate debug info");
        };
        di_ptr.* = DebugInfo.init(allocator, .{}) catch {
            allocator.destroy(di_ptr);
            @panic("Failed to initialize debug info");
        };
        parser.debugInfo = di_ptr;
    };
    parser.scanner = @import("scanner.zig").init(source);
    advance();
    expression();

    consume(TokenType.Eof, "Expect end of expression.");

    endCompiler() catch |err| {
        return .{ !parser.had_error, parser.debugInfo, err };
    };
    return .{ !parser.had_error, parser.debugInfo, null };
}
inline fn endCompiler() !void {
    try emitReturn();
}
inline fn emitReturn() !void {
    try emitByte(@intFromEnum(op.RETURN));
}
/// Emit a constant value from "previous" token
fn number() CompilerError!void {
    const val = std.fmt.parseFloat(f64, parser.previous.lexeme) catch return CompilerError.NaN;
    try emitConstant(Value{ .Number = val });
}

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const op = @import("opcode.zig").OpCode;
const Token = @import("scanner.zig").Token;
const TokenType = @import("scanner.zig").TokenType;
const Scanner = @import("scanner.zig");
const DebugInfo = @import("debug.zig").DebugInfo;
const Value = @import("value.zig").Value;

const CompilerError = error{
    OutOfMemory,
    NaN,
};
