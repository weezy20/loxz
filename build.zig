const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add CLHash as a static library
    const clhash = b.addStaticLibrary(.{
        .name = "clhash",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    clhash.addIncludePath(b.path("src/clhash/include"));
    clhash.addCSourceFile(.{
        .file = b.path("src/clhash/src/clhash.c"),
        .flags = &.{
            "-std=c99",
            "-msse4.2",
            "-mpclmul",
            "-march=native",
            "-funroll-loops",
        },
    });

    // Install the library
    b.installArtifact(clhash);

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.linkLibrary(clhash);
    lib_mod.addIncludePath(b.path("src/clhash/include"));

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const clap = b.dependency("clap", .{});
    const cli = b.createModule(.{
        .root_source_file = b.path("cli/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli.addImport("clap", clap.module("clap"));
    cli.addImport("loxz", lib_mod);

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    exe_mod.addImport("cli", cli);

    const exe = b.addExecutable(.{
        .name = "loxz",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/tests.zig"),
        .link_libc = true,
    });
    test_mod.linkLibrary(clhash);
    test_mod.addIncludePath(b.path("src/clhash/include"));

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
