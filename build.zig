const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Zig 0.16's self-hosted backend is useful for large validation builds and
    // optional companions on constrained builders. Default remains Zig's
    // platform choice; callers may select `-Duse-llvm=false` explicitly.
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM for executables and test artifacts");
    const sqlite_lib_dir = b.option([]const u8, "sqlite-lib-dir", "Directory containing a linkable sqlite3 library");

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
    typescript_parser.root_module.addCSourceFiles(.{
        .files = &.{
            "vendor/tree-sitter/lib/src/lib.c",
            "vendor/typescript-parser/typescript/src/parser.c",
            "vendor/typescript-parser/typescript/src/scanner.c",
        },
        .flags = &.{ "-std=gnu11", "-D_POSIX_C_SOURCE=200809L", "-D_DEFAULT_SOURCE", "-fno-strict-aliasing" },
    });

    const mod = b.addModule("pi_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const catalog_tool = b.createModule(.{ .root_source_file = b.path("tools/catalog.zig"), .target = target, .optimize = optimize });
    mod.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, mod, quickjs);
    linkTypeScriptParser(b, mod, typescript_parser);
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
    test_mod.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, test_mod, quickjs);
    linkTypeScriptParser(b, test_mod, typescript_parser);
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
    const mcp_fixture = b.addExecutable(.{
        .name = "pi-mcp-fixture",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp/stdio_fixture.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const install_mcp_fixture = b.addInstallArtifact(mcp_fixture, .{});
    const mcp_process_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp/stdio_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_mcp_process_tests = b.addRunArtifact(mcp_process_tests);
    run_mcp_process_tests.step.dependOn(&install_mcp_fixture.step);
    const mcp_test_step = b.step("test-mcp-stdio", "Exercise real native MCP pipe framing and protocol negotiation");
    mcp_test_step.dependOn(&run_mcp_process_tests.step);
    test_step.dependOn(&run_mcp_process_tests.step);
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
    linkQuickJs(b, engine_tests.root_module, quickjs);
    const run_engine_tests = b.addRunArtifact(engine_tests);
    const engine_test_step = b.step("test-extension-engine", "Test the directly linked extension-language engine");
    engine_test_step.dependOn(&run_engine_tests.step);
    test_step.dependOn(&run_engine_tests.step);
    const commonjs_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/commonjs.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, commonjs_tests.root_module, quickjs);
    const run_commonjs_tests = b.addRunArtifact(commonjs_tests);
    const commonjs_test_step = b.step("test-extension-commonjs", "Test native CommonJS cache and module ownership");
    commonjs_test_step.dependOn(&run_commonjs_tests.step);
    test_step.dependOn(&run_commonjs_tests.step);
    const buffer_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/node_buffer.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, buffer_tests.root_module, quickjs);
    const run_buffer_tests = b.addRunArtifact(buffer_tests);
    const buffer_test_step = b.step("test-extension-buffer", "Test native extension Buffer views and encodings");
    buffer_test_step.dependOn(&run_buffer_tests.step);
    test_step.dependOn(&run_buffer_tests.step);
    const schema_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/typebox.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, schema_tests.root_module, quickjs);
    const run_schema_tests = b.addRunArtifact(schema_tests);
    const schema_test_step = b.step("test-extension-schemas", "Test native extension schema bindings");
    schema_test_step.dependOn(&run_schema_tests.step);
    test_step.dependOn(&run_schema_tests.step);
    const binding_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/native_bindings.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, binding_tests.root_module, quickjs);
    const run_binding_tests = b.addRunArtifact(binding_tests);
    const binding_test_step = b.step("test-extension-bindings", "Test native Pi extension registrations and invocation");
    binding_test_step.dependOn(&run_binding_tests.step);
    test_step.dependOn(&run_binding_tests.step);
    const filesystem_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/node_fs.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, filesystem_tests.root_module, quickjs);
    const run_filesystem_tests = b.addRunArtifact(filesystem_tests);
    const filesystem_test_step = b.step("test-extension-filesystem", "Test native extension filesystem APIs");
    filesystem_test_step.dependOn(&run_filesystem_tests.step);
    test_step.dependOn(&run_filesystem_tests.step);
    const path_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/node_path.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, path_tests.root_module, quickjs);
    const run_path_tests = b.addRunArtifact(path_tests);
    const path_test_step = b.step("test-extension-path", "Test native cross-platform extension path APIs");
    path_test_step.dependOn(&run_path_tests.step);
    test_step.dependOn(&run_path_tests.step);
    const url_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/node_url.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, url_tests.root_module, quickjs);
    const run_url_tests = b.addRunArtifact(url_tests);
    const url_test_step = b.step("test-extension-url", "Test native file URL conversion for extensions");
    url_test_step.dependOn(&run_url_tests.step);
    test_step.dependOn(&run_url_tests.step);
    const console_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/console.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, console_tests.root_module, quickjs);
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
    linkQuickJs(b, encoding_tests.root_module, quickjs);
    const run_encoding_tests = b.addRunArtifact(encoding_tests);
    const encoding_test_step = b.step("test-extension-encoding", "Test native text encoding host APIs");
    encoding_test_step.dependOn(&run_encoding_tests.step);
    test_step.dependOn(&run_encoding_tests.step);
    const worker_process_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/native_worker_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_worker_process_tests = b.addRunArtifact(worker_process_tests);
    run_worker_process_tests.step.dependOn(b.getInstallStep());
    const worker_process_step = b.step("test-native-worker", "Exercise a real native extension process without Node on PATH");
    worker_process_step.dependOn(&run_worker_process_tests.step);
    test_step.dependOn(&run_worker_process_tests.step);
    const typescript_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/extensions/typescript.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, typescript_tests.root_module, quickjs);
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
    const run_maintenance = b.addRunArtifact(maintenance);
    if (b.args) |args| run_maintenance.addArgs(args);
    const maintenance_step = b.step("maintenance", "Run native repository maintenance commands");
    maintenance_step.dependOn(&run_maintenance.step);
    const maintenance_tests = b.addTest(.{ .root_module = maintenance.root_module, .use_llvm = use_llvm });
    const run_maintenance_tests = b.addRunArtifact(maintenance_tests);
    const maintenance_test_step = b.step("test-maintenance", "Test native repository maintenance");
    maintenance_test_step.dependOn(&run_maintenance_tests.step);
    test_step.dependOn(&run_maintenance_tests.step);

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

fn linkQuickJs(b: *std.Build, module: *std.Build.Module, library: *std.Build.Step.Compile) void {
    module.addIncludePath(b.path("vendor/quickjs"));
    module.addIncludePath(b.path("src/extensions"));
    module.linkLibrary(library);
    module.link_libc = true;
}

fn linkSqlite(module: *std.Build.Module, library_dir: ?[]const u8) void {
    if (library_dir) |path| module.addLibraryPath(.{ .cwd_relative = path });
    module.linkSystemLibrary("sqlite3", .{});
    module.link_libc = true;
}
