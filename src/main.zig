pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const config = cli.run(allocator) catch |err| {
        std.debug.print("Error parsing CLI : {}\n", .{err});
        std.process.exit(128);
    };
    if (config.file_path) |filename| {
        dbg("Running loxz on File: {s}\n", .{filename});
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
    try chunk.writeWithDebugInfo(@intFromEnum(op.ADD), &debugInfo, 2, .{ 0, 6 });
    try chunk.writeWithDebugInfo(@intFromEnum(op.RETURN), &debugInfo, 3, .{ 0, 6 });
    // try chunk.disassemble("test chunk", &debugInfo);
    const result = vm.interpret(&chunk, .{ .stack_tracing = config.stack_tracing });
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

const lib = @import("loxz");
const Value = lib.Value;
const std = @import("std");
const cli = @import("cli");
const dbg = std.debug.print;
const op = lib.OpCode;
