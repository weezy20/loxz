pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    if (try file_or_repl(allocator)) |filename| {
        defer allocator.free(filename);
        if (validate_file(filename) catch |err| {
            dbg("Error: {s}", .{@errorName(err)});
            std.process.exit(1);
        }) {
            dbg("Running loxz on File: {s}\n", .{filename});
        } else {
            dbg("Invalid file extension, exiting...", .{});
            std.process.exit(1);
        }
    } else {
        dbg("Dev Mode\n", .{});
    }
    var chunk = lib.Chunk.init(&allocator);
    defer chunk.deinit();
    const idx = try chunk.addConstant(lib.Value{ .Number = 1.0e10 });
    if (idx > std.math.maxInt(u8)) {
        dbg("More than 256 constants in one chunk\n", .{});
        std.process.exit(1);
    }
    var debugInfo = try lib.DebugInfo.init(allocator, 8);
    defer debugInfo.deinit();
    try chunk.writeWithDebugInfo(@as(u8, @intFromEnum(op.CONSTANT)), &debugInfo, 1, .{ 0, 6 }); // Write the index of the constant in the constant pool
    try chunk.writeWithDebugInfo(@as(u8, @intCast(try chunk.addConstant(lib.Value{ .String = "hello world" }))), &debugInfo, 1, .{ 5, 6 }); // Write the index of the constant in the constant pool
    try chunk.writeWithDebugInfo(@intFromEnum(op.RETURN), &debugInfo, 2, .{ 0, 6 }); // Write a return instruction

    try chunk.disassemble("test chunk", &debugInfo);
}

/// Check cli args to decide to run loxz on file path or repl mode
fn file_or_repl(allocator: std.mem.Allocator) !?[]u8 {
    // Parse args into string array
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2) {
        // type corecion to path.resolve could also look like args[1][0..] -> []u8 then &.{ []u8 } for slice into array into slice of slice
        // const path = try std.fs.path.resolve(allocator, &.{args[1][0..]});
        const path = try std.fs.path.resolve(allocator, &[_][]const u8{args[1][0..]});
        return path;
    } else if (args.len > 2) {
        dbg("Usage: loxz <file.lox>", .{});
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
const dbg = std.debug.print;
const op = lib.OpCode;
