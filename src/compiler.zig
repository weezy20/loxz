var debug_level: u8 = 0;
// Current compiler global
var cc: *Compiler = undefined;
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
    .repl_mode = true,
    .allocator = undefined,
    .vm = undefined,
    .canAssign = null,
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
    repl_mode: bool,
    allocator: std.mem.Allocator,
    vm: *VM,
    canAssign: ?bool,

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
        self.canAssign = null;
    }
};
pub fn resetParser() void {
    parser.reset();
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
fn emitBytes(bytes: []const u8) !void {
    for (bytes) |b| try currentChunk().write(b);
}
fn emitConstant(value: Value) !void {
    _ = try currentChunk().writeConstant(
        value,
        parser.debugInfo,
        parser.previous.line,
        spanInfo(),
    );
}
fn emitU16Op(b: op, arg: usize) CompilerError!void {
    try emitByte(@intFromEnum(b));
    if (arg > std.math.maxInt(u16)) {
        // Safe: we know that arg is <= 65535
        @panic("Argument exceeds maximum allowed value of 65535");
    }
    // Emit the argument as two separate bytes: MSB (Most Significant Byte) and LSB (Least Significant Byte).
    // This ensures the 16-bit value is correctly represented in the bytecode.
    try emitByte(@intCast((arg >> 8) & 0xff)); // MSB
    try emitByte(@intCast(arg & 0xff)); // LSB
}
const emit = struct {
    fn byte(b: op) void {
        emitByte(@intFromEnum(b)) catch @panic(BYTECODE_FAIL);
    }
    fn ops(opcodes: []const op) void {
        for (opcodes) |o| emitByte(@intFromEnum(o)) catch @panic(BYTECODE_FAIL);
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
/// Emit a variable
fn variable() void {
    namedVariable(
        parser.previous,
        parser.canAssign.?,
        &cc.stringTable,
    );
}
fn namedVariable(name: Token, canAssign: bool, intern_table: *Table) void {
    const arg: isize = cc.resolveLocal(&name);
    if (arg != -1) {
        const uarg: u8 = @intCast(arg); // u8 limit for locals
        if (canAssign and match(TokenType.Equal)) {
            expression();
            emitBytes(&.{ @intFromEnum(op.SET_LOCAL), uarg }) catch @panic(BYTECODE_FAIL);
        } else {
            emitBytes(&.{ @intFromEnum(op.GET_LOCAL), uarg }) catch @panic(BYTECODE_FAIL);
        }
    } else {
        // If the variable is not found in the locals, it must be a global variable
        // Fetch the variable's index in the chunk constant pool
        // Safe as the index returned is within u16 range
        const uarg = identifierConstant(&name, intern_table);
        if (canAssign and match(TokenType.Equal)) {
            expression();
            emitU16Op(op.SET_GLOBAL, uarg) catch @panic(BYTECODE_FAIL);
        } else {
            emitU16Op(op.GET_GLOBAL, uarg) catch @panic(BYTECODE_FAIL);
        }
        return;
    }
}
/// Emit a string
fn string() void {
    const str = parser.previous.lexeme[1 .. parser.previous.lexeme.len - 1];
    // We need to allocate the string on the heap
    const value = b: {
        const objstr = Object.newString(
            parser.vm,
            &[_][]const u8{str},
            &cc.stringTable,
        ) catch @panic(HEAP_FAIL);
        // In REPL mode, we need to allocate the string as the line buffer will get deallocated
        break :b Value{ .Obj = objstr.obj };
    };
    // Emit the string constant
    emitConstant(value) catch @panic(BYTECODE_FAIL);
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
        .BangEqual => emit.ops(&.{ op.EQUAL, op.NOT }),
        .EqualEqual => emit.byte(op.EQUAL),
        .Greater => emit.byte(op.GREATER),
        .GreaterEqual => emit.ops(&.{ op.LESS, op.NOT }),
        .Less => emit.byte(op.LESS),
        .LessEqual => emit.ops(&.{ op.GREATER, op.NOT }),
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
    const global_canAssign = parser.canAssign;
    const local_canAssign = @intFromEnum(precedence) <= @intFromEnum(Precedence.Assignment);
    if (prefix_rule) |rule| {
        parser.canAssign = local_canAssign;
        rule();
        parser.canAssign = global_canAssign;
    } else {
        Error("Expect expression");
        return;
    }
    while (@intFromEnum(precedence) <= @intFromEnum(getRule(parser.current.tokenType).precedence)) {
        advance();
        const infix_rule = getRule(parser.previous.tokenType).infix;
        infix_rule.?();
    }
    if (local_canAssign and match(TokenType.Equal)) {
        Error("Invalid assignment target.");
    }
}
fn check(tokenType: TokenType) bool {
    return parser.current.tokenType == tokenType;
}
/// Match the current token with the provided token type, consuming & advancing it if it matches.
fn match(tokenType: TokenType) bool {
    if (!check(tokenType)) return false;
    advance();
    return true;
}
fn printStatement() void {
    expression();
    consume(TokenType.Semicolon, "Expect ';' after value.");
    emitByte(@intFromEnum(op.PRINT)) catch @panic(BYTECODE_FAIL);
}
fn expressionStatement() void {
    expression();
    consume(TokenType.Semicolon, "Expect ';' after expression.");
    emitByte(@intFromEnum(op.POP)) catch @panic(BYTECODE_FAIL);
}
fn beginScope() void {
    cc.scopeDepth += 1;
}
fn block() void {
    // A block is a sequence of statements enclosed in braces
    while (!check(TokenType.RightBrace) and !check(TokenType.Eof)) {
        declaration();
    }
    consume(TokenType.RightBrace, "Expect '}' after block.");
}
fn endScope() void {
    // Decrease the scope depth, popping all locals in the current scope
    cc.scopeDepth -= 1;
    // Pop all locals in the current scope
    while (cc.localCount > 0 and cc.locals[cc.localCount - 1].depth > cc.scopeDepth) {
        cc.localCount -= 1;
        emitByte(@intFromEnum(op.POP)) catch @panic(BYTECODE_FAIL);
    }
}
/// Parse a statement
/// statement      → exprStmt
///               | printStmt
///               | block ;
fn statement() void {
    if (match(TokenType.Print)) { // print statement
        printStatement();
    } else if (match(TokenType.LeftBrace)) { // block
        // Block statement
        // cc.scopeDepth += 1;
        // while (!check(TokenType.RightBrace) and !check(TokenType.Eof)) {
        //     declaration();
        // }
        // consume(TokenType.RightBrace, "Expect '}' after block.");
        // cc.scopeDepth -= 1;
        beginScope();
        block();
        endScope();
    } else { // expression statement
        expressionStatement();
    }
}
/// Build a non-interned constant for a variable name and return its index in the chunk's constants table.
/// index is u16
fn identifierConstant(token: *const Token, intern_table: *Table) usize {
    const obj_intern = (Object.newString(
        parser.vm,
        &[_][]const u8{token.lexeme},
        intern_table,
    ) catch @panic(HEAP_FAIL));
    const obj, _ = .{ obj_intern.obj, obj_intern.interned };
    const index_at_table = cc.constantTable.get(obj.asObjString().?);
    if (index_at_table) |present| {
        return @intFromFloat(present.asNumber().?);
    }
    const index = makeConstant(Value{ .Obj = obj });
    const isNewKey = cc.constantTable.set(obj.asObjString().?, Value{ .Number = @floatFromInt(index) }) catch @panic("Out of memory interning string constant");
    std.debug.assert(isNewKey);
    return index;
}
inline fn addLocal(name: *const Token) void {
    if (@as(usize, cc.localCount) == LOCAL_COUNT - 1) {
        Error("Too many local variables in function.");
        return;
    }
    cc.locals[cc.localCount] = Local{
        .name = name.*,
        .depth = -1,
    };
    cc.localCount += 1;
}
/// Lox allows variable shadowing but within the same scope, it's an error.
/// var a = 1;      // Outer scope
/// {
///     var a = 2;  // ✅ Allowed (shadowing)
///     var a = 3;  // ❌ Error (redeclaration in same scope)
/// }
fn declareVariable() void {
    if (cc.scopeDepth == 0) return; // Global variable, no need to declare
    if (cc.localCount >= LOCAL_COUNT) {
        Error("Too many local variables in function.");
        return;
    }
    const name = parser.previous;
    // Detect if the variable is already declared in the current scope
    var i: isize = if (cc.localCount == 0) -1 else @intCast(cc.localCount - 1);
    while (i >= 0) : (i -= 1) {
        const local = &cc.locals[@intCast(i)];
        // If we encounter a variable from an outer scope (depth < cc.scopeDepth), we stop checking further to enable shadowed var declaration.
        if (local.depth != -1 and local.depth < cc.scopeDepth) {
            break;
        }
        // cc.scopeDepth == local.depth here, and it is an error to shadow a variable in the same scope.
        // Invariant: local.depth ≤ cc.scopeDepth because cc.scopeDepth is tracking the inner most scope.
        if (identifiersEqual(&name, &local.name)) {
            Error("Already a variable with this name in this scope.");
        }
    }
    addLocal(&name);
}
// Compare the lexemes of the two tokens
fn identifiersEqual(a: *const Token, b: *const Token) bool {
    return std.mem.eql(u8, a.lexeme, b.lexeme);
}
fn parseVariable(errMessage: []const u8, intern_table: *Table) usize {
    consume(TokenType.Identifier, errMessage);
    declareVariable(); // Entry point for local variable declaration
    if (cc.scopeDepth > 0) return 0;

    //TODO: If error this still proceeds silently.. fix
    return identifierConstant(&parser.previous, intern_table);
}
fn varDeclaration() void {
    const global: usize = parseVariable("Expect variable name.", &cc.stringTable);
    if (global > std.math.maxInt(u16)) {
        Error("Cannot declare more than 65535 variables in a single function");
        return;
    }
    if (match(TokenType.Equal)) {
        expression();
    } else {
        emitConstant(Value.Nil) catch @panic(BYTECODE_FAIL);
    }
    consume(TokenType.Semicolon, "Expect ';' after variable declaration.");
    // Emit the variable declaration
    defineVariable(global);
}
fn defineVariable(global: usize) void {
    if (cc.scopeDepth > 0) {
        markInitialized();
        return;
    }
    emitU16Op(op.DEFINE_GLOBAL, global) catch @panic("Failed to emit DEFINE_GLOBAL bytecode");
}
/// Emit bytecode for a declaration
fn declaration() void {
    if (match(TokenType.Var)) varDeclaration() else statement();
    if (parser.panic_mode) synchronize();
}
/// Mark the last local variable as initialized.
/// Declaring” is when the variable is added to the scope
fn markInitialized() void {
    if (cc.localCount == 0) return; // No locals in the current scope
    cc.locals[cc.localCount - 1].depth = @intCast(cc.scopeDepth); // Safe: we don't expect a nesting depth greater than 2^31
}
fn synchronize() void {
    parser.panic_mode = false;
    while (parser.current.tokenType != TokenType.Eof) {
        if (parser.previous.tokenType == TokenType.Semicolon) return;
        switch (parser.current.tokenType) {
            // Statement can begin with any of these tokens
            .Class, .Fun, .Var, .For, .If, .While, .Print, .Return => return,
            else => {},
        }
        advance();
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
/// Make a constant value and return its index in the chunk's constants table
/// Writes a 2 byte index. If one byte is needed use chunk.constants.write() directly.
fn makeConstant(value: Value) usize {
    return currentChunk().writeU16Constant(value) catch @panic("developer: propagate this error up");
}
inline fn currentChunk() *Chunk {
    return cc.compilingChunk;
}
/// Report error at current token
fn ErrorAtCurrent(msg: ?[]const u8) void {
    errorAt(&parser.current, msg, spanInfo()) catch {};
}
/// Report error at previous token
fn Error(msg: ?[]const u8) void {
    errorAt(&parser.previous, msg, null) catch {};
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
            try stderr.writeAll(" at '");
            try stderr.writeAll("\x1b[1m");
            try stderr.writeAll(token.lexeme);
            try stderr.writeAll("\x1b[0m");
            try stderr.writeAll("'");
        },
        else => {
            try stderr.writeAll(" (at '");
            try stderr.writeAll("\x1b[1m");
            try stderr.writeAll(token.lexeme);
            try stderr.writeAll("\x1b[0m");
            try stderr.writeAll("')");
            if (span) |s| if (debug_level > 0) {
                try stderr.print(" [lex {d}..{d}]", .{ s[0], s[1] });
            };
        },
    }
    try stderr.writeAll("\n");
}
pub fn compile(
    compiler: *Compiler,
    source: []const u8,
    vm: *VM,
    allocator: std.mem.Allocator,
    opts: ?struct {
        debug: bool,
        debug_level: ?u8,
        repl_mode: bool,
    },
) CompilationResult {
    cc = compiler; // Set the global compiler instance
    parser.allocator = allocator;
    parser.vm = vm;
    parser.scanner = Scanner.init(source);
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
        parser.repl_mode = o.repl_mode;
    }
    advance();
    while (!match(TokenType.Eof)) {
        declaration();
    }
    var retval: CompilationResult = .{
        .success = !parser.had_error,
        .debugInfo = parser.debugInfo,
        .err = null,
    };
    endCompiler(allocator) catch |err| {
        retval.err = err;
    };
    return retval;
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
const Object = @import("object.zig").Object;
const BYTECODE_FAIL = "fatal: failed to emit bytecode";
const HEAP_FAIL = "fatal: failed to heap allocate";
const CompilerError = @import("error.zig").CompilerError;
const Table = @import("table.zig").Table;
const VM = @import("vm.zig").VM;
const lib = @import("root.zig");

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
    ParseRule{ .prefix = variable, .infix = null, .precedence = Precedence.None },
    // TOKEN_STRING
    ParseRule{ .prefix = string, .infix = null, .precedence = Precedence.None },
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

const CompilationResult = struct {
    success: bool,
    debugInfo: ?*DebugInfo,
    err: ?CompilerError,
};

const LOCAL_COUNT: usize = 256; // Sticking to clox specs

pub const Compiler = struct {
    locals: [LOCAL_COUNT]Local,
    /// Number of locals in current scope
    localCount: u8,
    /// Number of blocks surrounding current code block
    scopeDepth: usize,
    /// Compiler constant Table
    constantTable: Table,
    /// Compiler string table
    stringTable: Table,
    /// Current chunk being compiled
    compilingChunk: *Chunk,

    // Use same hash across table/objstring,
    // NOTE: ObjString still uses loxHash, but the HashTable uses Clhash if available. This doesn't matter for checking values
    // but should be cleared up in the future. For now we just stick to the defaults...
    // cc.constantTable = Table.initWithHashFn(allocator, if (lib.hasClhash) .clhash else .default);

    pub fn init(allocator: std.mem.Allocator, chunk: *Chunk) @This() {
        return .{
            .locals = undefined,
            .localCount = 0,
            .scopeDepth = 0,
            .stringTable = Table.init(allocator),
            .constantTable = Table.initWithHashFn(allocator, .default),
            .compilingChunk = chunk,
        };
    }
    pub fn deinit(self: *@This()) void {
        self.stringTable.deinit();
        self.constantTable.deinit();
        self.* = undefined;
    }
    fn resolveLocal(self: *Compiler, name: *const Token) isize {
        if (self.localCount == 0) return -1; // No locals in the current scope
        var i: usize = self.localCount - 1; // Safe
        while (i >= 0) : (i -= 1) {
            const local = &self.locals[i];
            if (identifiersEqual(&local.name, name)) {
                if (local.depth == -1) {
                    Error("Cannot read local variable in its own initializer.");
                    return -1;
                }
                return @intCast(i);
            }
            if (i == 0) break;
        }
        return -1;
    }
};

pub const Local = struct {
    name: Token,
    depth: isize,
};
