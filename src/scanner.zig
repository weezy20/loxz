/// Current lexeme being scanned
current: usize,
/// Start of the current lexeme byte
start: usize,
/// Line information
line: u32,
/// Source slice
source: []const u8,

pub fn init(source: []const u8) Scanner {
    return Scanner{ .source = source, .start = 0, .current = 0, .line = 0 };
}
inline fn makeToken(sc: *const Scanner, @"type": TokenType) Token {
    return Token{
        .tokenType = @"type",
        .line = sc.line,
        .lexeme = sc.source[sc.start..sc.current],
    };
}
inline fn errorToken(sc: *const Scanner, msg: []const u8) Token {
    return Token{
        .tokenType = TokenType.Error,
        .line = sc.line,
        .lexeme = sc.source[sc.start..sc.current],
        .error_msg = msg,
    };
}
/// If current == source.len, return true
inline fn isAtEnd(sc: *const Scanner) bool {
    return sc.current == sc.source.len;
}
/// Unsafe. Unchecked increment current index and return the previous byte
pub inline fn advance(sc: *Scanner) u8 {
    if (!sc.isAtEnd()) {
        sc.current += 1;
    }
    return sc.source[sc.current - 1];
}
/// Check `current` byte and increment it if it matches `expected`
inline fn match(sc: *Scanner, expected: u8) bool {
    if (sc.isAtEnd()) return false; // Safety: prevent out of bounds access
    if (sc.source[sc.current] != expected) return false;
    sc.current += 1;
    return true;
}
/// Peek the current byte without incrementing `current`. Returns null if we're out of bounds.
inline fn peek(sc: *const Scanner) ?u8 {
    if (sc.isAtEnd()) return null; // Safety: prevent out of bounds access
    return sc.source[sc.current];
}
/// Peek the next byte without incrementing `current`. Returns null if we're out of bounds.
inline fn peekNext(sc: *const Scanner) ?u8 {
    if (sc.current + 1 >= sc.source.len) return null; // Safety: prevent out of bounds access
    return sc.source[sc.current + 1];
}
/// Skip whitespace and newline (increment scanner line on `\n`)
inline fn skipNonTokens(sc: *Scanner) void {
    while (true) {
        if (sc.isAtEnd()) return;
        const c = sc.source[sc.current];
        switch (c) {
            ' ', '\r', '\t' => sc.current += 1,
            '\n' => {
                sc.line += 1;
                sc.current += 1;
            },
            '/' => {
                if (sc.peekNext() == '/') {
                    while (sc.peek() != '\n' and !sc.isAtEnd()) sc.current += 1;
                } else return;
            },
            else => break,
        }
    }
}
/// Returns a string
inline fn string(sc: *Scanner) Token {
    while (sc.peek() != '"' and !sc.isAtEnd()) : (sc.current += 1) {
        if (sc.peek() == '\n') {
            sc.line += 1;
        }
    }
    if (sc.isAtEnd()) return sc.errorToken("Unterminated string literal");
    sc.current += 1;
    return sc.makeToken(TokenType.String);
}
fn checkKeyword(sc: *Scanner, start: usize, length: usize, rest: []const u8, keywordTokenType: TokenType) TokenType {
    if (sc.current - sc.start == start + length and
        std.mem.eql(u8, sc.source[sc.start + start .. sc.start + start + length], rest))
    {
        return keywordTokenType;
    }
    return TokenType.Identifier;
}
/// Check identifier for keyword
fn identifierType(sc: *Scanner) TokenType {
    switch (sc.source[sc.start]) {
        'a' => return sc.checkKeyword(1, 2, "nd", TokenType.And),
        'c' => return sc.checkKeyword(1, 4, "lass", TokenType.Class),
        'e' => return sc.checkKeyword(1, 3, "lse", TokenType.Else),
        'i' => return sc.checkKeyword(1, 1, "f", TokenType.If),
        'n' => return sc.checkKeyword(1, 2, "il", TokenType.Nil),
        'o' => return sc.checkKeyword(1, 1, "r", TokenType.Or),
        'p' => return sc.checkKeyword(1, 4, "rint", TokenType.Print),
        'r' => return sc.checkKeyword(1, 5, "eturn", TokenType.Return),
        's' => return sc.checkKeyword(1, 4, "uper", TokenType.Super),
        'v' => return sc.checkKeyword(1, 2, "ar", TokenType.Var),
        'w' => return sc.checkKeyword(1, 4, "hile", TokenType.While),
        'f' => {
            if (sc.current - sc.start == 1) {
                return TokenType.Identifier;
            }
            switch (sc.source[sc.start + 1]) {
                'a' => return sc.checkKeyword(2, 3, "lse", TokenType.False),
                'o' => return sc.checkKeyword(2, 1, "r", TokenType.For),
                'u' => return sc.checkKeyword(2, 1, "n", TokenType.Fun),
                else => return TokenType.Identifier,
            }
        },
        't' => {
            if (sc.current - sc.start == 1) {
                return TokenType.Identifier;
            }
            switch (sc.source[sc.start + 1]) {
                'r' => return sc.checkKeyword(2, 2, "ue", TokenType.True),
                'h' => return sc.checkKeyword(2, 2, "is", TokenType.This),
                else => return TokenType.Identifier,
            }
        },
        else => return TokenType.Identifier,
    }
}
inline fn identifier(sc: *Scanner) Token {
    while (sc.peek()) |id| {
        if (isAlpha(id) or isDigit(id)) {
            sc.current += 1;
        } else break;
    }
    return sc.makeToken(sc.identifierType());
}
inline fn number(sc: *Scanner) Token {
    // Consume integer part digits. peek() ensures !sc.isAtEnd()
    while (sc.peek()) |val| {
        if (isDigit(val)) {
            sc.current += 1;
        } else {
            break;
        }
    }
    // Check for decimal point and fractional part
    if (sc.peek()) |dec| {
        if (dec == '.' and if (sc.peekNext()) |val| isDigit(val) else false) {
            sc.current += 1; // Consume the '.'
            // Consume fractional digits
            while (sc.peek()) |val| {
                if (isDigit(val)) {
                    sc.current += 1;
                } else {
                    break;
                }
            }
        } else if (dec == '.') {
            // Still in decimal, we should find at least one digit after the decimal point
            return sc.errorToken("No number after decimal point");
        }
    }
    return sc.makeToken(TokenType.Number);
}
/// Scan from current lexeme until a Token is formed
pub fn scanToken(sc: *Scanner) Token {
    sc.skipNonTokens();
    sc.start = sc.current;
    if (sc.isAtEnd())
        return sc.makeToken(TokenType.Eof);
    const byte = sc.advance();
    if (isDigit(byte)) return sc.number() else if (isAlpha(byte)) return sc.identifier();
    switch (byte) {
        '(' => return makeToken(sc, TokenType.LeftParen),
        ')' => return makeToken(sc, TokenType.RightParen),
        '{' => return makeToken(sc, TokenType.LeftBrace),
        '}' => return makeToken(sc, TokenType.RightBrace),
        ';' => return makeToken(sc, TokenType.Semicolon),
        ',' => return makeToken(sc, TokenType.Comma),
        '.' => return makeToken(sc, TokenType.Dot),
        '-' => return makeToken(sc, TokenType.Minus),
        '+' => return makeToken(sc, TokenType.Plus),
        '/' => return makeToken(sc, TokenType.Slash),
        '*' => return makeToken(sc, TokenType.Star),
        '!' => return if (sc.match('='))
            makeToken(sc, TokenType.BangEqual)
        else
            makeToken(sc, TokenType.Bang),
        '=' => return if (sc.match('='))
            makeToken(sc, TokenType.EqualEqual)
        else
            makeToken(sc, TokenType.Equal),
        '<' => return if (sc.match('='))
            makeToken(sc, TokenType.LessEqual)
        else
            makeToken(sc, TokenType.Less),
        '>' => return if (sc.match('='))
            makeToken(sc, TokenType.GreaterEqual)
        else
            makeToken(sc, TokenType.Greater),
        '"' => return sc.string(),

        else => return sc.errorToken("Unexpected character"),
    }
}
pub const Token = struct {
    tokenType: TokenType, // 1 byte
    lexeme: []const u8, // 16 bytes
    line: u32, // 4 bytes
    error_msg: ?[]const u8 = null, // 16 bytes
};

