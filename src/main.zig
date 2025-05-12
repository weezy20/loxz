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
    var debugInfo = try lib.DebugInfo.init(allocator, .{});
    defer debugInfo.deinit();
    // uncomment for printing debug info and stack
    var vm = lib.initVM(allocator, .{ .debugInfo = &debugInfo });
    // uncomment for silencing debug info
    // var vm = lib.VM.init(allocator, .{});
    defer vm.deinitVM();
    var chunk = lib.Chunk.init(&allocator);
    defer chunk.deinit(); // deinit of chunk is now handled by VM
    // for (0..300) |i| {
    //     try chunk.writeConstant(lib.Value{ .Number = @floatFromInt(i) }, &debugInfo, i + 1, .{ 0, 2 });
    // }
    try chunk.writeConstant(Value{ .String = "Hello World" }, &debugInfo, 1, .{ 0, 11 });
    try chunk.writeConstant(Value{ .String = "Hello World2" }, &debugInfo, 1, .{ 0, 11 });
    try chunk.writeConstant(Value{ .Number = 10 }, &debugInfo, 1, .{ 0, 11 });
    try chunk.writeWithDebugInfo(@intFromEnum(op.NEGATE), &debugInfo, 2, .{ 0, 6 });
    try chunk.writeConstant(Value{ .Number = 5 }, &debugInfo, 1, .{ 0, 11 });
    try chunk.writeWithDebugInfo(@intFromEnum(op.DIVIDE), &debugInfo, 2, .{ 0, 6 });
    try chunk.writeWithDebugInfo(@intFromEnum(op.RETURN), &debugInfo, 3, .{ 0, 6 });
    // try chunk.disassemble("test chunk", &debugInfo);
    const result = vm.interpret(&chunk);
    switch (result) {
        .ok => {
            std.debug.print("Program executed successfully.\n", .{});
            std.process.exit(0);
        },
        .compile_error => |err| {
            std.debug.print("Compiler Error: {s}\n", .{@errorName(err)});
            std.process.exit(5);
        },
        .runtime_error => |err| {
            std.debug.print("Runtime Error: {s}\n", .{@errorName(err)});
            std.process.exit(3);
        },
    }
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
const Value = lib.Value;
const std = @import("std");
const dbg = std.debug.print;
const op = lib.OpCode;
