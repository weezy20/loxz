var parser: Parser = Parser{
    .previous = undefined,
    .current = undefined,
    .had_error = false,
    .panic_mode = false,
    .scanner = undefined,
    .debugInfo = null,
};

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
};
/// Advance parser by one token, reporting a token error if found.
fn advance() void {
    parser.previous = parser.current;
    while (true) {
        parser.current = parser.scanner.scanToken();
        if (parser.current.tokenType != TokenType.Error) break;

        // Use ErrorAtCurrent since we're reporting the current token
        ErrorAtCurrent(parser.current.lexeme);
        parser.had_error = true;
    }
}

fn consume(@"type": TokenType, message: []const u8) void {
    if (parser.current.tokenType == @"type") {
        advance();
        return;
    }
    ErrorAtCurrent(message);
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
fn expression() void {}

pub fn compile(source: []const u8, chunk: *Chunk, allocator: std.mem.Allocator, opts: ?struct { debug: bool }) struct { bool, ?*DebugInfo } {
    _ = chunk;

    if (opts) |o| if (o.debug) {
        var di = DebugInfo.init(allocator, .{}) catch {
            // We panic here because it's probably OOM
            @panic("Failed to initialize debug info");
        };
        parser.debugInfo = &di;
    };
    parser.scanner = @import("scanner.zig").init(source);
    advance();
    expression();
    consume(TokenType.Eof, "Expect end of expression.");
    return .{ !parser.had_error, parser.debugInfo };
}

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Token = @import("scanner.zig").Token;
const TokenType = @import("scanner.zig").TokenType;
const Scanner = @import("scanner.zig");
const DebugInfo = @import("debug.zig").DebugInfo;
