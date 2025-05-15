const std = @import("std");
const t = std.testing;
const Scanner = @import("scanner.zig");
const TokenType = Scanner.TokenType;

test "scanner: numbers and decimals" {
    const source = "123 45.67 89. .123";
    var scanner = Scanner.init(source);

    // Test integer
    const token1 = scanner.scanToken();
    try t.expectEqual(TokenType.Number, token1.tokenType);
    try t.expectEqualStrings("123", token1.lexeme);

    // Test decimal
    const token2 = scanner.scanToken();
    try t.expectEqual(TokenType.Number, token2.tokenType);
    try t.expectEqualStrings("45.67", token2.lexeme);

    // Test invalid decimal (should be error)
    const token3 = scanner.scanToken();
    try t.expectEqual(TokenType.Error, token3.tokenType);
    try t.expectEqualStrings("No number after decimal point", token3.lexeme);

    // Test decimal starting with . which is invalid and should be parsed as a dot
    const token4 = scanner.scanToken();
    try t.expectEqual(TokenType.Dot, token4.tokenType);
    try t.expectEqualStrings(".", token4.lexeme);
    // Second dot
    const token5 = scanner.scanToken();
    try t.expectEqual(TokenType.Dot, token4.tokenType);
    try t.expectEqualStrings(".", token5.lexeme);

    // Test final number
    const token6 = scanner.scanToken();
    try t.expectEqual(TokenType.Number, token6.tokenType);

    const token7 = scanner.scanToken();
    try t.expectEqual(TokenType.Eof, token7.tokenType);
}

test "scanner: identifiers" {
    const source = "foo bar_baz _qux123";
    var scanner = Scanner.init(source);

    const token1 = scanner.scanToken();
    try t.expectEqual(TokenType.Identifier, token1.tokenType);
    try t.expectEqualStrings("foo", token1.lexeme);

    const token2 = scanner.scanToken();
    try t.expectEqual(TokenType.Identifier, token2.tokenType);
    try t.expectEqualStrings("bar_baz", token2.lexeme);

    const token3 = scanner.scanToken();
    try t.expectEqual(TokenType.Identifier, token3.tokenType);
    try t.expectEqualStrings("_qux123", token3.lexeme);

    const token4 = scanner.scanToken();
    try t.expectEqual(TokenType.Eof, token4.tokenType);
}

test "scanner: keywords" {
    const source = "and class else false for fun if nil or print return super this true var while";
    var scanner = Scanner.init(source);

    const expected = [_]TokenType{
        TokenType.And,
        TokenType.Class,
        TokenType.Else,
        TokenType.False,
        TokenType.For,
        TokenType.Fun,
        TokenType.If,
        TokenType.Nil,
        TokenType.Or,
        TokenType.Print,
        TokenType.Return,
        TokenType.Super,
        TokenType.This,
        TokenType.True,
        TokenType.Var,
        TokenType.While,
    };

    for (expected) |expected_type| {
        const token = scanner.scanToken();
        try t.expectEqual(expected_type, token.tokenType);
    }

    const eof = scanner.scanToken();
    try t.expectEqual(TokenType.Eof, eof.tokenType);
}

test "scanner: punctuations and operators" {
    const source = "(){};,.-+/*! != == = <= < >= >";
    var scanner = Scanner.init(source);

    const expected = [_]struct { TokenType, []const u8 }{
        .{ TokenType.LeftParen, "(" },
        .{ TokenType.RightParen, ")" },
        .{ TokenType.LeftBrace, "{" },
        .{ TokenType.RightBrace, "}" },
        .{ TokenType.Semicolon, ";" },
        .{ TokenType.Comma, "," },
        .{ TokenType.Dot, "." },
        .{ TokenType.Minus, "-" },
        .{ TokenType.Plus, "+" },
        .{ TokenType.Slash, "/" },
        .{ TokenType.Star, "*" },
        .{ TokenType.Bang, "!" },
        .{ TokenType.BangEqual, "!=" },
        .{ TokenType.EqualEqual, "==" },
        .{ TokenType.Equal, "=" },
        .{ TokenType.LessEqual, "<=" },
        .{ TokenType.Less, "<" },
        .{ TokenType.GreaterEqual, ">=" },
        .{ TokenType.Greater, ">" },
    };

    for (expected) |item| {
        const token = scanner.scanToken();
        try t.expectEqual(item[0], token.tokenType);
        try t.expectEqualStrings(item[1], token.lexeme);
    }

    const eof = scanner.scanToken();
    try t.expectEqual(TokenType.Eof, eof.tokenType);
}

test "scanner: strings" {
    const source = "\"hello\" \"world\" \"unterminated";
    var scanner = Scanner.init(source);

    const token1 = scanner.scanToken();
    try t.expectEqual(TokenType.String, token1.tokenType);
    try t.expectEqualStrings("\"hello\"", token1.lexeme);

    const token2 = scanner.scanToken();
    try t.expectEqual(TokenType.String, token2.tokenType);
    try t.expectEqualStrings("\"world\"", token2.lexeme);

    const token3 = scanner.scanToken();
    try t.expectEqual(TokenType.Error, token3.tokenType);
    try t.expectEqualStrings("Unterminated string literal", token3.lexeme);
}

test "scanner: whitespace and comments" {
    const source =
        \\ 123 // This is a comment
        \\ 456
        \\ // Another comment
        \\ 789
    ;
    var scanner = Scanner.init(source);

    const token1 = scanner.scanToken();
    try t.expectEqual(TokenType.Number, token1.tokenType);
    try t.expectEqualStrings("123", token1.lexeme);

    const token2 = scanner.scanToken();
    try t.expectEqual(TokenType.Number, token2.tokenType);
    try t.expectEqualStrings("456", token2.lexeme);

    const token3 = scanner.scanToken();
    try t.expectEqual(TokenType.Number, token3.tokenType);
    try t.expectEqualStrings("789", token3.lexeme);

    const eof = scanner.scanToken();
    try t.expectEqual(TokenType.Eof, eof.tokenType);
}

test "scanner: error handling" {
    const source = "@ # $";
    var scanner = Scanner.init(source);

    const token1 = scanner.scanToken();
    try t.expectEqual(TokenType.Error, token1.tokenType);
    try t.expectEqualStrings("Unexpected character", token1.lexeme);

    const token2 = scanner.scanToken();
    try t.expectEqual(TokenType.Error, token2.tokenType);
    try t.expectEqualStrings("Unexpected character", token2.lexeme);

    const token3 = scanner.scanToken();
    try t.expectEqual(TokenType.Error, token3.tokenType);
    try t.expectEqualStrings("Unexpected character", token3.lexeme);

    const eof = scanner.scanToken();
    try t.expectEqual(TokenType.Eof, eof.tokenType);
}

test "scanner: line counting" {
    const source =
        \\123
        \\456
        \\789
    ;
    var scanner = Scanner.init(source);

    const token1 = scanner.scanToken();
    try t.expectEqual(@as(u32, 0), token1.line);

    const token2 = scanner.scanToken();
    try t.expectEqual(@as(u32, 1), token2.line);

    const token3 = scanner.scanToken();
    try t.expectEqual(@as(u32, 2), token3.line);

    const eof = scanner.scanToken();
    try t.expectEqual(@as(u32, 2), eof.line);
}
