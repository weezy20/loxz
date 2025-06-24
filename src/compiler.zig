var debug_level: u8 = 0;
/// Compiler global singleton
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
            null,
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
fn emitU16Op(b: OpCode, arg: usize) CompilerError!void {
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
    const Self = @This();
    fn op(b: OpCode) void {
        emitByte(@intFromEnum(b)) catch @panic(BYTECODE_FAIL);
    }
    fn ops(opcodes: []const OpCode) void {
        for (opcodes) |o| emitByte(@intFromEnum(o)) catch @panic(BYTECODE_FAIL);
    }
    /// Emit a jump instruction.
    /// Returns the offset of the jump placeholder operand in the current chunk.
    /// Use `patchJump` to fill in the jump offset later.
    fn jump(b: OpCode) usize {
        emitU16Op(b, 0xffff) catch @panic(BYTECODE_FAIL);
        // ^^^ equivalent to `emitByte(b)` followed by `emitByte(0xff)` twice
        return currentChunk().count - 2;
    }
    fn byte(b: u8) void {
        emitByte(b) catch @panic(BYTECODE_FAIL);
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
        cc.stringTable,
    );
}
fn namedVariable(name: Token, canAssign: bool, intern_table: *Table) void {
    if (cc.resolveLocal(&name)) |arg| {
        if (canAssign and match(TokenType.Equal)) {
            expression();
            emitU16Op(OpCode.SET_LOCAL, arg) catch @panic(BYTECODE_FAIL);
        } else {
            emitU16Op(OpCode.GET_LOCAL, arg) catch @panic(BYTECODE_FAIL);
        }
    } else |_| {
        // switch (err) {
        //     // No action required as the two errors we generate are handled.
        //     CompilerError.LocalNotFound => {},
        //     CompilerError.SameInitializer => {}, // Will be reported by resolveLocal()
        //     else => unreachable,
        // }

        // Fetch the variable's index in the chunk constant pool
        // Safe as the index returned is within u16 range
        const uarg = identifierConstant(&name, intern_table);
        if (canAssign and match(TokenType.Equal)) {
            expression();
            emitU16Op(OpCode.SET_GLOBAL, uarg) catch @panic(BYTECODE_FAIL);
        } else {
            emitU16Op(OpCode.GET_GLOBAL, uarg) catch @panic(BYTECODE_FAIL);
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
            cc.stringTable,
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
        .True => emit.op(OpCode.TRUE),
        .False => emit.op(OpCode.FALSE),
        .Nil => emit.op(OpCode.NIL),
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
        .Plus => emit.op(OpCode.ADD),
        .Minus => emit.op(OpCode.SUBTRACT),
        .Star => emit.op(OpCode.MULTIPLY),
        .Slash => emit.op(OpCode.DIVIDE),
        .Modulo => emit.op(OpCode.MOD),
        // Logical infix expression
        .BangEqual => emit.ops(&.{ OpCode.EQUAL, OpCode.NOT }),
        .EqualEqual => emit.op(OpCode.EQUAL),
        .Greater => emit.op(OpCode.GREATER),
        .GreaterEqual => emit.ops(&.{ OpCode.LESS, OpCode.NOT }),
        .Less => emit.op(OpCode.LESS),
        .LessEqual => emit.ops(&.{ OpCode.GREATER, OpCode.NOT }),
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
        TokenType.Minus => emitByte(@intFromEnum(OpCode.NEGATE)) catch @panic(BYTECODE_FAIL),
        TokenType.Bang => emitByte(@intFromEnum(OpCode.NOT)) catch @panic(BYTECODE_FAIL),
        else => return,
    }
}
/// Logical `and` operator
fn logical_and() void {
    const end_jump = emit.jump(OpCode.JUMP_IF_FALSE); // Skip the right operand
    emit.op(OpCode.POP); // Pop the left operand
    parsePrecedence(Precedence.And); // Parse the right operand
    patchJump(end_jump); // Patch the jump to skip the right operand if the left operand is truthy
}
/// Logical `or` operator
fn logical_or() void {
    const elseJump = emit.jump(OpCode.JUMP_IF_FALSE);
    const endJump = emit.jump(OpCode.JUMP); // if left is truthy, we jump to the end

    patchJump(elseJump); // If left is falsey, we jump to the right operand
    emit.op(OpCode.POP);
    parsePrecedence(Precedence.Or);
    patchJump(endJump); // if left was true, we jump and land here i.e. after the right operand
    // True i.e. left operand is left on the stack here.. if op.JUMP was executed, otherwise it's the value of the right operand
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
/// Check if the current tokenType matches the function param
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
    emitByte(@intFromEnum(OpCode.PRINT)) catch @panic(BYTECODE_FAIL);
}
fn expressionStatement() void {
    expression();
    consume(TokenType.Semicolon, "Expect ';' after expression.");
    emitByte(@intFromEnum(OpCode.POP)) catch @panic(BYTECODE_FAIL);
}
fn beginScope() void {
    // Practically Safe: scopeDepth is i32
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
    while (cc.localCount() > 0 and cc.locals.items[cc.localCount() - 1].depth > cc.scopeDepth) {
        _ = cc.locals.pop();
        emitByte(@intFromEnum(OpCode.POP)) catch @panic(BYTECODE_FAIL);
    }
}
/// `offset` is the jump placeholder to be patched.
fn patchJump(placeholder_addr: usize) void {
    // -2 to adjust for the bytecode for the jump offset itself.
    // Because, placeholder_addr points to the start of the 2 byte operand of the jump instruction.
    // I find a bit confusing how the book describes it, but nothing a bit of parentheses can't fix.
    // The book writes: `jumpOffset = currentChunk().count - placeholder_addr - 2;`
    // currentChunk().count will point to the next byte after the `then` block has ended compiling.
    const jumpOffset: usize = currentChunk().count - (placeholder_addr + 2);
    if (jumpOffset > std.math.maxInt(u16)) {
        Error("Too much code to jump over.");
        return;
    }
    // Write the jump offset as a 2-byte value
    currentChunk().code[placeholder_addr] = @intCast((jumpOffset >> 8) & 0xff); // MSB
    currentChunk().code[placeholder_addr + 1] = @intCast(jumpOffset & 0xff); // LSB
}
fn emitLoop(loop_start: usize) void {
    emit.op(OpCode.LOOP);
    const offset = currentChunk().count - loop_start + 2; // +2 for the LOOP 2-byte operand which also needs to be jumped over.
    if (offset > std.math.maxInt(u16)) {
        Error("Loop body too large.");
        return;
    }
    emitBytes(&[_]u8{ @truncate((offset >> 8) & 0xff), @truncate(offset & 0xff) }) catch @panic(BYTECODE_FAIL);
}
fn switchStatement() void {
    consume(TokenType.LeftParen, "Expect '(' after 'switch'.");
    expression();
    const currentSwitchDepth = cc.switchDepth;
    emit.op(OpCode.SWITCH_VAL);
    emit.byte(currentSwitchDepth);
    cc.switchDepth += 1;
    consume(TokenType.RightParen, "Expect ')' after switch expression.");
    consume(TokenType.LeftBrace, "Expect opening block '{' after switch expression.");
    // To track the end of switch-case for each case; each will be patched after the entire switch statement is compiled.
    var endJumps = std.ArrayList(usize).init(parser.allocator);
    defer endJumps.deinit();

    var seenDefault: bool = false;

    while (!check(TokenType.RightBrace) and !check(TokenType.Eof)) {
        if (match(TokenType.Case)) {
            // Eval the case expression
            expression();
            consume(TokenType.Colon, "Expect ':' after 'case'.");
            emit.op(OpCode.SWITCH_COMP);
            emit.byte(currentSwitchDepth);
            const jump_to_next_case = emit.jump(OpCode.JUMP_IF_FALSE);
            emit.op(OpCode.POP); // Pop the switch comparison result from the stack
            statement();
            endJumps.append(emit.jump(OpCode.JUMP)) catch @panic("Out of memory: Processing case for switch statement");
            patchJump(jump_to_next_case);
        } else if (match(TokenType.Default)) {
            if (seenDefault) {
                ErrorAtCurrent("Switch statement can only have one default case.");
                return;
            }
            seenDefault = !seenDefault;
            consume(TokenType.Colon, "Expect ':' after 'default'.");
            statement();
        } else {
            ErrorAtCurrent("Switch/Case can only have 'case' or 'default' statements.");
            advance();
        }
    }
    // Patch end jumps for each case
    for (endJumps.items) |jump| {
        patchJump(jump);
        emit.op(OpCode.POP); // Pop the switch comparison result from the stack
    }
    consume(TokenType.RightBrace, "Expect '}' after switch cases.");
    cc.switchDepth -= 1;
}
fn whileStatement() void {
    const loop_start = currentChunk().count;
    consume(TokenType.LeftParen, "Expect '(' after 'while'.");
    expression(); // while condition
    consume(TokenType.RightParen, "Expect ')' after condition.");

    const exitJump = emit.jump(OpCode.JUMP_IF_FALSE);
    emit.op(OpCode.POP); // Pop while-condition from stack, put on stack on every iteration
    statement();
    emitLoop(loop_start);
    patchJump(exitJump);
    emit.op(OpCode.POP); // Pop while-condition from stack when the loop exists due to condition being falsey
}
fn ifStatement() void {
    consume(TokenType.LeftParen, "Expect '(' after 'if'.");
    expression(); // if condition
    consume(TokenType.RightParen, "Expect ')' after condition.");

    const thenJump = emit.jump(OpCode.JUMP_IF_FALSE);
    emit.op(OpCode.POP); // Pop the condition value if condition was true
    statement(); // then block

    const elseJump = emit.jump(OpCode.JUMP); // jump over else block
    patchJump(thenJump); // if true, we resume after the else jump instruction but before the else block

    emit.op(OpCode.POP); // Pop the condition value, if condition was falsey
    if (match(TokenType.Else)) statement();
    patchJump(elseJump);
}
fn forStatement() void {
    beginScope();
    // > For loop initializer
    consume(TokenType.LeftParen, "Expect '(' after 'for'.");
    if (match(TokenType.Semicolon)) {
        // Empty initializer
    } else if (match(TokenType.Var)) {
        varDeclaration();
    } else {
        expressionStatement();
    }
    // < For loop initializer
    // > For loop condition start
    var loop_start = currentChunk().count;
    var exitJump: ?usize = null;
    if (!match(TokenType.Semicolon)) {
        expression();
        consume(TokenType.Semicolon, "Expect ';' after loop condition.");
        exitJump = emit.jump(OpCode.JUMP_IF_FALSE);
        emit.op(OpCode.POP);
    }
    // < For loop condition end
    // > For loop increment clause
    if (!match(TokenType.RightParen)) {
        const bodyJump = emit.jump(OpCode.JUMP); // Jump to the loop body without executing the increment clause
        const incrementStart = currentChunk().count;
        expression();
        emit.op(OpCode.POP); // Pop the increment value
        consume(TokenType.RightParen, "Expect ')' after for clauses.");
        emitLoop(loop_start); // Jump back to the start of the loop
        loop_start = incrementStart; // Update loop_start to the start of the increment clause
        patchJump(bodyJump); // body starts here
    }
    // < For loop increment clause
    // > Loop body
    statement();
    // < Loop body
    emitLoop(loop_start);
    if (exitJump) |exit_jump| {
        patchJump(exit_jump);
        emit.op(OpCode.POP);
    }
    endScope();
}
/// Parse a statement: statements don't leave anything on the stack.
/// statement      → exprStmt
///               | printStmt
///               | block ;
fn statement() void {
    switch (parser.current.tokenType) {
        TokenType.Print => {
            advance();
            printStatement();
        },
        TokenType.LeftBrace => {
            advance();
            beginScope();
            block();
            endScope();
        },
        TokenType.If => {
            advance();
            ifStatement();
        },
        TokenType.Switch => {
            advance();
            switchStatement();
        },
        TokenType.While => {
            advance();
            whileStatement();
        },
        TokenType.For => {
            advance();
            forStatement();
        },
        else => {
            expressionStatement();
        },
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
    // Redundant check, but ensures we don't overflow the localCount
    if (cc.localCount() == MAX_LOCAL_COUNT) {
        Error("add local: Too many local variables in function.");
        return;
    }
    cc.locals.append(Local{
        .name = name.*,
        .depth = -1,
    }) catch @panic("Out of memory : adding local variable");
}
// Lox allows variable shadowing but within the same scope, it's an error.
// var a = 1;      // Outer scope
// {
//     var a = 2;  // ✅ Allowed (shadowing)
//     var a = 3;  // ❌ Error (redeclaration in same scope)
// }
fn declareLocalVariable() void {
    if (cc.scopeDepth == 0) return; // Global variable, no need to declare
    if (cc.localCount() == MAX_LOCAL_COUNT) {
        Error("Too many local variables in function.");
        return;
    }
    const name = parser.previous;
    // Detect if the variable is already declared in the current scope
    var i: isize = if (cc.localCount() == 0) -1 else @intCast(cc.localCount() - 1);
    while (i >= 0) : (i -= 1) {
        const local = &cc.locals.items[@intCast(i)];
        // If we encounter a variable from an outer scope (depth < cc.scopeDepth), we stop checking further to enable shadowed var declaration.
        if (local.depth != -1 and local.depth < cc.scopeDepth) {
            // -1 means the variable is not initialized yet.
            // If local variable is shallower than the current scope, we stop checking further as shadowing is now possible.
            // All locals are added in the order of increasing scope depth for a given scope before they're popped so we can break the loop here.
            break;
        }
        // cc.scopeDepth == local.depth here, and it is an error to shadow a variable in the same scope.
        // Invariant: local.depth ≤ cc.scopeDepth because cc.scopeDepth is tracking the inner most scope.
        if (identifiersEqual(&name, &local.name)) {
            Error("Already a variable with this name in this scope.");
            // return; //TODO: Should we continue to add the local anyway?
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
    if (parser.panic_mode) return 0;
    declareLocalVariable(); // Entry point for local variable declaration
    if (cc.scopeDepth > 0) return 0; // Dummy index, var already handled by declareLocalVariable
    return identifierConstant(&parser.previous, intern_table);
}
fn varDeclaration() void {
    const global: usize = parseVariable("Expect variable name.", cc.stringTable);
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
    emitU16Op(OpCode.DEFINE_GLOBAL, global) catch @panic("Failed to emit DEFINE_GLOBAL bytecode");
}
/// Function declaration
fn funDeclaration() void {
    const global: usize = parseVariable("Expect function name.", cc.stringTable);
    if (global > std.math.maxInt(u16)) {
        // TODO: Switch to error propagation
        Error("Cannot declare more than 65535 functions in a single file");
        return;
    }
    markInitialized();
    defineFunction(FunctionType.Function);
    defineVariable(global);
}
fn defineFunction(ty: FunctionType) void {
    // We pass the parent's string table to share interned strings.
    var compiler = Compiler.init(
        parser.allocator,
        parser.vm,
        ty,
    ) catch @panic("Error: Initializing compiler for function");

    const enclosing_compiler = cc;
    cc = &compiler;

    // The function's name is the previous token. We set it in the new function object.
    cc.function.name = (Object.newString(parser.vm, &.{parser.previous.lexeme}, cc.stringTable) catch @panic(HEAP_FAIL)).obj.asObjString();

    beginScope();
    consume(TokenType.LeftParen, "Expect '(' after function name.");
    // TODO: Parse parameters here.
    // if (!check(TokenType.RightParen)) {
    //     // do-while loop to parse comma-separated parameters
    //     // until we hit the right parenthesis.
    // }
    consume(TokenType.RightParen, "Expect ')' after function parameters.");
    consume(TokenType.LeftBrace, "Expect '{' before function body.");
    block();

    const func = endCompiler() catch @panic("Failed to compile function");

    // Restore the enclosing compiler
    cc = enclosing_compiler;

    emitU16Op(OpCode.CONSTANT_LONG, makeConstant(Value{ .Obj = func })) catch @panic("Failed to emit function constant bytecode");
}
/// Emit bytecode for a declaration
fn declaration() void {
    if (match(TokenType.Fun)) funDeclaration() else if (match(TokenType.Var)) varDeclaration() else statement();
    if (parser.panic_mode) synchronize();
}
/// Mark the last local variable as initialized.
/// Declaring is when the variable is added to the scope
fn markInitialized() void {
    if (cc.scopeDepth == 0) return; // Functions in global scope such as the top level function
    if (cc.localCount() == 0) return; // No locals in the current scope
    cc.locals.items[cc.localCount() - 1].depth = cc.scopeDepth;
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
    return &cc.function.chunk;
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

inline fn emitReturn() !void {
    try emitByte(@intFromEnum(OpCode.RETURN));
}

const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("opcode.zig").OpCode;
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
    Factor, // * / %
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
    ParseRule{ .prefix = null, .infix = logical_and, .precedence = Precedence.And },
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
    ParseRule{ .prefix = null, .infix = logical_or, .precedence = Precedence.Or },
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
    // TOKEN_MODULO
    ParseRule{ .prefix = null, .infix = binary, .precedence = Precedence.Factor },
    // TOKEN_SWITCH
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_CASE
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_DEFAULT
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
    // TOKEN_COLON
    ParseRule{ .prefix = null, .infix = null, .precedence = Precedence.None },
};

pub fn compile(
    compiler: *Compiler,
    source: []const u8,
    vm: *VM,
    allocator: std.mem.Allocator,
    opts: lib.CompilerOpts,
) CompilationResult {
    cc = compiler; // Set the global compiler instance
    parser.allocator = allocator;
    parser.vm = vm;
    parser.scanner = Scanner.init(source);
    if (opts.debug) {
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
    debug_level = opts.debug_level;
    parser.repl_mode = opts.repl_mode;
    advance();
    while (!match(TokenType.Eof)) {
        declaration();
    }
    const function = endCompiler() catch |err| b: {
        std.debug.print("[Compiler Error]: {s}\n", .{@errorName(err)});
        break :b null;
    };
    return .{
        .function = function,
        .success = !parser.had_error,
        .debugInfo = parser.debugInfo,
    };
}

inline fn endCompiler() !*ObjFunction {
    try emitReturn();
    return cc.function;
}

const CompilationResult = struct {
    success: bool,
    debugInfo: ?*DebugInfo,
    function: ?*ObjFunction,
};

const MAX_LOCAL_COUNT: u16 = std.math.maxInt(u16); // Extending to 65535 locals

pub const Compiler = struct {
    function: *ObjFunction,
    type: FunctionType,
    locals: std.ArrayList(Local),
    /// Number of blocks surrounding current code block
    scopeDepth: i32, // Same as clox
    /// Compiler constant Table
    constantTable: *Table,
    /// Compiler string table
    stringTable: *Table,
    /// Switch depth
    switchDepth: u8 = 0,

    // Use same hash across table/objstring,
    // NOTE: ObjString still uses loxHash, but the HashTable uses Clhash if available. This doesn't matter for checking values
    // but should be cleared up in the future. For now we just stick to the defaults...
    // cc.constantTable = Table.initWithHashFn(allocator, if (lib.hasClhash) .clhash else .default);

    pub fn init(allocator: std.mem.Allocator, vm: *VM, @"type": FunctionType) !@This() {
        var locals = std.ArrayList(Local).initCapacity(allocator, 16) catch @panic("Failed to allocate locals array");
        // Claim slot 0 for vm usage
        try locals.append(Local{ .depth = 0, .name = Token{
            .tokenType = TokenType.Error,
            .lexeme = "",
            .error_msg = "VM Reserved Token",
            .line = 0,
        } });
        return .{
            .locals = locals,
            .scopeDepth = 0,
            .stringTable = try Table.init(allocator),
            .constantTable = try Table.initWithHashFn(allocator, .default),
            .function = try lib.newFunction(vm, null, null),
            .type = @"type",
        };
    }
    pub fn deinit(self: *@This()) void {
        self.stringTable.deinit();
        self.constantTable.deinit();
        self.locals.deinit();
        self.* = undefined;
    }
    /// Number of locals in Compiler.locals as usize
    inline fn localCount(self: *const @This()) usize {
        return self.locals.items.len;
    }
    fn resolveLocal(self: *Compiler, name: *const Token) CompilerError!u16 {
        if (self.localCount() == 0) return CompilerError.LocalNotFound;
        var i: u16 = @intCast(self.localCount() - 1); // Safe: we never add more than MAX_LOCAL_COUNT locals

        while (true) {
            const local = &self.locals.items[i];
            if (identifiersEqual(&local.name, name)) {
                if (local.depth == -1) {
                    Error("Cannot read local variable in its own initializer.");
                    return CompilerError.SameInitializer;
                }
                return i;
            }

            if (i == 0) break;
            i -= 1;
        }
        return CompilerError.LocalNotFound;
    }
};

pub const Local = struct {
    name: Token,
    depth: i32,
};

const FunctionType = enum {
    Function,
    Script,
};

const ObjFunction = @import("object.zig").ObjFunction;
