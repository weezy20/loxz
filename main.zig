pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    // const allocator = arena.allocator();
    // defer arena.deinit();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();
    // const allocator = std.heap.c_allocator;
    cli.setup();
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
        return cli.repl(allocator, &config);
    }
}

const std = @import("std");
const cli = @import("cli");
