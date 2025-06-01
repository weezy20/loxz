const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clhash_c_source_path = "src/clhash/src/clhash.c";
    const clhash_include_path = "src/clhash/include";
    const use_clhash = blk: {
        var c_source_exists = false;
        var include_exists = false;

        if (std.fs.cwd().access(clhash_c_source_path, .{})) |_| {
            c_source_exists = true;
        } else |_| {}
        if (std.fs.cwd().access(clhash_include_path, .{})) |_| {
            include_exists = true;
        } else |_| {}

        break :blk c_source_exists and include_exists;
    };

    // std.debug.print("use_clhash: {}\n", .{use_clhash});
    // if (use_clhash) {
    //     std.log.info("clhash submodule found, building..", .{});
    // }

    const build_options = b.addOptions();
    build_options.addOption(bool, "has_clhash", use_clhash);

    var clhash_static_lib: ?*std.Build.Step.Compile = null;
    if (use_clhash) {
        const clhash = b.addStaticLibrary(.{
            .name = "clhash",
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        clhash.addIncludePath(b.path(clhash_include_path));
        clhash.addCSourceFile(.{
            .file = b.path(clhash_c_source_path),
            .flags = &.{
                "-std=c99",
                "-msse4.2",
                "-mpclmul",
                "-march=native",
                "-funroll-loops",
            },
        });
        clhash_static_lib = clhash;
    }

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = use_clhash,
    });
    lib_mod.addOptions("build_options", build_options); // Make `has_clhash` available in lib_mod

    if (use_clhash and clhash_static_lib != null) {
        lib_mod.linkLibrary(clhash_static_lib.?);
        lib_mod.addIncludePath(b.path(clhash_include_path));
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = use_clhash,
    });
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });
    const cli = b.createModule(.{
        .root_source_file = b.path("cli/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli.addImport("clap", clap.module("clap"));
    cli.addImport("loxz", lib_mod);
    cli.addOptions("build_options", build_options);

    exe_mod.addImport("cli", cli);

    const exe = b.addExecutable(.{
        .name = "loxz",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/tests.zig"),
        .link_libc = use_clhash,
    });
    test_mod.addOptions("build_options", build_options);

    if (use_clhash and clhash_static_lib != null) {
        test_mod.linkLibrary(clhash_static_lib.?);
        test_mod.addIncludePath(b.path(clhash_include_path));
    }

    const lib_unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
