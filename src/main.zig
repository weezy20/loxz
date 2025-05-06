pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    if (try file_or_repl(gpa.allocator())) |filename| {
        defer gpa.allocator().free(filename);
        if (validate_file(filename) catch |err| {
            debug("Error: {s}", .{@errorName(err)});
            std.process.exit(1);
        }) {
            debug("Running loxz on File: {s}\n", .{filename});
        } else {
            debug("Invalid file extension, exiting...", .{});
            std.process.exit(1);
        }
    } else {
        debug("Dev Mode\n", .{});
    }
    var chunk = lib.Chunk.init();
    defer chunk.deinit(gpa.allocator());
    for (0..1) |i| {
        try chunk.write(@intCast(i), gpa.allocator());
    }
    try chunk.disassemble("test chunk");
}

/// Check cli args to decide to run loxz on file path or repl mode
fn file_or_repl(allocator: std.mem.Allocator) !?[]u8 {
    // Parse args into string array
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2) {
        // type corecion to path.resolve could also look like args[1][0..] -> []u8 then &.{ []u8 } for slice into array from anonymous struct literal
        // const path = try std.fs.path.resolve(allocator, &.{args[1][0..]});
        const path = try std.fs.path.resolve(allocator, &[_][]const u8{args[1][0..]});
        return path;
    } else if (args.len > 2) {
        debug("Usage: loxz <file.lox>", .{});
    }
    return null;
}

/// Validate the file extension. Returns:
/// - `true` if the file exists AND ends with exactly `.lox`
/// - `false` for every other extension
fn validate_file(file: []const u8) !bool {
    const lox_ext = ".lox";
    // Must have at least one character before `.lox` (e.g., `a.lox`)
    if (file.len <= lox_ext.len) return error.InvalidFilename;

    // Extract the last 4 characters
    const ext_start = file.len - lox_ext.len;
    const extension = file[ext_start..];

    // Case-sensitive exact match
    if (!std.mem.eql(u8, extension, lox_ext)) return false;

    // Check if the file exists in the filesystem
    const file_exists = try std.fs.cwd().openFile(file, .{ .mode = .read_only });
    file_exists.close();

    return true;
}

const lib = @import("loxz");
const std = @import("std");
const debug = std.debug.print;
