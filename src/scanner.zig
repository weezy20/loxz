/// Current lexeme being scanned
current: *const u8,
/// Start of the current lexeme byte
start: *const u8,
/// Line information
line: u32,

pub fn init(source: []const u8) Scanner {
    return Scanner{ .start = &source[0], .current = &source[0], .line = 0 };
}

pub fn scanToken(sc: *Scanner) Token {
    _ = sc;
    return .{ .tokenType = TokenType.Eof, .lexeme = "lmao", .line = 1 };
}
pub const Token = struct {
    tokenType: TokenType, // 1 byte
    lexeme: []const u8, // 2 bytes
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

pub fn debugTokens(sc: *Scanner) void {
    var line: u32 = 0;
    while (true) {
        const t = sc.scanToken();
        if (t.line != line) {
            std.debug.print("{d: <4}", .{line});
            line = t.line;
        } else {
            std.debug.print("   |", .{});
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
