//! Cli utilities

const clap = @import("clap");
const std = @import("std");

pub fn run(allocator: std.mem.Allocator) !struct { debug: bool, stack_tracing: bool, file_path: ?[]const u8 } {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help message and exit
        \\-d, --debug           Enable debug mode
        \\-t, --tracing         Enable stack traces
        \\<str>                 Optional path to .lox file
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
        .stack_tracing = res.args.tracing != 0,
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
