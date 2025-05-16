var parser: Parser = Parser{
    .previous = undefined,
    .current = undefined,
    .had_error = false,
    .panic_mode = false,
};

const stderr = std.io.getStdErr().writer();
const Parser = struct {
    previous: Token,
    current: Token,
    had_error: bool,
    panic_mode: bool,
};

fn advance(sc: *Scanner) void {
    parser.previous = parser.current; // Doesn't work for initial condition where parser.current = undefined
    while (true) {
        parser.current = sc.scanToken();
        if (parser.current.tokenType != TokenType.Error) break;

        // Use ErrorAtCurrent since we're reporting the current token
        ErrorAtCurrent(parser.current.lexeme);
        parser.had_error = true;
    }
}
fn ErrorAtCurrent(msg: []const u8) void {
    errorAt(&parser.current, msg) catch |err| {
        std.debug.print("Failed to report error: {s}", .{@errorName(err)});
    };
}
/// Report error at previous token
fn Error(msg: []const u8) void {
    errorAt(&parser.previous, msg) catch |err| {
        std.debug.print("Failed to report error: {s}", .{@errorName(err)});
    };
}
fn errorAt(token: *Token, msg: []const u8) !void {
    try stderr.print("[line {}] Error: {s}", .{ token.line, msg });

    switch (token.tokenType) {
        .Eof => try stderr.writeAll(" at end"),
        .Error => {}, // No location info captured for error lexeme
        else => {
            try stderr.writeAll(" at");
            try stderr.writeAll(token.lexeme);
        },
    }
    try stderr.writeAll("\n");
}
fn expression() void {}
fn consume(@"type": TokenType, msg: []const u8) void {
    _ = @"type";
    _ = msg;
}
pub fn compile(source: []const u8, chunk: *Chunk, allocator: std.mem.Allocator, opts: ?struct { debug: bool }) bool {
    _ = chunk;
    _ = allocator;
    _ = opts;
    var scanner = @import("scanner.zig").init(source);
    advance(&scanner);
    expression();
    consume(TokenType.Eof, "Expect end of expression.");
    return !parser.had_error;
}

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Token = @import("scanner.zig").Token;
const TokenType = @import("scanner.zig").TokenType;
const Scanner = @import("scanner.zig");
