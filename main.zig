pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const config = cli.run(allocator) catch |err| {
        std.debug.print("Error parsing CLI : {}\n", .{err});
        std.process.exit(128);
    };
    defer if (config.file_path) |f| {
        allocator.free(f);
    };
    if (config.file_path) |_| {
        return cli.run_file(allocator, &config);
    } else {
        return cli.repl(allocator, &config);
    }
}

const std = @import("std");
const cli = @import("cli");
