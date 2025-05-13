//! Cli utilities

const clap = @import("clap");
const std = @import("std");
const lib = @import("loxz");

pub const Config = struct { debug: bool, stack_tracing: bool, file_path: ?[]const u8 };

pub fn run(allocator: std.mem.Allocator) !Config {
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

    return .{
        // Provide false as default if the flags weren't provided
        .debug = res.args.debug != 0,
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

pub fn repl(allocator: std.mem.Allocator, config: *const Config) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    try stdout.writeAll("Welcome to the Loxz REPL! Write some Lox (use \\ to continue lines)\n");

    if (config.debug) {
        try stdout.writeAll("Debug mode is enabled.\n");
    }
    if (config.stack_tracing) {
        try stdout.writeAll("Stack tracing is enabled.\n");
    }

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    var line_buf: [2048]u8 = [_]u8{0} ** 2048;
    var multi_line = false;

    while (true) {
        if (!multi_line) {
            try stdout.writeAll(">> ");
        } else {
            try stdout.writeAll("...  ");
        }

        const bytes_read = try stdin.readUntilDelimiter(&line_buf, '\n');

        try buffer.appendSlice(bytes_read);

        // Check if the line ends with '\' (escaped newline)
        if (buffer.items.len > 0 and buffer.items[buffer.items.len - 1] == '\\') {
            // Remove the '\' and keep reading
            _ = buffer.pop(); // Remove trailing backslash
            multi_line = true;
            continue; // Read next line
        } else {
            multi_line = false;
        }

        // If we get here, the input is complete
        try stdout.writeAll("You entered: ");
        try stdout.writeAll(buffer.items);
        try stdout.writeAll("\n");

        buffer.clearRetainingCapacity(); // clear bytes but don't resize without need
    }
}

pub fn run_file(allocator: std.mem.Allocator, config: *const Config) !void {
    const file = config.file_path.?;
    const source = try std.fs.cwd().openFile(file, .{ .mode = .read_only });
    defer source.close();

    var buf_reader = std.io.bufferedReader(source.reader());
    const reader = buf_reader.reader();

    while (true) {
        const line = reader.readUntilDelimiterAlloc(allocator, '\n', 4096) catch |err| switch (err) {
            error.EndOfStream => break, // EOF
            else => return err,
        };
        defer allocator.free(line);

        try std.io.getStdOut().writer().print("{s}\n", .{line});
    }
}
