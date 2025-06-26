pub usingnamespace @import("common.zig");
pub usingnamespace @import("chunk.zig");
pub usingnamespace @import("value.zig");
pub usingnamespace @import("debug.zig");
pub usingnamespace @import("vm.zig");
pub usingnamespace @import("compiler.zig");
pub usingnamespace @import("error.zig");
pub usingnamespace @import("object.zig");
pub usingnamespace @import("table.zig");

const std = @import("std");
const build_options = @import("build_options");

// Make hasClhash a comptime constant
pub const hasClhash = build_options.has_clhash;
var RANDOM: ?*anyopaque = null;

// Conditionally define the functions
pub const ClHash = if (hasClhash) struct {
    const clhash = @cImport({
        @cInclude("clhash.h");
    });

    pub fn init() void {
        if (RANDOM == null) {
            RANDOM = clhash.get_random_key_for_clhash(0x23a23cf5033c3c81, 0xb3816f6a2c68e530) orelse @panic("Failed to initialize CLHash random key");
        } else {
            @panic("CLHash already initialized");
        }
    }

    pub fn hash(key: []const u8) u64 {
        std.debug.assert(RANDOM != null);
        std.debug.print("\n\n\n\nUsing CLHash for key: {s}\n", .{key});
        return clhash.clhash(RANDOM, key.ptr, key.len);
    }
} else struct {
    pub fn init() void {}
    pub fn hash(s: []const u8) u64 {
        std.debug.print("CLHash is not enabled, using fallback hash function.\n", .{});
        return @import("table.zig").loxHash(s);
    }
};

// Initialize during startup
pub fn initHash() void {
    if (hasClhash) {
        ClHash.init();
    }
}
