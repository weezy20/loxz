comptime {
    _ = @import("root.zig");
    _ = @import("chunk.zig");
    _ = @import("common.zig");
}
test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
