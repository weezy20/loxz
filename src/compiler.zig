pub fn compile(source: []const u8, opts: ?struct { debug: bool, stack_tracing: bool }) void {
    _ = opts;
    var sc = @import("scanner.zig").init(source);
    sc.debugTokens();
}

const std = @import("std");
