const std = @import("std");

pub fn build(b: *std.Build) void {
    const install_schemas = b.addInstallDirectory(.{ .source_dir = b.path("schemas"), .install_dir = .prefix, .install_subdir = "share/pi/schemas" });
    b.getInstallStep().dependOn(&install_schemas.step);
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Zig 0.16's self-hosted backend is useful for large validation builds and
    // optional companions on constrained builders. Default remains Zig's
    // platform choice; callers may select `-Duse-llvm=false` explicitly.
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM for executables and test artifacts");
    const sqlite_lib_dir = b.option([]const u8, "sqlite-lib-dir", "Directory containing a linkable sqlite3 library");
    const sqlite_library: ?*std.Build.Step.Compile = if (sqlite_lib_dir == null) blk: {
        const library = b.addLibrary(.{
            .name = "pi-sqlite",
            .linkage = .static,
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        });
        library.root_module.addIncludePath(b.path("vendor/sqlite"));
        library.root_module.addCSourceFile(.{
            .file = b.path("vendor/sqlite/sqlite3.c"),
            .flags = &.{ "-std=gnu11", "-DSQLITE_THREADSAFE=1", "-DSQLITE_ENABLE_FTS5", "-DSQLITE_ENABLE_RTREE", "-DSQLITE_OMIT_LOAD_EXTENSION" },
        });
        break :blk library;
    } else null;
    const diagnostic_tests = b.option(bool, "diagnostic-tests", "Stream individual environment lifecycle tests to diagnose blocked teardown") orelse false;
    const lifecycle_test_runner: ?std.Build.Step.Compile.TestRunner = if (diagnostic_tests) .{
        .path = .{ .cwd_relative = b.graph.zig_lib_directory.join(b.allocator, &.{ "compiler", "test_runner.zig" }) catch @panic("OOM") },
        .mode = .simple,
    } else null;

    // The extension language is evaluated by a pinned C engine through Zig's
    // C ABI. Host behavior and bindings remain native Zig.
    const quickjs = b.addLibrary(.{
        .name = "pi-quickjs",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    quickjs.root_module.addIncludePath(b.path("vendor/quickjs"));
    // Native public storage is installed for every extension VM. Carry SQLite
    // through this common dependency so CLI, SDK and bindings all receive it.
    linkSqlite(quickjs.root_module, sqlite_lib_dir, sqlite_library);
    quickjs.root_module.addCSourceFiles(.{
        .root = b.path("vendor/quickjs"),
        .files = &.{ "dtoa.c", "libregexp.c", "libunicode.c", "quickjs.c" },
        .flags = &.{ "-std=gnu11", "-D_GNU_SOURCE", "-DQUICKJS_NG_BUILD", "-funsigned-char", "-fno-strict-aliasing" },
    });
    quickjs.root_module.addCSourceFile(.{
        .file = b.path("src/extensions/engine_abi.c"),
        .flags = &.{"-std=gnu11"},
    });
    const typescript_parser = b.addLibrary(.{
        .name = "pi-typescript-parser",
        .linkage = .static,
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
    });
    typescript_parser.root_module.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    typescript_parser.root_module.addIncludePath(b.path("vendor/tree-sitter/lib/src"));
    typescript_parser.root_module.addIncludePath(b.path("vendor/typescript-parser/typescript/src"));
    const typescript_parser_flags = [_][]const u8{ "-std=gnu11", "-D_POSIX_C_SOURCE=200809L", "-D_DEFAULT_SOURCE", "-fno-strict-aliasing" };
    typescript_parser.root_module.addCSourceFiles(.{
        .files = &.{
            "vendor/tree-sitter/lib/src/lib.c",
            "vendor/typescript-parser/typescript/src/parser.c",
        },
        .flags = &typescript_parser_flags,
    });
    typescript_parser.root_module.addCSourceFile(.{
        .file = b.path("vendor/typescript-parser/typescript/src/scanner.c"),
        // Supply the same prototype as the generated parser before the legacy
        // scanner definition. Preserve function-type checks and vendor bytes.
        .flags = &.{ "-std=gnu11", "-D_POSIX_C_SOURCE=200809L", "-D_DEFAULT_SOURCE", "-fno-strict-aliasing", "-include", b.pathFromRoot("src/extensions/typescript_scanner_abi.h") },
    });

    const mod = b.addModule("pi_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const catalog_tool = b.createModule(.{ .root_source_file = b.path("tools/catalog.zig"), .target = target, .optimize = optimize });
    mod.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, mod, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, mod, typescript_parser);
    linkDurable(b, mod);
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
    const sdk_embedder = b.addExecutable(.{
        .name = "pi-sdk-embedder",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_embedder.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "pi_zig", .module = mod }} }),
        .use_llvm = use_llvm,
    });
    const sdk_install = b.addInstallArtifact(sdk_embedder, .{});
    const sdk_step = b.step("sdk-embedder", "Build the no-Node native SDK module embedder");
    sdk_step.dependOn(&sdk_install.step);

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
    linkSqlite(sqlite_exe.root_module, sqlite_lib_dir, sqlite_library);
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
    linkSqlite(sqlite_live_exe.root_module, sqlite_lib_dir, sqlite_library);
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
    test_mod.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, test_mod, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, test_mod, typescript_parser);
    linkSqlite(test_mod, sqlite_lib_dir, sqlite_library);
    linkDurable(b, test_mod);
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
    linkSqlite(sqlite_tests.root_module, sqlite_lib_dir, sqlite_library);
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
    linkSqlite(sqlite_cli_tests.root_module, sqlite_lib_dir, sqlite_library);
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
    const activation_tests = b.addTest(.{ .root_module = exe.root_module, .use_llvm = use_llvm, .filters = &.{"native CLI activation allocation"} });
    const run_activation_tests = b.addRunArtifact(activation_tests);
    const activation_step = b.step("test-tool-activation-atomic", "Exercise every allocation failure before native activation and schema acknowledgement");
    activation_step.dependOn(&run_activation_tests.step);

    const sqlite_persistence_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sqlite_server_persistence.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "pi_zig", .module = mod }},
        }),
        .use_llvm = use_llvm,
    });
    linkSqlite(sqlite_persistence_tests.root_module, sqlite_lib_dir, sqlite_library);
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
    const theme_schema_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/theme_schema_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const run_theme_schema_tests = b.addRunArtifact(theme_schema_tests);
    theme_schema_tests.root_module.link_libc = true;
    b.step("test-theme-schema", "Replay current upstream strict theme validation").dependOn(&run_theme_schema_tests.step);
    test_step.dependOn(&run_theme_schema_tests.step);
    const mistral_header_tests = b.addTest(.{ .root_module = test_mod, .use_llvm = use_llvm, .filters = &.{ "ai.http_fetch", "ai.mistral" } });
    const run_mistral_header_tests = b.addRunArtifact(mistral_header_tests);
    const mistral_header_step = b.step("test-mistral-header-timeout", "Exercise source Mistral header deadlines and caller cancellation");
    mistral_header_step.dependOn(&run_mistral_header_tests.step);
    test_step.dependOn(&run_mistral_header_tests.step);
    const wheel_settings_tests = b.addTest(.{ .root_module = test_mod, .use_llvm = use_llvm, .filters = &.{ "fullscreen wheel setting", "coding_agent.settings_tui" } });
    const run_wheel_settings_tests = b.addRunArtifact(wheel_settings_tests);
    const wheel_settings_step = b.step("test-wheel-settings", "Exercise source wheel setting admission persistence and UI choices");
    wheel_settings_step.dependOn(&run_wheel_settings_tests.step);
    test_step.dependOn(&run_wheel_settings_tests.step);
    const latest_catalog_tests = b.addTest(.{ .root_module = test_mod, .use_llvm = use_llvm, .filters = &.{ "ai.bedrock", "ai.catalog", "ai.providers" } });
    const run_latest_catalog_tests = b.addRunArtifact(latest_catalog_tests);
    const latest_catalog_step = b.step("test-latest-catalog", "Exercise reviewed Pi 1.1 model catalog and Bedrock contracts");
    latest_catalog_step.dependOn(&run_latest_catalog_tests.step);
    test_step.dependOn(&run_latest_catalog_tests.step);
    const program_status_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/program_status_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_program_status_tests = b.addRunArtifact(program_status_tests);
    const program_status_step = b.step("test-program-status", "Exercise Pi program status negotiation and interactive lifecycle ownership");
    program_status_step.dependOn(&run_program_status_tests.step);
    test_step.dependOn(&run_program_status_tests.step);
    const terminal_theme_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/terminal_theme_producer_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "native terminal report", "terminal color" },
        .use_llvm = use_llvm,
    });
    terminal_theme_tests.root_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, terminal_theme_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, terminal_theme_tests.root_module, typescript_parser);
    linkDurable(b, terminal_theme_tests.root_module);
    const run_terminal_theme_tests = b.addRunArtifact(terminal_theme_tests);
    const terminal_theme_step = b.step("test-terminal-theme-producer", "Exercise actual terminal report cache and owned ThemeState producer");
    terminal_theme_step.dependOn(&run_terminal_theme_tests.step);
    test_step.dependOn(&run_terminal_theme_tests.step);
    const sdk_process_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_sdk_process_tests = b.addRunArtifact(sdk_process_tests);
    run_sdk_process_tests.step.dependOn(&sdk_install.step);
    const sdk_test_step = b.step("test-native-sdk", "Exercise source-captured programmatic SDK lifecycle without Node on PATH");
    sdk_test_step.dependOn(&run_sdk_process_tests.step);
    const sdk_host_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_host_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"host SDK snapshot crosses"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_host_tests.root_module, quickjs, sqlite_lib_dir);
    const run_sdk_host_tests = b.addRunArtifact(sdk_host_tests);
    run_sdk_host_tests.step.dependOn(&sdk_install.step);
    sdk_test_step.dependOn(&run_sdk_host_tests.step);
    test_step.dependOn(&run_sdk_host_tests.step);
    test_step.dependOn(&run_sdk_process_tests.step);
    const upstream_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("tools/upstream_contract.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_upstream_contract_tests = b.addRunArtifact(upstream_contract_tests);
    const upstream_contract_step = b.step("test-upstream-contract", "Check whole-tree upstream drift admission and malformed identities");
    upstream_contract_step.dependOn(&run_upstream_contract_tests.step);
    test_step.dependOn(&run_upstream_contract_tests.step);
    const latest_bash_output_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/latest_bash_output_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, latest_bash_output_tests.root_module, quickjs, sqlite_lib_dir);
    const run_latest_bash_output_tests = b.addRunArtifact(latest_bash_output_tests);
    const latest_bash_output_step = b.step("test-latest-bash-output", "Check latest user bash ANSI stream and Android clipboard contracts");
    latest_bash_output_step.dependOn(&run_latest_bash_output_tests.step);
    test_step.dependOn(&run_latest_bash_output_tests.step);
    const latest_bash_process_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/latest_bash_output_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_latest_bash_process_tests = b.addRunArtifact(latest_bash_process_tests);
    run_latest_bash_process_tests.step.dependOn(b.getInstallStep());
    run_latest_bash_process_tests.setEnvironmentVariable("PI_TEST_BINARY", b.getInstallPath(.bin, b.fmt("pi{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    const latest_bash_process_step = b.step("test-latest-bash-output-process", "Replay native RPC streaming bash sanitization and persistence");
    latest_bash_process_step.dependOn(&run_latest_bash_process_tests.step);
    test_step.dependOn(&run_latest_bash_process_tests.step);
    const durable_fixture = b.addExecutable(.{
        .name = "pi-durable-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable/process_fixture.zig"), .target = target, .optimize = optimize, .link_libc = true }),
        .use_llvm = use_llvm,
    });
    const install_durable_fixture = b.addInstallArtifact(durable_fixture, .{});
    const durable_fixture_path = b.getInstallPath(.bin, b.fmt("pi-durable-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)}));
    for ([_]*std.Build.Step.Run{ run_mod_tests, run_exe_tests, run_sqlite_persistence_tests, run_sqlite_live_tests }) |run_tests| {
        run_tests.step.dependOn(&install_durable_fixture.step);
        run_tests.setEnvironmentVariable("PI_DURABLE_FIXTURE", durable_fixture_path);
    }
    const durable_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkDurable(b, durable_tests.root_module);
    linkQuickJs(b, durable_tests.root_module, quickjs, sqlite_lib_dir);
    const run_durable_tests = b.addRunArtifact(durable_tests);
    run_durable_tests.step.dependOn(&install_durable_fixture.step);
    run_durable_tests.setEnvironmentVariable("PI_DURABLE_FIXTURE", durable_fixture_path);
    const durable_step = b.step("test-durable", "Exercise native durable readers output processes and polling watch contracts");
    durable_step.dependOn(&run_durable_tests.step);
    test_step.dependOn(&run_durable_tests.step);
    const durable_tools_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_tools_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"read"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, durable_tools_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, durable_tools_tests.root_module);
    const run_durable_tools_tests = b.addRunArtifact(durable_tools_tests);
    const durable_tools_step = b.step("test-durable-tools", "Exercise bounded durable reader integration with existing native CLI tools");
    durable_tools_step.dependOn(&run_durable_tools_tests.step);
    test_step.dependOn(&run_durable_tools_tests.step);
    const env_daemon = b.addExecutable(.{
        .name = "pi-env",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/env_daemon.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkDurable(b, env_daemon.root_module);
    const install_env_daemon = b.addInstallArtifact(env_daemon, .{});
    const env_build_step = b.step("env", "Build the native framed Pi environment daemon");
    env_build_step.dependOn(&install_env_daemon.step);
    const identity_fixture = b.addExecutable(.{ .name = "pi-env-watch-identity-fixture", .root_module = b.createModule(.{ .root_source_file = b.path("src/env_watch_identity_fixture.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    linkDurable(b, identity_fixture.root_module);
    const install_identity_fixture = b.addInstallArtifact(identity_fixture, .{});
    const identity_fixture_step = b.step("env-watch-identity-fixture", "Build native process participant for actual isolated filesystem identity gates");
    identity_fixture_step.dependOn(&install_identity_fixture.step);
    const env_fixture = b.addExecutable(.{
        .name = "pi-env-process-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/env_process_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const install_env_fixture = b.addInstallArtifact(env_fixture, .{});
    const env_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/env_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .test_runner = lifecycle_test_runner,
    });
    linkDurable(b, env_tests.root_module);
    const run_env_tests = b.addRunArtifact(env_tests);
    if (diagnostic_tests) run_env_tests.stdio = .inherit;
    run_env_tests.step.dependOn(&install_env_daemon.step);
    run_env_tests.step.dependOn(&install_env_fixture.step);
    run_env_tests.step.dependOn(&install_durable_fixture.step);
    run_env_tests.setEnvironmentVariable("PI_DURABLE_FIXTURE", durable_fixture_path);
    run_env_tests.setEnvironmentVariable("PI_TEST_ENV_DAEMON", b.getInstallPath(.bin, if (target.result.os.tag == .windows) "pi-env.exe" else "pi-env"));
    run_env_tests.setEnvironmentVariable("PI_TEST_SSH_FIXTURE", b.getInstallPath(.bin, if (target.result.os.tag == .windows) "pi-env-process-fixture.exe" else "pi-env-process-fixture"));
    const env_test_step = b.step("test-env", "Check native daemon framing files processes client sessions and SSH contracts");
    env_test_step.dependOn(&run_env_tests.step);
    test_step.dependOn(&run_env_tests.step);
    const capability_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/env_capability_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"env capability"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkDurable(b, capability_tests.root_module);
    const native_durable_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native durable VM"}, .use_llvm = use_llvm });
    linkDurable(b, native_durable_tests.root_module);
    linkQuickJs(b, native_durable_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_durable_tests.root_module, sqlite_lib_dir, sqlite_library);
    const run_native_durable_tests = b.addRunArtifact(native_durable_tests);
    const native_durable_step = b.step("test-native-durable-vm", "Exercise native public durable VM storage and Session objects");
    native_durable_step.dependOn(&run_native_durable_tests.step);
    const sqlite_source_fixture = b.addExecutable(.{
        .name = "pi-durable-sqlite-source-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_sqlite_source_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkSqlite(sqlite_source_fixture.root_module, sqlite_lib_dir, sqlite_library);
    const sqlite_source_fixture_step = b.step("durable-sqlite-source-fixture", "Build original SQLite interoperability fixture");
    sqlite_source_fixture_step.dependOn(&b.addInstallArtifact(sqlite_source_fixture, .{}).step);
    test_step.dependOn(&run_native_durable_tests.step);
    linkQuickJs(b, capability_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(capability_tests.root_module, sqlite_lib_dir, sqlite_library);
    const run_capability_tests = b.addRunArtifact(capability_tests);
    if (diagnostic_tests) run_capability_tests.stdio = .inherit;
    if (target.result.os.tag == .windows) if (sqlite_lib_dir) |directory| {
        const inherited_path = b.graph.environ_map.get("PATH") orelse "";
        run_capability_tests.setEnvironmentVariable("PATH", b.fmt("{s};{s}", .{ directory, inherited_path }));
    };
    run_capability_tests.step.dependOn(&install_env_daemon.step);
    run_capability_tests.step.dependOn(&install_durable_fixture.step);
    run_capability_tests.setEnvironmentVariable("PI_TEST_ENV_DAEMON", b.getInstallPath(.bin, if (target.result.os.tag == .windows) "pi-env.exe" else "pi-env"));
    run_capability_tests.setEnvironmentVariable("PI_DURABLE_FIXTURE", durable_fixture_path);
    const capability_step = b.step("test-env-capability", "Exercise shared local and remote durable storage environment capabilities");
    capability_step.dependOn(&run_capability_tests.step);
    test_step.dependOn(&run_capability_tests.step);
    const jsonl_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_jsonl_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"durable JSONL"}, .use_llvm = use_llvm });
    linkDurable(b, jsonl_tests.root_module);
    const run_jsonl_tests = b.addRunArtifact(jsonl_tests);
    run_jsonl_tests.step.dependOn(&install_env_daemon.step);
    run_jsonl_tests.setEnvironmentVariable("PI_TEST_ENV_DAEMON", b.getInstallPath(.bin, if (target.result.os.tag == .windows) "pi-env.exe" else "pi-env"));
    const jsonl_step = b.step("test-durable-jsonl", "Verify portable durable JSONL publication recovery and source-compatible scans");
    jsonl_step.dependOn(&run_jsonl_tests.step);
    test_step.dependOn(&run_jsonl_tests.step);
    const jsonl_fixture = b.addExecutable(.{ .name = "pi-durable-jsonl-fixture", .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_jsonl_fixture.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    linkDurable(b, jsonl_fixture.root_module);
    const install_jsonl_fixture = b.addInstallArtifact(jsonl_fixture, .{});
    const jsonl_fixture_step = b.step("jsonl-fixture", "Build original/native durable JSONL interop fixture");
    jsonl_fixture_step.dependOn(&install_jsonl_fixture.step);
    const durable_backend_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_backend_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .test_runner = lifecycle_test_runner,
    });
    linkSqlite(durable_backend_tests.root_module, sqlite_lib_dir, sqlite_library);
    linkDurable(b, durable_backend_tests.root_module);
    const run_durable_backend_tests = b.addRunArtifact(durable_backend_tests);
    if (diagnostic_tests) run_durable_backend_tests.stdio = .inherit;
    const durable_backend_step = b.step("test-durable-backend", "Exercise native numeric durable transactions document history SQLite fencing and Session");
    durable_backend_step.dependOn(&run_durable_backend_tests.step);
    test_step.dependOn(&run_durable_backend_tests.step);
    const durable_harness_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_harness_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{ "durable.harness", "durable.session" },
    });
    linkSqlite(durable_harness_tests.root_module, sqlite_lib_dir, sqlite_library);
    linkQuickJs(b, durable_harness_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, durable_harness_tests.root_module);
    const run_durable_harness_tests = b.addRunArtifact(durable_harness_tests);
    const durable_harness_step = b.step("test-durable-harness", "Exercise native registry schema tool output retained invocations and committed results");
    durable_harness_step.dependOn(&run_durable_harness_tests.step);
    test_step.dependOn(&run_durable_harness_tests.step);
    const durable_scheduler_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_scheduler_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"durable.scheduler"},
    });
    linkSqlite(durable_scheduler_tests.root_module, sqlite_lib_dir, sqlite_library);
    const run_durable_scheduler_tests = b.addRunArtifact(durable_scheduler_tests);
    const durable_scheduler_fixture = b.addExecutable(.{
        .name = "pi-durable-scheduler-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_scheduler_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkSqlite(durable_scheduler_fixture.root_module, sqlite_lib_dir, sqlite_library);
    const install_durable_scheduler_fixture = b.addInstallArtifact(durable_scheduler_fixture, .{});
    run_durable_scheduler_tests.step.dependOn(&install_durable_scheduler_fixture.step);
    run_durable_scheduler_tests.setEnvironmentVariable("PI_DURABLE_SCHEDULER_FIXTURE", b.getInstallPath(.bin, b.fmt("pi-durable-scheduler-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    const durable_scheduler_step = b.step("test-durable-scheduler", "Exercise native durable task recovery ownership cascades concurrent phases and late-write fences");
    durable_scheduler_step.dependOn(&run_durable_scheduler_tests.step);
    test_step.dependOn(&run_durable_scheduler_tests.step);
    const durable_powershell_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_powershell_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"durable.powershell"},
    });
    linkSqlite(durable_powershell_tests.root_module, sqlite_lib_dir, sqlite_library);
    linkQuickJs(b, durable_powershell_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, durable_powershell_tests.root_module);
    const run_durable_powershell_tests = b.addRunArtifact(durable_powershell_tests);
    const durable_command_fixture = b.addExecutable(.{
        .name = "pi-durable-command-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable/command_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const install_durable_command_fixture = b.addInstallArtifact(durable_command_fixture, .{});
    run_durable_powershell_tests.step.dependOn(&install_durable_command_fixture.step);
    run_durable_powershell_tests.setEnvironmentVariable("PI_DURABLE_COMMAND_FIXTURE", b.getInstallPath(.bin, b.fmt("pi-durable-command-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    const durable_powershell_step = b.step("test-durable-powershell", "Exercise real native PowerShell argv startup fallback preparation and retained output");
    durable_powershell_step.dependOn(&run_durable_powershell_tests.step);
    test_step.dependOn(&run_durable_powershell_tests.step);
    const mcp_configured_fixture = b.addExecutable(.{
        .name = "pi-mcp-configured-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_configured_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const install_mcp_configured_fixture = b.addInstallArtifact(mcp_configured_fixture, .{});
    const mcp_configured_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_configured_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"mcp.configured"},
    });
    linkDurable(b, mcp_configured_tests.root_module);
    linkQuickJs(b, mcp_configured_tests.root_module, quickjs, sqlite_lib_dir);
    const resource_adapter_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_resource_tools_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"MCP resource adapter"}, .use_llvm = use_llvm });
    linkQuickJs(b, resource_adapter_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, resource_adapter_tests.root_module);
    resource_adapter_tests.root_module.addImport("catalog_tool", catalog_tool);
    const resource_adapter_run = b.addRunArtifact(resource_adapter_tests);
    b.step("test-mcp-resource-tools", "Replay Source resource listing reading and model output contracts").dependOn(&resource_adapter_run.step);
    test_step.dependOn(&resource_adapter_run.step);
    const run_mcp_configured_tests = b.addRunArtifact(mcp_configured_tests);
    const install_mcp_configured_cli = b.addInstallArtifact(exe, .{});
    run_mcp_configured_tests.step.dependOn(&install_mcp_configured_cli.step);
    run_mcp_configured_tests.setEnvironmentVariable("PI_MCP_CONFIGURED_CLI", b.getInstallPath(.bin, b.fmt("pi{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    run_mcp_configured_tests.step.dependOn(&install_mcp_configured_fixture.step);
    run_mcp_configured_tests.setEnvironmentVariable("PI_MCP_CONFIGURED_FIXTURE", b.getInstallPath(.bin, b.fmt("pi-mcp-configured-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    const mcp_startup_pool_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_startup_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const mcp_startup_pool_run = b.addRunArtifact(mcp_startup_pool_tests);
    b.step("test-mcp-startup-pool", "Replay Source script waits and producer ownership failure cleanup").dependOn(&mcp_startup_pool_run.step);
    test_step.dependOn(&mcp_startup_pool_run.step);
    const main_settings_module = b.createModule(.{ .root_source_file = b.path("src/codemode_settings_test.zig"), .target = target, .optimize = optimize });
    main_settings_module.addImport("catalog_tool", catalog_tool);
    const main_settings_tests = b.addTest(.{ .root_module = main_settings_module, .use_llvm = use_llvm });
    const main_settings_run = b.addRunArtifact(main_settings_tests);
    const extension_settings_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_settings_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const extension_settings_run = b.addRunArtifact(extension_settings_tests);
    const main_settings_step = b.step("test-main-settings", "Replay effective settings migrations scoped modifiers and allocation ownership");
    main_settings_step.dependOn(&main_settings_run.step);
    main_settings_step.dependOn(&extension_settings_run.step);
    test_step.dependOn(&main_settings_run.step);
    test_step.dependOn(&extension_settings_run.step);
    const mcp_startup_tests = b.addTest(.{ .root_module = mcp_configured_tests.root_module, .use_llvm = use_llvm, .filters = &.{"mcp.configured background"} });
    const mcp_startup_run = b.addRunArtifact(mcp_startup_tests);
    mcp_startup_run.step.dependOn(&install_mcp_configured_fixture.step);
    mcp_startup_run.setEnvironmentVariable("PI_MCP_CONFIGURED_FIXTURE", b.getInstallPath(.bin, b.fmt("pi-mcp-configured-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-mcp-startup", "Exercise owned background discovery direct waits and exact worker retirement").dependOn(&mcp_startup_run.step);
    test_step.dependOn(&mcp_startup_run.step);
    const mcp_configured_step = b.step("test-mcp-configured", "Exercise trusted configured native MCP direct tools and real agent execution");
    mcp_configured_step.dependOn(&run_mcp_configured_tests.step);
    test_step.dependOn(&run_mcp_configured_tests.step);
    const mcp_adapter_probe = b.addExecutable(.{
        .name = "pi-mcp-adapter-probe",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_adapter_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkDurable(b, mcp_adapter_probe.root_module);
    linkQuickJs(b, mcp_adapter_probe.root_module, quickjs, sqlite_lib_dir);
    const install_mcp_adapter_probe = b.addInstallArtifact(mcp_adapter_probe, .{});
    const mcp_adapter_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_adapter_integration_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"mcp.adapter"},
    });
    linkDurable(b, mcp_adapter_tests.root_module);
    linkQuickJs(b, mcp_adapter_tests.root_module, quickjs, sqlite_lib_dir);
    const run_mcp_adapter_tests = b.addRunArtifact(mcp_adapter_tests);
    run_mcp_adapter_tests.step.dependOn(&install_mcp_adapter_probe.step);
    run_mcp_adapter_tests.setEnvironmentVariable("PI_MCP_ADAPTER_CLI", b.getInstallPath(.bin, b.fmt("pi-mcp-adapter-probe{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    run_mcp_adapter_tests.setEnvironmentVariable("PI_MCP_ADAPTER_PROBE", b.getInstallPath(.bin, b.fmt("pi-mcp-adapter-probe{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    run_mcp_adapter_tests.setEnvironmentVariable("PI_MCP_ADAPTER_SERVER", b.getInstallPath(.bin, b.fmt("pi-mcp-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    const mcp_adapter_step = b.step("test-mcp-adapter", "Exercise native legacy-client ownership PATH lookup and real stdio HTTP CLI gates");
    mcp_adapter_step.dependOn(&run_mcp_adapter_tests.step);
    test_step.dependOn(&run_mcp_adapter_tests.step);
    const mcp_fixture = b.addExecutable(.{
        .name = "pi-mcp-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp/stdio_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const install_mcp_fixture = b.addInstallArtifact(mcp_fixture, .{});
    run_mcp_adapter_tests.step.dependOn(&install_mcp_fixture.step);
    const mcp_process_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_adapter_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkDurable(b, mcp_process_tests.root_module);
    linkQuickJs(b, mcp_process_tests.root_module, quickjs, sqlite_lib_dir);
    const run_mcp_process_tests = b.addRunArtifact(mcp_process_tests);
    run_mcp_process_tests.step.dependOn(&install_mcp_fixture.step);
    const mcp_test_step = b.step("test-mcp-stdio", "Exercise real native MCP pipe framing and protocol negotiation");
    const mcp_oauth_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_oauth_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, mcp_oauth_tests.root_module, quickjs, sqlite_lib_dir);
    const run_mcp_oauth_tests = b.addRunArtifact(mcp_oauth_tests);
    const mcp_oauth_step = b.step("test-mcp-oauth", "Exercise native MCP OAuth registration and issuer contracts");
    mcp_oauth_step.dependOn(&run_mcp_oauth_tests.step);
    test_step.dependOn(&run_mcp_oauth_tests.step);
    const prompt_sections_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/prompt_sections_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_prompt_sections_tests = b.addRunArtifact(prompt_sections_tests);
    const prompt_sections_step = b.step("test-prompt-sections", "Check native structured prompts against latest upstream captures");
    prompt_sections_step.dependOn(&run_prompt_sections_tests.step);
    test_step.dependOn(&run_prompt_sections_tests.step);
    mcp_test_step.dependOn(&run_mcp_process_tests.step);
    test_step.dependOn(&run_mcp_process_tests.step);
    const codemode_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_codemode_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native codemode"},
    });
    linkQuickJs(b, codemode_tests.root_module, quickjs, sqlite_lib_dir);
    const run_codemode_tests = b.addRunArtifact(codemode_tests);
    const codemode_step = b.step("test-codemode", "Exercise isolated native codemode user scripts and Zig host callbacks");
    const discovery_process_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/codemode_discovery_process_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const discovery_process_run = b.addRunArtifact(discovery_process_tests);
    discovery_process_run.step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    discovery_process_run.setEnvironmentVariable("PI_CODEMODE_BINARY", b.getInstallPath(.bin, b.fmt("pi{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-codemode-discovery-process", "Exercise real CLI discovery and nested native tools without Node").dependOn(&discovery_process_run.step);
    codemode_step.dependOn(&discovery_process_run.step);
    test_step.dependOn(&discovery_process_run.step);
    const typed_lease_tests = b.addTest(.{ .root_module = codemode_tests.root_module, .use_llvm = use_llvm, .filters = &.{"native codemode typed owner program"} });
    const typed_lease_run = b.addRunArtifact(typed_lease_tests);
    b.step("test-typed-model-lease", "Exercise program-scoped typed registry admission and cleanup").dependOn(&typed_lease_run.step);
    test_step.dependOn(&typed_lease_run.step);
    const discovery_tests = b.addTest(.{ .root_module = codemode_tests.root_module, .use_llvm = use_llvm, .filters = &.{"native codemode discovery"} });
    const discovery_run = b.addRunArtifact(discovery_tests);
    b.step("test-codemode-discovery", "Replay source session discovery globals").dependOn(&discovery_run.step);
    codemode_step.dependOn(&run_codemode_tests.step);
    test_step.dependOn(&run_codemode_tests.step);
    const nested_module = b.createModule(.{ .root_source_file = b.path("src/codemode_nested_pipeline_test.zig"), .target = target, .optimize = optimize });
    nested_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, nested_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, nested_module, typescript_parser);
    linkDurable(b, nested_module);
    const nested_tests = b.addTest(.{ .root_module = nested_module, .use_llvm = use_llvm, .filters = &.{"native codemode nested pipeline"} });
    const run_nested_tests = b.addRunArtifact(nested_tests);
    codemode_step.dependOn(&run_nested_tests.step);
    const codemode_models_module = b.createModule(.{ .root_source_file = b.path("src/codemode_models_test.zig"), .target = target, .optimize = optimize });
    codemode_models_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, codemode_models_module, quickjs, sqlite_lib_dir);
    const codemode_models_tests = b.addTest(.{ .root_module = codemode_models_module, .use_llvm = use_llvm, .filters = &.{"native codemode models"} });
    const codemode_models_run = b.addRunArtifact(codemode_models_tests);
    b.step("test-codemode-models", "Compare model globals against original registry behavior and concurrency").dependOn(&codemode_models_run.step);
    const structured_result_tests = b.addTest(.{ .root_module = codemode_models_module, .use_llvm = use_llvm, .filters = &.{"native codemode models structured"} });
    b.step("test-codemode-structured-results", "Replay original arbitrary structured fields across the tool protocol").dependOn(&b.addRunArtifact(structured_result_tests).step);
    codemode_step.dependOn(&codemode_models_run.step);
    test_step.dependOn(&codemode_models_run.step);
    const mcp_activation_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_activation_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const mcp_activation_run = b.addRunArtifact(mcp_activation_tests);
    b.step("test-mcp-activation", "Replay upstream preconnection builtin activation and unreachable warnings").dependOn(&mcp_activation_run.step);
    test_step.dependOn(&mcp_activation_run.step);
    const loadout_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/codemode_loadout_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native codemode loadout"} });
    const loadout_run = b.addRunArtifact(loadout_tests);
    b.step("test-codemode-loadout", "Replay Source catalog budgets mode preparation and namespace grouping").dependOn(&loadout_run.step);
    codemode_step.dependOn(&loadout_run.step);
    test_step.dependOn(&loadout_run.step);
    const model_owner_module = b.createModule(.{ .root_source_file = b.path("src/native_model_owner_transport_test.zig"), .target = target, .optimize = optimize });
    model_owner_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, model_owner_module, quickjs, sqlite_lib_dir);
    linkDurable(b, model_owner_module);
    linkTypeScriptParser(b, model_owner_module, typescript_parser);
    const model_owner_tests = b.addTest(.{ .root_module = model_owner_module, .use_llvm = use_llvm, .filters = &.{"native model owner transport"} });
    const model_owner_run = b.addRunArtifact(model_owner_tests);
    b.step("test-model-owner-transport", "Exercise exact model registry leases over the native worker protocol").dependOn(&model_owner_run.step);
    test_step.dependOn(&model_owner_run.step);
    const main_context_module = b.createModule(.{ .root_source_file = b.path("src/main_native_context_test.zig"), .target = target, .optimize = optimize });
    main_context_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, main_context_module, quickjs, sqlite_lib_dir);
    linkDurable(b, main_context_module);
    linkTypeScriptParser(b, main_context_module, typescript_parser);
    const main_context_tests = b.addTest(.{ .root_module = main_context_module, .use_llvm = use_llvm, .filters = &.{"native main context"} });
    const main_context_run = b.addRunArtifact(main_context_tests);
    b.step("test-main-native-context", "Verify admitted startup keybindings and theme validation context").dependOn(&main_context_run.step);
    test_step.dependOn(&main_context_run.step);
    const main_context_process_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/main_native_context_process_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const main_context_process_run = b.addRunArtifact(main_context_process_tests);
    main_context_process_run.step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    main_context_process_run.setEnvironmentVariable("PI_MAIN_CONTEXT_BINARY", b.getInstallPath(.bin, b.fmt("pi{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-main-native-context-process", "Prove CLI validation bootstrap precedes extension registration without Node").dependOn(&main_context_process_run.step);
    test_step.dependOn(&main_context_process_run.step);
    const strict_theme_module = b.createModule(.{ .root_source_file = b.path("src/strict_theme_validation_test.zig"), .target = target, .optimize = optimize });
    strict_theme_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, strict_theme_module, quickjs, sqlite_lib_dir);
    linkDurable(b, strict_theme_module);
    const strict_theme_tests = b.addTest(.{ .root_module = strict_theme_module, .use_llvm = use_llvm, .filters = &.{"Source6fb strict Theme"} });
    const strict_theme_run = b.addRunArtifact(strict_theme_tests);
    b.step("test-theme-file-admission", "Replay Source optional theme validation and context admission").dependOn(&strict_theme_run.step);
    test_step.dependOn(&strict_theme_run.step);
    const keybindings_manager_module = b.createModule(.{ .root_source_file = b.path("src/keybindings_manager_test.zig"), .target = target, .optimize = optimize });
    keybindings_manager_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, keybindings_manager_module, quickjs, sqlite_lib_dir);
    linkDurable(b, keybindings_manager_module);
    const keybindings_manager_tests = b.addTest(.{ .root_module = keybindings_manager_module, .use_llvm = use_llvm, .filters = &.{"Source6fb public KeybindingsManager"} });
    const keybindings_manager_run = b.addRunArtifact(keybindings_manager_tests);
    b.step("test-keybindings-manager", "Replay Source public keybinding manager and admitted runtime context").dependOn(&keybindings_manager_run.step);
    test_step.dependOn(&keybindings_manager_run.step);
    const utf16_input_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/utf16_input_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const utf16_input_run = b.addRunArtifact(utf16_input_tests);
    const unicode_generator = b.addExecutable(.{ .name = "unicode-graphemes-generator", .root_module = b.createModule(.{ .root_source_file = b.path("tools/unicode_graphemes.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const unicode_check = b.addRunArtifact(unicode_generator);
    unicode_check.addArg("--check");
    unicode_check.setCwd(b.path("."));
    unicode_check.has_side_effects = true;
    b.step("check-unicode-graphemes", "Verify pinned Unicode17 inputs and generated tables").dependOn(&unicode_check.step);
    const utf16_step = b.step("test-tui-utf16-input", "Replay Source UTF16 input state and official grapheme conformance");
    utf16_step.dependOn(&utf16_input_run.step);
    utf16_step.dependOn(&unicode_check.step);
    test_step.dependOn(&utf16_input_run.step);
    test_step.dependOn(&unicode_check.step);
    test_step.dependOn(&run_nested_tests.step);
    const oauth_lock_fixture = b.addExecutable(.{
        .name = "pi-mcp-oauth-lock-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_oauth_lock_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const install_oauth_lock_fixture = b.addInstallArtifact(oauth_lock_fixture, .{});
    const oauth_lock_fixture_step = b.step("mcp-oauth-lock-fixture", "Build native directory lease interoperability helper");
    oauth_lock_fixture_step.dependOn(&install_oauth_lock_fixture.step);
    const mcp_runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_runtime_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"mcp.runtime"},
    });
    linkDurable(b, mcp_runtime_tests.root_module);
    linkQuickJs(b, mcp_runtime_tests.root_module, quickjs, sqlite_lib_dir);
    const run_mcp_runtime_tests = b.addRunArtifact(mcp_runtime_tests);
    const mcp_runtime_fixture = b.addExecutable(.{
        .name = "pi-mcp-runtime-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_runtime_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const install_mcp_runtime_fixture = b.addInstallArtifact(mcp_runtime_fixture, .{});
    run_mcp_adapter_tests.step.dependOn(&install_mcp_runtime_fixture.step);
    run_mcp_adapter_tests.setEnvironmentVariable("PI_MCP_ADAPTER_ALLOC_SERVER", b.getInstallPath(.bin, b.fmt("pi-mcp-runtime-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    run_mcp_runtime_tests.step.dependOn(&install_mcp_runtime_fixture.step);
    run_mcp_runtime_tests.setEnvironmentVariable("PI_MCP_RUNTIME_FIXTURE", b.getInstallPath(.bin, b.fmt("pi-mcp-runtime-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    const mcp_runtime_step = b.step("test-mcp-runtime", "Exercise native multiplex MCP request ownership pending-connect shutdown and transports");
    mcp_runtime_step.dependOn(&run_mcp_runtime_tests.step);
    test_step.dependOn(&run_mcp_runtime_tests.step);
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_sqlite_tests.step);
    test_step.dependOn(&run_sqlite_cli_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_sqlite_persistence_tests.step);
    test_step.dependOn(&run_sqlite_live_tests.step);

    const engine_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/extensions/engine.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, engine_tests.root_module, quickjs, sqlite_lib_dir);
    const run_engine_tests = b.addRunArtifact(engine_tests);
    const engine_test_step = b.step("test-extension-engine", "Test the directly linked extension-language engine");
    engine_test_step.dependOn(&run_engine_tests.step);
    test_step.dependOn(&run_engine_tests.step);
    const commonjs_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/commonjs.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, commonjs_tests.root_module, quickjs, sqlite_lib_dir);
    const run_commonjs_tests = b.addRunArtifact(commonjs_tests);
    const commonjs_test_step = b.step("test-extension-commonjs", "Test native CommonJS cache and module ownership");
    commonjs_test_step.dependOn(&run_commonjs_tests.step);
    test_step.dependOn(&run_commonjs_tests.step);
    const buffer_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/node_buffer.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, buffer_tests.root_module, quickjs, sqlite_lib_dir);
    const run_buffer_tests = b.addRunArtifact(buffer_tests);
    const buffer_test_step = b.step("test-extension-buffer", "Test native extension Buffer views and encodings");
    buffer_test_step.dependOn(&run_buffer_tests.step);
    test_step.dependOn(&run_buffer_tests.step);
    const schema_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/typebox.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, schema_tests.root_module, quickjs, sqlite_lib_dir);
    const run_schema_tests = b.addRunArtifact(schema_tests);
    const schema_test_step = b.step("test-extension-schemas", "Test native extension schema bindings");
    schema_test_step.dependOn(&run_schema_tests.step);
    test_step.dependOn(&run_schema_tests.step);
    const binding_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_bindings_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, binding_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, binding_tests.root_module);
    binding_tests.root_module.addImport("catalog_tool", catalog_tool);
    const typed_provider_tests = b.addTest(.{ .root_module = binding_tests.root_module, .filters = &.{"typed provider owner"}, .use_llvm = use_llvm });
    const typed_provider_run = b.addRunArtifact(typed_provider_tests);
    b.step("test-typed-provider-owner", "Exercise exact typed provider callback receiver and signal ownership").dependOn(&typed_provider_run.step);
    test_step.dependOn(&typed_provider_run.step);
    const typed_catalog_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_typed_catalog_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"typed catalog"}, .use_llvm = use_llvm });
    linkQuickJs(b, typed_catalog_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, typed_catalog_tests.root_module);
    typed_catalog_tests.root_module.addImport("catalog_tool", catalog_tool);
    const typed_catalog_run = b.addRunArtifact(typed_catalog_tests);
    b.step("test-typed-catalog", "Exercise Source typed catalog registration and allocation ownership").dependOn(&typed_catalog_run.step);
    test_step.dependOn(&typed_catalog_run.step);
    const sdk_stream_ownership_tests = b.addTest(.{
        .root_module = binding_tests.root_module,
        .filters = &.{ "SDK lazy chat stream continuation", "terminal admission allocation" },
        .use_llvm = use_llvm,
    });
    const sdk_stream_ownership_run = b.addRunArtifact(sdk_stream_ownership_tests);
    const sdk_stream_ownership_step = b.step("test-sdk-stream-ownership", "Exercise SDK stream continuations and atomic terminal allocation ownership");
    sdk_stream_ownership_step.dependOn(&sdk_stream_ownership_run.step);
    const sdk_refresh_ownership_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_refresh_ownership_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native model refresh retained publications"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_refresh_ownership_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_refresh_ownership_tests.root_module);
    sdk_refresh_ownership_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_refresh_ownership_run = b.addRunArtifact(sdk_refresh_ownership_tests);
    const sdk_refresh_ownership_step = b.step("test-sdk-refresh-ownership", "Exercise provider refresh publication and cancellation allocation ownership");
    sdk_refresh_ownership_step.dependOn(&sdk_refresh_ownership_run.step);
    test_step.dependOn(&sdk_refresh_ownership_run.step);
    const sdk_auth_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_auth_ownership_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "SDK auth snapshot key synchronization", "availability v2 auth status" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_auth_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_auth_tests.root_module);
    sdk_auth_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_auth_run = b.addRunArtifact(sdk_auth_tests);
    const sdk_auth_step = b.step("test-sdk-auth-ownership", "Exercise auth snapshot and runtime credential allocation ownership");
    sdk_auth_step.dependOn(&sdk_auth_run.step);
    test_step.dependOn(&sdk_auth_run.step);
    const sdk_config_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_config_ownership_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "SDK immutable model configuration", "SDK config template references" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_config_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_config_tests.root_module);
    sdk_config_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_config_run = b.addRunArtifact(sdk_config_tests);
    b.step("test-sdk-config-ownership", "Exercise immutable SDK configuration allocation ownership").dependOn(&sdk_config_run.step);
    test_step.dependOn(&sdk_config_run.step);
    const sdk_virtual_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_virtual_ownership_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK virtual catalog routing filtering stream"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_virtual_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_virtual_tests.root_module);
    sdk_virtual_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_virtual_run = b.addRunArtifact(sdk_virtual_tests);
    b.step("test-sdk-virtual-ownership", "Exercise virtual routing allocation ownership").dependOn(&sdk_virtual_run.step);
    test_step.dependOn(&sdk_virtual_run.step);
    const sdk_model_bridge_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_model_bridge_test.zig"), .target = target, .optimize = optimize });
    sdk_model_bridge_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, sdk_model_bridge_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_model_bridge_module);
    const sdk_model_bridge_tests = b.addTest(.{ .root_module = sdk_model_bridge_module, .use_llvm = use_llvm, .filters = &.{"SDK model bridge"} });
    const sdk_model_bridge_run = b.addRunArtifact(sdk_model_bridge_tests);
    b.step("test-sdk-model-bridge", "Exercise owner-only generation-leased model operations and cancellation").dependOn(&sdk_model_bridge_run.step);
    test_step.dependOn(&sdk_model_bridge_run.step);
    const sdk_session_lease_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_lease_test.zig"), .target = target, .optimize = optimize });
    sdk_session_lease_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, sdk_session_lease_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_session_lease_module);
    const sdk_session_lease_tests = b.addTest(.{ .root_module = sdk_session_lease_module, .use_llvm = use_llvm, .filters = &.{"SDK session model lease"} });
    const sdk_session_lease_run = b.addRunArtifact(sdk_session_lease_tests);
    b.step("test-sdk-session-model-lease", "Exercise exact SDK session model admissions and safe lease retirement").dependOn(&sdk_session_lease_run.step);
    test_step.dependOn(&sdk_session_lease_run.step);
    const sdk_registry_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_model_registry_test.zig"), .target = target, .optimize = optimize });
    sdk_registry_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, sdk_registry_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_registry_module);
    const sdk_registry_tests = b.addTest(.{ .root_module = sdk_registry_module, .use_llvm = use_llvm, .filters = &.{"SDK model registry"} });
    const sdk_registry_run = b.addRunArtifact(sdk_registry_tests);
    b.step("test-sdk-model-registry", "Exercise Source compatibility facade and exact model ownership").dependOn(&sdk_registry_run.step);
    test_step.dependOn(&sdk_registry_run.step);
    const sdk_settings_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_settings_ownership_test.zig"), .target = target, .optimize = optimize });
    sdk_settings_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, sdk_settings_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_settings_module);
    const sdk_settings_tests = b.addTest(.{ .root_module = sdk_settings_module, .use_llvm = use_llvm, .filters = &.{"SDK settings"} });
    const sdk_settings_run = b.addRunArtifact(sdk_settings_tests);
    b.step("test-sdk-settings-ownership", "Exercise SDK settings persistence and ownership against Source").dependOn(&sdk_settings_run.step);
    test_step.dependOn(&sdk_settings_run.step);
    const sdk_session_manager_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_manager_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK session manager"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_session_manager_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_session_manager_tests.root_module);
    sdk_session_manager_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_session_manager_run = b.addRunArtifact(sdk_session_manager_tests);
    b.step("test-sdk-session-manager", "Exercise Source session manager identities projections and allocation ownership").dependOn(&sdk_session_manager_run.step);
    test_step.dependOn(&sdk_session_manager_run.step);
    const tui_word_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/tui_word_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const run_tui_word_tests = b.addRunArtifact(tui_word_tests);
    const tui_word_step = b.step("test-tui-words", "Replay Source word rules dictionaries and signed UTF16 cursor boundaries");
    tui_word_step.dependOn(&run_tui_word_tests.step);
    test_step.dependOn(&run_tui_word_tests.step);
    inline for (.{ .{ "unicode-words-generator", "tools/unicode_words.zig" }, .{ "word-language-data-generator", "tools/word_language_data.zig" }, .{ "word-normalization-data-generator", "tools/word_normalization_data.zig" } }) |item| {
        const generator = b.addExecutable(.{ .name = item[0], .root_module = b.createModule(.{ .root_source_file = b.path(item[1]), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
        const check = b.addRunArtifact(generator);
        check.addArg("--check");
        check.setCwd(b.path("."));
        check.has_side_effects = true;
        tui_word_step.dependOn(&check.step);
        test_step.dependOn(&check.step);
    }
    const native_input_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_input_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "Source6fb public Input", "native JS UTF16" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, native_input_tests.root_module, quickjs, sqlite_lib_dir);
    const run_native_input_tests = b.addRunArtifact(native_input_tests);
    const unicode_width_generator = b.addExecutable(.{ .name = "unicode-width-generator", .root_module = b.createModule(.{ .root_source_file = b.path("tools/unicode_width.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const check_unicode_width = b.addRunArtifact(unicode_width_generator);
    check_unicode_width.addArg("--check");
    check_unicode_width.setCwd(b.path("."));
    check_unicode_width.has_side_effects = true;
    b.step("check-unicode-width", "Verify pinned Source Unicode17 width capture and generated native width tables").dependOn(&check_unicode_width.step);
    const native_input_step = b.step("test-native-input", "Replay Source public Input UTF16 values callbacks and rendering");
    native_input_step.dependOn(&run_native_input_tests.step);
    native_input_step.dependOn(&check_unicode_width.step);
    test_step.dependOn(&run_native_input_tests.step);
    test_step.dependOn(&check_unicode_width.step);
    const sdk_session_files_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_files_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"SDK session files"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_session_files_tests.root_module, quickjs, sqlite_lib_dir);
    linkDurable(b, sdk_session_files_tests.root_module);
    sdk_session_files_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_session_files_run = b.addRunArtifact(sdk_session_files_tests);
    b.step("test-sdk-session-files", "Exercise Source file session open repair persistence and allocation ownership").dependOn(&sdk_session_files_run.step);
    test_step.dependOn(&sdk_session_files_run.step);
    const run_binding_tests = b.addRunArtifact(binding_tests);
    const binding_test_step = b.step("test-extension-bindings", "Test native Pi extension registrations and invocation");
    const cursor_boundary_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/cursor_boundary_test.zig"), .target = target, .optimize = optimize, .link_libc = true }),
        .use_llvm = use_llvm,
    });
    const run_cursor_boundary_tests = b.addRunArtifact(cursor_boundary_tests);
    const cursor_boundary_step = b.step("test-cursor-boundaries", "Replay actual Source cursor overlays Input graphemes and allocator boundaries");
    cursor_boundary_step.dependOn(&run_cursor_boundary_tests.step);
    test_step.dependOn(&run_cursor_boundary_tests.step);
    const theme_constructor_module = b.createModule(.{ .root_source_file = b.path("src/theme_constructor_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, theme_constructor_module, quickjs, sqlite_lib_dir);
    linkDurable(b, theme_constructor_module);
    theme_constructor_module.addImport("catalog_tool", catalog_tool);
    const theme_constructor_tests = b.addTest(.{ .root_module = theme_constructor_module, .use_llvm = use_llvm, .filters = &.{"Source6fb Theme constructor"} });
    const theme_constructor_run = b.addRunArtifact(theme_constructor_tests);
    b.step("test-theme-constructor-6fb", "Replay selected Source Theme constructors fallback slots and retained colors").dependOn(&theme_constructor_run.step);
    test_step.dependOn(&theme_constructor_run.step);
    const dialog_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_dialog_test.zig"), .target = target, .optimize = optimize, .link_libc = true }),
        .use_llvm = use_llvm,
    });
    const run_dialog_tests = b.addRunArtifact(dialog_tests);
    const dialog_test_step = b.step("test-native-dialog", "Compare extension selector/input state with original Source and allocator failures");
    dialog_test_step.dependOn(&run_dialog_tests.step);
    test_step.dependOn(&run_dialog_tests.step);
    binding_test_step.dependOn(&run_binding_tests.step);
    test_step.dependOn(&run_binding_tests.step);
    const theme_state_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/theme_state_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "Controller cached theme", "cached theme DTO" },
        .use_llvm = use_llvm,
    });
    theme_state_tests.root_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, theme_state_tests.root_module, quickjs, sqlite_lib_dir);
    const run_theme_state_tests = b.addRunArtifact(theme_state_tests);
    const theme_state_step = b.step("test-theme-state", "Prove cached theme snapshot ownership and explicit empty reports without terminal I/O");
    theme_state_step.dependOn(&run_theme_state_tests.step);
    test_step.dependOn(&run_theme_state_tests.step);
    const filesystem_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/node_fs.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, filesystem_tests.root_module, quickjs, sqlite_lib_dir);
    const run_filesystem_tests = b.addRunArtifact(filesystem_tests);
    const filesystem_test_step = b.step("test-extension-filesystem", "Test native extension filesystem APIs");
    filesystem_test_step.dependOn(&run_filesystem_tests.step);
    test_step.dependOn(&run_filesystem_tests.step);
    const path_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/node_path.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, path_tests.root_module, quickjs, sqlite_lib_dir);
    const run_path_tests = b.addRunArtifact(path_tests);
    const path_test_step = b.step("test-extension-path", "Test native cross-platform extension path APIs");
    path_test_step.dependOn(&run_path_tests.step);
    test_step.dependOn(&run_path_tests.step);
    const url_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/node_url.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, url_tests.root_module, quickjs, sqlite_lib_dir);
    const run_url_tests = b.addRunArtifact(url_tests);
    const url_test_step = b.step("test-extension-url", "Test native file URL conversion for extensions");
    url_test_step.dependOn(&run_url_tests.step);
    test_step.dependOn(&run_url_tests.step);
    const console_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/console.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, console_tests.root_module, quickjs, sqlite_lib_dir);
    const run_console_tests = b.addRunArtifact(console_tests);
    const console_test_step = b.step("test-extension-console", "Test native console formatting and builtin module identity");
    console_test_step.dependOn(&run_console_tests.step);
    test_step.dependOn(&run_console_tests.step);
    const resolver_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/module_resolver.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_resolver_tests = b.addRunArtifact(resolver_tests);
    const resolver_test_step = b.step("test-extension-resolver", "Test native extension package and file resolution");
    resolver_test_step.dependOn(&run_resolver_tests.step);
    test_step.dependOn(&run_resolver_tests.step);
    const encoding_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/text_encoding.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, encoding_tests.root_module, quickjs, sqlite_lib_dir);
    const run_encoding_tests = b.addRunArtifact(encoding_tests);
    const encoding_test_step = b.step("test-extension-encoding", "Test native text encoding host APIs");
    encoding_test_step.dependOn(&run_encoding_tests.step);
    test_step.dependOn(&run_encoding_tests.step);
    const autocomplete_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/editor_autocomplete_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native autocomplete"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, autocomplete_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, autocomplete_tests.root_module, typescript_parser);
    const run_autocomplete_tests = b.addRunArtifact(autocomplete_tests);
    const autocomplete_step = b.step("test-editor-autocomplete", "Exercise native asynchronous editor providers cancellation selection and UTF16 completion positions");
    autocomplete_step.dependOn(&run_autocomplete_tests.step);
    test_step.dependOn(&run_autocomplete_tests.step);
    const editor_owner_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/editor_owner_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native editor"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, editor_owner_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, editor_owner_tests.root_module, typescript_parser);
    const run_editor_owner_tests = b.addRunArtifact(editor_owner_tests);
    const editor_owner_step = b.step("test-custom-editor", "Exercise native editor classes persistent factories and callback owner teardown");
    editor_owner_step.dependOn(&run_editor_owner_tests.step);
    test_step.dependOn(&run_editor_owner_tests.step);
    const editor_frontend_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/editor_frontend_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"custom editor frontend"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, editor_frontend_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, editor_frontend_tests.root_module, typescript_parser);
    const run_editor_frontend_tests = b.addRunArtifact(editor_frontend_tests);
    const editor_frontend_step = b.step("test-custom-editor-components", "Exercise custom editor fullscreen frame/input/snapshot ownership and close fences");
    editor_frontend_step.dependOn(&run_editor_frontend_tests.step);
    test_step.dependOn(&run_editor_frontend_tests.step);
    const renderer_control_race_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/renderer_control_race_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"renderer control arrives"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, renderer_control_race_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, renderer_control_race_tests.root_module, typescript_parser);
    const run_renderer_control_race_tests = b.addRunArtifact(renderer_control_race_tests);
    const renderer_control_race_step = b.step("test-renderer-control-race", "Exercise persistent renderer controls arriving between owner pump and FIFO dequeue");
    renderer_control_race_step.dependOn(&run_renderer_control_race_tests.step);
    test_step.dependOn(&run_renderer_control_race_tests.step);
    const worker_process_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/native_worker_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_worker_process_tests = b.addRunArtifact(worker_process_tests);
    run_worker_process_tests.step.dependOn(b.getInstallStep());
    const worker_process_step = b.step("test-native-worker", "Exercise a real native extension process without Node on PATH");
    worker_process_step.dependOn(&run_worker_process_tests.step);
    test_step.dependOn(&run_worker_process_tests.step);
    const native_runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_runtime_process_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native runtime"},
        .use_llvm = use_llvm,
    });
    const run_native_runtime_tests = b.addRunArtifact(native_runtime_tests);
    run_native_runtime_tests.step.dependOn(b.getInstallStep());
    const typed_owner_process_tests = b.addTest(.{ .root_module = native_runtime_tests.root_module, .filters = &.{"native runtime typed provider owner"}, .use_llvm = use_llvm });
    const typed_owner_process_run = b.addRunArtifact(typed_owner_process_tests);
    typed_owner_process_run.step.dependOn(b.getInstallStep());
    b.step("test-typed-provider-process", "Exercise typed callbacks over the real native owner transport without Node").dependOn(&typed_owner_process_run.step);
    test_step.dependOn(&typed_owner_process_run.step);
    const native_runtime_step = b.step("test-native-runtime", "Exercise the persistent native extension runtime and host without Node");
    native_runtime_step.dependOn(&run_native_runtime_tests.step);
    const late_registration_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_runtime_process_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native runtime late"},
        .use_llvm = use_llvm,
    });
    const run_late_registration_tests = b.addRunArtifact(late_registration_tests);
    run_late_registration_tests.step.dependOn(b.getInstallStep());
    const late_registration_step = b.step("test-native-late-registration", "Prove late native registrations, atomic metadata allocation failures and live CLI discovery");
    late_registration_step.dependOn(&run_late_registration_tests.step);
    test_step.dependOn(&run_late_registration_tests.step);
    const selection_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/tool_selection_process_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native CLI tool selection"},
        .use_llvm = use_llvm,
    });
    const run_selection_tests = b.addRunArtifact(selection_tests);
    run_selection_tests.step.dependOn(b.getInstallStep());
    const selection_step = b.step("test-tool-selection-process", "Replay source tool loadouts and registration transitions in the actual native CLI without Node");
    selection_step.dependOn(&run_selection_tests.step);
    test_step.dependOn(&run_selection_tests.step);
    const custom_editor_runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_runtime_process_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native runtime custom editor"},
        .use_llvm = use_llvm,
    });
    const run_custom_editor_runtime_tests = b.addRunArtifact(custom_editor_runtime_tests);
    run_custom_editor_runtime_tests.step.dependOn(b.getInstallStep());
    const custom_editor_runtime_step = b.step("test-custom-editor-runtime", "Exercise original upstream modal editor input through a real native worker");
    custom_editor_runtime_step.dependOn(&run_custom_editor_runtime_tests.step);
    test_step.dependOn(&run_native_runtime_tests.step);
    for ([_]struct { name: []const u8, source: []const u8 }{
        .{ .name = "test-provider-method-protocol", .source = "src/provider_method_protocol_test.zig" },
        .{ .name = "test-provider-stream-protocol", .source = "src/provider_stream_protocol_test.zig" },
        .{ .name = "test-provider-oauth-protocol", .source = "src/provider_oauth_protocol_test.zig" },
        .{ .name = "test-provider-models-protocol", .source = "src/provider_models_protocol_test.zig" },
    }) |contract| {
        const raw_tests = b.addTest(.{
            .root_module = b.createModule(.{ .root_source_file = b.path(contract.source), .target = target, .optimize = optimize }),
            .use_llvm = use_llvm,
        });
        const run_raw_tests = b.addRunArtifact(raw_tests);
        run_raw_tests.step.dependOn(b.getInstallStep());
        run_raw_tests.setEnvironmentVariable("PI_TEST_BINARY", b.getInstallPath(.bin, if (target.result.os.tag == .windows) "pi.exe" else "pi"));
        const raw_step = b.step(contract.name, "Exercise original provider raw protocol contracts through the native worker without Node");
        raw_step.dependOn(&run_raw_tests.step);
        test_step.dependOn(&run_raw_tests.step);
    }
    const auth_screen_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/auth_screen_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_auth_screen_tests = b.addRunArtifact(auth_screen_tests);
    run_auth_screen_tests.step.dependOn(b.getInstallStep());
    const auth_screen_step = b.step("test-auth-screen", "Exercise native authentication selectors through a real Linux PTY");
    auth_screen_step.dependOn(&run_auth_screen_tests.step);
    test_step.dependOn(&run_auth_screen_tests.step);
    const auth_opener = b.addExecutable(.{
        .name = "pi-auth-opener",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/test_support/http_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const install_auth_opener = b.addInstallArtifact(auth_opener, .{});
    const auth_dialog_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/auth_dialog_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_auth_dialog_tests = b.addRunArtifact(auth_dialog_tests);
    run_auth_dialog_tests.step.dependOn(b.getInstallStep());
    run_auth_dialog_tests.step.dependOn(&install_auth_opener.step);
    const auth_dialog_step = b.step("test-auth-dialog", "Exercise native browser and device OAuth through a real Linux PTY");
    auth_dialog_step.dependOn(&run_auth_dialog_tests.step);
    test_step.dependOn(&run_auth_dialog_tests.step);
    const bootstrap_network_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/bootstrap_network_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_bootstrap_network_tests = b.addRunArtifact(bootstrap_network_tests);
    run_bootstrap_network_tests.step.dependOn(b.getInstallStep());
    const bootstrap_network_step = b.step("test-bootstrap-network", "Exercise bootstrap HTTP retries timeouts persistence and proxies through the native CLI");
    bootstrap_network_step.dependOn(&run_bootstrap_network_tests.step);
    test_step.dependOn(&run_bootstrap_network_tests.step);
    const provider_retry_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/provider_retry_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_provider_retry_tests = b.addRunArtifact(provider_retry_tests);
    run_provider_retry_tests.step.dependOn(b.getInstallStep());
    const provider_retry_step = b.step("test-provider-retry-process", "Exercise provider retries and live RPC policy reload through the native CLI");
    provider_retry_step.dependOn(&run_provider_retry_tests.step);
    test_step.dependOn(&run_provider_retry_tests.step);
    const project_settings_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/project_settings_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_project_settings_tests = b.addRunArtifact(project_settings_tests);
    run_project_settings_tests.step.dependOn(b.getInstallStep());
    const project_settings_step = b.step("test-project-settings-process", "Exercise global and project settings through the real native PTY");
    project_settings_step.dependOn(&run_project_settings_tests.step);
    test_step.dependOn(&run_project_settings_tests.step);
    const settings_screen_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/settings_screen_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_settings_screen_tests = b.addRunArtifact(settings_screen_tests);
    run_settings_screen_tests.step.dependOn(b.getInstallStep());
    const settings_screen_step = b.step("test-settings-screen-process", "Exercise settings transactions reload tree filters and quiet startup through the native PTY");
    settings_screen_step.dependOn(&run_settings_screen_tests.step);
    test_step.dependOn(&run_settings_screen_tests.step);
    const auth_flow_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/auth_flow_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_auth_flow_tests = b.addRunArtifact(auth_flow_tests);
    run_auth_flow_tests.step.dependOn(b.getInstallStep());
    const auth_flow_step = b.step("test-auth-flow-process", "Exercise authentication stages sources masked keys and scoped selection through native PTY");
    auth_flow_step.dependOn(&run_auth_flow_tests.step);
    test_step.dependOn(&run_auth_flow_tests.step);
    const auth_live_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/auth_live_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_auth_live_tests = b.addRunArtifact(auth_live_tests);
    run_auth_live_tests.step.dependOn(b.getInstallStep());
    const auth_live_step = b.step("test-auth-live-process", "Exercise live login credential rebinding and logout fallback through native PTY and HTTP");
    auth_live_step.dependOn(&run_auth_live_tests.step);
    test_step.dependOn(&run_auth_live_tests.step);

    const tree_controls_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/tree_controls_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_tree_controls_tests = b.addRunArtifact(tree_controls_tests);
    run_tree_controls_tests.step.dependOn(b.getInstallStep());
    const tree_controls_step = b.step("test-tree-controls-process", "Exercise durable tree labels, search, filters and OSC 52 through native RPC and PTY");
    tree_controls_step.dependOn(&run_tree_controls_tests.step);
    test_step.dependOn(&run_tree_controls_tests.step);

    const summary_options_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/summary_options_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_summary_options_tests = b.addRunArtifact(summary_options_tests);
    run_summary_options_tests.step.dependOn(b.getInstallStep());
    const summary_options_step = b.step("test-summary-options-process", "Exercise summary token caps and omitted affinity/cache options through native RPC, PTY and HTTP");
    summary_options_step.dependOn(&run_summary_options_tests.step);
    test_step.dependOn(&run_summary_options_tests.step);

    const media_skills_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/media_skills_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_media_skills_tests = b.addRunArtifact(media_skills_tests);
    run_media_skills_tests.step.dependOn(b.getInstallStep());
    const media_skills_step = b.step("test-media-skills-process", "Exercise image privacy, durable normalized pixels and live skill command reload through native HTTP and RPC");
    media_skills_step.dependOn(&run_media_skills_tests.step);
    test_step.dependOn(&run_media_skills_tests.step);

    const compaction_policy_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/compaction_policy_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_compaction_policy_tests = b.addRunArtifact(compaction_policy_tests);
    run_compaction_policy_tests.step.dependOn(b.getInstallStep());
    const compaction_policy_step = b.step("test-compaction-policy-process", "Exercise persisted token budgets, split-turn hooks and append-only compaction through native RPC");
    compaction_policy_step.dependOn(&run_compaction_policy_tests.step);
    test_step.dependOn(&run_compaction_policy_tests.step);

    const branch_policy_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/branch_policy_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_branch_policy_tests = b.addRunArtifact(branch_policy_tests);
    run_branch_policy_tests.step.dependOn(b.getInstallStep());
    const branch_policy_step = b.step("test-branch-policy-process", "Exercise custom branch summaries, durable usage and labels, and skip-prompt hooks through native RPC and PTY");
    branch_policy_step.dependOn(&run_branch_policy_tests.step);
    test_step.dependOn(&run_branch_policy_tests.step);

    const fullscreen_frontend_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/fullscreen_frontend_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_fullscreen_frontend_tests = b.addRunArtifact(fullscreen_frontend_tests);
    const late_frontend_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/fullscreen_frontend_process_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native late live"},
    });
    const run_late_frontend_tests = b.addRunArtifact(late_frontend_tests);
    run_late_frontend_tests.step.dependOn(b.getInstallStep());
    const late_frontend_step = b.step("test-native-late-frontend", "Prove live native late command completion and agent tool invocation through real terminal cells");
    late_frontend_step.dependOn(&run_late_frontend_tests.step);
    test_step.dependOn(&run_late_frontend_tests.step);
    const custom_editor_frontend_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/fullscreen_frontend_process_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"real custom editor"},
        .use_llvm = use_llvm,
    });
    const run_custom_editor_frontend_tests = b.addRunArtifact(custom_editor_frontend_tests);
    run_custom_editor_frontend_tests.step.dependOn(b.getInstallStep());
    const custom_editor_frontend_step = b.step("test-custom-editor-frontend", "Exercise custom editor input submit reload and terminal ownership in real PTY cells");
    custom_editor_frontend_step.dependOn(&run_custom_editor_frontend_tests.step);
    run_fullscreen_frontend_tests.step.dependOn(b.getInstallStep());
    if (target.result.os.tag == .macos) {
        fullscreen_frontend_tests.root_module.link_libc = true;
        late_frontend_tests.root_module.link_libc = true;
        custom_editor_frontend_tests.root_module.link_libc = true;
    }
    if (target.result.os.tag == .windows) {
        for ([_]struct { name: []const u8, source: []const u8, environment: []const u8 }{
            .{ .name = "pi-conpty-launcher", .source = "src/test_support/conpty_launcher.zig", .environment = "PI_TEST_CONPTY_LAUNCHER" },
            .{ .name = "pi-terminal-probe", .source = "src/test_support/terminal_probe.zig", .environment = "PI_TEST_CONPTY_PROBE" },
        }) |helper| {
            const program = b.addExecutable(.{
                .name = helper.name,
                .root_module = b.createModule(.{ .root_source_file = b.path(helper.source), .target = target, .optimize = optimize }),
                .use_llvm = use_llvm,
            });
            const installation = b.addInstallArtifact(program, .{});
            run_fullscreen_frontend_tests.step.dependOn(&installation.step);
            run_custom_editor_frontend_tests.step.dependOn(&installation.step);
            run_fullscreen_frontend_tests.setEnvironmentVariable(helper.environment, b.getInstallPath(.bin, b.fmt("{s}.exe", .{helper.name})));
            run_late_frontend_tests.step.dependOn(&installation.step);
            run_late_frontend_tests.setEnvironmentVariable(helper.environment, b.getInstallPath(.bin, b.fmt("{s}.exe", .{helper.name})));
            run_custom_editor_frontend_tests.setEnvironmentVariable(helper.environment, b.getInstallPath(.bin, b.fmt("{s}.exe", .{helper.name})));
        }
    }
    const fullscreen_frontend_step = b.step("test-fullscreen-frontend-process", "Exercise persistent fullscreen CLI behavior through real native PTY terminal cells");
    fullscreen_frontend_step.dependOn(&run_fullscreen_frontend_tests.step);
    test_step.dependOn(&run_fullscreen_frontend_tests.step);

    const fullscreen_frontend_components = b.addTest(.{
        .root_module = test_mod,
        .filters = &.{ "coding_agent.fullscreen_frontend", "coding_agent.transcript_view", "tui.line_editor.test.fullscreen", "ai.mock.test.paced" },
        .use_llvm = use_llvm,
    });
    const run_fullscreen_frontend_components = b.addRunArtifact(fullscreen_frontend_components);
    const fullscreen_frontend_components_step = b.step("test-fullscreen-frontend-components", "Exercise retained fullscreen mailbox, surfaces, editor and transcript allocation ownership");
    fullscreen_frontend_components_step.dependOn(&run_fullscreen_frontend_components.step);

    const clipboard_helper = b.addExecutable(.{
        .name = "pi-clipboard-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/test_support/clipboard_helper.zig"), .target = target, .optimize = optimize }),
    });
    const install_clipboard_helper = b.addInstallArtifact(clipboard_helper, .{});
    const clipboard_copy_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/clipboard_copy_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_clipboard_copy_tests = b.addRunArtifact(clipboard_copy_tests);
    run_clipboard_copy_tests.step.dependOn(b.getInstallStep());
    run_clipboard_copy_tests.step.dependOn(&install_clipboard_helper.step);
    const clipboard_copy_step = b.step("test-clipboard-copy-process", "Exercise local and remote clipboard copy and extension compatibility through native PTY and clipboard fixture");
    clipboard_copy_step.dependOn(&run_clipboard_copy_tests.step);
    test_step.dependOn(&run_clipboard_copy_tests.step);

    const clipboard_paste_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/clipboard_paste_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_clipboard_paste_tests = b.addRunArtifact(clipboard_paste_tests);
    run_clipboard_paste_tests.step.dependOn(b.getInstallStep());
    run_clipboard_paste_tests.step.dependOn(&install_clipboard_helper.step);
    const clipboard_paste_step = b.step("test-clipboard-paste-process", "Exercise keyboard image and sanitized text paste with native clipboard input and owned temp cleanup");
    clipboard_paste_step.dependOn(&run_clipboard_paste_tests.step);
    test_step.dependOn(&run_clipboard_paste_tests.step);

    const session_hooks_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/session_hooks_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_session_hooks_tests = b.addRunArtifact(session_hooks_tests);
    run_session_hooks_tests.step.dependOn(b.getInstallStep());
    const session_hooks_step = b.step("test-session-hooks-process", "Exercise compaction replacement, immediate cancellation actions and tree hook persistence through native RPC and PTY");
    session_hooks_step.dependOn(&run_session_hooks_tests.step);
    test_step.dependOn(&run_session_hooks_tests.step);

    const tool_fixture = b.addExecutable(.{
        .name = "pi-tool-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/test_support/tool_helper.zig"), .target = target, .optimize = optimize }),
    });
    const install_tool_fixture = b.addInstallArtifact(tool_fixture, .{});
    const session_update_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/session_update_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_session_update_tests = b.addRunArtifact(session_update_tests);
    run_session_update_tests.step.dependOn(b.getInstallStep());
    run_session_update_tests.step.dependOn(&install_tool_fixture.step);
    const session_update_step = b.step("test-session-update-process", "Exercise startup and live resume isolation and managed self update through native PTY HTTP and package-manager fixture");
    session_update_step.dependOn(&run_session_update_tests.step);
    test_step.dependOn(&run_session_update_tests.step);
    const model_update_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/model_update_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_model_update_tests = b.addRunArtifact(model_update_tests);
    run_model_update_tests.step.dependOn(b.getInstallStep());
    run_model_update_tests.step.dependOn(&install_tool_fixture.step);
    const model_update_step = b.step("test-model-update-process", "Exercise durable model selection lifecycle telemetry and native managed tool archive/cache reuse");
    model_update_step.dependOn(&run_model_update_tests.step);
    test_step.dependOn(&run_model_update_tests.step);
    const image_processing_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/image_processing_process_test.zig"), .target = target, .optimize = optimize }),
    });
    const run_image_processing_tests = b.addRunArtifact(image_processing_tests);
    run_image_processing_tests.step.dependOn(b.getInstallStep());
    const image_processing_step = b.step("test-image-processing-process", "Exercise actual attachment read-tool and extension post-hook image normalization with native fixtures");
    image_processing_step.dependOn(&run_image_processing_tests.step);
    test_step.dependOn(&run_image_processing_tests.step);
    const typescript_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/extensions/typescript.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, typescript_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, typescript_tests.root_module, typescript_parser);
    const run_typescript_tests = b.addRunArtifact(typescript_tests);
    const typescript_test_step = b.step("test-extension-typescript", "Test native extension input transformation");
    typescript_test_step.dependOn(&run_typescript_tests.step);
    test_step.dependOn(&run_typescript_tests.step);

    const maintenance = b.addExecutable(.{
        .name = "pi-maintenance",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/maintenance.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
    });
    maintenance.root_module.addImport("release_config", b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const run_maintenance = b.addRunArtifact(maintenance);
    if (b.args) |args| run_maintenance.addArgs(args);
    const maintenance_step = b.step("maintenance", "Run native repository maintenance commands");
    maintenance_step.dependOn(&run_maintenance.step);
    const maintenance_tests = b.addTest(.{ .root_module = maintenance.root_module, .use_llvm = use_llvm });
    const run_maintenance_tests = b.addRunArtifact(maintenance_tests);
    const maintenance_test_step = b.step("test-maintenance", "Test native repository maintenance");
    maintenance_test_step.dependOn(&run_maintenance_tests.step);
    test_step.dependOn(&run_maintenance_tests.step);
    const duration_module = b.createModule(.{
        .root_source_file = b.path("src/latest_duration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    duration_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, duration_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, duration_module, typescript_parser);
    linkSqlite(duration_module, sqlite_lib_dir, sqlite_library);
    linkDurable(b, duration_module);
    const duration_tests = b.addTest(.{
        .root_module = duration_module,
        .use_llvm = use_llvm,
        .filters = &.{ "latest tool duration", "parallel tool end events", "streaming external update", "agent event payload" },
    });
    const run_duration_tests = b.addRunArtifact(duration_tests);
    const duration_step = b.step("test-tool-duration", "Check monotonic execution duration and lossless event/session persistence");
    duration_step.dependOn(&run_duration_tests.step);
    test_step.dependOn(&run_duration_tests.step);
    const azure_alias_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/azure_alias_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Azure"},
        .use_llvm = use_llvm,
    });
    const run_azure_alias_tests = b.addRunArtifact(azure_alias_tests);
    const azure_alias_step = b.step("test-azure-aliases", "Check Azure identity compatibility across models settings and credentials");
    azure_alias_step.dependOn(&run_azure_alias_tests.step);
    test_step.dependOn(&run_azure_alias_tests.step);
    const fullscreen_key_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/fullscreen_key_routing_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_fullscreen_key_tests = b.addRunArtifact(fullscreen_key_tests);
    const fullscreen_key_step = b.step("test-fullscreen-keys", "Check editor and transcript navigation through real native components");
    fullscreen_key_step.dependOn(&run_fullscreen_key_tests.step);

    const classifier_tests = b.addTest(.{
        .root_module = test_mod,
        .use_llvm = use_llvm,
        .filters = &.{"classifier"},
    });
    const run_classifier_tests = b.addRunArtifact(classifier_tests);
    const classifier_test_step = b.step("test-classifier", "Test native classifier contracts");
    classifier_test_step.dependOn(&run_classifier_tests.step);
    // Behavioral replacement for the retired Python source-text audits.
    const provider_contract_tests = b.addTest(.{
        .root_module = test_mod,
        .use_llvm = use_llvm,
        .filters = &.{ "extensions.provider_", "extensions.models_store", "auth.storage" },
    });
    const run_provider_contract_tests = b.addRunArtifact(provider_contract_tests);
    const provider_contract_step = b.step("test-provider-contracts", "Exercise provider ownership OAuth refresh model publication and stream contracts");
    provider_contract_step.dependOn(&run_provider_contract_tests.step);
    provider_contract_step.dependOn(&run_binding_tests.step);
    provider_contract_step.dependOn(&run_worker_process_tests.step);
    const tool_schema_tests = b.addTest(.{
        .root_module = test_mod,
        .use_llvm = use_llvm,
        .filters = &.{ "tool schema", "native Unicode schema regexp" },
    });
    const run_tool_schema_tests = b.addRunArtifact(tool_schema_tests);
    const tool_schema_step = b.step("test-tool-schemas", "Verify native tool schemas against real tuple and record shapes");
    tool_schema_step.dependOn(&run_tool_schema_tests.step);
    const catalog_projection_tests = b.addTest(.{
        .root_module = test_mod,
        .filters = &.{"native catalog projection"},
        .use_llvm = use_llvm,
    });
    const run_catalog_projection_tests = b.addRunArtifact(catalog_projection_tests);
    const catalog_projection_step = b.step("test-catalog-projection", "Check native catalog projection against the prior generator");
    catalog_projection_step.dependOn(&run_catalog_projection_tests.step);
}

fn linkTypeScriptParser(b: *std.Build, module: *std.Build.Module, library: *std.Build.Step.Compile) void {
    module.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    module.linkLibrary(library);
    module.link_libc = true;
}

fn linkQuickJs(b: *std.Build, module: *std.Build.Module, library: *std.Build.Step.Compile, sqlite_lib_dir: ?[]const u8) void {
    if (sqlite_lib_dir) |directory| module.addLibraryPath(.{ .cwd_relative = directory });
    module.addIncludePath(b.path("vendor/quickjs"));
    module.addIncludePath(b.path("src/extensions"));
    module.linkLibrary(library);
    module.link_libc = true;
    // SDK imports can reach native durable filesystem watchers from any VM
    // consumer. Darwin framework dependencies belong to each final module.
    if (module.resolved_target.?.result.os.tag == .macos) {
        module.linkFramework("CoreFoundation", .{});
        module.linkFramework("CoreServices", .{});
    }
}

fn linkSqlite(module: *std.Build.Module, library_dir: ?[]const u8, library: ?*std.Build.Step.Compile) void {
    if (library) |compiled| module.linkLibrary(compiled) else {
        if (library_dir) |path| module.addLibraryPath(.{ .cwd_relative = path });
        module.linkSystemLibrary("sqlite3", .{});
    }
    module.link_libc = true;
}
fn linkDurable(b: *std.Build, module: *std.Build.Module) void {
    module.addCSourceFile(.{ .file = b.path("src/durable/process_probe.c"), .flags = &.{"-std=gnu11"} });
    module.link_libc = true;
    if (module.resolved_target.?.result.os.tag == .macos) {
        module.linkFramework("CoreFoundation", .{});
        module.linkFramework("CoreServices", .{});
    }
}