fn isDigit(c: u8) bool {
    return '0' <= c and c <= '9';
}

fn isAlpha(char: u8) bool {
    return (('a' <= char and char <= 'z') or
        ('A' <= char and char <= 'Z') or
        char == '_');
}
/// Print tokens to stderr
pub fn printTokens(sc: *Scanner) void {
    var line: u32 = undefined;
    while (true) {
        const t = sc.scanToken();
        if (t.line != line) {
            line = t.line;
            std.debug.print("{d: <4}", .{line});
        } else {
            std.debug.print("   | ", .{});
        }
        std.debug.print("{any} '{s}'\n", .{ t.tokenType, t.lexeme });
        if (t.tokenType == TokenType.Eof) break;
    }
}

// Can also be used to track lexemes
const DebugInfo = @import("debug.zig").DebugInfo;
const Scanner = @This();
const std = @import("std");

pub const TokenType = enum(u8) {
    // Single-character tokens.
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Slash,
    Star,

    // One or two character tokens.
    Bang,
    BangEqual,
    Equal,
    EqualEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,

    // Literals.
    Identifier,
    String,
    Number,

    // Keywords.
    And,
    Class,
    Else,
    False,
    For,
    Fun,
    If,
    Nil,
    Or,
    Print,
    Return,
    Super,
    This,
    True,
    Var,
    While,
    Error,
    Eof,
};
