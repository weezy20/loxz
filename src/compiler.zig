var debug_level: u8 = 0;
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

    fn reset(self: *Parser) void {
        self.previous = Token{
            .tokenType = TokenType.Error,
            .line = 0,
            .lexeme = "",
        };
        self.current = Token{
            .tokenType = TokenType.Error,
            .line = 0,
            .lexeme = "",
        };
        self.had_error = false;
        self.panic_mode = false;
        self.currentSpan = 0;
    }
};
pub fn resetParser() void {
    parser.reset();
}
fn previousSpanInfo() [2]usize {
    if (debug_level > 2) {
        std.debug.print("=== Previous span info === \n", .{});
        std.debug.print("Previous lexeme:  >> {s} <<  (len {})\n", .{ parser.previous.lexeme, parser.previous.lexeme.len });
        std.debug.print("Previous span: {} - {}\n", .{
            parser.currentSpan - parser.previous.lexeme.len,
            parser.currentSpan - 1,
        });
        std.debug.print("=== Previous span info === \n", .{});
    }
    // Returns the span for the previous token (exclusive of current)
    return [2]usize{
        parser.currentSpan - parser.previous.lexeme.len,
        parser.currentSpan - 1,
    };
}
/// Returns span info for the current token
fn spanInfo() [2]usize {
    if (debug_level > 2) {
        std.debug.print("=== Current span info === \n", .{});
        std.debug.print("Previous lexeme:  >> {s} <<  (len {})\n", .{ parser.previous.lexeme, parser.previous.lexeme.len });
        std.debug.print("Current lexeme:  >> {s} <<  (len {})\n", .{ parser.current.lexeme, parser.current.lexeme.len });
        std.debug.print("=== Current span info === \n", .{});
    }
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
const emit = struct {
    fn byte(b: op) void {
        emitByte(@intFromEnum(b)) catch @panic(BYTECODE_FAIL);
    }
    fn bytes(ops: []const op) void {
        for (ops) |b| emitByte(@intFromEnum(b)) catch @panic(BYTECODE_FAIL);
    }
};

/// Advance parser by one token, reporting a token error if found.
fn advance() void {
    parser.previous = parser.current;
    // Error token lexeme's no longer contain the error message so we can do this
    parser.currentSpan += parser.previous.lexeme.len;

    while (true) {
        parser.current = parser.scanner.scanToken();
        if (parser.current.tokenType != TokenType.Error) break;

        // Use ErrorAtCurrent since we're reporting the current token
        ErrorAtCurrent(null);
    }
}
/// Emit a literal from "previous"
fn literal() void {
    switch (parser.previous.tokenType) {
        .True => emitByte(@intFromEnum(op.TRUE)) catch @panic(BYTECODE_FAIL),
        .False => emitByte(@intFromEnum(op.FALSE)) catch @panic(BYTECODE_FAIL),
        .Nil => emitByte(@intFromEnum(op.NIL)) catch @panic(BYTECODE_FAIL),
        else => return,
    }
}
/// Emit a constant value from "previous" token
fn number() void {
    const val = std.fmt.parseFloat(f64, parser.previous.lexeme) catch unreachable;
    emitConstant(Value{ .Number = val }) catch @panic(BYTECODE_FAIL);
}
/// Assumes the left operand is compiled and infix operator is consumed.
/// Since Lox uses left-to-right associativity, this is exactly what we want.
/// Based on the operator type, we parse the correct infix expression
fn binary() void {
    const operator_tt: TokenType = parser.previous.tokenType;
    const rule: *const ParseRule = getRule(operator_tt);
    // ensures that the right-hand side of the operator is parsed with precedence one level higher than the operator itself.
    // For example:  2 + 3 * 4, the precedence of the multiplication is higher than the addition, so the right side
    // of + is parsed with the precedence of multiplication
    parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));
    // Finally we emit the bytecode for the operator

    switch (operator_tt) {
        // Arithemtic infix expressions
        .Plus => emit.byte(op.ADD),
        .Minus => emit.byte(op.SUBTRACT),
        .Star => emit.byte(op.MULTIPLY),
        .Slash => emit.byte(op.DIVIDE),
        // Logical infix expression
        .BangEqual => emit.bytes(&.{ op.EQUAL, op.NOT }),
        .EqualEqual => emit.byte(op.EQUAL),
        .Greater => emit.byte(op.GREATER),
        .GreaterEqual => emit.bytes(.{ op.LESS, op.NOT }),
        .Less => emit.byte(op.LESS),
        .LessEqual => emit.byte(.{ op.GREATER, op.NOT }),
        else => return, // Unreachable
    }
}
/// Assumes TokenType.LeftParen is already consumed
fn grouping() void {
    expression();
    consume(TokenType.RightParen, "Expect ')' after expression.");
}
/// Prefix unary operator
fn unary() void {
    // Fetch the prefix operator
    const operatorType: TokenType = parser.previous.tokenType;
    // Compile the operand
    parsePrecedence(Precedence.Unary);
    switch (operatorType) {
        TokenType.Minus => emitByte(@intFromEnum(op.NEGATE)) catch @panic(BYTECODE_FAIL),
        TokenType.Bang => emitByte(@intFromEnum(op.NOT)) catch @panic(BYTECODE_FAIL),
        else => return,
    }
}
/// Parses an expression upto the provided precedence
fn parsePrecedence(precedence: Precedence) void {
    advance();
    const prefix_rule = getRule(parser.previous.tokenType).prefix;
    if (prefix_rule) |rule| rule() else {
        Error("Expect expression");
        return;
    }
    while (@intFromEnum(precedence) <= @intFromEnum(getRule(parser.current.tokenType).precedence)) {
        advance();
        const infix_rule = getRule(parser.previous.tokenType).infix;
        infix_rule.?();
    }
}
/// Emit bytecode for a expression
fn expression() void {
    parsePrecedence(Precedence.Assignment);
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
fn ErrorAtCurrent(msg: ?[]const u8) void {
    errorAt(&parser.current, msg, spanInfo()) catch {};
}
/// Report error at previous token
fn Error(msg: ?[]const u8) void {
    errorAt(&parser.previous, msg, previousSpanInfo()) catch {};
}
fn errorAt(token: *Token, msg: ?[]const u8, span: ?[2]usize) !void {
    parser.had_error = true;
    if (parser.panic_mode) return;
    parser.panic_mode = true;
    const token_error_msg = if (msg) |m| m else if (token.tokenType == TokenType.Error and token.error_msg != null)
        token.error_msg.?
    else
        "Uncaught exception";

    try stderr.print("\x1b[31m[line {}] Error: {s}\x1b[0m", .{ token.line, token_error_msg });

    switch (token.tokenType) {
        .Eof => try stderr.writeAll(" (at end)"),
        .Error => {
            try stderr.writeAll(" at \"");
            try stderr.writeAll(token.lexeme);
            try stderr.writeAll("\"");
            if (span) |s| if (debug_level > 0) {
                try stderr.print(" [lex {}..{}]", .{ s[0], s[1] - 1 });
            };
        },
        else => {
            try stderr.writeAll(" (at \"");
            try stderr.writeAll(token.lexeme);
            try stderr.writeAll("\")");
            if (span) |s| if (debug_level > 0) {
                try stderr.print(" [lex {d}..{d}]", .{ s[0], s[1] });
            };
        },
    }
    try stderr.writeAll("\n");
}
pub fn compile(
    source: []const u8,
    chunk: *Chunk,
    allocator: std.mem.Allocator,
    opts: ?struct { debug: bool, debug_level: ?u8 },
) struct {
    bool,
    ?*DebugInfo,
    ?CompilerError,
} {
    compilingChunk = chunk;
    if (opts) |o| {
        if (o.debug) {
            // Allocate DebugInfo on the heap
            const di_ptr = allocator.create(DebugInfo) catch {
                @panic("Failed to allocate debug info");
            };
            di_ptr.* = DebugInfo.init(allocator, .{}) catch {
                allocator.destroy(di_ptr);
                @panic("Failed to initialize debug info");
            };
            parser.debugInfo = di_ptr;
        }
        if (o.debug_level) |lvl| debug_level = lvl;
    }
    parser.scanner = Scanner.init(source);
    advance();
    expression();

    consume(TokenType.Eof, "Expect end of expression.");

    endCompiler(allocator) catch |err| {
        return .{ !parser.had_error, parser.debugInfo, err };
    };
    return .{ !parser.had_error, parser.debugInfo, null };
}
/// `allocator` is only used in debug mode
inline fn endCompiler(allocator: std.mem.Allocator) !void {
    if (debug_level > 0) currentChunk().disassemble(allocator, "code", parser.debugInfo) catch std.debug.print("Skipping: Disassemble code chunk");
    try emitReturn();
}
inline fn emitReturn() !void {
    try emitByte(@intFromEnum(op.RETURN));
}

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const op = @import("opcode.zig").OpCode;
const Token = @import("scanner.zig").Token;
const TokenType = @import("scanner.zig").TokenType;
const Scanner = @import("scanner.zig");
const DebugInfo = @import("debug.zig").DebugInfo;
const Value = @import("value.zig").Value;
const BYTECODE_FAIL = "fatal: failed to emit bytecode";
const CompilerError = @import("error.zig").CompilerError;

/// Lowest to highest precedence
const Precedence = enum {
    None,
    Assignment, // =
    Or, // or
    And, // and
    Equality, // == !=
    Comparison, // < > <= >=
    Term, // + -
    Factor, // * /
    Unary, // ! -
    Call, // . ()
    Primary,
};

const ParseRule = struct {
    prefix: ?*const fn () void,
    infix: ?*const fn () void,
    precedence: Precedence,
};

/// - **In C:** The function indirection (`getRule()`) is needed to avoid declaration cycles.
/// ParseRule contains a function ptr to `binary()` and `unary()`, but if they want to use the table, the table must be declared first.
/// The table cannot be declared first because it contains function ptrs to `binary()` and `unary()`, which are not declared yet.
/// Hence the book describes a workaround where the function is declared first, and then the table is declared.
/// - **In Zig:** We do **not** need this workaround; you can access the table directly from any function, regardless of order.
/// This function is here just to follow the book's example.
fn getRule(tokenType: TokenType) *const ParseRule {
    return &rules[@intFromEnum(tokenType)];
}

const rules = [_]ParseRule{
    // TOKEN_LEFT_PAREN
    ParseRule{ .prefix = grouping, .infix = null, .precedence = Precedence.None },
    // TOKEN_RIGHT_PAREN
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_LEFT_BRACE
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_RIGHT_BRACE
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_COMMA
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_DOT
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_MINUS
    ParseRule{ .prefix = unary, .infix = binary, .precedence = Precedence.Term },
    // TOKEN_PLUS
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Term },
    // TOKEN_SEMICOLON
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_SLASH
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Factor },
    // TOKEN_STAR
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Factor },
    // TOKEN_BANG
    ParseRule{ .prefix = unary, .infix = null, .precedence = Precedence.None },
    // TOKEN_BANG_EQUAL
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Equality },
    // TOKEN_EQUAL
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_EQUAL_EQUAL
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Equality },
    // TOKEN_GREATER
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Equality },
    // TOKEN_GREATER_EQUAL
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Equality },
    // TOKEN_LESS
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Equality },
    // TOKEN_LESS_EQUAL
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Equality },
    // TOKEN_IDENTIFIER
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_STRING
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_NUMBER
    ParseRule{ .prefix = number, .infix = null, .precedence = Precedence.None },
    // TOKEN_AND
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_CLASS
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_ELSE
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_FALSE
    ParseRule{ .prefix = literal, .infix = null, .precedence = Precedence.None },
    // TOKEN_FOR
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_FUN
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_IF
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_NIL
    ParseRule{ .prefix = literal, .infix = null, .precedence = Precedence.None },
    // TOKEN_OR
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_PRINT
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_RETURN
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_SUPER
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_THIS
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_TRUE
    ParseRule{ .prefix = literal, .infix = null, .precedence = Precedence.None },
    // TOKEN_VAR
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_WHILE
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_ERROR
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_EOF
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
};
