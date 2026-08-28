const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Zig 0.16's self-hosted backend is useful for large validation builds and
    // optional companions on constrained builders. Default remains Zig's
    // platform choice; callers may select `-Duse-llvm=false` explicitly.
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM for executables and test artifacts");
    const sqlite_lib_dir = b.option([]const u8, "sqlite-lib-dir", "Directory containing a linkable sqlite3 library");

    const mod = b.addModule("pi_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sqlite_persistence_mod = b.createModule(.{
        .root_source_file = b.path("src/sqlite_server_persistence.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "pi_zig", .module = mod }},
    });
    const no_sqlite_features = b.createModule(.{
        .root_source_file = b.path("src/features_no_sqlite.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sqlite_features = b.createModule(.{
        .root_source_file = b.path("src/features_sqlite.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "pi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pi_zig", .module = mod },
                .{ .name = "pi_features", .module = no_sqlite_features },
                .{ .name = "sqlite_persistence", .module = sqlite_persistence_mod },
            },
        }),
        .use_llvm = use_llvm,
    });
    // Strip debug info for smaller release artifacts; also avoids Windows PDB install issues.
    if (optimize != .Debug) {
        exe.root_module.strip = true;
    } else if (target.result.os.tag == .windows) {
        exe.root_module.strip = true;
    }

    b.installArtifact(exe);

    // The canonical SQLite backend remains optional so the ordinary `pi`
    // executable stays self-contained. `zig build sqlite` installs the
    // separately linked administration binary as `pi-sqlite`.
    const sqlite_exe = b.addExecutable(.{
        .name = "pi-sqlite",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sqlite_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
    });
    linkSqlite(sqlite_exe.root_module, sqlite_lib_dir);
    if (optimize != .Debug) sqlite_exe.root_module.strip = true;
    const install_sqlite = b.addInstallArtifact(sqlite_exe, .{});

    // A second build of the same complete CLI root enables SQLite-backed live
    // protocol serving without making the ordinary `pi` executable depend on
    // libc or libsqlite3. Sharing the `pi_zig` module also avoids compiling a
    // second monolithic server root solely for the linked backend.
    const sqlite_live_exe = b.addExecutable(.{
        .name = "pi-sqlite-live",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pi_zig", .module = mod },
                .{ .name = "pi_features", .module = sqlite_features },
                .{ .name = "sqlite_persistence", .module = sqlite_persistence_mod },
            },
        }),
        .use_llvm = use_llvm,
    });
    linkSqlite(sqlite_live_exe.root_module, sqlite_lib_dir);
    if (optimize != .Debug) sqlite_live_exe.root_module.strip = true;
    const install_sqlite_live = b.addInstallArtifact(sqlite_live_exe, .{});

    const sqlite_step = b.step("sqlite", "Build and install the SQLite administration and live-agent companions");
    sqlite_step.dependOn(&install_sqlite.step);
    sqlite_step.dependOn(&install_sqlite_live.step);
    const sqlite_server_step = b.step("sqlite-server", "Build and install the SQLite-enabled complete Pi CLI/server");
    sqlite_server_step.dependOn(&install_sqlite_live.step);

    const run_step = b.step("run", "Run pi");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Keep the normal executable free of a hard SQLite development-library
    // dependency. The all-package test module opts into the native backend.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    linkSqlite(test_mod, sqlite_lib_dir);
    const mod_tests = b.addTest(.{
        .root_module = test_mod,
        .use_llvm = use_llvm,
    });
    // Use terminal-mode runners so allocator and leak checks remain active.
    const run_mod_tests = std.Build.Step.Run.create(b, "run module tests");
    run_mod_tests.addArtifactArg(mod_tests);
    // SQLite's C runtime gets a dedicated process. The full all-package test
    // executable intentionally skips only these six runtime cases; the next
    // artifact runs them together with their ABI/schema dependencies.
    run_mod_tests.setEnvironmentVariable("PI_SQLITE_REPOSITORY_TESTS", "0");

    const sqlite_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/storage/sqlite/repository.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
    });
    linkSqlite(sqlite_tests.root_module, sqlite_lib_dir);
    const run_sqlite_tests = std.Build.Step.Run.create(b, "run SQLite repository integration tests");
    run_sqlite_tests.addArtifactArg(sqlite_tests);
    run_sqlite_tests.setEnvironmentVariable("PI_SQLITE_REPOSITORY_TESTS", "1");

    const sqlite_cli_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sqlite_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
    });
    linkSqlite(sqlite_cli_tests.root_module, sqlite_lib_dir);
    const run_sqlite_cli_tests = std.Build.Step.Run.create(b, "run SQLite CLI integration tests");
    run_sqlite_cli_tests.addArtifactArg(sqlite_cli_tests);
    run_sqlite_cli_tests.setEnvironmentVariable("PI_SQLITE_REPOSITORY_TESTS", "0");
    run_sqlite_cli_tests.setEnvironmentVariable("PI_SQLITE_CLI_TESTS", "1");

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
        .use_llvm = use_llvm,
    });
    const run_exe_tests = std.Build.Step.Run.create(b, "run executable tests");
    run_exe_tests.addArtifactArg(exe_tests);

    const sqlite_persistence_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sqlite_server_persistence.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "pi_zig", .module = mod }},
        }),
        .use_llvm = use_llvm,
    });
    linkSqlite(sqlite_persistence_tests.root_module, sqlite_lib_dir);
    const run_sqlite_persistence_tests = std.Build.Step.Run.create(b, "run SQLite live-persistence tests");
    run_sqlite_persistence_tests.addArtifactArg(sqlite_persistence_tests);
    run_sqlite_persistence_tests.setEnvironmentVariable("PI_SQLITE_REPOSITORY_TESTS", "1");

    const sqlite_live_tests = b.addTest(.{
        .root_module = sqlite_live_exe.root_module,
        .use_llvm = use_llvm,
    });
    const run_sqlite_live_tests = std.Build.Step.Run.create(b, "run SQLite-enabled executable tests");
    run_sqlite_live_tests.addArtifactArg(sqlite_live_tests);

    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_sqlite_tests.step);
    test_step.dependOn(&run_sqlite_cli_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_sqlite_persistence_tests.step);
    test_step.dependOn(&run_sqlite_live_tests.step);
}

fn linkSqlite(module: *std.Build.Module, library_dir: ?[]const u8) void {
    if (library_dir) |path| module.addLibraryPath(.{ .cwd_relative = path });
    module.linkSystemLibrary("sqlite3", .{});
    module.link_libc = true;
}
