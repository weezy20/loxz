const std = @import("std");
const debug = @import("debug.zig");
const DebugInfo = debug.DebugInfo;
const Allocator = std.mem.Allocator;
const Location = debug.Location;
const ColumnSpan = debug.ColumnSpan;
const LineRun = debug.LineRun;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "DebugInfo.addLocation creates new line run for new line" {
    var debug_info = try DebugInfo.init(std.testing.allocator, null, null);
    defer debug_info.deinit();

    // First location
    try debug_info.addLocation(.{
        .offset = 0,
        .line = 1,
        .start_column = 5,
        .end_column = 10,
    });

    // Second location on same line - should extend run
    try debug_info.addLocation(.{
        .offset = 1,
        .line = 1,
        .start_column = 11,
        .end_column = 15,
    });

    // Third location on new line - should create new run
    try debug_info.addLocation(.{
        .offset = 2,
        .line = 2,
        .start_column = 1,
        .end_column = 5,
    });

    try expectEqual(@as(usize, 2), debug_info.line_runs.items.len);
    try expectEqual(@as(usize, 3), debug_info.col_spans.items.len);

    // Verify first run
    try expectEqual(@as(usize, 0), debug_info.line_runs.items[0].start_offset);
    try expectEqual(@as(usize, 2), debug_info.line_runs.items[0].length);
    try expectEqual(@as(usize, 1), debug_info.line_runs.items[0].line);

    // Verify second run
    try expectEqual(@as(usize, 2), debug_info.line_runs.items[1].start_offset);
    try expectEqual(@as(usize, 1), debug_info.line_runs.items[1].length);
    try expectEqual(@as(usize, 2), debug_info.line_runs.items[1].line);
}

test "DebugInfo.getLocation finds correct location" {
    var debug_info = try DebugInfo.init(std.testing.allocator, null, null);
    defer debug_info.deinit();

    // Add some locations
    try debug_info.addLocation(.{
        .offset = 0,
        .line = 1,
        .start_column = 5,
        .end_column = 10,
    });
    try debug_info.addLocation(.{
        .offset = 1,
        .line = 1,
        .start_column = 11,
        .end_column = 15,
    });
    try debug_info.addLocation(.{
        .offset = 2,
        .line = 2,
        .start_column = 1,
        .end_column = 5,
    });

    // Test getting locations
    const loc0 = debug_info.getLocation(0) orelse {
        try expect(false); // force test failure
        return;
    };
    try expectEqual(@as(usize, 0), loc0.offset);
    try expectEqual(@as(usize, 1), loc0.line);
    try expectEqual(@as(usize, 5), loc0.start_column);
    try expectEqual(@as(usize, 10), loc0.end_column);

    const loc1 = debug_info.getLocation(1) orelse {
        try expect(false); // force test failure
        return;
    };
    try expectEqual(@as(usize, 1), loc1.offset);
    try expectEqual(@as(usize, 1), loc1.line);
    try expectEqual(@as(usize, 11), loc1.start_column);
    try expectEqual(@as(usize, 15), loc1.end_column);

    const loc2 = debug_info.getLocation(2) orelse {
        try expect(false); // force test failure
        return;
    };
    try expectEqual(@as(usize, 2), loc2.offset);
    try expectEqual(@as(usize, 2), loc2.line);
    try expectEqual(@as(usize, 1), loc2.start_column);
    try expectEqual(@as(usize, 5), loc2.end_column);

    // Test non-existent location
    try expect(debug_info.getLocation(3) == null);
}

test "DebugInfo.getLocation works with binary search for large spans" {
    var debug_info = try DebugInfo.init(std.testing.allocator, null, null);
    defer debug_info.deinit();

    // Add enough locations to trigger binary search
    const count = 100;
    for (0..count) |i| {
        try debug_info.addLocation(.{
            .offset = i,
            .line = @intCast(i / 10 + 1), // 10 instructions per line
            .start_column = @intCast(i % 20),
            .end_column = @intCast(i % 20 + 5),
        });
    }

    // Test random locations
    const loc0 = debug_info.getLocation(0) orelse {
        try expect(false); // force test failure
        return;
    };
    try expectEqual(@as(usize, 0), loc0.offset);
    try expectEqual(@as(usize, 1), loc0.line);

    const loc49 = debug_info.getLocation(49) orelse {
        try expect(false); // force test failure
        return;
    };
    try expectEqual(@as(usize, 49), loc49.offset);
    try expectEqual(@as(usize, 5), loc49.line); // 49 / 10 + 1 = 5

    const loc99 = debug_info.getLocation(99) orelse {
        try expect(false); // force test failure
        return;
    };
    try expectEqual(@as(usize, 99), loc99.offset);
    try expectEqual(@as(usize, 10), loc99.line); // 99 / 10 + 1 = 10

    // Test non-existent location
    try expect(debug_info.getLocation(100) == null);
}

test "DebugInfo.getLocation handles empty debug info" {
    var debug_info = try DebugInfo.init(std.testing.allocator, null, null);
    defer debug_info.deinit();

    try expect(debug_info.getLocation(0) == null);
}

test "DebugInfo.addLocation maintains correct column spans" {
    var debug_info = try DebugInfo.init(std.testing.allocator, null, null);
    defer debug_info.deinit();

    // Add locations with same line but different columns
    try debug_info.addLocation(.{
        .offset = 0,
        .line = 1,
        .start_column = 5,
        .end_column = 10,
    });
    try debug_info.addLocation(.{
        .offset = 1,
        .line = 1,
        .start_column = 11,
        .end_column = 15,
    });

    try expectEqual(@as(usize, 2), debug_info.col_spans.items.len);

    // Verify column spans
    try expectEqual(@as(usize, 0), debug_info.col_spans.items[0].offset);
    try expectEqual(@as(usize, 5), debug_info.col_spans.items[0].start_column);
    try expectEqual(@as(usize, 10), debug_info.col_spans.items[0].end_column);

    try expectEqual(@as(usize, 1), debug_info.col_spans.items[1].offset);
    try expectEqual(@as(usize, 11), debug_info.col_spans.items[1].start_column);
    try expectEqual(@as(usize, 15), debug_info.col_spans.items[1].end_column);
}
