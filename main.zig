pub fn main() !void {
    // TODO: Switch back to GPA after implementing GC to catch memory leaks
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();
    // defer _ = gpa.deinit();

    // Using c_allocator to bypass memory leak detection until GC is implemented
    const allocator = std.heap.c_allocator;
    var config = cli.parseArgs(allocator) catch |err| {
        std.debug.print("Error parsing CLI : {}\n", .{err});
        std.process.exit(128);
    };
    defer if (config.file_path) |f| {
        allocator.free(f);
    };
    if (config.file_path) |_| {
        return cli.run_file(allocator, &config);
    } else {
        return cli.repl(&config);
    }
}

const std = @import("std");
const cli = @import("cli");
