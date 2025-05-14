/// Current lexeme being scanned
current: usize,
/// Start of the current lexeme byte
start: usize,
/// Line information
line: u32,
/// Source slice
source: []const u8,

inline fn isAtEnd(sc: *const Scanner) bool {
    return sc.current == sc.source.len - 1;
}

pub fn init(source: []const u8) Scanner {
    return Scanner{ .source = source, .start = 0, .current = 0, .line = 0 };
}

inline fn makeToken(sc: *const Scanner, @"type": TokenType) Token {
    return Token{ .tokenType = @"type", .line = sc.line, .lexeme = sc.source[sc.start..sc.current] };
}
inline fn errorToken(sc: *const Scanner, msg: []const u8) Token {
    return Token{ .tokenType = TokenType.Error, .line = sc.line, .lexeme = msg };
}

/// Scan from current lexeme until a Token is formed
pub fn scanToken(sc: *Scanner) Token {
    sc.start = sc.current;
    if (sc.isAtEnd())
        return sc.makeToken(TokenType.Eof);
    return sc.errorToken("Unexpected character");
}
pub const Token = struct {
    tokenType: TokenType, // 1 byte
    lexeme: []const u8, // 16 bytes
    line: u32, // 4 bytes
};

fn isDigit(c: u8) bool {
    return '0' <= c and c <= '9';
}

fn isAlpha(char: u8) bool {
    return (('a' <= char and char <= 'z') or
        ('A' <= char and char <= 'Z') or
        char == '_');
}

pub fn printTokens(sc: *Scanner) void {
    var line: u32 = 0;
    while (true) {
        const t = sc.scanToken();
        if (t.line != line) {
            std.debug.print("{d: <4}", .{line});
            line = t.line;
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
