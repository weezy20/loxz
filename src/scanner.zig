//! Scanner for Lox

/// Current lexeme being scanned
current: *const u8,
/// Start of the current lexeme byte
start: *const u8,
/// Line information
line: usize,

// Can also be used to track lexemes
const DebugInfo = @import("debug.zig").DebugInfo;
const Scanner = @This();
