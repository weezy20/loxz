//! Loxz command line interface

const clap = @import("clap");
const std = @import("std");
const lib = @import("loxz");
const VM = lib.VM;

pub const Config = struct {
    debug: bool,
    debug_level: u8,
    stack_tracing: bool,
    file_path: ?[]const u8,
    repl_mode: bool = undefined,
};
fn setup() void {
    lib.initHash();
}

pub fn parseArgs(allocator: std.mem.Allocator) !Config {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                     Display this help message and exit
        \\-d, --debug                    Enable debug mode
        \\-t, --stack-tracing            Enable stack traces
        \\<str>                          Optional path to .lox file
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .terminating_positional = 0,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
        std.process.exit(0);
    }
    setup();
    return .{
        // Provide false as default if the flags weren't provided
        .debug = res.args.debug != 0,
        .debug_level = if (res.args.debug > 0) res.args.debug else 0,
        .stack_tracing = res.args.@"stack-tracing" != 0,
        .file_path = if (res.positionals.len > 0) blk: {
            const filename: []const u8 = res.positionals[0] orelse break :blk null;
            const file = try std.fs.path.resolve(allocator, &[_][]const u8{filename});
            validate_file(file) catch |err| {
                switch (err) {
                    error.InvalidExtension, error.FileNotFound => {
                        std.log.warn("Invalid file '{s}': must be an existing .lox file", .{filename});
                        return err;
                    },
                    else => return err,
                }
            };
            break :blk file;
        } else null,
    };
}

/// Validate the file extension. Returns:
/// - Valid if the file exists AND ends with exactly `.lox`
/// - Invalid for every other extension
fn validate_file(file: []const u8) !void {
    const lox_ext = ".lox";
    // Must have at least one character before `.lox` (e.g., `a.lox`)
    if (file.len <= lox_ext.len) return error.InvalidFilename;

    // Extract the last 4 characters
    const ext_start = file.len - lox_ext.len;
    const extension = file[ext_start..];

    // Case-sensitive exact match
    if (!std.mem.eql(u8, extension, lox_ext)) return error.InvalidExtension;

    // Check if the file exists in the filesystem
    const file_exists = try std.fs.cwd().openFile(file, .{ .mode = .read_only });
    file_exists.close();
}

pub fn repl(allocator: std.mem.Allocator, config: *Config) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    try stdout.writeAll("\u{1F4BB} Welcome to the Loxz REPL! Write some Lox code [use \\\u{23CE} to continue lines]\n");

    if (config.debug) {
        try stdout.writeAll("Debug mode is enabled.");
        if (config.debug_level > 1) {
            try stdout.print(" Debug level {}.", .{config.debug_level});
        }
        try stdout.writeAll("\n");
    }
    if (config.stack_tracing) {
        try stdout.writeAll("Stack tracing is enabled.\n");
    }
    config.repl_mode = true;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 128);
    defer buffer.deinit();
    var line_buf: [2048]u8 = [_]u8{0} ** 2048;
    var multi_line = false;
    var vm = lib.initVM(allocator);
    defer lib.deinitVM(&vm);
    while (true) {
        if (!multi_line) {
            try stdout.writeAll(">> ");
        } else {
            try stdout.writeAll("...  ");
        }
        // This is a subslice of `line_buf`
        const bytes_read = try stdin.readUntilDelimiter(&line_buf, '\n');
        std.debug.assert(bytes_read.ptr == &line_buf);
        try buffer.appendSlice(bytes_read);

        // Check if the line ends with '\' (escaped newline)
        if (buffer.items.len > 0 and buffer.items[buffer.items.len - 1] == '\\') {
            // Remove the '\' and keep reading
            _ = buffer.pop(); // Remove trailing backslash
            buffer.append('\n') catch unreachable;
            multi_line = true;
            continue; // Read next line
        } else {
            multi_line = false;
        }
        // REPL: "exit" command
        if (std.mem.eql(u8, buffer.items, "exit")) {
            try stdout.writeAll("Exiting REPL. Goodbye!\n");
            return;
        }

        const result = interpret(buffer.items, config, allocator, &vm) catch |err| {
            std.debug.print("Unhandled exception: {s}\n", .{@errorName(err)});
            buffer.clearRetainingCapacity(); // clear bytes but don't resize without need
            continue;
        };
        if (result != .ok) {
            vm.resetStack();
            lib.resetParser();
        }
        buffer.clearRetainingCapacity(); // clear bytes but don't resize without need
    }
}

pub fn run_file(allocator: std.mem.Allocator, config: *Config) !void {
    const file_path = config.file_path.?;
    const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
    const file_size = if (file.stat()) |s| s.size else |_| blk: {
        std.debug.print("Warning: Failed to get file stats for '{s}'. Using default size.\n", .{file_path});
        break :blk 999_999;
    };
    file.close();

    const source = try std.fs.cwd().readFileAlloc(allocator, file_path, file_size);
    std.debug.assert(source.len == file_size);
    defer allocator.free(source);

    var vm = lib.initVM(allocator);
    defer lib.deinitVM(&vm);
    config.repl_mode = false;
    _ = interpret(source, config, allocator, &vm) catch |err| {
        std.debug.print("Unhandled exception: {s}\n", .{@errorName(err)});
        std.process.exit(69);
    };
}
/// Compile source code into a chunk then load it into the VM and interpret it
fn interpret(source: []const u8, config: *const Config, allocator: std.mem.Allocator, vm: *VM) !InterpretResult {
    var chunk = lib.Chunk.init(&allocator);
    defer chunk.deinit();
    const compile_result = lib.compile(source, &chunk, vm, allocator, .{
        .debug = config.debug,
        .debug_level = config.debug_level,
        .repl_mode = config.repl_mode,
    });
    var compilerTable = compile_result.stringTable;
    defer {
        if (compile_result.debugInfo) |d| {
            d.deinit();
            allocator.destroy(d);
        }
    }
    if (!compile_result.success) {
        compilerTable.deinit();
        return .compile_error;
    }
    return lib.interpret(vm, &chunk, .{
        .stack_tracing = config.stack_tracing,
        .debug_level = config.debug_level,
        .debugInfo = compile_result.debugInfo,
        .init_string_table = if (compilerTable.count > 0) &compilerTable else null,
    });
}

const InterpretResult = @import("loxz").InterpretResult;
