//! Cli utilities

const cli = @import("clap");
const std = @import("std");

pub fn run(allocator: std.mem.Allocator) struct { stack_tracing: bool } {
    _ = allocator;
    return .{ .stack_tracing = false };
}
