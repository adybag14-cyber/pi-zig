const std = @import("std");

pub fn build(b: *std.Build) void {
    const install_dark_theme = b.addInstallFileWithDir(b.path("src/themes/fixtures/dark-original-6fb.json"), .bin, "theme/dark.json");
    const install_light_theme = b.addInstallFileWithDir(b.path("src/themes/fixtures/light-original-6fb.json"), .bin, "theme/light.json");
    b.getInstallStep().dependOn(&install_dark_theme.step);
    b.getInstallStep().dependOn(&install_light_theme.step);
    const install_schemas = b.addInstallDirectory(.{ .source_dir = b.path("schemas"), .install_dir = .prefix, .install_subdir = "share/pi/schemas" });
    b.getInstallStep().dependOn(&install_schemas.step);
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Zig 0.16's self-hosted backend is useful for large validation builds and
    // optional companions on constrained builders. Default remains Zig's
    // platform choice; callers may select `-Duse-llvm=false` explicitly.
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM for executables and test artifacts");
    const vm_identity = @import("tools/build_native_vm_identity.zig").add(b, target, optimize, use_llvm) catch |err| std.debug.panic("Native VM identity cannot bind its source/tool inputs: {s}", .{@errorName(err)});
    b.modules.put(b.graph.arena, "native_vm_identity", vm_identity) catch @panic("OOM");
    const native_yaml = @import("tools/build_native_yaml.zig").add(b, target, optimize);
    const frontmatter_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_frontmatter_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native frontmatter"}, .use_llvm = use_llvm });
    frontmatter_tests.root_module.addIncludePath(b.path("vendor/libfyaml"));
    frontmatter_tests.root_module.linkLibrary(native_yaml);
    const frontmatter_run = b.addRunArtifact(frontmatter_tests);
    b.step("test-native-frontmatter", "Replay all Source461 YAML grammar errors and native schema alias allocation ownership").dependOn(&frontmatter_run.step);
    const codemode_source_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/codemode_source_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native codemode source"},
        .use_llvm = use_llvm,
    });
    b.step("test-codemode-source", "Compare ECMAScript source directives with actual upstream results").dependOn(&b.addRunArtifact(codemode_source_tests).step);
    const latest12_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/latest12_small_contracts_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "native codemode source", "Wayland copy", "latest Pi 1.2 selected inventory" },
        .use_llvm = use_llvm,
    });
    b.step("test-latest12-small-contracts", "Replay latest directive placement and explicit remote clipboard opt-in").dependOn(&b.addRunArtifact(latest12_tests).step);
    const native_photon_library = @import("tools/build_photon.zig").library(b, target, optimize);
    const native_photon_link = b.addModule("native_photon_link", .{ .root_source_file = b.path("src/ai/photon_session.zig"), .target = target, .optimize = optimize, .link_libc = true });
    native_photon_link.addIncludePath(b.path("vendor/photon-native"));
    native_photon_link.linkLibrary(native_photon_library);
    if (target.result.os.tag != .windows) native_photon_link.linkSystemLibrary("m", .{});
    const photon_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_photon_test.zig"), .target = target, .optimize = optimize, .link_libc = true }),
        .use_llvm = use_llvm,
    });
    photon_tests.root_module.addIncludePath(b.path("vendor/photon-native"));
    photon_tests.root_module.linkLibrary(native_photon_library);
    if (target.result.os.tag != .windows) photon_tests.root_module.linkSystemLibrary("m", .{});
    b.step("test-native-photon", "Compare native C image algorithms and Zig resize ownership against actual upstream results").dependOn(&b.addRunArtifact(photon_tests).step);
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
    const native_icu = @import("tools/build_native_icu.zig").add(b, target, optimize);
    quickjs.root_module.linkLibrary(native_icu.library);
    quickjs.root_module.link_libcpp = true;
    quickjs.root_module.linkLibrary(native_yaml);
    quickjs.root_module.addIncludePath(b.path("vendor/quickjs"));
    // Native public storage is installed for every extension VM. Carry SQLite
    // through this common dependency so CLI, SDK and bindings all receive it.
    linkSqlite(quickjs.root_module, sqlite_lib_dir, sqlite_library);
    const quickjs_c_flags = [_][]const u8{ "-std=gnu11", "-D_GNU_SOURCE", "-DQUICKJS_NG_BUILD", "-funsigned-char", "-fno-strict-aliasing" };
    quickjs.root_module.addCSourceFiles(.{
        .root = b.path("vendor/quickjs"),
        .files = &.{ "dtoa.c", "libregexp.c", "libunicode.c", "quickjs.c" },
        // QuickJS's unoptimized interpreter reserves about 60 KiB per call on
        // Windows. Keep Zig Debug and C assertions while reducing C frame size
        // enough for ordinary nested terminal callbacks within the VM limit.
        .flags = if (optimize == .Debug) &(quickjs_c_flags ++ [_][]const u8{"-Og"}) else &quickjs_c_flags,
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
    const codemode_clock_module = b.createModule(.{ .root_source_file = b.path("src/native_codemode_clock_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, codemode_clock_module, quickjs, sqlite_lib_dir);
    linkSqlite(codemode_clock_module, sqlite_lib_dir, sqlite_library);
    const codemode_clock_tests = b.addTest(.{ .root_module = codemode_clock_module, .use_llvm = use_llvm, .filters = &.{ "native CodeMode deterministic", "CodeMode virtual clock" } });
    b.step("compile-native-codemode-clock", "Compile the exact native clock test artifact without running tests").dependOn(&b.addInstallArtifact(codemode_clock_tests, .{ .dest_sub_path = "native-codemode-clock.exe" }).step);
    b.step("test-native-codemode-clock", "Compare native context time seed and UTC against actual latest WASM observations").dependOn(&b.addRunArtifact(codemode_clock_tests).step);
    const codemode_run_module = b.createModule(.{ .root_source_file = b.path("src/native_codemode_run_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, codemode_run_module, quickjs, sqlite_lib_dir);
    linkSqlite(codemode_run_module, sqlite_lib_dir, sqlite_library);
    const codemode_run_tests = b.addTest(.{ .root_module = codemode_run_module, .use_llvm = use_llvm, .filters = &.{"native CodeMode controlled run"} });
    b.step("test-native-codemode-run", "Compare real native controlled VM execution with original deterministic Source observations").dependOn(&b.addRunArtifact(codemode_run_tests).step);
    const codemode_worker_module = b.createModule(.{ .root_source_file = b.path("src/native_codemode_vm_worker_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, codemode_worker_module, quickjs, sqlite_lib_dir);
    linkSqlite(codemode_worker_module, sqlite_lib_dir, sqlite_library);
    const codemode_worker_tests = b.addTest(.{ .root_module = codemode_worker_module, .use_llvm = use_llvm, .filters = &.{"native CodeMode worker"} });
    b.step("test-native-codemode-vm-worker", "Replay controlled Source runs on owned native VM threads and verify cancellation and joined teardown").dependOn(&b.addRunArtifact(codemode_worker_tests).step);
    const codemode_worker_allocation_tests = b.addTest(.{ .root_module = codemode_worker_tests.root_module, .use_llvm = use_llvm, .filters = &.{"native CodeMode worker releases every failed owner allocation across native thread startup execution event publication and joined teardown"} });
    b.step("test-native-codemode-worker-allocation", "Run the complete original worker-owner failure indices, optionally partitioned").dependOn(&b.addRunArtifact(codemode_worker_allocation_tests).step);
    const codemode_owner_module = b.createModule(.{ .root_source_file = b.path("src/native_codemode_controlled_binding_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, codemode_owner_module, quickjs, sqlite_lib_dir);
    linkSqlite(codemode_owner_module, sqlite_lib_dir, sqlite_library);
    const codemode_owner_tests = b.addTest(.{ .root_module = codemode_owner_module, .use_llvm = use_llvm, .filters = &.{"native CodeMode JavaScript owner"} });
    b.step("test-native-codemode-controlled-binding", "Compare actual JavaScript controlled-run callbacks and lifecycle through native worker VMs").dependOn(&b.addRunArtifact(codemode_owner_tests).step);
    const codemode_sandbox_module = b.createModule(.{ .root_source_file = b.path("src/native_codemode_sandbox_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, codemode_sandbox_module, quickjs, sqlite_lib_dir);
    linkSqlite(codemode_sandbox_module, sqlite_lib_dir, sqlite_library);
    const codemode_sandbox_tests = b.addTest(.{ .root_module = codemode_sandbox_module, .use_llvm = use_llvm, .filters = &.{"native CodeMode sandbox"} });
    b.step("test-native-codemode-sandbox", "Exercise the native sandbox class, real async tools, cancellation and deadlines through worker VMs").dependOn(&b.addRunArtifact(codemode_sandbox_tests).step);
    const composed_vm_module = b.createModule(.{ .root_source_file = b.path("src/native_composed_vm_test.zig"), .target = target, .optimize = optimize });
    composed_vm_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, composed_vm_module, quickjs, sqlite_lib_dir);
    linkSqlite(composed_vm_module, sqlite_lib_dir, sqlite_library);
    const composed_vm_tests = b.addTest(.{
        .root_module = composed_vm_module,
        .use_llvm = use_llvm,
        .filters = @import("tools/native_composed_scope.zig").filters,
    });
    const composed_vm_run = b.addRunArtifact(composed_vm_tests);
    composed_vm_run.has_side_effects = true;
    b.step("test-native-composed-vm", "Run unchanged SDK locale allocation retention image command and stdio suites in one VM test artifact").dependOn(&composed_vm_run.step);
    const coverage_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("tools/native_composed_coverage.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    b.step("test-native-composed-coverage", "Reject missing duplicate skipped or unexecuted composed tests").dependOn(&b.addRunArtifact(coverage_tests).step);
    mod.addImport("catalog_tool", catalog_tool);
    const locale_compare_source_step = b.step("test-native-localecompare-source", "Replay original69 API, original2100 JS comparisons, original90 coercion edges, original12 lifecycle and exhaustive host allocation cleanup");
    for ([_]struct { file: []const u8, filter: []const u8 }{
        .{ .file = "src/native_localecompare_binding_source_test.zig", .filter = "Native localeCompare Source" },
        .{ .file = "src/native_localecompare_coercion_edge_source_test.zig", .filter = "Native localeCompare Coercion Source" },
        .{ .file = "src/native_localecompare_lifecycle_source_test.zig", .filter = "Native localeCompare Lifecycle Source" },
    }) |entry| {
        const source_module = b.createModule(.{ .root_source_file = b.path(entry.file), .target = target, .optimize = optimize });
        source_module.addImport("catalog_tool", catalog_tool);
        linkQuickJs(b, source_module, quickjs, sqlite_lib_dir);
        const source_tests = b.addTest(.{ .root_module = source_module, .filters = &.{entry.filter}, .use_llvm = use_llvm });
        locale_compare_source_step.dependOn(&b.addRunArtifact(source_tests).step);
    }
    linkQuickJs(b, mod, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, mod, typescript_parser);
    // Private command-only Source gate. It does not activate a Main provider
    // or install/export the complete Combined class or any fd implementation.
    const command_source_module = b.createModule(.{ .root_source_file = b.path("src/native_command_autocomplete_source_test.zig"), .target = target, .optimize = optimize });
    command_source_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, command_source_module, quickjs, sqlite_lib_dir);
    const command_source_tests = b.addTest(.{ .root_module = command_source_module, .filters = &.{"Command Source"}, .use_llvm = use_llvm });
    b.step("test-native-command-autocomplete-source", "Replay 292 command-component records (142 commands,20 caller-empty-FS editor turns,97 prefixes,33 completions), holder lifecycle and host GPA; full Combined constructor remains a separate required gate").dependOn(&b.addRunArtifact(command_source_tests).step);
    // Private live command ownership gate only; no Main/provider activation.
    const live_command_module = b.createModule(.{ .root_source_file = b.path("src/native_command_live_owner_test.zig"), .target = target, .optimize = optimize });
    live_command_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, live_command_module, quickjs, sqlite_lib_dir);
    const live_command_tests = b.addTest(.{ .root_module = live_command_module, .filters = &.{"Live command metadata"}, .use_llvm = use_llvm });
    b.step("test-native-command-live-owner", "Replay all55 Source live command records across metadata6 retained7 lifetime18 and two shared12 corpora, twelve private boundaries and complete raw/frontend host GPA; no Main activation").dependOn(&b.addRunArtifact(live_command_tests).step);
    const live_command_allocation_tests = b.addTest(.{ .root_module = live_command_module, .filters = &.{"Live command metadata exhaustive host allocation"}, .use_llvm = use_llvm });
    b.step("test-native-command-live-owner-allocation-diagnostic", "Run the unchanged live-owner allocation universe with original failure index and marker diagnostics").dependOn(&b.addRunArtifact(live_command_allocation_tests).step);
    const ui8a9_pure_module = b.createModule(.{ .root_source_file = b.path("src/native_ui8a9_pure_test.zig"), .target = target, .optimize = optimize });
    const ui8a9_pure_tests = b.addTest(.{ .root_module = ui8a9_pure_module, .filters = &.{ "Source8a9 pure stdin", "Source8a9 terminal capabilities" }, .use_llvm = use_llvm });
    b.step("test-ui8a9-pure", "Replay actual8a9 delayed terminal replies and all928 capability inputs with complete pure framing allocation cleanup").dependOn(&b.addRunArtifact(ui8a9_pure_tests).step);
    const codemode_run_host_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/codemode_run_host_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"CodeMode host"}, .use_llvm = use_llvm });
    b.step("test-codemode-run-host", "Verify native host answer ownership ordered delivery and original host protocol records; VM integration remains separate").dependOn(&b.addRunArtifact(codemode_run_host_tests).step);
    const ui8a9_source_module = b.createModule(.{ .root_source_file = b.path("src/native_ui8a9_source_test.zig"), .target = target, .optimize = optimize });
    ui8a9_source_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, ui8a9_source_module, quickjs, sqlite_lib_dir);
    const ui8a9_source_tests = b.addTest(.{ .root_module = ui8a9_source_module, .filters = &.{"Source8a9 native"}, .use_llvm = use_llvm });
    b.step("test-ui8a9-source", "Replay actual8a9 native StdinBuffer14 real timer scenarios and ten Herdr capability profiles").dependOn(&b.addRunArtifact(ui8a9_source_tests).step);
    const error_stack_step = b.step("test-native-error-stack-rejection-source", "Private genuine Error own-stack Node42 and caller frame1, original rejection19 and async-context8 boundaries; no Engine worker Main activation");
    inline for (.{ .{ "src/native_promise_rejections_test.zig", "Promise rejection bookkeeping" }, .{ "src/native_promise_rejection_policy_test.zig", "Promise rejection policy" }, .{ "src/native_promise_rejection_source_test.zig", "Promise rejection Source original19" }, .{ "src/native_error_stack_source_test.zig", "Native Error stack Source" } }) |entry| {
        const error_stack_module = b.createModule(.{ .root_source_file = b.path(entry[0]), .target = target, .optimize = optimize });
        error_stack_module.addImport("catalog_tool", catalog_tool);
        linkQuickJs(b, error_stack_module, quickjs, sqlite_lib_dir);
        const error_stack_tests = b.addTest(.{ .root_module = error_stack_module, .filters = &.{entry[1]}, .use_llvm = use_llvm });
        error_stack_step.dependOn(&b.addRunArtifact(error_stack_tests).step);
    }
    const command_allocation_tests = b.addTest(.{ .root_module = command_source_module, .filters = &.{"Command Source exhaustive host allocation"}, .use_llvm = use_llvm });
    b.step("test-native-command-autocomplete-allocation", "Preserve genuine native fuzzy allocation failures through the complete command GPA sweep").dependOn(&b.addRunArtifact(command_allocation_tests).step);
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
    sdk_install.step.dependOn(&install_dark_theme.step);
    sdk_install.step.dependOn(&install_light_theme.step);
    const main_ui_adapter_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_main_ui_adapter_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native Main UI adapter", "native Main UI sync" }, .use_llvm = use_llvm });
    linkQuickJs(b, main_ui_adapter_tests.root_module, quickjs, sqlite_lib_dir);
    main_ui_adapter_tests.root_module.addImport("catalog_tool", catalog_tool);
    const main_ui_adapter_run = b.addRunArtifact(main_ui_adapter_tests);
    b.step("test-native-main-ui-adapter", "Replay Source Main UI themes and expanded tool output against actual producers").dependOn(&main_ui_adapter_run.step);
    const main_ui_sync_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_main_ui_sync_process_test.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "pi_zig", .module = mod }} }), .filters = &.{"native Main UI sync process"}, .use_llvm = use_llvm });
    const main_ui_sync_run = b.addRunArtifact(main_ui_sync_tests);
    main_ui_sync_run.step.dependOn(&sdk_install.step);
    main_ui_sync_run.setEnvironmentVariable("PI_UI_SERVICE_TEST_BINARY", b.getInstallPath(.bin, b.fmt("pi-sdk-embedder{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-native-main-ui-sync-process", "Prove blocking Main UI service ordering on a real no-Node worker").dependOn(&main_ui_sync_run.step);
    const ui_service_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ui_service_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native UI service"}, .use_llvm = use_llvm });
    linkQuickJs(b, ui_service_tests.root_module, quickjs, sqlite_lib_dir);
    ui_service_tests.root_module.addImport("catalog_tool", catalog_tool);
    const ui_service_run = b.addRunArtifact(ui_service_tests);
    b.step("test-native-ui-service", "Exercise retained Main service leases without changing SDK async admission").dependOn(&ui_service_run.step);
    const ui_service_process_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ui_service_process_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native UI service process"}, .use_llvm = use_llvm });
    linkQuickJs(b, ui_service_process_tests.root_module, quickjs, sqlite_lib_dir);
    ui_service_process_tests.root_module.addImport("catalog_tool", catalog_tool);
    const ui_service_process_run = b.addRunArtifact(ui_service_process_tests);
    ui_service_process_run.step.dependOn(&sdk_install.step);
    ui_service_process_run.setEnvironmentVariable("PI_UI_SERVICE_TEST_BINARY", b.getInstallPath(.bin, b.fmt("pi-sdk-embedder{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-native-ui-service-process", "Prove completed Main services on a real no-Node worker and idle transport").dependOn(&ui_service_process_run.step);
    const stdio_process_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_stdio_process_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native actual SDK stdio"}, .use_llvm = use_llvm });
    linkDurable(b, stdio_process_tests.root_module);
    const stdio_process_run = b.addRunArtifact(stdio_process_tests);
    stdio_process_run.step.dependOn(&sdk_install.step);
    stdio_process_run.setEnvironmentVariable("PI_NATIVE_STDIO_TEST_BINARY", b.getInstallPath(.bin, b.fmt("pi-sdk-embedder{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-native-stdio-process", "Replay genuine Source terminal IO through actual SDK process pipes").dependOn(&stdio_process_run.step);
    const process_protocol_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/process_stream_parent.zig"), .target = target, .optimize = optimize }), .filters = &.{"process stream"}, .use_llvm = use_llvm });
    const process_protocol_run = b.addRunArtifact(process_protocol_tests);
    b.step("test-native-process-stream-protocol", "Check binary process IO, exact leases, EOF ordering and paired detach").dependOn(&process_protocol_run.step);
    const physical_stdio_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_physical_stdio_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"physical stdio"}, .use_llvm = use_llvm });
    linkQuickJs(b, physical_stdio_tests.root_module, quickjs, sqlite_lib_dir);
    physical_stdio_tests.root_module.addImport("catalog_tool", catalog_tool);
    const physical_stdio_run = b.addRunArtifact(physical_stdio_tests);
    b.step("test-native-physical-stdio", "Check physical stdio adapter forwarding, Main queue continuity and replacement sink EOF").dependOn(&physical_stdio_run.step);
    const physical_stdio_fixture = b.addExecutable(.{ .name = "pi-physical-stdio-fixture", .root_module = b.createModule(.{ .root_source_file = b.path("src/native_physical_stdio_fixture.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    linkQuickJs(b, physical_stdio_fixture.root_module, quickjs, sqlite_lib_dir);
    physical_stdio_fixture.root_module.addImport("catalog_tool", catalog_tool);
    const physical_fixture_install = b.addInstallArtifact(physical_stdio_fixture, .{});
    b.step("build-native-physical-stdio-fixture", "Build an actual physical stdio owner for bounded pipe and cancellation checks").dependOn(&physical_fixture_install.step);
    const physical_process_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_physical_stdio_process_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"physical stdio process"}, .use_llvm = use_llvm });
    linkDurable(b, physical_process_tests.root_module);
    const physical_process_run = b.addRunArtifact(physical_process_tests);
    physical_process_run.step.dependOn(&physical_fixture_install.step);
    physical_process_run.setEnvironmentVariable("PI_PHYSICAL_STDIO_TEST_BINARY", b.getInstallPath(.bin, b.fmt("pi-physical-stdio-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-native-physical-stdio-process", "Prove one physical producer, binary fanout, EOF replacement and blocked reader cancellation over real pipes").dependOn(&physical_process_run.step);
    const json_envelope_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/native_json_envelope.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const json_envelope_run = b.addRunArtifact(json_envelope_tests);
    b.step("test-native-json-envelope", "Validate ECMA JSON grammar while retaining opaque UTF16 escapes and top-level routing").dependOn(&json_envelope_run.step);
    const image_option_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_image_resize_options_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native image worker option"} });
    linkQuickJs(b, image_option_tests.root_module, quickjs, sqlite_lib_dir);
    image_option_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-image-options", "Preserve Source option cloning spread order and fallback getter identity").dependOn(&b.addRunArtifact(image_option_tests).step);
    const native_binary_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_binary_operator_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native binary operators"} });
    linkQuickJs(b, native_binary_tests.root_module, quickjs, sqlite_lib_dir);
    native_binary_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-binary-operators", "Use actual guest runtime arithmetic and comparison semantics in native algorithms").dependOn(&b.addRunArtifact(native_binary_tests).step);
    b.step("build-native-binary-operators", "Compile original VM arithmetic ABI regression independently of runtime deadlines").dependOn(&native_binary_tests.step);
    const image_strategy_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_image_resize_strategy_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native image JavaScript-valued strategy"} });
    linkQuickJs(b, image_strategy_tests.root_module, quickjs, sqlite_lib_dir);
    image_strategy_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-image-js-strategy", "Replay upstream image bytes using actual JS-valued options and native Photon").dependOn(&b.addRunArtifact(image_strategy_tests).step);
    const process_stdio_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_process_stdio_process_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native process stdio factory startup"}, .use_llvm = use_llvm });
    linkQuickJs(b, process_stdio_tests.root_module, quickjs, sqlite_lib_dir);
    process_stdio_tests.root_module.addImport("catalog_tool", catalog_tool);
    const process_stdio_run = b.addRunArtifact(process_stdio_tests);
    process_stdio_run.step.dependOn(&sdk_install.step);
    process_stdio_run.setEnvironmentVariable("PI_NATIVE_STDIO_TEST_BINARY", b.getInstallPath(.bin, b.fmt("pi-sdk-embedder{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-native-process-stdio-process", "Prove genuine terminal factory startup over authenticated framed parent IO").dependOn(&process_stdio_run.step);
    const ui_service_allocation_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ui_service_allocation_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Main UI service allocation"}, .use_llvm = use_llvm });
    linkQuickJs(b, ui_service_allocation_tests.root_module, quickjs, sqlite_lib_dir);
    ui_service_allocation_tests.root_module.addImport("catalog_tool", catalog_tool);
    const ui_service_allocation_run = b.addRunArtifact(ui_service_allocation_tests);
    b.step("test-native-ui-service-allocation", "Sweep every retained frontend service host allocation; PI_SDK_ALLOCATION_SHARD/SHARDS partitions hosted jobs").dependOn(&ui_service_allocation_run.step);
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
    test_step.dependOn(&json_envelope_run.step);
    test_step.dependOn(&stdio_process_run.step);
    test_step.dependOn(&process_protocol_run.step);
    test_step.dependOn(&process_stdio_run.step);
    test_step.dependOn(&main_ui_adapter_run.step);
    test_step.dependOn(&main_ui_sync_run.step);
    test_step.dependOn(&ui_service_run.step);
    test_step.dependOn(&ui_service_process_run.step);
    test_step.dependOn(&ui_service_allocation_run.step);
    const catalog_wire_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_tool_catalog_wire_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "private native catalog", "native durable VM MCP parameter bodies", "native durable VM Main builtin catalog" } });
    catalog_wire_tests.root_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, catalog_wire_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, catalog_wire_tests.root_module, typescript_parser);
    const run_catalog_wire_tests = b.addRunArtifact(catalog_wire_tests);
    b.step("test-native-tool-catalog-wire", "Exercise private native catalog admission and lifetime control").dependOn(&run_catalog_wire_tests.step);
    test_step.dependOn(&run_catalog_wire_tests.step);
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
    const latest_catalog_step = b.step("test-latest-catalog", "Exercise reviewed current model catalog and Bedrock contracts");
    latest_catalog_step.dependOn(&run_latest_catalog_tests.step);
    test_step.dependOn(&run_latest_catalog_tests.step);
    const latest_catalog_data_module = b.createModule(.{ .root_source_file = b.path("src/latest_catalog_data_test.zig"), .target = target, .optimize = optimize });
    latest_catalog_data_module.addImport("catalog_tool", catalog_tool);
    const latest_catalog_data_tests = b.addTest(.{ .root_module = latest_catalog_data_module, .use_llvm = use_llvm, .filters = &.{ "latest pinned Pi ae7 FFA3", "catalog contains only real provider entries", "generated catalog preserves exact upstream identity cardinality", "native catalog projection preserves all existing model metadata", "every provider default resolves to its public catalog identity" } });
    b.step("build-latest-catalog-data", "Compile focused current catalog data regressions").dependOn(&latest_catalog_data_tests.step);
    b.step("test-latest-catalog-data", "Verify complete current catalog provenance metadata projection and native lookup without application runtime compilation").dependOn(&b.addRunArtifact(latest_catalog_data_tests).step);
    const highlight_complete191_direct = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_highlight_complete191_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native actual complete191"}, .use_llvm = use_llvm });
    linkQuickJs(b, highlight_complete191_direct.root_module, quickjs, sqlite_lib_dir);
    highlight_complete191_direct.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-highlight-complete191-direct", "Compile private actual191 registration and readiness audit without default application binding").dependOn(&highlight_complete191_direct.step);
    b.step("test-native-highlight-complete191-direct", "Require actual191 successful factories and preserve guest import/factory failure readiness distinctions").dependOn(&b.addRunArtifact(highlight_complete191_direct).step);
    const highlight_root55_foundation = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_highlight_root55_foundation_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "matches actual Original32", "matches genuine Original74", "nested actual grammar scanner completes128", "match genuine Original deep7", "registration preserves proven host OOM" }, .use_llvm = use_llvm });
    linkQuickJs(b, highlight_root55_foundation.root_module, quickjs, sqlite_lib_dir);
    highlight_root55_foundation.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-highlight-root55-foundation", "Compile actual Legacy32 Original74 Deep7 and trusted-OOM functional gates on additive Root55 VM").dependOn(&highlight_root55_foundation.step);
    b.step("test-native-highlight-root55-foundation", "Compare unchanged genuine computational and legacy function probes before full191 qualification").dependOn(&b.addRunArtifact(highlight_root55_foundation).step);
    const highlight_root463_recovery = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_highlight_root463_engine_recovery_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "extensions.engine.", "restores inactive frames after actual native enumeration cancellation", "targeted C VM heap budgets", "native Root463 dispatch" }, .use_llvm = use_llvm });
    linkQuickJs(b, highlight_root463_recovery.root_module, quickjs, sqlite_lib_dir);
    highlight_root463_recovery.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-highlight-root463-engine-recovery", "Compile preserved ordinary VM interrupt and legacy cancellation budget recovery gates").dependOn(&highlight_root463_recovery.step);
    b.step("test-native-highlight-root463-engine-recovery", "Require ordinary VM constructor stack GC interrupt and selected legacy recovery before complete191").dependOn(&b.addRunArtifact(highlight_root463_recovery).step);
    const highlight_complete191_host = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_highlight_complete191_host_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native actual complete191 host unchanged"}, .use_llvm = use_llvm });
    linkQuickJs(b, highlight_complete191_host.root_module, quickjs, sqlite_lib_dir);
    highlight_complete191_host.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-highlight-complete191-host", "Compile unchanged genuine Source445 caller against actual native Immediate and whole191 loader").dependOn(&highlight_complete191_host.step);
    b.step("test-native-highlight-complete191-host", "Compare419 successful and26 failure Source observations with independent private readiness").dependOn(&b.addRunArtifact(highlight_complete191_host).step);
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
    const run_durable_tools_tests = b.addRunArtifact(durable_tools_tests);
    const durable_tools_step = b.step("test-durable-tools", "Exercise bounded durable reader integration with existing native CLI tools");
    durable_tools_step.dependOn(&run_durable_tools_tests.step);
    test_step.dependOn(&run_durable_tools_tests.step);
    const durable_read_images_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_read_images42a_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "images42a", "durable b7df" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, durable_read_images_tests.root_module, quickjs, sqlite_lib_dir);
    const durable_read_images_run = b.addRunArtifact(durable_read_images_tests);
    b.step("test-durable-read-images", "Replay actual newest Durable image reads and sweep owned image allocation failures").dependOn(&durable_read_images_run.step);
    test_step.dependOn(&durable_read_images_run.step);
    const env_daemon = b.addExecutable(.{
        .name = "pi-env",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/env_daemon.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkDurable(b, env_daemon.root_module);
    env_daemon.root_module.addCSourceFile(.{ .file = b.path("src/env/pty_abi.c"), .flags = &.{"-std=gnu11"} });
    if (target.result.os.tag == .linux) env_daemon.root_module.linkSystemLibrary("util", .{});
    const install_env_daemon = b.addInstallArtifact(env_daemon, .{});
    const terminal_primitive_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/env/pty_abi_test.zig"), .target = target, .optimize = optimize, .link_libc = true }),
        .use_llvm = use_llvm,
    });
    terminal_primitive_tests.root_module.addCSourceFile(.{ .file = b.path("src/env/pty_abi.c"), .flags = &.{"-std=gnu11"} });
    if (target.result.os.tag == .linux) terminal_primitive_tests.root_module.linkSystemLibrary("util", .{});
    b.step("test-env-terminal-primitives", "Exercise actual POSIX controlling terminal raw IO resize foreground and owned child lifetime").dependOn(&b.addRunArtifact(terminal_primitive_tests).step);
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
    const readable_oom_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_readable_stream_oom_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native readable host OOM"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkQuickJs(b, readable_oom_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(readable_oom_tests.root_module, sqlite_lib_dir, sqlite_library);
    const readable_oom_run = b.addRunArtifact(readable_oom_tests);
    if (diagnostic_tests) readable_oom_run.stdio = .inherit;
    b.step("test-native-readable-host-oom", "Reject actual tee consumers after permanent host allocator failure and free all ownership").dependOn(&readable_oom_run.step);
    addCompileOnlyGroup(b, "build-hosted-native-readable-host-oom", &.{"test-native-readable-host-oom"});
    const capability_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/env_capability_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"env capability"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    const native_durable_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native durable VM"}, .use_llvm = use_llvm });
    linkQuickJs(b, native_durable_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_durable_tests.root_module, sqlite_lib_dir, sqlite_library);
    const run_native_durable_tests = b.addRunArtifact(native_durable_tests);
    const native_durable_step = b.step("test-native-durable-vm", "Exercise native public durable VM storage and Session objects");
    native_durable_step.dependOn(&run_native_durable_tests.step);
    const chord_context_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_chord_context_source_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "native Chord Context", "native durable VM actual Storage context" } });
    linkQuickJs(b, chord_context_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(chord_context_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-chord-context-source", "Replay genuine Chord2 Context classes and cancellation with native GC and allocation ownership").dependOn(&b.addRunArtifact(chord_context_tests).step);
    const chord_resource_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_chord_resource_source_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native Chord Resource"} });
    linkQuickJs(b, chord_resource_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(chord_resource_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-chord-resource-source", "Replay actual Chord Host resource lifecycle factory facade late abort cleanup and raw errors").dependOn(&b.addRunArtifact(chord_resource_tests).step);
    const chord_contract_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_chord_contract_source_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native Chord contracts"} });
    linkQuickJs(b, chord_contract_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(chord_contract_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-chord-contract-source", "Replay actual Chord canonical identity contract fingerprints compatibility and version adapters").dependOn(&b.addRunArtifact(chord_contract_tests).step);
    const chord_clone_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_chord_clone_source_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native Chord clone"} });
    linkQuickJs(b, chord_clone_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(chord_clone_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-chord-clone-source", "Replay original TypeBox SystemClone Host normalization prerequisite and ownership").dependOn(&b.addRunArtifact(chord_clone_tests).step);
    const chord_normalization_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_chord_normalization_source_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native Chord normalization workers"} });
    linkQuickJs(b, chord_normalization_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(chord_normalization_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-chord-normalization-workers-source", "Replay original private Default/Clean workers; Instantiate/Evaluate remains required separately").dependOn(&b.addRunArtifact(chord_normalization_tests).step);
    const chord_evaluator_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_chord_type_evaluator_source_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native Chord evaluator"} });
    linkQuickJs(b, chord_evaluator_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(chord_evaluator_tests.root_module, sqlite_lib_dir, sqlite_library);
    const chord_evaluator_run = b.addRunArtifact(chord_evaluator_tests);
    b.step("test-native-chord-evaluator-source", "Replay original625 TypeBox Compare/Narrow and11 real Intersect/deferred normalization cases").dependOn(&chord_evaluator_run.step);
    const chord_normalization_evaluator = b.step("test-native-chord-normalization-evaluate-source", "Replay original32 Default/Clean cases plus actual TypeBox evaluator625/11 and ownership");
    chord_normalization_evaluator.dependOn(&b.addRunArtifact(chord_normalization_tests).step);
    chord_normalization_evaluator.dependOn(&chord_evaluator_run.step);
    const storage_lifetime_tests = b.addTest(.{ .root_module = native_durable_tests.root_module, .use_llvm = use_llvm, .filters = &.{
        "Storage adapter lifetime",
        "agent selections store names from cyclic",
        "document watch overflow replaces",
        "documentState bounded pending deliveries",
        "constructors clean up every GPA failure",
        "receiver owner retires every host allocation",
        "DTO cache and multiple waiter settlement",
        "late waiter read queries replies and cancellation",
        "task definitions scheduler subscriptions and Session leases",
        "document addresses proxies native publication and cache admission",
        "scheduler control queue promises and requests unwind",
    } });
    const run_storage_lifetime_tests = b.addRunArtifact(storage_lifetime_tests);
    const storage_lifetime_step = b.step("test-native-durable-storage-lifetime", "Exercise Storage GC roots and native allocation error propagation");
    storage_lifetime_step.dependOn(&run_storage_lifetime_tests.step);

    const guest_join_tests = b.addTest(.{ .root_module = native_durable_tests.root_module, .use_llvm = use_llvm, .filters = &.{
        "observed guest dispatch remains joined",
        "Harness closed getter returns",
        "late builtin Storage getter overrides",
        "public task abort joins observed run while cleanup",
        "task abort observed-run cancellation uses Source",
        "task abort observed run ends with SessionFailed",
        "owned abort marks actual child then waits",
        "public task abort signals the old invocation",
        "public tasks create owned children wait",
        "terminal publication precedes a held phase end",
        "phase dispatch refreshes replacement registry",
        "constructors clean up every GPA failure",
        "task definitions scheduler subscriptions and Session leases",
    } });
    const run_guest_join_tests = b.addRunArtifact(guest_join_tests);
    const guest_join_step = b.step("test-native-durable-guest-join", "Exercise actual guest handler joins and the public Harness closed promise");
    guest_join_step.dependOn(&run_guest_join_tests.step);
    const owned_tasks_tests = b.addTest(.{ .root_module = native_durable_tests.root_module, .use_llvm = use_llvm, .filters = &.{"ownedTasks actual ea"} });
    const run_owned_tasks_tests = b.addRunArtifact(owned_tasks_tests);
    b.step("test-native-durable-owned-tasks", "Replay actual ea Source direct-owned live task copies and cancellation").dependOn(&run_owned_tasks_tests.step);
    const ea_retention_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_ea_retention_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "ownedTasks actual ea", "actual ea retention", "ownership publication index readiness" } });
    linkQuickJs(b, ea_retention_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ea_retention_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-ea-retention", "Replay actual ea retention and direct ownership while fencing partial owner publications").dependOn(&b.addRunArtifact(ea_retention_tests).step);
    const ea_publication_failure_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{"failed ownership observer"} });
    b.step("test-native-durable-ea-publication-failure", "Preserve a native failed publication while closing without joining its unready queue").dependOn(&b.addRunArtifact(ea_publication_failure_tests).step);
    const ea_runtime_overlay_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{"actual ea runtime overlay"} });
    b.step("test-native-durable-ea-runtime-overlay", "Replay actual ea runtime candidate work in an existing owned conversation").dependOn(&b.addRunArtifact(ea_runtime_overlay_tests).step);
    const ea_partial_owner_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{"actual ea partial owner Source"} });
    b.step("test-native-durable-ea-partial-owner", "Replay actual ea missing scopes opaque checkpoint recovery and original Storage contexts").dependOn(&b.addRunArtifact(ea_partial_owner_tests).step);
    const ea_open_scope_promise_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{"actual ea open returns Promise"} });
    b.step("test-native-durable-ea-open-scope-promise", "Compare public open Promise readiness with a real held owner-scope Storage operation").dependOn(&b.addRunArtifact(ea_open_scope_promise_tests).step);
    const ea_open_failure_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{"actual ea open failure cleanup"} });
    b.step("test-native-durable-ea-open-failure", "Replay actual Source failed-open cleanup and original cancellation identity").dependOn(&b.addRunArtifact(ea_open_failure_tests).step);
    const public_open_lifecycle_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{"native durable public open lifecycle"} });
    b.step("test-native-durable-public-open-lifecycle", "Exercise public open continuation cleanup and reporter roots through every GPA failure").dependOn(&b.addRunArtifact(public_open_lifecycle_tests).step);
    const ea_inflight_index_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{"actual ea inflight index"} });
    b.step("test-native-durable-ea-inflight-index", "Replay an actual Storage Promise gate and serialized read readiness").dependOn(&b.addRunArtifact(ea_inflight_index_tests).step);
    const cdaf_retention_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{"actual cdaf public document retention"} });
    b.step("test-native-durable-cdaf-retention", "Replay latest Source public document retention and observer reload behavior").dependOn(&b.addRunArtifact(cdaf_retention_tests).step);
    const cdaf_retention_phase_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{ "actual cdaf public document retention", "actual cdaf settings phase" } });
    b.step("test-native-durable-cdaf-retention-phase", "Preserve public retention and compare actual Source getter phases and field order").dependOn(&b.addRunArtifact(cdaf_retention_phase_tests).step);
    const cdaf_retention_pin_tests = b.addTest(.{ .root_module = ea_retention_tests.root_module, .use_llvm = use_llvm, .filters = &.{"actual cdaf retention pins"} });
    b.step("test-native-durable-cdaf-retention-pins", "Replay actual Source observer incarnation pins unload and held-transaction timer expiry").dependOn(&b.addRunArtifact(cdaf_retention_pin_tests).step);
    const owner_settlement_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_owner_settlement_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "owner settlement", "document retention" } });
    linkSqlite(owner_settlement_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-owner-settlement", "Verify original worker line ownership, reentrant close, operation order and document retention index").dependOn(&b.addRunArtifact(owner_settlement_tests).step);
    const e6_input_entry_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_e6_input_entry_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable actual e6 input entry public contract"} });
    linkQuickJs(b, e6_input_entry_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(e6_input_entry_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-e6-input-entry", "Replay actual upstream input entries with a held public user provider and queued reset fence").dependOn(&b.addRunArtifact(e6_input_entry_tests).step);
    const latest_compaction_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_89_compaction_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable actual 89 compaction failure public contract"} });
    linkQuickJs(b, latest_compaction_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(latest_compaction_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-89-compaction", "Replay actual latest blocking compaction failure, persistent live state and produced-summary cleanup").dependOn(&b.addRunArtifact(latest_compaction_tests).step);
    const upstream_698a_retry_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_upstream_698a_retry_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native upstream698"} });
    linkQuickJs(b, upstream_698a_retry_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(upstream_698a_retry_tests.root_module, sqlite_lib_dir, sqlite_library);
    upstream_698a_retry_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-upstream-698a-retry", "Compare genuine Source698 classifier160 and typed36 observations").dependOn(&b.addRunArtifact(upstream_698a_retry_tests).step);
    b.step("build-native-upstream-698a-retry", "Compile Source698 retry comparisons independently of runtime").dependOn(&b.addInstallArtifact(upstream_698a_retry_tests, .{}).step);
    const upstream_0fb_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_upstream_0fb_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native upstream0fb"} });
    linkQuickJs(b, upstream_0fb_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(upstream_0fb_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-upstream-0fb", "Compare genuine latest0fb policy retry public compaction and tool controls").dependOn(&b.addRunArtifact(upstream_0fb_tests).step);
    b.step("build-native-upstream-0fb", "Compile latest0fb source comparisons separately from runtime").dependOn(&upstream_0fb_tests.step);
    const inspection_guard_tests = b.addTest(.{ .root_module = latest_compaction_tests.root_module, .use_llvm = use_llvm, .filters = &.{"native durable actual 89 inspection Storage guard"} });
    b.step("test-native-durable-inspection-storage-guard", "Replay actual original read errors fatal close and underway successful-read discard").dependOn(&b.addRunArtifact(inspection_guard_tests).step);
    const schema_tool_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_243_schema_tool_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable actual 243 schema tool error results"} });
    linkQuickJs(b, schema_tool_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(schema_tool_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-243-schema-tools", "Replay actual latest nested schema-tool errors and model-issued controls").dependOn(&b.addRunArtifact(schema_tool_tests).step);
    const wait_cycle_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_148622_wait_cycle_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable latest148622 wait cycle"} });
    linkQuickJs(b, wait_cycle_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(wait_cycle_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-148622-wait-cycle", "Replay actual latest wait cycles ordinary holds abort marks and background owner waits").dependOn(&b.addRunArtifact(wait_cycle_tests).step);
    const schema_comparison_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_schema_compare.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native schema duration measurements"} });
    b.step("test-native-durable-schema-comparison", "Compare raw Source schema results and bound only explicitly identified real attempt measurements").dependOn(&b.addRunArtifact(schema_comparison_tests).step);
    const codemode_outcome_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_codemode_outcome_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable CodeMode actual148622 nested outcome16"} });
    linkQuickJs(b, codemode_outcome_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(codemode_outcome_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-codemode-outcome", "Compare actual nested tool outcomes including schema-null errors diagnostics and own undefined value").dependOn(&b.addRunArtifact(codemode_outcome_tests).step);
    const codemode_journal_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_codemode_journal_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable CodeMode journal real tool API"} });
    linkQuickJs(b, codemode_journal_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(codemode_journal_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-codemode-journal-core", "Exercise actual durable tool API document transactions and atomic CodeMode outcome store decisions").dependOn(&b.addRunArtifact(codemode_journal_tests).step);
    const persistent_auth_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_auth_storage_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native persistent AuthStorage"} });
    linkQuickJs(b, persistent_auth_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(persistent_auth_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-auth-storage-persistent", "Replay original AuthStorage Source over real owned files and native directory locks").dependOn(&b.addRunArtifact(persistent_auth_tests).step);
    const auth_timer_control_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_auth_timer_controls_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "extensions.timers.", "native allocation original identity", "native authentication selected timer inventory" } });
    linkQuickJs(b, auth_timer_control_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(auth_timer_control_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-auth-timer-controls", "Verify shared timer failure provenance and original native allocation identity controls").dependOn(&b.addRunArtifact(auth_timer_control_tests).step);
    const oauth_codex_radius_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_codex_radius_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native OAuth Codex Radius actual ae7"} });
    linkQuickJs(b, oauth_codex_radius_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(oauth_codex_radius_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-ai-oauth-codex-radius", "Compare actual Codex and Radius public OAuth flows with immutable ae7 Source observations").dependOn(&b.addRunArtifact(oauth_codex_radius_tests).step);
    b.step("build-native-ai-oauth-codex-radius", "Compile public Codex and Radius OAuth bodies separately from execution deadlines").dependOn(&oauth_codex_radius_tests.step);
    const oauth_codex_radius_browser_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_codex_radius_browser_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native OAuth Codex Radius browser actual ae7"} });
    linkQuickJs(b, oauth_codex_radius_browser_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(oauth_codex_radius_browser_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-ai-oauth-codex-radius-browser", "Replay genuine original Codex and Radius browser callbacks and complete HTTP pages").dependOn(&b.addRunArtifact(oauth_codex_radius_browser_tests).step);
    b.step("build-native-ai-oauth-codex-radius-browser", "Compile original Codex and Radius browser OAuth flows separately from execution deadlines").dependOn(&oauth_codex_radius_browser_tests.step);
    const typed_models_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_models_typed_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "native Models actual Source9", "native Models actual Source10", "native Models actual Source6", "native Models actual typed services credential queues", "native Models actual Source streams10", "native Models actual streaming auth continuations", "native Models actual Source login8", "native Models actual login credential mutation", "native Models actual Source auth mutation3", "native Models actual Source provider factory7", "native Models actual provider factory catalog refresh" } });
    linkQuickJs(b, typed_models_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(typed_models_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-models-typed-services", "Replay actual Source typed Models auth and service operations over native instance and credential store").dependOn(&b.addRunArtifact(typed_models_tests).step);
    const models_stream_regressions = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_models_stream_regression_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "native pi-ai EventStream", "native EventStream", "native AssistantMessageEventStream genuine Source result-only", "native terminal admission", "native provider validation", "native provider cancellation" } });
    linkQuickJs(b, models_stream_regressions.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(models_stream_regressions.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-models-stream-regressions", "Retain shared native stream identity terminal admission result-only queue allocation and cancellation controls").dependOn(&b.addRunArtifact(models_stream_regressions).step);
    const codemode_models_catalog_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_codemode_models_catalog_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "native durable default CodeMode model catalog actual Source program", "native durable default CodeMode model calls Source", "native durable default CodeMode model images Source" } });
    linkQuickJs(b, codemode_models_catalog_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(codemode_models_catalog_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-codemode-model-catalog", "Exercise the original default model catalog script over the actual native Models query registry").dependOn(&b.addRunArtifact(codemode_models_catalog_tests).step);
    const owner_wakeup_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_owner_wakeup_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "native owner", "native timer owner" } });
    linkQuickJs(b, owner_wakeup_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(owner_wakeup_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-owner-wakeup", "Wake native owners without losing publications or starving ready Promise jobs behind timers").dependOn(&b.addRunArtifact(owner_wakeup_tests).step);
    const node_base64_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_base64_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native Node base64"} });
    linkQuickJs(b, node_base64_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(node_base64_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-node-base64", "Replay actual Node base64 string validation coercion errors and public identities").dependOn(&b.addRunArtifact(node_base64_tests).step);
    const codemode_output_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_codemode_output_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable CodeMode output"} });
    linkQuickJs(b, codemode_output_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(codemode_output_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-codemode-output", "Replay actual durable CodeMode output layout truncation images and asynchronous writer outcomes").dependOn(&b.addRunArtifact(codemode_output_tests).step);
    const durable_json_dto_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_json_dto_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable JSON DTO"} });
    linkQuickJs(b, durable_json_dto_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(durable_json_dto_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-json-dto", "Preserve JSON.parse semantics while avoiding native DTO format/reparse allocations").dependOn(&b.addRunArtifact(durable_json_dto_tests).step);
    const inspection_comparison_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_inspection_compare.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable inspection timestamp comparison"} });
    b.step("test-native-durable-inspection-comparison", "Reject missing malformed out-of-bounds or unstable actual inspection timestamps").dependOn(&b.addRunArtifact(inspection_comparison_tests).step);
    const summary_transcript_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_summary_transcript_source_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"latest89 serializer"} });
    b.step("test-native-summary-transcript-source", "Compare both native agent summary callers with actual latest canonical message captures").dependOn(&b.addRunArtifact(summary_transcript_tests).step);
    const ea_nested_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_ea_nested_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable ea nested"} });
    linkQuickJs(b, ea_nested_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, ea_nested_tests.root_module, typescript_parser);
    linkSqlite(ea_nested_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-durable-ea-nested", "Replay actual ea Source keyed nested documents and full Harness events").dependOn(&b.addRunArtifact(ea_nested_tests).step);
    const ea_owned_memo_tests = b.addTest(.{ .root_module = native_durable_tests.root_module, .use_llvm = use_llvm, .filters = &.{ "ownedTasks actual ea", "public task memos use durable winners" } });
    b.step("test-native-durable-ea-owned-memo", "Exercise direct-owned copies and original durable memo winners").dependOn(&b.addRunArtifact(ea_owned_memo_tests).step);
    const ea_owner_step_tests = b.addTest(.{ .root_module = native_durable_tests.root_module, .use_llvm = use_llvm, .filters = &.{"scheduler ea owner cancellation"} });
    b.step("test-native-durable-ea-owner-step", "Fence a foreground phase before its owner's cancellation cascade").dependOn(&b.addRunArtifact(ea_owner_step_tests).step);
    const ownership_index_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_ownership_index_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"durable ownership index"} });
    b.step("test-durable-ownership-index", "Check actual ea ownership retention sizes and native allocation cleanup").dependOn(&b.addRunArtifact(ownership_index_tests).step);
    const ownership_line_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/durable_scheduler_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"scheduler ea actual Storage owner line"} });
    linkSqlite(ownership_line_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-durable-ownership-line", "Compare actual native Storage owner-line retention and rejected-read sweep with ea Source").dependOn(&b.addRunArtifact(ownership_line_tests).step);
    const opaque_checkpoint_tests = b.addTest(.{ .root_module = ownership_line_tests.root_module, .use_llvm = use_llvm, .filters = &.{"scheduler ea opaque stored checkpoint"} });
    b.step("test-durable-ea-opaque-checkpoint", "Preserve an actual ea opaque stored checkpoint through native recovery and missing definition admission").dependOn(&b.addRunArtifact(opaque_checkpoint_tests).step);
    const durable_tool_output_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_tool_output_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable v2"} });
    linkQuickJs(b, durable_tool_output_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, durable_tool_output_tests.root_module, typescript_parser);
    const durable_tool_output_run = b.addRunArtifact(durable_tool_output_tests);
    b.step("test-native-durable-tool-output", "Replay actual Durable v2 structured output and independent schema cache contracts").dependOn(&durable_tool_output_run.step);
    const generation_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_tool_output_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "native durable v2 generation", "native durable v2 prompt" } });
    linkQuickJs(b, generation_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, generation_tests.root_module, typescript_parser);
    const generation_run = b.addRunArtifact(generation_tests);
    b.step("test-native-durable-generation", "Compare native generation phases and prompt planning with upstream").dependOn(&generation_run.step);
    b.step("build-native-durable-generation", "Compile generation regression separately from its bounded runtime").dependOn(&generation_tests.step);
    const durable_view_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_durable_view_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{"native durable view"} });
    linkQuickJs(b, durable_view_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, durable_view_tests.root_module, typescript_parser);
    durable_view_tests.root_module.addImport("catalog_tool", catalog_tool);
    const durable_view_run = b.addRunArtifact(durable_view_tests);
    b.step("test-native-durable-views", "Compare native conversation view projections and persistent revisions with upstream").dependOn(&durable_view_run.step);
    test_step.dependOn(&durable_view_run.step);
    test_step.dependOn(&durable_tool_output_run.step);
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
    const durable_json_clone_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/durable/backend/json.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "durable JSON scalar array clone", "durable JSON object clone" } });
    b.step("test-durable-json-clone", "Verify known-size JSON clone allocations and object insertion order").dependOn(&b.addRunArtifact(durable_json_clone_tests).step);
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
    linkQuickJs(b, mcp_configured_tests.root_module, quickjs, sqlite_lib_dir);
    const resource_adapter_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_resource_tools_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"MCP resource adapter"}, .use_llvm = use_llvm });
    linkQuickJs(b, resource_adapter_tests.root_module, quickjs, sqlite_lib_dir);
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
    linkQuickJs(b, mcp_adapter_probe.root_module, quickjs, sqlite_lib_dir);
    const install_mcp_adapter_probe = b.addInstallArtifact(mcp_adapter_probe, .{});
    const mcp_adapter_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/mcp_adapter_integration_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"mcp.adapter"},
    });
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
    const codemode_allocation_tests = b.addTest(.{
        .root_module = codemode_tests.root_module,
        .use_llvm = use_llvm,
        .filters = &.{ "native codemode allocation failures", "native codemode discovery allocation failures", "native codemode agent adapter allocation failures" },
    });
    b.step("test-codemode-allocation", "Check all four codemode host worker discovery and adapter allocation sweeps without repeating CLI and model suites").dependOn(&b.addRunArtifact(codemode_allocation_tests).step);
    const codemode_inline_tests = b.addTest(.{
        .root_module = codemode_tests.root_module,
        .use_llvm = use_llvm,
        .filters = &.{"native codemode Source c5 inline"},
    });
    b.step("test-codemode-inline", "Check current upstream inline interruption and terminal result ordering").dependOn(&b.addRunArtifact(codemode_inline_tests).step);
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
    const nested_tests = b.addTest(.{ .root_module = nested_module, .use_llvm = use_llvm, .filters = &.{"native codemode nested pipeline"} });
    const run_nested_tests = b.addRunArtifact(nested_tests);
    codemode_step.dependOn(&run_nested_tests.step);
    const codemode_models_module = b.createModule(.{ .root_source_file = b.path("src/codemode_models_test.zig"), .target = target, .optimize = optimize });
    codemode_models_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, codemode_models_module, quickjs, sqlite_lib_dir);
    const codemode_models_tests = b.addTest(.{ .root_module = codemode_models_module, .use_llvm = use_llvm, .filters = &.{"native codemode models"} });
    const codemode_models_run = b.addRunArtifact(codemode_models_tests);
    b.step("test-codemode-models", "Compare model globals against original registry behavior and concurrency").dependOn(&codemode_models_run.step);
    const codemode_model_allocation_tests = b.addTest(.{ .root_module = codemode_models_module, .use_llvm = use_llvm, .filters = &.{"native codemode models allocation failures"} });
    const codemode_model_allocation_run = b.addRunArtifact(codemode_model_allocation_tests);
    codemode_model_allocation_run.has_side_effects = true;
    b.step("test-codemode-model-allocation-shard", "Exercise one exhaustive model worker allocation range").dependOn(&codemode_model_allocation_run.step);
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
    linkTypeScriptParser(b, model_owner_module, typescript_parser);
    const model_owner_tests = b.addTest(.{ .root_module = model_owner_module, .use_llvm = use_llvm, .filters = &.{"native model owner transport"} });
    const model_owner_run = b.addRunArtifact(model_owner_tests);
    b.step("test-model-owner-transport", "Exercise exact model registry leases over the native worker protocol").dependOn(&model_owner_run.step);
    test_step.dependOn(&model_owner_run.step);
    const main_context_module = b.createModule(.{ .root_source_file = b.path("src/main_native_context_test.zig"), .target = target, .optimize = optimize });
    main_context_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, main_context_module, quickjs, sqlite_lib_dir);
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
    const strict_theme_tests = b.addTest(.{ .root_module = strict_theme_module, .use_llvm = use_llvm, .filters = &.{"Source6fb strict Theme"} });
    const strict_theme_run = b.addRunArtifact(strict_theme_tests);
    b.step("test-theme-file-admission", "Replay Source optional theme validation and context admission").dependOn(&strict_theme_run.step);
    test_step.dependOn(&strict_theme_run.step);
    const keybindings_manager_module = b.createModule(.{ .root_source_file = b.path("src/keybindings_manager_test.zig"), .target = target, .optimize = optimize });
    keybindings_manager_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, keybindings_manager_module, quickjs, sqlite_lib_dir);
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
    const mcp_issuer_exchange_tests = b.addTest(.{
        .root_module = mcp_runtime_tests.root_module,
        .use_llvm = use_llvm,
        .filters = &.{"mcp.runtime Source c5f5b328"},
    });
    b.step("test-mcp-issuer-exchange", "Check the actual OAuth token boundary when issuer metadata is missing").dependOn(&b.addRunArtifact(mcp_issuer_exchange_tests).step);
    test_step.dependOn(&run_mcp_runtime_tests.step);
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_sqlite_tests.step);
    test_step.dependOn(&run_sqlite_cli_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_sqlite_persistence_tests.step);
    test_step.dependOn(&run_sqlite_live_tests.step);

    const engine_tests = b.addTest(.{
        // Keep each standalone extension target focused on its own tests.
        // Imported storage/SDK suites have separate fixture-aware targets.
        .filters = &.{"extensions.engine."},
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/extension_engine_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, engine_tests.root_module, quickjs, sqlite_lib_dir);
    const run_engine_tests = b.addRunArtifact(engine_tests);
    const engine_test_step = b.step("test-extension-engine", "Test the directly linked extension-language engine");
    engine_test_step.dependOn(&run_engine_tests.step);
    b.step("build-extension-engine", "Compile unchanged ordinary engine tests separately for metadata and matching runtime qualification").dependOn(&engine_tests.step);
    const original_oom_tests = b.addTest(.{ .root_module = engine_tests.root_module, .use_llvm = use_llvm, .filters = &.{"native allocation original identity"} });
    b.step("test-native-allocation-original-identity", "Preserve original native OOM identity across cleanup without accepting user or stale causes").dependOn(&b.addRunArtifact(original_oom_tests).step);
    test_step.dependOn(&run_engine_tests.step);
    const commonjs_tests = b.addTest(.{
        .filters = &.{"extensions.commonjs."},
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_commonjs_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, commonjs_tests.root_module, quickjs, sqlite_lib_dir);
    const run_commonjs_tests = b.addRunArtifact(commonjs_tests);
    const commonjs_test_step = b.step("test-extension-commonjs", "Test native CommonJS cache and module ownership");
    commonjs_test_step.dependOn(&run_commonjs_tests.step);
    test_step.dependOn(&run_commonjs_tests.step);
    const buffer_tests = b.addTest(.{
        .filters = &.{"extensions.node_buffer."},
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_node_buffer_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, buffer_tests.root_module, quickjs, sqlite_lib_dir);
    const run_buffer_tests = b.addRunArtifact(buffer_tests);
    const buffer_test_step = b.step("test-extension-buffer", "Test native extension Buffer views and encodings");
    buffer_test_step.dependOn(&run_buffer_tests.step);
    test_step.dependOn(&run_buffer_tests.step);
    const schema_tests = b.addTest(.{
        .filters = &.{"extensions.typebox."},
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_typebox_test.zig"), .target = target, .optimize = optimize }),
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
    binding_tests.root_module.addImport("catalog_tool", catalog_tool);
    const typed_provider_tests = b.addTest(.{ .root_module = binding_tests.root_module, .filters = &.{"typed provider owner"}, .use_llvm = use_llvm });
    const typed_provider_run = b.addRunArtifact(typed_provider_tests);
    b.step("test-typed-provider-owner", "Exercise exact typed provider callback receiver and signal ownership").dependOn(&typed_provider_run.step);
    test_step.dependOn(&typed_provider_run.step);
    const typed_catalog_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_typed_catalog_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"typed catalog"}, .use_llvm = use_llvm });
    linkQuickJs(b, typed_catalog_tests.root_module, quickjs, sqlite_lib_dir);
    typed_catalog_tests.root_module.addImport("catalog_tool", catalog_tool);
    const typed_catalog_run = b.addRunArtifact(typed_catalog_tests);
    b.step("test-typed-catalog", "Exercise Source typed catalog registration and allocation ownership").dependOn(&typed_catalog_run.step);
    test_step.dependOn(&typed_catalog_run.step);
    const typed_auth_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_typed_auth_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"typed auth"}, .use_llvm = use_llvm });
    const typed_auth_run = b.addRunArtifact(typed_auth_tests);
    b.step("test-typed-auth", "Exercise private typed request credential and header ownership").dependOn(&typed_auth_run.step);
    test_step.dependOn(&typed_auth_run.step);
    const typed_registry_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_typed_registry_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"typed registry owner"}, .use_llvm = use_llvm });
    linkQuickJs(b, typed_registry_tests.root_module, quickjs, sqlite_lib_dir);
    typed_registry_tests.root_module.addImport("catalog_tool", catalog_tool);
    const typed_registry_run = b.addRunArtifact(typed_registry_tests);
    b.step("test-typed-registry-owner", "Exercise actual Main registry snapshots and generation admission").dependOn(&typed_registry_run.step);
    test_step.dependOn(&typed_registry_run.step);
    const weakref_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_weakref_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native WeakRef"}, .use_llvm = use_llvm });
    linkQuickJs(b, weakref_tests.root_module, quickjs, sqlite_lib_dir);
    weakref_tests.root_module.addImport("catalog_tool", catalog_tool);
    const weakref_run = b.addRunArtifact(weakref_tests);
    b.step("test-native-weakref", "Compare WeakRef kept objects with actual V8 job checkpoints").dependOn(&weakref_run.step);
    test_step.dependOn(&weakref_run.step);
    const async_iterator_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_iterator_intrinsic_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    linkQuickJs(b, async_iterator_tests.root_module, quickjs, sqlite_lib_dir);
    async_iterator_tests.root_module.addImport("catalog_tool", catalog_tool);
    const async_iterator_run = b.addRunArtifact(async_iterator_tests);
    b.step("test-native-async-iterator-intrinsic", "Verify native async iterator prototype identity and owned reference cleanup").dependOn(&async_iterator_run.step);
    test_step.dependOn(&async_iterator_run.step);
    const async_function_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_function_intrinsic_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    linkQuickJs(b, async_function_tests.root_module, quickjs, sqlite_lib_dir);
    async_function_tests.root_module.addImport("catalog_tool", catalog_tool);
    const async_function_run = b.addRunArtifact(async_function_tests);
    b.step("test-native-async-function-intrinsic", "Verify native async function intrinsic identity and owned reference cleanup").dependOn(&async_function_run.step);
    const native_async_body_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_function_body_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native async body proposal"}, .use_llvm = use_llvm });
    linkQuickJs(b, native_async_body_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_async_body_tests.root_module, sqlite_lib_dir, sqlite_library);
    native_async_body_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-async-function-body-proposal", "Compile reviewed native AsyncFunction body proposal after genuine Source capture").dependOn(&native_async_body_tests.step);
    b.step("test-native-async-function-body-proposal", "Qualify reviewed genuine native AsyncFunction brand return Await realm and ownership").dependOn(&b.addRunArtifact(native_async_body_tests).step);
    const native_async_qualification_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_function_qualification_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native async body proposal", "native async generator functional", "native AI JSON actual OpenAI request builder", "native AI JSON OpenAI decoder", "native AI JSON helpers and native partial fallback", "native AI JSON genuine b06 delegates", "native AI JSON private hooks", "native AI JSON ordinary no-hook", "native borrowed view span" }, .use_llvm = use_llvm });
    linkQuickJs(b, native_async_qualification_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_async_qualification_tests.root_module, sqlite_lib_dir, sqlite_library);
    native_async_qualification_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-async-function-qualification", "Compile genuine AsyncFunction Source42 and inherited generator JSON live-view span regression cohort").dependOn(&b.addInstallArtifact(native_async_qualification_tests, .{}).step);
    b.step("test-native-async-function-qualification", "Run the matching cached qualification cohort with enforced per-test deadlines").dependOn(&b.addRunArtifact(native_async_qualification_tests).step);
    test_step.dependOn(&async_function_run.step);
    const async_scope_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_scope_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    linkQuickJs(b, async_scope_tests.root_module, quickjs, sqlite_lib_dir);
    async_scope_tests.root_module.addImport("catalog_tool", catalog_tool);
    const async_scope_run = b.addRunArtifact(async_scope_tests);
    async_scope_run.step.dependOn(&install_durable_fixture.step);
    async_scope_run.setEnvironmentVariable("PI_DURABLE_FIXTURE", durable_fixture_path);
    b.step("test-native-async-scope", "Prove four private promise and timer execution scopes").dependOn(&async_scope_run.step);
    test_step.dependOn(&async_scope_run.step);
    const sdk_public_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_public_session_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK public"}, .use_llvm = use_llvm });
    const sdk_usage_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_usage_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session usage"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_usage_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_usage_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_usage_run = b.addRunArtifact(sdk_usage_tests);
    b.step("test-native-sdk-session-usage", "Replay Source billed session totals and projected context usage").dependOn(&sdk_usage_run.step);
    test_step.dependOn(&sdk_usage_run.step);
    const sdk_public_allocation_range = b.option(u8, "sdk-public-allocation-range", "SDK public model and thenable exhaustive allocation range 0..7; omit to run all indices");
    if (sdk_public_allocation_range) |range| if (range >= 8) @panic("SDK public allocation range must be 0..7");
    const sdk_public_options = b.addOptions();
    sdk_public_options.addOption(?u8, "range", sdk_public_allocation_range);
    sdk_public_tests.root_module.addOptions("sdk_public_allocation_options", sdk_public_options);
    linkQuickJs(b, sdk_public_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_public_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_public_run = b.addRunArtifact(sdk_public_tests);
    const agent_directory_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_directory_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"agent directory contract"}, .use_llvm = use_llvm });
    linkQuickJs(b, agent_directory_tests.root_module, quickjs, sqlite_lib_dir);
    agent_directory_tests.root_module.addImport("catalog_tool", catalog_tool);
    const agent_directory_run = b.addRunArtifact(agent_directory_tests);
    b.step("test-native-agent-directory", "Compare canonical CLI and SDK agent-directory configuration against upstream").dependOn(&agent_directory_run.step);
    test_step.dependOn(&agent_directory_run.step);
    b.step("test-native-sdk-public-session", "Replay actual Source SDK session mutations and observable effects").dependOn(&sdk_public_run.step);
    test_step.dependOn(&sdk_public_run.step);
    const sdk_ui_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_ui_context_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK UI"}, .use_llvm = use_llvm });
    const sdk_input_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_input_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK input"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_input_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_input_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_input_run = b.addRunArtifact(sdk_input_tests);
    const edit_diff_source_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_edit_diff_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, edit_diff_source_module, quickjs, sqlite_lib_dir);
    edit_diff_source_module.addImport("catalog_tool", catalog_tool);
    const edit_diff_source_tests = b.addTest(.{ .root_module = edit_diff_source_module, .use_llvm = use_llvm, .filters = &.{"native edit diff matches genuine Source54"} });
    b.step("test-native-edit-diff-source", "Replay actual jsdiff words/lines and Source edit matching display and rendering").dependOn(&b.addRunArtifact(edit_diff_source_tests).step);
    const edit_diff_owner_tests = b.addTest(.{ .root_module = edit_diff_source_module, .use_llvm = use_llvm, .filters = &.{"native edit diff releases every failed Source54"} });
    b.step("test-native-edit-diff-ownership", "Exercise complete sharded edit diff allocation ownership").dependOn(&b.addRunArtifact(edit_diff_owner_tests).step);
    addCompileOnlyGroup(b, "build-native-edit-diff-source", &.{"test-native-edit-diff-source"});
    addCompileOnlyGroup(b, "build-native-edit-diff-ownership", &.{"test-native-edit-diff-ownership"});
    const file_renderer_source_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_file_renderers_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, file_renderer_source_module, quickjs, sqlite_lib_dir);
    file_renderer_source_module.addImport("catalog_tool", catalog_tool);
    const file_renderer_source_tests = b.addTest(.{ .root_module = file_renderer_source_module, .use_llvm = use_llvm, .filters = &.{ "native file renderers match actual Source28", "native file renderers retain and release five selected" } });
    b.step("test-native-file-renderers-source", "Replay actual Source read/write text components and real async edit previews").dependOn(&b.addRunArtifact(file_renderer_source_tests).step);
    const file_renderer_owner_tests = b.addTest(.{ .root_module = file_renderer_source_module, .use_llvm = use_llvm, .filters = &.{"native file renderers release every actual Source28"} });
    b.step("test-native-file-renderers-ownership", "Exercise complete sharded file renderer allocation ownership").dependOn(&b.addRunArtifact(file_renderer_owner_tests).step);
    addCompileOnlyGroup(b, "build-native-file-renderers-source", &.{"test-native-file-renderers-source"});
    addCompileOnlyGroup(b, "build-native-file-renderers-ownership", &.{"test-native-file-renderers-ownership"});
    b.step("test-native-sdk-input", "Replay genuine Source input reducer chains and original context ownership").dependOn(&sdk_input_run.step);
    test_step.dependOn(&sdk_input_run.step);
    const sdk_queue_order_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_queue_order_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK queue order"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_queue_order_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_queue_order_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_queue_order_run = b.addRunArtifact(sdk_queue_order_tests);
    b.step("test-native-sdk-queue-order", "Replay genuine Source476/477 template iterator and callee ordering").dependOn(&sdk_queue_order_run.step);
    const agent_foundation_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_foundations_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Agent foundations"}, .use_llvm = use_llvm });
    linkQuickJs(b, agent_foundation_tests.root_module, quickjs, sqlite_lib_dir);
    agent_foundation_tests.root_module.addImport("catalog_tool", catalog_tool);
    const agent_foundation_run = b.addRunArtifact(agent_foundation_tests);
    b.step("test-native-agent-foundations", "Compare private native Agent constructor and real method bodies with current Source observations").dependOn(&agent_foundation_run.step);
    const agent_return_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_return_adapter_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Agent return adapter"}, .use_llvm = use_llvm });
    const agent_guest_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_af_guest_provenance_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Agent guest provenance"}, .use_llvm = use_llvm });
    linkQuickJs(b, agent_guest_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(agent_guest_tests.root_module, sqlite_lib_dir, sqlite_library);
    agent_guest_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-agent-af-guest-provenance", "Compile actual Agent guest DATA and native producer controls").dependOn(&b.addInstallArtifact(agent_guest_tests, .{ .dest_sub_path = b.fmt("native-agent-af-guest-provenance{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    b.step("test-native-agent-af-guest-provenance", "Run actual Agent guest DATA and native producer controls").dependOn(&b.addRunArtifact(agent_guest_tests).step);
    linkQuickJs(b, agent_return_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(agent_return_tests.root_module, sqlite_lib_dir, sqlite_library);
    agent_return_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-agent-return-adapter", "Compile genuine Agent return-adoption and actual resumable factory controls").dependOn(&b.addInstallArtifact(agent_return_tests, .{ .dest_sub_path = b.fmt("native-agent-return-adapter{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    b.step("test-native-agent-return-adapter", "Run genuine Agent AF return-adoption and production factory controls").dependOn(&b.addRunArtifact(agent_return_tests).step);
    const agent_parallel_af_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_parallel_async_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Agent parallel AF"}, .use_llvm = use_llvm });
    linkQuickJs(b, agent_parallel_af_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(agent_parallel_af_tests.root_module, sqlite_lib_dir, sqlite_library);
    agent_parallel_af_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-agent-parallel-af", "Compile genuine parallel tool AF states and original ownership dependencies").dependOn(&b.addInstallArtifact(agent_parallel_af_tests, .{ .dest_sub_path = b.fmt("native-agent-parallel-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    b.step("test-native-agent-parallel-af", "Run real parallel tool AF Await and DATA controls").dependOn(&b.addRunArtifact(agent_parallel_af_tests).step);
    const agent_loop_af_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_loop_async_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Agent loop AF"}, .use_llvm = use_llvm });
    linkQuickJs(b, agent_loop_af_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(agent_loop_af_tests.root_module, sqlite_lib_dir, sqlite_library);
    agent_loop_af_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-agent-loop-af", "Compile actual loop AF entries IteratorClose and original helper dependencies").dependOn(&b.addInstallArtifact(agent_loop_af_tests, .{ .dest_sub_path = b.fmt("native-agent-loop-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    b.step("test-native-agent-loop-af", "Run actual loop AF Await iterator and DATA controls").dependOn(&b.addRunArtifact(agent_loop_af_tests).step);
    const agent_loop_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_loop_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AgentLoop"}, .use_llvm = use_llvm });
    linkQuickJs(b, agent_loop_tests.root_module, quickjs, sqlite_lib_dir);
    agent_loop_tests.root_module.addImport("catalog_tool", catalog_tool);
    const agent_loop_run = b.addRunArtifact(agent_loop_tests);
    b.step("test-native-agent-loop", "Compare actual native low-level AgentLoop bodies with original Source controlled streams").dependOn(&agent_loop_run.step);
    const agent_allocation_diagnostic_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_loop_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"SDK Agent allocation2631"}, .use_llvm = use_llvm });
    linkQuickJs(b, agent_allocation_diagnostic_tests.root_module, quickjs, sqlite_lib_dir);
    agent_allocation_diagnostic_tests.root_module.addImport("catalog_tool", catalog_tool);
    const agent_allocation_diagnostic_run = b.addRunArtifact(agent_allocation_diagnostic_tests);
    b.step("test-sdk-agent-allocation-diagnostic", "Observe the exact first native Agent producer allocation failure without changing settlement").dependOn(&agent_allocation_diagnostic_run.step);
    const agent_allocation2654_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_loop_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"SDK Agent allocation2654"}, .use_llvm = use_llvm });
    linkQuickJs(b, agent_allocation2654_tests.root_module, quickjs, sqlite_lib_dir);
    agent_allocation2654_tests.root_module.addImport("catalog_tool", catalog_tool);
    const agent_allocation2654_run = b.addRunArtifact(agent_allocation2654_tests);
    b.step("test-sdk-agent-allocation2654-diagnostic", "Observe the exact next native Agent producer allocation failure without changing settlement").dependOn(&agent_allocation2654_run.step);
    const agent_owned_fault_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_loop_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "SDK Agent allocation2631", "SDK Agent allocation2654" }, .use_llvm = use_llvm });
    linkQuickJs(b, agent_owned_fault_tests.root_module, quickjs, sqlite_lib_dir);
    agent_owned_fault_tests.root_module.addImport("catalog_tool", catalog_tool);
    const agent_owned_fault_run = b.addRunArtifact(agent_owned_fault_tests);
    b.step("test-sdk-agent-owned-faults", "Verify native producer fault identities without settling ordinary pending streams").dependOn(&agent_owned_fault_run.step);
    const agent_complete_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_agent_complete_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Agent complete"}, .use_llvm = use_llvm });
    linkQuickJs(b, agent_complete_tests.root_module, quickjs, sqlite_lib_dir);
    agent_complete_tests.root_module.addImport("catalog_tool", catalog_tool);
    const agent_complete_run = b.addRunArtifact(agent_complete_tests);
    b.step("test-native-agent-complete", "Compare privately assembled complete Agent bodies and lexical stream fallback with original Source").dependOn(&agent_complete_run.step);
    const agent_contract_compile = b.step("build-native-agent-contract", "Compile both Agent contract artifacts separately from their bounded runtime checks");
    agent_contract_compile.dependOn(&agent_loop_tests.step);
    agent_contract_compile.dependOn(&agent_complete_tests.step);
    b.step("build-native-agent-loop", "Compile the AgentLoop contract artifact without running its tests").dependOn(&agent_loop_tests.step);
    b.step("build-native-agent-complete", "Compile the complete Agent contract artifact without running its tests").dependOn(&agent_complete_tests.step);
    const sdk_await_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_await_primitives_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK await primitives"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_await_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_await_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-await-primitives", "Compare intrinsic await resolution and old ToNumeric with guest semantics").dependOn(&b.addRunArtifact(sdk_await_tests).step);
    const sdk_skill_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_skill_expansion_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK skill expansion"}, .use_llvm = use_llvm });
    const sdk_send_user_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_send_user_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK sendUserMessage"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_send_user_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_send_user_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-send-user", "Replay latest Source user-message normalization and asynchronous prompt delegation").dependOn(&b.addRunArtifact(sdk_send_user_tests).step);
    const sdk_session_queries_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_queries_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session queries"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_session_queries_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_session_queries_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-queries", "Compare callable tool loadouts and user-message fork queries with actual latest Source").dependOn(&b.addRunArtifact(sdk_session_queries_tests).step);
    const sdk_lifecycle_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_lifecycle_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK private session lifecycle"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_lifecycle_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_lifecycle_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-lifecycle", "Compare original custom ingestion run/finally and settlement component ordering without partial factory activation").dependOn(&b.addRunArtifact(sdk_lifecycle_tests).step);
    const sdk_events_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_events_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session events"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_events_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_events_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-events", "Compare Source awaited extension/public/persistence ordering using actual native Agent runner and manager").dependOn(&b.addRunArtifact(sdk_events_tests).step);
    const cache_warmer_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_cache_warmer_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK cache warmer"}, .use_llvm = use_llvm });
    linkQuickJs(b, cache_warmer_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(cache_warmer_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-sdk-cache-warmer", "Replay original latest cache warming class cost environment refresh cancellation and native allocation ownership").dependOn(&b.addRunArtifact(cache_warmer_tests).step);
    const attribution_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_provider_attribution_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK provider attribution"}, .use_llvm = use_llvm });
    linkQuickJs(b, attribution_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(attribution_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-sdk-provider-attribution", "Compare original provider attribution telemetry precedence live header merging and native allocation ownership").dependOn(&b.addRunArtifact(attribution_tests).step);
    const factory_provider_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_factory_provider_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK factory provider callbacks"}, .use_llvm = use_llvm });
    linkQuickJs(b, factory_provider_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(factory_provider_tests.root_module, sqlite_lib_dir, sqlite_library);
    factory_provider_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-factory-provider", "Compare latest Source factory callbacks header snapshot live hooks promise ordering and cache prefixes over native collaborators").dependOn(&b.addRunArtifact(factory_provider_tests).step);
    const image_process_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_image_process_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK image processing"}, .use_llvm = use_llvm });
    linkQuickJs(b, image_process_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(image_process_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-sdk-image-process", "Compare original SDK image normalization against linked Photon conversion native resize and complete iterator ownership").dependOn(&b.addRunArtifact(image_process_tests).step);
    const sdk_loadout_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_loadout_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session loadout"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_loadout_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_loadout_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-session-loadout", "Compile the private Source55 loadout artifact without running tests").dependOn(&sdk_loadout_tests.step);
    b.step("test-native-sdk-session-loadout", "Replay full latest Source loadout hooks and structured prompt sections with private native collaborators and exhaustive host allocation cleanup").dependOn(&b.addRunArtifact(sdk_loadout_tests).step);
    const tool_matcher_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_tool_name_matcher_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK tool-name matcher"}, .use_llvm = use_llvm });
    linkQuickJs(b, tool_matcher_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(tool_matcher_tests.root_module, sqlite_lib_dir, sqlite_library);
    b.step("test-native-sdk-tool-name-matcher", "Compare original constructor tool-name wildcard matching live collections and complete callback ownership").dependOn(&b.addRunArtifact(tool_matcher_tests).step);
    const constructor_phase_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_constructor_phase_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK constructor initialization phase"}, .use_llvm = use_llvm });
    linkQuickJs(b, constructor_phase_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(constructor_phase_tests.root_module, sqlite_lib_dir, sqlite_library);
    constructor_phase_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-constructor-phase", "Compare actual Source constructor field config subscription and native hook phase before runtime building").dependOn(&b.addRunArtifact(constructor_phase_tests).step);
    const session_values_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_public_values_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session public values"}, .use_llvm = use_llvm });
    linkQuickJs(b, session_values_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_values_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_values_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-values", "Compare original ordinary AgentSession getters routes metadata and complete native owner graphs").dependOn(&b.addRunArtifact(session_values_tests).step);
    const prompt_images_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_prompt_images_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session prompt images"}, .use_llvm = use_llvm });
    linkQuickJs(b, prompt_images_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(prompt_images_tests.root_module, sqlite_lib_dir, sqlite_library);
    prompt_images_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-prompt-images", "Compare original prompt-image preprocessing with native codec limits hints and complete owner lifetimes").dependOn(&b.addRunArtifact(prompt_images_tests).step);
    b.step("build-native-sdk-session-prompt-images", "Compile prompt-image normalization independently of its original runtime deadline").dependOn(&prompt_images_tests.step);
    const prompt_handlers_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_prompt_handlers_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session prompt handlers"}, .use_llvm = use_llvm });
    linkQuickJs(b, prompt_handlers_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(prompt_handlers_tests.root_module, sqlite_lib_dir, sqlite_library);
    prompt_handlers_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-prompt-handlers", "Compare original input and command dispatch with native receiver collection and allocation lifetimes").dependOn(&b.addRunArtifact(prompt_handlers_tests).step);
    b.step("build-native-sdk-session-prompt-handlers", "Compile original input and command dispatch separately from its runtime envelope").dependOn(&prompt_handlers_tests.step);
    const session_prompt_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_prompt_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session prompt preflight and queues"}, .use_llvm = use_llvm });
    linkQuickJs(b, session_prompt_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_prompt_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_prompt_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-prompt", "Compare original public prompt preflight and ordinary queue methods with retained owner graphs").dependOn(&b.addRunArtifact(session_prompt_tests).step);
    b.step("build-native-sdk-session-prompt", "Compile public prompt and queue bodies separately from runtime deadlines").dependOn(&session_prompt_tests.step);
    const session_control_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_control_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session control"}, .use_llvm = use_llvm });
    linkQuickJs(b, session_control_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_control_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_control_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-control", "Compare original session cancellation idle disposal modes and shared resource cleanup with complete owner graphs").dependOn(&b.addRunArtifact(session_control_tests).step);
    b.step("build-native-sdk-session-control", "Compile ordinary session cancellation and disposal separately from runtime deadlines").dependOn(&session_control_tests.step);
    const node_crypto_hash_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_crypto_hash_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native node crypto SHA256"}, .use_llvm = use_llvm });
    linkQuickJs(b, node_crypto_hash_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(node_crypto_hash_tests.root_module, sqlite_lib_dir, sqlite_library);
    node_crypto_hash_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-node-crypto-sha256", "Compile real SHA256 createHash dependency independently").dependOn(&node_crypto_hash_tests.step);
    b.step("build-native-node-crypto-sha256-artifact", "Install the compiled SHA256 test artifact for metadata-only verification").dependOn(&b.addInstallArtifact(node_crypto_hash_tests, .{}).step);
    b.step("test-native-node-crypto-sha256", "Compare actual Node SHA256 package observations and native state ownership").dependOn(&b.addRunArtifact(node_crypto_hash_tests).step);
    // Private converted-native internal builtin require. Install only; Root
    // separately admits metadata/runtime and actual util/TTY provider wiring.
    const internal_builtin_require_leaf = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_internal_builtin_require_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native internal require"}, .use_llvm = use_llvm });
    linkQuickJs(b, internal_builtin_require_leaf.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(internal_builtin_require_leaf.root_module, sqlite_lib_dir, sqlite_library);
    linkTypeScriptParser(b, internal_builtin_require_leaf.root_module, typescript_parser);
    internal_builtin_require_leaf.root_module.addImport("catalog_tool", catalog_tool);
    @import("tools/build_native_transform_compression.zig").link(b, internal_builtin_require_leaf.root_module);
    if (target.result.os.tag == .windows) {
        internal_builtin_require_leaf.root_module.linkSystemLibrary("advapi32", .{});
        internal_builtin_require_leaf.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-internal-builtin-require", "Install actual native builtin internal require controls without execution").dependOn(&b.addInstallArtifact(internal_builtin_require_leaf, .{}).step);
    // Current Main compile/link-only body gate. This step has no runner, query
    // or reference dependency. Its installed sentinel artifact MUST NOT RUN.
    const current_jiti_sdk_agent_compile_only = b.addTest(.{
        .name = "pi-current-jiti-sdk-agent-compile-only",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_jiti_current_compile_only_root.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "CURRENT_MAIN_COMPILE_LINK_ONLY_SENTINEL_NEVER_EXECUTE", "native get-tsconfig JSONC", "jiti MD5 actual", "jiti MD5 every", "jiti local cancellation", "jiti local quota", "native jiti mlly", "mlly ", "native jiti pathe", "Pathe ", "jiti nativeImport actual" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, current_jiti_sdk_agent_compile_only.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, current_jiti_sdk_agent_compile_only.root_module, typescript_parser);
    linkSqlite(current_jiti_sdk_agent_compile_only.root_module, sqlite_lib_dir, sqlite_library);
    current_jiti_sdk_agent_compile_only.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-current-main-jiti-sdk-agent-compile-only-artifact", "Compile/link actual current Jiti, dependencies, SDK application and Agent AF/control bodies; NEVER RUN").dependOn(&b.addInstallArtifact(current_jiti_sdk_agent_compile_only, .{}).step);
    // Prospective expanded f912/c43 body gate: install only, NEVER RUN.
    const expanded_jiti_sdk_agent_compile_only = b.addTest(.{
        .name = "pi-expanded-jiti-sdk-agent-compile-only",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_jiti_expanded_compile_only_root.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "EXPANDED_MAIN_COMPILE_LINK_ONLY_SENTINEL_NEVER_EXECUTE", "native get-tsconfig JSONC", "jiti MD5 actual", "jiti MD5 every", "jiti local cancellation", "jiti local quota", "native jiti mlly", "mlly ", "native jiti pathe", "Pathe ", "jiti nativeImport actual", "native Agent AF correction", "SDK actual application", "CommonJS patched script", "CommonJS load failure", "converted CommonJS" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, expanded_jiti_sdk_agent_compile_only.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, expanded_jiti_sdk_agent_compile_only.root_module, typescript_parser);
    linkSqlite(expanded_jiti_sdk_agent_compile_only.root_module, sqlite_lib_dir, sqlite_library);
    expanded_jiti_sdk_agent_compile_only.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        expanded_jiti_sdk_agent_compile_only.root_module.linkSystemLibrary("advapi32", .{});
        expanded_jiti_sdk_agent_compile_only.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-expanded-main-jiti-sdk-agent-compile-only-artifact", "Compile/link actual latest full Agent AF, SDK bootstrap and Jiti/CommonJS bodies; NEVER RUN").dependOn(&b.addInstallArtifact(expanded_jiti_sdk_agent_compile_only, .{}).step);

    const auth_resource_af_controls = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_auth_resource_genuine_af_compile_root.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Auth resource actual-owner"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, auth_resource_af_controls.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, auth_resource_af_controls.root_module, typescript_parser);
    linkSqlite(auth_resource_af_controls.root_module, sqlite_lib_dir, sqlite_library);
    auth_resource_af_controls.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        auth_resource_af_controls.root_module.linkSystemLibrary("advapi32", .{});
        auth_resource_af_controls.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-auth-resource-owned-completion-controls-artifact", "Compile/link ten genuine SDK-owner integration bodies; NEVER RUN sentinel or invent missing owners").dependOn(&b.addInstallArtifact(auth_resource_af_controls, .{}).step);

    const auth_file_af_controls = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_auth_file_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Auth file genuine AF"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, auth_file_af_controls.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, auth_file_af_controls.root_module, typescript_parser);
    linkSqlite(auth_file_af_controls.root_module, sqlite_lib_dir, sqlite_library);
    auth_file_af_controls.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        auth_file_af_controls.root_module.linkSystemLibrary("advapi32", .{});
        auth_file_af_controls.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-auth-file-genuine-af-controls-artifact", "Build actual file/lock AF controls; runtime requires Root grant and accepted current VM producer").dependOn(&b.addInstallArtifact(auth_file_af_controls, .{}).step);

    const auth_readonly_af_controls = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_auth_readonly_genuine_af_compile_root.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Auth readonly actual-owner"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, auth_readonly_af_controls.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, auth_readonly_af_controls.root_module, typescript_parser);
    linkSqlite(auth_readonly_af_controls.root_module, sqlite_lib_dir, sqlite_library);
    auth_readonly_af_controls.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        auth_readonly_af_controls.root_module.linkSystemLibrary("advapi32", .{});
        auth_readonly_af_controls.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-auth-readonly-genuine-af-controls-artifact", "Compile/link six genuine owner-required Readonly bodies; NEVER RUN sentinel").dependOn(&b.addInstallArtifact(auth_readonly_af_controls, .{}).step);

    const auth_guest_producer_controls = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_auth_guest_producer_compile_root.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Auth guest-producer actual-owner"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, auth_guest_producer_controls.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, auth_guest_producer_controls.root_module, typescript_parser);
    linkSqlite(auth_guest_producer_controls.root_module, sqlite_lib_dir, sqlite_library);
    auth_guest_producer_controls.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        auth_guest_producer_controls.root_module.linkSystemLibrary("advapi32", .{});
        auth_guest_producer_controls.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-auth-guest-producer-controls-artifact", "Compile/link ten genuine owner-required guest-producer bodies; NEVER RUN sentinel").dependOn(&b.addInstallArtifact(auth_guest_producer_controls, .{}).step);

    const sdk_application_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_application_native_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK actual application"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_application_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_application_tests.root_module, typescript_parser);
    linkSqlite(sdk_application_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_application_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_application_tests.root_module.linkSystemLibrary("advapi32", .{});
        sdk_application_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-application-bootstrap-artifact", "Compile actual SDK platform/AI/manager/OS and full factory/session body anchors").dependOn(&b.addInstallArtifact(sdk_application_tests, .{}).step);
    b.step("test-native-sdk-application-bootstrap", "Execute actual SDK available bootstrap controls after explicit grant").dependOn(&b.addRunArtifact(sdk_application_tests).step);
    const sdk_management_http_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_management_http_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK management HTTP"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_management_http_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_management_http_tests.root_module, typescript_parser);
    linkSqlite(sdk_management_http_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_management_http_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_management_http_tests.root_module.linkSystemLibrary("advapi32", .{});
        sdk_management_http_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-management-http", "Compile actual management HTTP and genuine SDK owner readiness controls without running").dependOn(&b.addInstallArtifact(sdk_management_http_tests, .{}).step);
    b.step("test-native-sdk-management-http", "Run actual management HTTP controls only after an explicit qualification grant").dependOn(&b.addRunArtifact(sdk_management_http_tests).step);
    const sdk_owned_completion_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_owned_completion_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK owned completion"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_owned_completion_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_owned_completion_tests.root_module, typescript_parser);
    linkSqlite(sdk_owned_completion_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_owned_completion_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_owned_completion_tests.root_module.linkSystemLibrary("advapi32", .{});
        sdk_owned_completion_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-owned-completion", "Compile SDK owned outcome/cleanup controls without execution").dependOn(&b.addInstallArtifact(sdk_owned_completion_tests, .{}).step);
    b.step("test-native-sdk-owned-completion", "Run SDK owned cleanup controls only after explicit qualification grant").dependOn(&b.addRunArtifact(sdk_owned_completion_tests).step);
    const sdk_manager_worker_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_manager_worker_bootstrap_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK manager worker bootstrap"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_manager_worker_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_manager_worker_tests.root_module, typescript_parser);
    linkSqlite(sdk_manager_worker_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_manager_worker_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_manager_worker_tests.root_module.linkSystemLibrary("advapi32", .{});
        sdk_manager_worker_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-manager-worker-bootstrap", "Install actual worker manager projection controls without running").dependOn(&b.addInstallArtifact(sdk_manager_worker_tests, .{}).step);
    const sdk_guest_operation_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_guest_operation_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK guest boundary"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_guest_operation_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_guest_operation_tests.root_module, typescript_parser);
    linkSqlite(sdk_guest_operation_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_guest_operation_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_guest_operation_tests.root_module.linkSystemLibrary("advapi32", .{});
        sdk_guest_operation_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-guest-operation", "Compile SDK guest DATA/current producer controls without execution").dependOn(&b.addInstallArtifact(sdk_guest_operation_tests, .{}).step);
    const public_cli_args_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_public_cli_args_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Public CLI actual"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, public_cli_args_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, public_cli_args_tests.root_module, typescript_parser);
    linkSqlite(public_cli_args_tests.root_module, sqlite_lib_dir, sqlite_library);
    public_cli_args_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        public_cli_args_tests.root_module.linkSystemLibrary("advapi32", .{});
        public_cli_args_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-public-cli-args", "Install actual c268 public CLI controls without execution").dependOn(&b.addInstallArtifact(public_cli_args_tests, .{}).step);
    const public_theme_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_public_theme_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Public Theme actual"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, public_theme_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, public_theme_tests.root_module, typescript_parser);
    linkSqlite(public_theme_tests.root_module, sqlite_lib_dir, sqlite_library);
    public_theme_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        public_theme_tests.root_module.linkSystemLibrary("advapi32", .{});
        public_theme_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-public-theme", "Install actual c268 public Theme helper controls without execution").dependOn(&b.addInstallArtifact(public_theme_tests, .{}).step);
    const sdk_output_guard_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_output_guard_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Native stdout guard actual"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_output_guard_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_output_guard_tests.root_module, typescript_parser);
    linkSqlite(sdk_output_guard_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_output_guard_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_output_guard_tests.root_module.linkSystemLibrary("advapi32", .{});
        sdk_output_guard_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-output-guard", "Install actual c268 output guard controls without execution").dependOn(&b.addInstallArtifact(sdk_output_guard_tests, .{}).step);
    const public_print_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_public_print_mode_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Public print actual"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, public_print_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, public_print_tests.root_module, typescript_parser);
    linkSqlite(public_print_tests.root_module, sqlite_lib_dir, sqlite_library);
    public_print_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        public_print_tests.root_module.linkSystemLibrary("advapi32", .{});
        public_print_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-public-print-mode", "Install actual c268 public print and JSON mode controls without execution").dependOn(&b.addInstallArtifact(public_print_tests, .{}).step);
    const public_rpc_jsonl_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_public_rpc_jsonl_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Public RPC JSONL actual"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, public_rpc_jsonl_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, public_rpc_jsonl_tests.root_module, typescript_parser);
    linkSqlite(public_rpc_jsonl_tests.root_module, sqlite_lib_dir, sqlite_library);
    public_rpc_jsonl_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        public_rpc_jsonl_tests.root_module.linkSystemLibrary("advapi32", .{});
        public_rpc_jsonl_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-public-rpc-jsonl", "Install actual c268 RPC JSONL framing controls without execution").dependOn(&b.addInstallArtifact(public_rpc_jsonl_tests, .{}).step);
    const node_http_header_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_http_header_checks_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Node HTTP header checks"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, node_http_header_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_http_header_tests.root_module, typescript_parser);
    linkSqlite(node_http_header_tests.root_module, sqlite_lib_dir, sqlite_library);
    node_http_header_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_http_header_tests.root_module.linkSystemLibrary("advapi32", .{});
        node_http_header_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-http-header-checks", "Install actual HTTP token and header checks without execution").dependOn(&b.addInstallArtifact(node_http_header_tests, .{}).step);
    const node_http_incoming_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_http_incoming_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Node HTTP incoming"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, node_http_incoming_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_http_incoming_tests.root_module, typescript_parser);
    linkSqlite(node_http_incoming_tests.root_module, sqlite_lib_dir, sqlite_library);
    node_http_incoming_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_http_incoming_tests.root_module.linkSystemLibrary("advapi32", .{});
        node_http_incoming_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-http-incoming", "Install actual Node IncomingMessage and genuine Stream controls without execution").dependOn(&b.addInstallArtifact(node_http_incoming_tests, .{}).step);
    const ai_oauth_callback_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_callback_server_genuine_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"AI OAuth callback"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, ai_oauth_callback_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, ai_oauth_callback_tests.root_module, typescript_parser);
    linkSqlite(ai_oauth_callback_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_oauth_callback_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        ai_oauth_callback_tests.root_module.linkSystemLibrary("advapi32", .{});
        ai_oauth_callback_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-ai-oauth-callback-server", "Install actual callback Source and controlled import comparisons without execution").dependOn(&b.addInstallArtifact(ai_oauth_callback_tests, .{}).step);
    const ai_oauth_page_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_page_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"AI OAuth page"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, ai_oauth_page_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, ai_oauth_page_tests.root_module, typescript_parser);
    linkSqlite(ai_oauth_page_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_oauth_page_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        ai_oauth_page_tests.root_module.linkSystemLibrary("advapi32", .{});
        ai_oauth_page_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-ai-oauth-page", "Install genuine OAuth page controls without execution").dependOn(&b.addInstallArtifact(ai_oauth_page_tests, .{}).step);
    const vm_template_literal_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_template_literal_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"VM template literal"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, vm_template_literal_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, vm_template_literal_tests.root_module, typescript_parser);
    linkSqlite(vm_template_literal_tests.root_module, sqlite_lib_dir, sqlite_library);
    vm_template_literal_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        vm_template_literal_tests.root_module.linkSystemLibrary("advapi32", .{});
        vm_template_literal_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-vm-template-literal", "Install intrinsic eager template literal controls without execution").dependOn(&b.addInstallArtifact(vm_template_literal_tests, .{}).step);
    const vm_async_retirement_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_frame_retirement_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"VM async retirement"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, vm_async_retirement_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, vm_async_retirement_tests.root_module, typescript_parser);
    linkSqlite(vm_async_retirement_tests.root_module, sqlite_lib_dir, sqlite_library);
    vm_async_retirement_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        vm_async_retirement_tests.root_module.linkSystemLibrary("advapi32", .{});
        vm_async_retirement_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-vm-async-retirement", "Install actual suspended async frame retirement controls without execution").dependOn(&b.addInstallArtifact(vm_async_retirement_tests, .{}).step);
    const vm_array_append_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_vm_array_append_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"VM array append"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, vm_array_append_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, vm_array_append_tests.root_module, typescript_parser);
    linkSqlite(vm_array_append_tests.root_module, sqlite_lib_dir, sqlite_library);
    vm_array_append_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        vm_array_append_tests.root_module.linkSystemLibrary("advapi32", .{});
        vm_array_append_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-vm-array-append", "Install actual VM array spread and constructor apply controls without execution").dependOn(&b.addInstallArtifact(vm_array_append_tests, .{}).step);
    const vm_borrowed_bridges_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_vm_borrowed_bridges_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"VM borrowed bridges"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, vm_borrowed_bridges_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, vm_borrowed_bridges_tests.root_module, typescript_parser);
    linkSqlite(vm_borrowed_bridges_tests.root_module, sqlite_lib_dir, sqlite_library);
    vm_borrowed_bridges_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        vm_borrowed_bridges_tests.root_module.linkSystemLibrary("advapi32", .{});
        vm_borrowed_bridges_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-vm-borrowed-bridges", "Install actual VM constructor prototype, for-in and ordinary array-call controls without execution").dependOn(&b.addInstallArtifact(vm_borrowed_bridges_tests, .{}).step);
    const vm_sync_arguments_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_vm_sync_arguments_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"VM sync arguments"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, vm_sync_arguments_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, vm_sync_arguments_tests.root_module, typescript_parser);
    linkSqlite(vm_sync_arguments_tests.root_module, sqlite_lib_dir, sqlite_library);
    vm_sync_arguments_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        vm_sync_arguments_tests.root_module.linkSystemLibrary("advapi32", .{});
        vm_sync_arguments_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-vm-sync-arguments", "Install actual synchronous VM argument ownership controls without execution").dependOn(&b.addInstallArtifact(vm_sync_arguments_tests, .{}).step);
    const public_rpc_mode_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_public_rpc_mode_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Public RPC actual"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, public_rpc_mode_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, public_rpc_mode_tests.root_module, typescript_parser);
    linkSqlite(public_rpc_mode_tests.root_module, sqlite_lib_dir, sqlite_library);
    public_rpc_mode_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        public_rpc_mode_tests.root_module.linkSystemLibrary("advapi32", .{});
        public_rpc_mode_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-public-rpc-mode", "Install complete actual c268 RPC mode controls without execution").dependOn(&b.addInstallArtifact(public_rpc_mode_tests, .{}).step);
    const sdk_actual_paths_owner_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_paths_owner_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK actual paths owner"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_actual_paths_owner_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_actual_paths_owner_tests.root_module, typescript_parser);
    linkSqlite(sdk_actual_paths_owner_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_actual_paths_owner_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_actual_paths_owner_tests.root_module.linkSystemLibrary("advapi32", .{});
        sdk_actual_paths_owner_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-actual-paths-owner", "Install actual paths/filesystem owner controls without running").dependOn(&b.addInstallArtifact(sdk_actual_paths_owner_tests, .{}).step);
    const sdk_factory_retirement_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_factory_retirement_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK factory retirement"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_factory_retirement_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_factory_retirement_tests.root_module, typescript_parser);
    linkSqlite(sdk_factory_retirement_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_factory_retirement_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_factory_retirement_tests.root_module.linkSystemLibrary("advapi32", .{});
        sdk_factory_retirement_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-factory-retirement", "Install actual PackageManager factory retirement controls without running").dependOn(&b.addInstallArtifact(sdk_factory_retirement_tests, .{}).step);
    const sdk_package_af_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_package_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK package AF"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_package_af_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_package_af_tests.root_module, typescript_parser);
    linkSqlite(sdk_package_af_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_package_af_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_package_af_tests.root_module.linkSystemLibrary("advapi32", .{});
        sdk_package_af_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-package-af", "Compile actual package AF progress and continuation controls without execution").dependOn(&b.addInstallArtifact(sdk_package_af_tests, .{}).step);
    b.step("test-native-sdk-package-af", "Run actual package AF controls only after an explicit qualification grant").dependOn(&b.addRunArtifact(sdk_package_af_tests).step);
    const idle_settlement_identity_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_idle_settlement_identity_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native idle settlement"}, .use_llvm = use_llvm });
    linkQuickJs(b, idle_settlement_identity_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(idle_settlement_identity_tests.root_module, sqlite_lib_dir, sqlite_library);
    idle_settlement_identity_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-idle-settlement-identity", "Compile exact fatal identity and entered-finally controls for the idle settlement leaf").dependOn(&idle_settlement_identity_tests.step);
    b.step("test-native-sdk-idle-settlement-identity", "Exercise exact native reason retention across idle settlement finalizers").dependOn(&b.addRunArtifact(idle_settlement_identity_tests).step);
    const hook_helper_realasync_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_hook_helpers_realasync_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native hook helper"}, .use_llvm = use_llvm });
    linkQuickJs(b, hook_helper_realasync_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(hook_helper_realasync_tests.root_module, sqlite_lib_dir, sqlite_library);
    hook_helper_realasync_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-hook-helpers-realasync", "Compile four actual session hook helper bodies and focused controls").dependOn(&hook_helper_realasync_tests.step);
    b.step("test-native-sdk-hook-helpers-realasync", "Exercise exact await getter and fatal identity boundaries of four session hook helpers").dependOn(&b.addRunArtifact(hook_helper_realasync_tests).step);
    const sdk_exception_boundary_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_exception_boundary_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK boundary"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_exception_boundary_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(sdk_exception_boundary_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_exception_boundary_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-exception-boundary", "Compile SDK pending-exception ownership regressions").dependOn(&b.addInstallArtifact(sdk_exception_boundary_tests, .{}).step);
    b.step("test-native-sdk-exception-boundary", "Preserve raw property and conversion failures over stale SDK captures").dependOn(&b.addRunArtifact(sdk_exception_boundary_tests).step);
    const session_models_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_models_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session models"}, .use_llvm = use_llvm });
    linkQuickJs(b, session_models_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_models_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_models_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-models", "Compare original ordinary session model selection thinking levels scoped cycles and complete owner graphs").dependOn(&b.addRunArtifact(session_models_tests).step);
    b.step("build-native-sdk-session-models", "Compile model selection and thinking capability bodies separately from runtime deadlines").dependOn(&session_models_tests.step);
    const session_utilities_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_utilities_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session utilities"}, .use_llvm = use_llvm });
    linkQuickJs(b, session_utilities_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_utilities_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_utilities_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-utilities", "Compare original ordinary session transcript queries replacement contexts and complete owner graphs").dependOn(&b.addRunArtifact(session_utilities_tests).step);
    b.step("build-native-sdk-session-utilities", "Compile session utility bodies separately from runtime deadlines").dependOn(&session_utilities_tests.step);
    const session_request_auth_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_request_auth_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session request auth"}, .use_llvm = use_llvm });
    linkQuickJs(b, session_request_auth_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_request_auth_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_request_auth_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-request-auth", "Compare original ordinary session auth routing and branch selection with complete owner graphs").dependOn(&b.addRunArtifact(session_request_auth_tests).step);
    b.step("build-native-sdk-session-request-auth", "Compile session auth and routing bodies separately from runtime deadlines").dependOn(&session_request_auth_tests.step);
    const session_statistics_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_statistics_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session statistics"}, .use_llvm = use_llvm });
    linkQuickJs(b, session_statistics_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_statistics_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_statistics_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-statistics", "Compare ordinary session billing and context usage with original Source and complete owner graphs").dependOn(&b.addRunArtifact(session_statistics_tests).step);
    b.step("build-native-sdk-session-statistics", "Compile ordinary statistics and context usage separately from runtime deadlines").dependOn(&session_statistics_tests.step);
    const compaction_estimate_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_compaction_estimate_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK compaction estimate"}, .use_llvm = use_llvm });
    linkQuickJs(b, compaction_estimate_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(compaction_estimate_tests.root_module, sqlite_lib_dir, sqlite_library);
    compaction_estimate_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-compaction-estimate", "Compare original token heuristic VM coercions getters iterators and ownership").dependOn(&b.addRunArtifact(compaction_estimate_tests).step);
    b.step("build-native-sdk-compaction-estimate", "Compile original token heuristic independently of runtime deadlines").dependOn(&compaction_estimate_tests.step);
    const compaction_files_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_compaction_files_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK compaction files"}, .use_llvm = use_llvm });
    linkQuickJs(b, compaction_files_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(compaction_files_tests.root_module, sqlite_lib_dir, sqlite_library);
    compaction_files_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-compaction-files", "Compare original file-operation tracking and formatting with complete native ownership checks").dependOn(&b.addRunArtifact(compaction_files_tests).step);
    b.step("build-native-sdk-compaction-files", "Compile original file-operation tracking separately from runtime deadlines").dependOn(&compaction_files_tests.step);
    const live_projection_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_projection_live_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK live projection"}, .use_llvm = use_llvm });
    linkQuickJs(b, live_projection_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(live_projection_tests.root_module, sqlite_lib_dir, sqlite_library);
    live_projection_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-projection-live", "Compare original canonical projections live getter ordering and complete native ownership").dependOn(&b.addRunArtifact(live_projection_tests).step);
    b.step("build-native-sdk-session-projection-live", "Compile original canonical projections independently of runtime deadlines").dependOn(&live_projection_tests.step);
    const compaction_prepare_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_compaction_prepare_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK compaction prepare"}, .use_llvm = use_llvm });
    linkQuickJs(b, compaction_prepare_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(compaction_prepare_tests.root_module, sqlite_lib_dir, sqlite_library);
    compaction_prepare_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-compaction-prepare", "Compare original canonical compaction preparation and complete native owner graphs").dependOn(&b.addRunArtifact(compaction_prepare_tests).step);
    b.step("build-native-sdk-compaction-prepare", "Compile canonical compaction preparation separately from runtime deadlines").dependOn(&compaction_prepare_tests.step);
    const compaction_text_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_compaction_text_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK compaction text"}, .use_llvm = use_llvm });
    linkQuickJs(b, compaction_text_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(compaction_text_tests.root_module, sqlite_lib_dir, sqlite_library);
    compaction_text_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-compaction-text", "Compare original summary serialization and failure text with complete native owner graphs").dependOn(&b.addRunArtifact(compaction_text_tests).step);
    b.step("build-native-sdk-compaction-text", "Compile original summary serialization independently of runtime deadlines").dependOn(&compaction_text_tests.step);
    const body_collect_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_body_collect_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native body collector"}, .use_llvm = use_llvm });
    linkQuickJs(b, body_collect_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(body_collect_tests.root_module, sqlite_lib_dir, sqlite_library);
    body_collect_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-body-collect", "Verify retained response bytes large bodies decoding and cancellation ownership").dependOn(&b.addRunArtifact(body_collect_tests).step);
    b.step("build-native-body-collect", "Compile the shared response body collector independently").dependOn(&body_collect_tests.step);
    const ai_one_shot_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_one_shot_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI one shot"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_one_shot_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_one_shot_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_one_shot_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-one-shot", "Verify actual image and classifier facades and pure helper ownership").dependOn(&b.addRunArtifact(ai_one_shot_tests).step);
    b.step("build-native-ai-one-shot", "Compile actual image and classifier provider facades independently").dependOn(&ai_one_shot_tests.step);
    const ai_pi_messages_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_pi_messages_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI pi messages"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_pi_messages_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_pi_messages_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_pi_messages_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-pi-messages", "Verify literal Pi messages requests event conversion awaited callbacks and ownership").dependOn(&b.addRunArtifact(ai_pi_messages_tests).step);
    b.step("build-native-ai-pi-messages", "Compile the actual native Pi messages provider separately").dependOn(&ai_pi_messages_tests.step);
    const ai_oauth_anthropic_router_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_anthropic_openrouter_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI OAuth Anthropic OpenRouter"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_oauth_anthropic_router_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_oauth_anthropic_router_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_oauth_anthropic_router_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-oauth-anthropic-openrouter", "Compare genuine Source24 OAuth metadata prompts requests signals and retained credentials").dependOn(&b.addRunArtifact(ai_oauth_anthropic_router_tests).step);
    b.step("build-native-ai-oauth-anthropic-openrouter", "Compile actual Anthropic and OpenRouter OAuth owner graphs separately").dependOn(&ai_oauth_anthropic_router_tests.step);
    const ai_retry_call_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_retry_call_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI retry call"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_retry_call_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_retry_call_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_retry_call_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-retry-call", "Compare original assistant retry async behavior and complete native owner graphs").dependOn(&b.addRunArtifact(ai_retry_call_tests).step);
    b.step("build-native-ai-retry-call", "Compile original assistant retry separately from runtime deadlines").dependOn(&ai_retry_call_tests.step);
    const google_mistral_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_google_mistral_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI Google Mistral"}, .use_llvm = use_llvm });
    linkQuickJs(b, google_mistral_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(google_mistral_tests.root_module, sqlite_lib_dir, sqlite_library);
    google_mistral_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-google-mistral", "Compile actual Google Vertex Mistral facades before runtime qualification").dependOn(&google_mistral_tests.step);
    b.step("test-native-ai-google-mistral", "Compare actual Source Google Vertex Mistral request events callbacks and native ownership").dependOn(&b.addRunArtifact(google_mistral_tests).step);
    const google_mistral_component_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_google_mistral_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "Source30 request component", "Source30 terminal callback", "retained facade roots", "complete native facade allocation graph", "preflight preserves thrown guest" }, .use_llvm = use_llvm });
    linkQuickJs(b, google_mistral_component_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(google_mistral_component_tests.root_module, sqlite_lib_dir, sqlite_library);
    google_mistral_component_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-google-mistral-components", "Compile separate functional Source30 and ownership components without claiming full scheduling").dependOn(&google_mistral_component_tests.step);
    b.step("test-native-ai-google-mistral-components", "Compare Source30 functional components and strict ownership; full snapshots stay in the full target").dependOn(&b.addRunArtifact(google_mistral_component_tests).step);
    const source_paths_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_source_paths_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Source path cwd"}, .use_llvm = use_llvm });
    linkQuickJs(b, source_paths_tests.root_module, quickjs, sqlite_lib_dir);
    source_paths_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-source-path-cwd", "Compile original path helpers and live Node current-directory fallback").dependOn(&source_paths_tests.step);
    b.step("test-native-sdk-source-path-cwd", "Compare original40 path callbacks ordering identity and native allocation cleanup").dependOn(&b.addRunArtifact(source_paths_tests).step);
    const transcript_context_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_transcript_context_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI transcript context"}, .use_llvm = use_llvm });
    linkQuickJs(b, transcript_context_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(transcript_context_tests.root_module, sqlite_lib_dir, sqlite_library);
    transcript_context_tests.root_module.addImport("catalog_tool", catalog_tool);
    const claude5ab_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_claude_request_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "native Claude5ab Anthropic", "native Claude5ab request owner" } });
    linkQuickJs(b, claude5ab_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(claude5ab_tests.root_module, sqlite_lib_dir, sqlite_library);
    claude5ab_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-claude5ab", "Compile actual Anthropic and Converse request codecs").dependOn(&claude5ab_tests.step);
    b.step("test-native-ai-claude5ab", "Compare actual Source Claude requests streams callbacks and retained owner graphs").dependOn(&b.addRunArtifact(claude5ab_tests).step);
    const claude5ab_extended = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_claude_extended_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm, .filters = &.{ "native Claude5ab extended", "native constrained sampling", "native SDK nullable headers", "native node function preserves caught getter", "native Anthropic SDK errors" } });
    linkQuickJs(b, claude5ab_extended.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(claude5ab_extended.root_module, sqlite_lib_dir, sqlite_library);
    claude5ab_extended.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-claude5ab-extended", "Compile genuine Source16 Anthropic SDK wire federation retry and result-only replay").dependOn(&claude5ab_extended.step);
    b.step("test-native-ai-claude5ab-extended", "Compare genuine Source16 wire callbacks events results and configured strict-schema recursion guards").dependOn(&b.addRunArtifact(claude5ab_extended).step);
    const claude5ab_allocations = b.addTest(.{ .root_module = claude5ab_tests.root_module, .use_llvm = use_llvm, .filters = &.{"native Claude5ab every host allocation"} });
    b.step("build-native-ai-claude5ab-allocation", "Compile exhaustive Claude request allocation cleanup separately").dependOn(&claude5ab_allocations.step);
    b.step("test-native-ai-claude5ab-allocation", "Exercise every native host allocation failure in Claude request owner graphs").dependOn(&b.addRunArtifact(claude5ab_allocations).step);
    b.step("test-native-ai-transcript-context", "Compare original context normalization and complete native owner graphs").dependOn(&b.addRunArtifact(transcript_context_tests).step);
    b.step("build-native-ai-transcript-context", "Compile original context normalization independently of runtime deadlines").dependOn(&transcript_context_tests.step);
    const meta_oauth_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_meta_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI Meta OAuth"}, .use_llvm = use_llvm });
    linkQuickJs(b, meta_oauth_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(meta_oauth_tests.root_module, sqlite_lib_dir, sqlite_library);
    meta_oauth_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-oauth-meta", "Compare actual Source Meta device flow identity mint errors callbacks and ownership").dependOn(&b.addRunArtifact(meta_oauth_tests).step);
    b.step("build-native-ai-oauth-meta", "Compile the native Meta OAuth facade independently of runtime deadlines").dependOn(&meta_oauth_tests.step);
    const session_restore_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_restore_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK transcript restore"}, .use_llvm = use_llvm });
    linkQuickJs(b, session_restore_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_restore_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_restore_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-restore", "Compare latest transcript modifiers and live restore callbacks with original Source").dependOn(&b.addRunArtifact(session_restore_tests).step);
    b.step("build-native-sdk-session-restore", "Compile latest transcript restoration before runtime checks").dependOn(&session_restore_tests.step);
    const ai_compat_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_compat_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI compat"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_compat_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_compat_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_compat_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-compat", "Compare original global API registry and compat dispatch with captured dependencies").dependOn(&b.addRunArtifact(ai_compat_tests).step);
    b.step("build-native-ai-compat", "Compile native compat before bounded runtime checks").dependOn(&ai_compat_tests.step);
    const ai_env_keys_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_env_keys_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI env keys"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_env_keys_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_env_keys_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_env_keys_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-env-keys", "Compare actual provider/env/ADC/Bun discovery and complete native ownership").dependOn(&b.addRunArtifact(ai_env_keys_tests).step);
    b.step("build-native-ai-env-keys", "Compile env-key helpers before bounded runtime checks").dependOn(&ai_env_keys_tests.step);
    const crypto_random_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_crypto_random_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native secure Crypto"}, .use_llvm = use_llvm });
    linkQuickJs(b, crypto_random_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(crypto_random_tests.root_module, sqlite_lib_dir, sqlite_library);
    crypto_random_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-crypto-random", "Compare actual Node24 secure random typed-view behavior and native owner graphs").dependOn(&b.addRunArtifact(crypto_random_tests).step);
    b.step("build-native-crypto-random", "Compile secure random host independently of runtime checks").dependOn(&crypto_random_tests.step);
    const immediates_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_immediates_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native immediates", "native timer", "native promise delay", "native microtasks" }, .use_llvm = use_llvm });
    linkQuickJs(b, immediates_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(immediates_tests.root_module, sqlite_lib_dir, sqlite_library);
    immediates_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-immediates", "Compare actual Node24 Immediate check batches and real loopback I/O controls").dependOn(&b.addRunArtifact(immediates_tests).step);
    b.step("build-native-immediates", "Compile native Immediate check scheduler before bounded runtime controls").dependOn(&immediates_tests.step);
    const web_crypto_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_web_crypto_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native WebCrypto"}, .use_llvm = use_llvm });
    linkQuickJs(b, web_crypto_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(web_crypto_tests.root_module, sqlite_lib_dir, sqlite_library);
    web_crypto_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-web-crypto", "Compare genuine Node24 WebCrypto digest and secure random host observations").dependOn(&b.addRunArtifact(web_crypto_tests).step);
    b.step("build-native-web-crypto", "Compile Pi WebCrypto prerequisite independently of runtime controls").dependOn(&web_crypto_tests.step);
    const writable_stream_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_writable_stream_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native WritableStream actual Node24"}, .use_llvm = use_llvm });
    linkQuickJs(b, writable_stream_tests.root_module, quickjs, sqlite_lib_dir);
    writable_stream_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-writable-stream", "Compile genuine native WritableStream state-machine controls").dependOn(&writable_stream_tests.step);
    b.step("test-native-writable-stream", "Compare actual Node24 sink queues writers promises abort close backpressure and GC").dependOn(&b.addRunArtifact(writable_stream_tests).step);
    const readable_pipe_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_readable_pipe_source_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native readable pipe Source"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkQuickJs(b, readable_pipe_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(readable_pipe_tests.root_module, sqlite_lib_dir, sqlite_library);
    readable_pipe_tests.root_module.addImport("catalog_tool", catalog_tool);
    const readable_pipe_run = b.addRunArtifact(readable_pipe_tests);
    if (diagnostic_tests) readable_pipe_run.stdio = .inherit;
    b.step("test-native-readable-pipe-source", "Compare actual reader writer pipe and identity Transform ownership against all twenty genuine Node24 packets").dependOn(&readable_pipe_run.step);
    addCompileOnlyGroup(b, "build-hosted-native-readable-pipe-source", &.{"test-native-readable-pipe-source"});
    const readable_pipe_oom_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_readable_pipe_oom_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native readable pipe host OOM"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkQuickJs(b, readable_pipe_oom_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(readable_pipe_oom_tests.root_module, sqlite_lib_dir, sqlite_library);
    readable_pipe_oom_tests.root_module.addImport("catalog_tool", catalog_tool);
    const readable_pipe_oom_run = b.addRunArtifact(readable_pipe_oom_tests);
    if (diagnostic_tests) readable_pipe_oom_run.stdio = .inherit;
    b.step("test-native-readable-pipe-host-oom", "Reject actual pending pipe write after permanent host failure and free owned capabilities").dependOn(&readable_pipe_oom_run.step);
    addCompileOnlyGroup(b, "build-hosted-native-readable-pipe-host-oom", &.{"test-native-readable-pipe-host-oom"});
    const stream_exports_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_stream_exports_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native stream captured constructor exports"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkQuickJs(b, stream_exports_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(stream_exports_tests.root_module, sqlite_lib_dir, sqlite_library);
    stream_exports_tests.root_module.addImport("catalog_tool", catalog_tool);
    @import("tools/build_native_transform_compression.zig").link(b, stream_exports_tests.root_module);
    const stream_exports_run = b.addRunArtifact(stream_exports_tests);
    if (diagnostic_tests) stream_exports_run.stdio = .inherit;
    b.step("test-native-stream-captured-exports", "Preserve original Transform compression and identity pair constructors through guest mutation and GC").dependOn(&stream_exports_run.step);
    addCompileOnlyGroup(b, "build-hosted-native-stream-captured-exports", &.{"test-native-stream-captured-exports"});
    const stream_web_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_stream_web_assembly_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native stream web"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkQuickJs(b, stream_web_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(stream_web_tests.root_module, sqlite_lib_dir, sqlite_library);
    stream_web_tests.root_module.addImport("catalog_tool", catalog_tool);
    @import("tools/build_native_transform_compression.zig").link(b, stream_web_tests.root_module);
    const stream_web_run = b.addRunArtifact(stream_web_tests);
    if (diagnostic_tests) stream_web_run.stdio = .inherit;
    b.step("test-native-stream-web-assembly", "Exercise the actual seventeen native stream classes queue strategies and text state").dependOn(&stream_web_run.step);
    addCompileOnlyGroup(b, "build-hosted-native-stream-web-assembly", &.{"test-native-stream-web-assembly"});
    const stream_web_source_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_stream_web_source16_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native stream web Source16"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkQuickJs(b, stream_web_source_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(stream_web_source_tests.root_module, sqlite_lib_dir, sqlite_library);
    stream_web_source_tests.root_module.addImport("catalog_tool", catalog_tool);
    @import("tools/build_native_transform_compression.zig").link(b, stream_web_source_tests.root_module);
    const stream_web_source_run = b.addRunArtifact(stream_web_source_tests);
    if (diagnostic_tests) stream_web_source_run.stdio = .inherit;
    b.step("test-native-stream-web-source16", "Compare every unfiltered actual Node namespace queue and text Source16 packet").dependOn(&stream_web_source_run.step);
    addCompileOnlyGroup(b, "build-hosted-native-stream-web-source16", &.{"test-native-stream-web-source16"});
    const classic_stream_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_stream_classic_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native classic stream"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkQuickJs(b, classic_stream_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(classic_stream_tests.root_module, sqlite_lib_dir, sqlite_library);
    linkTypeScriptParser(b, classic_stream_tests.root_module, typescript_parser);
    classic_stream_tests.root_module.addImport("catalog_tool", catalog_tool);
    @import("tools/build_native_transform_compression.zig").link(b, classic_stream_tests.root_module);
    const classic_stream_run = b.addRunArtifact(classic_stream_tests);
    if (diagnostic_tests) classic_stream_run.stdio = .inherit;
    b.step("test-native-node-stream-classic", "Exercise actual classic streams against original consumers and fail closed until complete genuine Node Source20 capture").dependOn(&classic_stream_run.step);
    addCompileOnlyGroup(b, "build-hosted-native-node-stream-classic", &.{"test-native-node-stream-classic"});
    b.step("build-native-node-stream-classic-artifact", "Install the compiled classic stream test artifact for metadata-only verification").dependOn(&b.addInstallArtifact(classic_stream_tests, .{}).step);
    const classic_iterator_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_stream_iterator_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native classic iterator"}, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkQuickJs(b, classic_iterator_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(classic_iterator_tests.root_module, sqlite_lib_dir, sqlite_library);
    classic_iterator_tests.root_module.addImport("catalog_tool", catalog_tool);
    const classic_iterator_run = b.addRunArtifact(classic_iterator_tests);
    if (diagnostic_tests) classic_iterator_run.stdio = .inherit;
    b.step("test-native-node-stream-classic-iterator", "Exercise genuine Readable AsyncGenerator consumption and required Node pipeline acknowledgement with complete original Source14 controls").dependOn(&classic_iterator_run.step);
    addCompileOnlyGroup(b, "build-hosted-native-node-stream-classic-iterator", &.{"test-native-node-stream-classic-iterator"});
    b.step("build-native-node-stream-classic-iterator-artifact", "Install the compiled classic iterator test artifact for metadata-only verification").dependOn(&b.addInstallArtifact(classic_iterator_tests, .{}).step);
    const classic_writer_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_fs_write_stream_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native classic writer", "native classic construct ordinary", "native writer retry SystemError", "native filesystem operation captures" }, .use_llvm = use_llvm, .test_runner = lifecycle_test_runner });
    linkQuickJs(b, classic_writer_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(classic_writer_tests.root_module, sqlite_lib_dir, sqlite_library);
    classic_writer_tests.root_module.addImport("catalog_tool", catalog_tool);
    @import("tools/build_native_transform_compression.zig").link(b, classic_writer_tests.root_module);
    const classic_writer_run = b.addRunArtifact(classic_writer_tests);
    if (diagnostic_tests) classic_writer_run.stdio = .inherit;
    b.step("test-native-node-fs-write-stream", "Exercise real file pipeline IO and exact completion exception/task shutdown ownership; Windows CRT selection remains guarded").dependOn(&classic_writer_run.step);
    addCompileOnlyGroup(b, "build-hosted-native-node-fs-write-stream", &.{"test-native-node-fs-write-stream"});
    b.step("build-native-node-fs-write-stream-artifact", "Install all reviewed writer controls for metadata-only verification").dependOn(&b.addInstallArtifact(classic_writer_tests, .{}).step);
    const ai_provider_helpers_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_provider_helpers_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI provider helpers"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_provider_helpers_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_provider_helpers_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_provider_helpers_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-provider-helpers", "Compare actual AI provider text estimates thinking and simple options with shared native dependencies").dependOn(&b.addRunArtifact(ai_provider_helpers_tests).step);
    b.step("build-native-ai-provider-helpers", "Compile original provider prerequisites before bounded runtime checks").dependOn(&ai_provider_helpers_tests.step);
    const oauth_callback_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_callback_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native OAuth callback"}, .use_llvm = use_llvm });
    linkQuickJs(b, oauth_callback_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(oauth_callback_tests.root_module, sqlite_lib_dir, sqlite_library);
    oauth_callback_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-oauth-callback", "Compare genuine Source callback pages errors lifecycle and manual races").dependOn(&b.addRunArtifact(oauth_callback_tests).step);
    b.step("build-native-ai-oauth-callback", "Compile shared callback server and owner RPC barrier").dependOn(&oauth_callback_tests.step);
    const ai_oauth_loader_graph_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_loader_graph_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native OAuth loader graph"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_oauth_loader_graph_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_oauth_loader_graph_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_oauth_loader_graph_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-oauth-loader-graph", "Validate actual nine OAuth flow modules shared loader identity and GC").dependOn(&b.addRunArtifact(ai_oauth_loader_graph_tests).step);
    b.step("build-native-ai-oauth-loader-graph", "Compile genuine OAuth flow import graph without network operations").dependOn(&ai_oauth_loader_graph_tests.step);
    const ai_auth_helpers_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_auth_helpers_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI auth helpers"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_auth_helpers_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_auth_helpers_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_auth_helpers_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-auth-helpers", "Validate actual native auth helper async identity and owned inputs").dependOn(&b.addRunArtifact(ai_auth_helpers_tests).step);
    b.step("build-native-ai-auth-helpers", "Compile public native auth helpers independently of OAuth network flows").dependOn(&ai_auth_helpers_tests.step);
    const sdk_public_extension_helpers = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_sdk_public_extension_helpers_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"SDK public extension helpers"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_extension_helpers.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_extension_helpers.root_module, typescript_parser);
    linkSqlite(sdk_public_extension_helpers.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_extension_helpers.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_public_extension_helpers.root_module.linkSystemLibrary("advapi32", .{});
        sdk_public_extension_helpers.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-public-extension-helpers", "Compile actual public extension helper controls without execution")
        .dependOn(&b.addInstallArtifact(sdk_public_extension_helpers, .{}).step);

    const sdk_public_truncation = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_sdk_public_truncation_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"SDK public truncation"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_truncation.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_truncation.root_module, typescript_parser);
    linkSqlite(sdk_public_truncation.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_truncation.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_public_truncation.root_module.linkSystemLibrary("advapi32", .{});
        sdk_public_truncation.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-public-truncation", "Compile actual public truncation controls without execution")
        .dependOn(&b.addInstallArtifact(sdk_public_truncation, .{}).step);

    const sdk_remote_catalog_genuine_af = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_sdk_remote_catalog_genuine_af_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{"SDK RemoteCatalog"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_remote_catalog_genuine_af.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_remote_catalog_genuine_af.root_module, typescript_parser);
    linkSqlite(sdk_remote_catalog_genuine_af.root_module, sqlite_lib_dir, sqlite_library);
    sdk_remote_catalog_genuine_af.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_remote_catalog_genuine_af.root_module.linkSystemLibrary("advapi32", .{});
        sdk_remote_catalog_genuine_af.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-remote-catalog-genuine-af", "Compile actual RemoteCatalog controls without execution")
        .dependOn(&b.addInstallArtifact(sdk_remote_catalog_genuine_af, .{}).step);

    const ai_auth_helper_genuine_af = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_ai_auth_helper_genuine_af_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{ "AI auth helper genuine AF", "AI auth successor" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, ai_auth_helper_genuine_af.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, ai_auth_helper_genuine_af.root_module, typescript_parser);
    linkSqlite(ai_auth_helper_genuine_af.root_module, sqlite_lib_dir, sqlite_library);
    ai_auth_helper_genuine_af.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        ai_auth_helper_genuine_af.root_module.linkSystemLibrary("advapi32", .{});
        ai_auth_helper_genuine_af.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-ai-auth-helper-genuine-af", "Compile genuine auth helper controls without execution")
        .dependOn(&b.addInstallArtifact(ai_auth_helper_genuine_af, .{}).step);

    const ai_anthropic_auth_genuine_af = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_ai_provider_anthropic_auth_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = &.{ "Anthropic actual auth" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, ai_anthropic_auth_genuine_af.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, ai_anthropic_auth_genuine_af.root_module, typescript_parser);
    linkSqlite(ai_anthropic_auth_genuine_af.root_module, sqlite_lib_dir, sqlite_library);
    ai_anthropic_auth_genuine_af.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        ai_anthropic_auth_genuine_af.root_module.linkSystemLibrary("advapi32", .{});
        ai_anthropic_auth_genuine_af.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-ai-anthropic-auth-genuine-af", "Compile actual Anthropic auth controls without execution")
        .dependOn(&b.addInstallArtifact(ai_anthropic_auth_genuine_af, .{}).step);

    const subscription_oauth_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_subscriptions_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native subscription OAuth"}, .use_llvm = use_llvm });
    linkQuickJs(b, subscription_oauth_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(subscription_oauth_tests.root_module, sqlite_lib_dir, sqlite_library);
    subscription_oauth_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-oauth-subscriptions", "Compare genuine Source Copilot Kimi and xAI OAuth public flows and owner roots").dependOn(&b.addRunArtifact(subscription_oauth_tests).step);
    b.step("build-native-ai-oauth-subscriptions", "Compile actual native subscription OAuth facades separately from runtime").dependOn(&subscription_oauth_tests.step);
    const ai_http_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_http_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI HTTP"}, .use_llvm = use_llvm });
    const ai_oauth_chatgpt_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_chatgpt_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI ChatGPT"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_oauth_chatgpt_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_oauth_chatgpt_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_oauth_chatgpt_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-oauth-chatgpt", "Compare ChatGPT dynamic client OAuth facade and owned callback/HTTP behavior").dependOn(&b.addRunArtifact(ai_oauth_chatgpt_tests).step);
    b.step("build-native-ai-oauth-chatgpt", "Compile ChatGPT native OAuth facade independently").dependOn(&ai_oauth_chatgpt_tests.step);
    const oauth_nine_flow_build = b.step("build-native-ai-oauth-nine-flow", "Compile the actual nine OAuth flow replays and shared loader graph");
    const oauth_nine_flow_test = b.step("test-native-ai-oauth-nine-flow", "Replay genuine Source224 provider observations plus Source18 loader identity and owned GC/wire checks");
    inline for (.{ "loader-graph", "anthropic-openrouter", "chatgpt", "codex-radius", "meta", "subscriptions" }) |suffix| {
        oauth_nine_flow_build.dependOn(&b.top_level_steps.get("build-native-ai-oauth-" ++ suffix).?.step);
        oauth_nine_flow_test.dependOn(&b.top_level_steps.get("test-native-ai-oauth-" ++ suffix).?.step);
    }
    linkQuickJs(b, ai_http_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_http_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_http_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-http", "Validate owned raw HTTP/SSE transport cancellation teardown and original wire fidelity").dependOn(&b.addRunArtifact(ai_http_tests).step);
    b.step("build-native-ai-http", "Compile native raw transport and narrow owner hooks before runtime").dependOn(&ai_http_tests.step);
    const ai_responses_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_responses_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Responses"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_responses_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_responses_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_responses_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-responses", "Compare actual Responses factories with Source18 and SourceRetry14 request and stream observations").dependOn(&b.addRunArtifact(ai_responses_tests).step);
    b.step("build-native-ai-responses", "Compile ordered Responses factories before bounded runtime checks").dependOn(&ai_responses_tests.step);
    const ai_codex_socket_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_codex_socket_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Codex socket"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_codex_socket_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_codex_socket_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_codex_socket_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-codex-socket-wire", "Verify actual RFC6455 transport against captured Source route headers and continuation frames").dependOn(&b.addRunArtifact(ai_codex_socket_tests).step);
    b.step("build-native-ai-codex-socket-wire", "Compile the owned Codex raw socket wire component").dependOn(&ai_codex_socket_tests.step);
    const ae7_json_transform_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_ae7_json_transform_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native ae7 JSON39"}, .use_llvm = use_llvm });
    linkQuickJs(b, ae7_json_transform_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ae7_json_transform_tests.root_module, sqlite_lib_dir, sqlite_library);
    ae7_json_transform_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-ae7-json-transform", "Compile fresh actual ae7 JSON39 and thinking DROP12 caller parity").dependOn(&ae7_json_transform_tests.step);
    b.step("test-native-ai-ae7-json-transform", "Compare genuine Source51 JSON error origins and latest cross-model thinking DROP ordering").dependOn(&b.addRunArtifact(ae7_json_transform_tests).step);
    const openai_sdk_stream_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_openai_sdk_stream_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native OpenAI SDK"}, .use_llvm = use_llvm });
    linkQuickJs(b, openai_sdk_stream_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(openai_sdk_stream_tests.root_module, sqlite_lib_dir, sqlite_library);
    openai_sdk_stream_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-openai-sdk-stream", "Compile actual pinned SDK chunk SSE and item generator bodies").dependOn(&openai_sdk_stream_tests.step);
    b.step("test-native-ai-openai-sdk-stream", "Compare genuine SDKProducer16 framing cleanup queues thenables raw exceptions and GC").dependOn(&b.addRunArtifact(openai_sdk_stream_tests).step);
    const openai_full58_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_openai_full58_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native OpenAI original Source58"}, .use_llvm = use_llvm });
    linkQuickJs(b, openai_full58_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(openai_full58_tests.root_module, sqlite_lib_dir, sqlite_library);
    openai_full58_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-openai-full58", "Compile original Source58 actual API Models Kimi graph and complete raw wire diagnostics").dependOn(&openai_full58_tests.step);
    b.step("test-native-ai-openai-full58", "Compare all original58 snapshots raw request bytes headers deep JSON and image split").dependOn(&b.addRunArtifact(openai_full58_tests).step);
    const actual_provider_factories_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_provider_factories_source_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native actual provider factories"}, .use_llvm = use_llvm });
    linkQuickJs(b, actual_provider_factories_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(actual_provider_factories_tests.root_module, sqlite_lib_dir, sqlite_library);
    actual_provider_factories_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-actual-provider-factories", "Compile actual provider factory Source92 qualification independently of runtime").dependOn(&actual_provider_factories_tests.step);
    b.step("test-native-actual-provider-factories", "Replay genuine Source92 over actual Models providers APIs and wrappers").dependOn(&b.addRunArtifact(actual_provider_factories_tests).step);
    const actual_models_class_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_models_class_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native actual Models class"}, .use_llvm = use_llvm });
    linkQuickJs(b, actual_models_class_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(actual_models_class_tests.root_module, sqlite_lib_dir, sqlite_library);
    actual_models_class_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-actual-models-class", "Compile original Source18 over actual ordinary Models class").dependOn(&actual_models_class_tests.step);
    b.step("test-native-actual-models-class", "Replay original Source18 ordinary Models receivers and promises").dependOn(&b.addRunArtifact(actual_models_class_tests).step);
    const await_rejection_data_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_await_rejection_data_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Await DATA"}, .use_llvm = use_llvm });
    linkQuickJs(b, await_rejection_data_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(await_rejection_data_tests.root_module, sqlite_lib_dir, sqlite_library);
    await_rejection_data_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-await-rejection-data", "Compile rejected DATA versus actual producer event regressions").dependOn(&await_rejection_data_tests.step);
    b.step("test-native-await-rejection-data", "Check rejected DATA catch finally raw identity current events allocator cancellation and C3 action frontier").dependOn(&b.addRunArtifact(await_rejection_data_tests).step);
    const async_rejected_allocation_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_rejected_allocation_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native async rejected allocation"}, .use_llvm = use_llvm });
    linkQuickJs(b, async_rejected_allocation_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(async_rejected_allocation_tests.root_module, sqlite_lib_dir, sqlite_library);
    async_rejected_allocation_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-async-rejected-allocation", "Compile explicit rejected native allocation boundary ownership checks").dependOn(&async_rejected_allocation_tests.step);
    b.step("test-native-async-rejected-allocation", "Check original OOM identity historical tags user lookalikes u64 wrap and real resumed job escape").dependOn(&b.addRunArtifact(async_rejected_allocation_tests).step);
    const promise_forwarding_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_promise_reaction_forwarding_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Promise forwarding"}, .use_llvm = use_llvm });
    linkQuickJs(b, promise_forwarding_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(promise_forwarding_tests.root_module, sqlite_lib_dir, sqlite_library);
    promise_forwarding_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-promise-reaction-forwarding", "Compile genuine VM Promise rejection DATA forwarding controls").dependOn(&promise_forwarding_tests.step);
    const install_promise_forwarding = b.addInstallArtifact(promise_forwarding_tests, .{ .dest_sub_path = b.fmt("native-promise-reaction-forwarding{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) });
    b.step("build-native-promise-reaction-forwarding-artifact", "Install the same genuine VM Promise forwarding control artifact without execution").dependOn(&install_promise_forwarding.step);
    b.step("test-native-promise-reaction-forwarding", "Check absent handlers preserve rejection DATA while actual native fatal handlers escape").dependOn(&b.addRunArtifact(promise_forwarding_tests).step);
    const openai_tool_output4dd_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_openai_tool_output4dd_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native OpenAI4dd tool output"}, .use_llvm = use_llvm });
    linkQuickJs(b, openai_tool_output4dd_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(openai_tool_output4dd_tests.root_module, sqlite_lib_dir, sqlite_library);
    openai_tool_output4dd_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-openai-tool-output4dd", "Compile latest tool-output whitespace and live trim coercion controls").dependOn(&openai_tool_output4dd_tests.step);
    b.step("test-native-ai-openai-tool-output4dd", "Check tool placeholders original text live trim order and raw throws").dependOn(&b.addRunArtifact(openai_tool_output4dd_tests).step);
    const google_tool_output4dd_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_google_tool_output4dd_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native Google4dd"}, .use_llvm = use_llvm });
    linkQuickJs(b, google_tool_output4dd_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(google_tool_output4dd_tests.root_module, sqlite_lib_dir, sqlite_library);
    google_tool_output4dd_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-google-tool-output4dd", "Compile latest Google tool-output whitespace and live trim coercion controls").dependOn(&google_tool_output4dd_tests.step);
    b.step("test-native-ai-google-tool-output4dd", "Check Google tool placeholders original text live trim order and raw throws").dependOn(&b.addRunArtifact(google_tool_output4dd_tests).step);
    const strict_schema_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_constrained_sampling_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native constrained sampling"}, .use_llvm = use_llvm });
    linkQuickJs(b, strict_schema_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(strict_schema_tests.root_module, sqlite_lib_dir, sqlite_library);
    strict_schema_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-constrained-sampling", "Compile shared native strict schema VM stack guard and raw exceptions").dependOn(&strict_schema_tests.step);
    b.step("test-native-ai-constrained-sampling", "Check configured VM guard on both walks and retain guest predicate/getter identities").dependOn(&b.addRunArtifact(strict_schema_tests).step);
    const ai_bedrock_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_bedrock_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI Bedrock"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_bedrock_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_bedrock_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_bedrock_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-bedrock", "Compare actual native Bedrock facade against genuine Source5ab SDK wire and hook traces").dependOn(&b.addRunArtifact(ai_bedrock_tests).step);
    b.step("build-native-ai-bedrock", "Compile private native Bedrock credential and binary EventStream adapters").dependOn(&ai_bedrock_tests.step);
    const ai_bedrock18_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_bedrock18_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI Bedrock"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_bedrock18_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_bedrock18_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_bedrock18_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-bedrock18", "Preserve Source14 gates and compare Source18 exact SDK requests and streamSimple traces").dependOn(&b.addRunArtifact(ai_bedrock18_tests).step);
    b.step("build-native-ai-bedrock18", "Compile Bedrock Source18 comparison and owned credential process cleanup").dependOn(&ai_bedrock18_tests.step);
    const ai_bedrock_credentials_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_bedrock_credentials_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native AI Bedrock", "native login DPoP" }, .use_llvm = use_llvm });
    linkQuickJs(b, ai_bedrock_credentials_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_bedrock_credentials_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_bedrock_credentials_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-ai-bedrock-credentials", "Compile owned AWS credentials against actual SDK Source25").dependOn(&ai_bedrock_credentials_tests.step);
    b.step("test-native-ai-bedrock-credentials", "Compare21 actual SDK credential outcomes plus empty bearer and DPoP checks").dependOn(&b.addRunArtifact(ai_bedrock_credentials_tests).step);
    const ai_json_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_json_parse_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI JSON"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_json_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_json_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_json_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-json-parse", "Compare original b06 final JSON helpers and intrinsic delegate error origin").dependOn(&b.addRunArtifact(ai_json_tests).step);
    b.step("build-native-ai-json-parse", "Compile native final JSON helpers and scoped C parser diagnostics").dependOn(&ai_json_tests.step);
    const native_generator_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_generator_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native async generator functional", "native AI JSON actual OpenAI request builder", "native AI JSON OpenAI decoder", "native AI JSON helpers and native partial fallback", "native AI JSON genuine b06 delegates", "native AI JSON private hooks", "native AI JSON ordinary no-hook", "native pi-ai EventStream exports", "native AssistantMessageEventStream genuine Source result-only producer retains more than64 events", "native provider validation", "native provider cancellation" }, .use_llvm = use_llvm });
    linkQuickJs(b, native_generator_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_generator_tests.root_module, sqlite_lib_dir, sqlite_library);
    native_generator_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-async-generator", "Compile private native-body QuickJS AsyncGenerator hook review tests").dependOn(&native_generator_tests.step);
    b.step("test-native-async-generator", "Verify intrinsic generator queue Await raw identity realms and targeted ownership failures").dependOn(&b.addRunArtifact(native_generator_tests).step);
    const native_generator_gpa_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_generator_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native async generator host GPA"}, .use_llvm = use_llvm });
    linkQuickJs(b, native_generator_gpa_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_generator_gpa_tests.root_module, sqlite_lib_dir, sqlite_library);
    native_generator_gpa_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-async-generator-gpa", "Compile native async generator host allocation sweep separately").dependOn(&native_generator_gpa_tests.step);
    b.step("test-native-async-generator-gpa", "Measure complete host allocation failure coverage independently").dependOn(&b.addRunArtifact(native_generator_gpa_tests).step);
    const live_event_stream_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_event_stream_live_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native live EventStream", "native node function preserves", "native node method retains", "native async generator functional" }, .use_llvm = use_llvm });
    linkQuickJs(b, live_event_stream_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(live_event_stream_tests.root_module, sqlite_lib_dir, sqlite_library);
    live_event_stream_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-event-stream-live", "Compile actual live-field EventStream Source27 and native generator integration").dependOn(&live_event_stream_tests.step);
    b.step("test-native-event-stream-live", "Compare genuine Source27 fields queues metadata GC and tagged allocation boundaries").dependOn(&b.addRunArtifact(live_event_stream_tests).step);
    const production_event_stream_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_event_stream_live_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native live EventStream", "native node function preserves", "native node method retains", "native async generator functional", "native pi-ai EventStream", "native EventStream allocation", "native terminal admission", "native AssistantMessageEventStream genuine Source result-only", "native provider validation", "native provider cancellation", "native AgentLoop private real eight original Source636", "native AgentLoop private real three original Source639" }, .use_llvm = use_llvm });
    linkQuickJs(b, production_event_stream_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(production_event_stream_tests.root_module, sqlite_lib_dir, sqlite_library);
    production_event_stream_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-event-stream-production", "Compile actual production pi-ai EventStream installation and retained AgentLoop consumers").dependOn(&production_event_stream_tests.step);
    b.step("test-native-event-stream-production", "Compare Source27 through production exports and retain raw fatal queue allocation cancellation and AgentLoop traces").dependOn(&b.addRunArtifact(production_event_stream_tests).step);
    const native_generator_oom_diagnostic = b.addTest(.{ .name = "native-generator-oom-diagnostic", .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_generator_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native async generator functional raw VM allocation"}, .use_llvm = use_llvm });
    linkQuickJs(b, native_generator_oom_diagnostic.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_generator_oom_diagnostic.root_module, sqlite_lib_dir, sqlite_library);
    native_generator_oom_diagnostic.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-async-generator-oom-diagnostic", "Install targeted VM OOM artifact for owned direct-run leak diagnostics").dependOn(&b.addInstallArtifact(native_generator_oom_diagnostic, .{}).step);
    const ai_uuid_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_uuid_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AI UUID"}, .use_llvm = use_llvm });
    linkQuickJs(b, ai_uuid_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(ai_uuid_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_uuid_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-ai-uuid", "Compare original UUIDv7 sequence clock and mutable guest hooks with native ownership").dependOn(&b.addRunArtifact(ai_uuid_tests).step);
    b.step("build-native-ai-uuid", "Compile original UUIDv7 separately from runtime checks").dependOn(&ai_uuid_tests.step);
    const complete_summary_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_complete_summarization_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native complete summarization"}, .use_llvm = use_llvm });
    linkQuickJs(b, complete_summary_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(complete_summary_tests.root_module, sqlite_lib_dir, sqlite_library);
    complete_summary_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-complete-summarization", "Compare actual summarization request orchestration with module-bound native dependencies").dependOn(&b.addRunArtifact(complete_summary_tests).step);
    b.step("build-native-sdk-complete-summarization", "Compile summarization request ownership separately from runtime checks").dependOn(&complete_summary_tests.step);
    const summary_generation_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_summary_generation_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native summary generation"}, .use_llvm = use_llvm });
    linkQuickJs(b, summary_generation_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(summary_generation_tests.root_module, sqlite_lib_dir, sqlite_library);
    summary_generation_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-summary-generation", "Compare original summaries and full prepared compaction including split turns and native ownership").dependOn(&b.addRunArtifact(summary_generation_tests).step);
    b.step("build-native-sdk-summary-generation", "Compile full summary generation and prepared compaction independently").dependOn(&summary_generation_tests.step);
    const latest_summary45_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_latest4dd_summary_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native latest4dd summary45"}, .use_llvm = use_llvm });
    linkQuickJs(b, latest_summary45_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(latest_summary45_tests.root_module, sqlite_lib_dir, sqlite_library);
    latest_summary45_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-latest4dd-summary45", "Compile latest Source replay with unchanged original45 callers and comparisons").dependOn(&latest_summary45_tests.step);
    b.step("test-native-sdk-latest4dd-summary45", "Compare genuine latest Source45 with actual compat providers Models and summary bindings").dependOn(&b.addRunArtifact(latest_summary45_tests).step);
    const latest_summary30_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_latest4dd_summary_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native latest4dd summary30"}, .use_llvm = use_llvm });
    linkQuickJs(b, latest_summary30_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(latest_summary30_tests.root_module, sqlite_lib_dir, sqlite_library);
    latest_summary30_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-latest4dd-summary30", "Compile all latest summary option getter and default-map observations").dependOn(&latest_summary30_tests.step);
    b.step("test-native-sdk-latest4dd-summary30", "Compare genuine latest Source30 without maximum or getter normalization").dependOn(&b.addRunArtifact(latest_summary30_tests).step);
    const registry_composition_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_registry_composition_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native private registry"}, .use_llvm = use_llvm });
    linkQuickJs(b, registry_composition_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(registry_composition_tests.root_module, sqlite_lib_dir, sqlite_library);
    registry_composition_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-registry-composition", "Compile real private session constructor registry and hook composition").dependOn(&registry_composition_tests.step);
    b.step("test-native-sdk-registry-composition", "Expose actual Original64 behavior and strict Source166 gaps without missing-method placeholders").dependOn(&b.addRunArtifact(registry_composition_tests).step);
    const session_integration_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_integration_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native private registry integrated", "native private registry full constructor matches" }, .use_llvm = use_llvm });
    linkQuickJs(b, session_integration_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_integration_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_integration_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-session-integration", "Compile integrated session constructor regression and fourteen new method descriptors").dependOn(&session_integration_tests.step);
    b.step("test-native-sdk-session-integration", "Verify integrated Source64 behavior and installed method descriptors while reporting remaining gaps").dependOn(&b.addRunArtifact(session_integration_tests).step);

    const production_prerequisite_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_production_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native production constructor"}, .use_llvm = use_llvm });
    linkQuickJs(b, production_prerequisite_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(production_prerequisite_tests.root_module, sqlite_lib_dir, sqlite_library);
    production_prerequisite_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-production-prerequisites", "Compile ordinary constructor namespace guards and genuine declaration order checks").dependOn(&production_prerequisite_tests.step);
    b.step("test-native-sdk-production-prerequisites", "Verify required namespace guards and Source166 order; positive factory qualification remains separate").dependOn(&b.addRunArtifact(production_prerequisite_tests).step);

    const reload_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_reload_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native ordinary reload"}, .use_llvm = use_llvm });
    linkQuickJs(b, reload_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(reload_tests.root_module, sqlite_lib_dir, sqlite_library);
    reload_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-session-reload", "Compile ordinary reload with actual shared provider registry reset").dependOn(&reload_tests.step);
    b.step("test-native-sdk-session-reload", "Compare actual upstream reload ordering and failure boundaries").dependOn(&b.addRunArtifact(reload_tests).step);

    const bindings_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_bindings_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native ordinary extension bindings"}, .use_llvm = use_llvm });
    linkQuickJs(b, bindings_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(bindings_tests.root_module, sqlite_lib_dir, sqlite_library);
    bindings_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-session-bindings", "Compile ordinary session extension binding and resource discovery bodies").dependOn(&bindings_tests.step);
    b.step("test-native-sdk-session-bindings", "Compare actual upstream extension binding and discovered resource ordering").dependOn(&b.addRunArtifact(bindings_tests).step);
    const boundary_tests = b.addTest(.{ .name = "sdk-boundaries-test", .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_boundaries_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK boundaries"}, .use_llvm = use_llvm });
    linkQuickJs(b, boundary_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(boundary_tests.root_module, sqlite_lib_dir, sqlite_library);
    boundary_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-boundaries", "Compile actual session boundary and nested tool bodies").dependOn(&b.addInstallArtifact(boundary_tests, .{}).step);
    b.step("test-native-sdk-boundaries", "Compare latest Source session boundary and nested pipeline behavior").dependOn(&b.addRunArtifact(boundary_tests).step);

    const resource_paths_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_resource_paths_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native real resource paths"}, .use_llvm = use_llvm });
    linkQuickJs(b, resource_paths_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(resource_paths_tests.root_module, sqlite_lib_dir, sqlite_library);
    resource_paths_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-resource-paths", "Compile real discovered skill prompt and theme path loading").dependOn(&resource_paths_tests.step);
    b.step("test-native-sdk-resource-paths", "Compare actual upstream loader path merging overrides and filesystem resources").dependOn(&b.addRunArtifact(resource_paths_tests).step);

    const active_tools_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_active_tools_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native ordinary active tool selection"}, .use_llvm = use_llvm });
    linkQuickJs(b, active_tools_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(active_tools_tests.root_module, sqlite_lib_dir, sqlite_library);
    active_tools_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-session-active-tools", "Compile ordinary active tool selection over registry and loadout dependencies").dependOn(&active_tools_tests.step);
    b.step("test-native-sdk-session-active-tools", "Compare actual upstream pending tool clearing and real loadout composition").dependOn(&b.addRunArtifact(active_tools_tests).step);
    const navigate_tests = b.addTest(.{ .name = "sdk-session-navigate-test", .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_navigate_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK navigate"}, .use_llvm = use_llvm });
    linkQuickJs(b, navigate_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(navigate_tests.root_module, sqlite_lib_dir, sqlite_library);
    navigate_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-session-navigate", "Compile actual tree navigation and branch summary collaborators").dependOn(&b.addInstallArtifact(navigate_tests, .{}).step);
    b.step("test-native-sdk-session-navigate", "Compare latest Source tree navigation and real branch summarization").dependOn(&b.addRunArtifact(navigate_tests).step);
    const runtime_credentials_production_tests = b.addTest(.{ .name = "sdk-runtime-credentials-production-test", .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_runtime_credentials_production_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native actual RuntimeCredentials"}, .use_llvm = use_llvm });
    linkQuickJs(b, runtime_credentials_production_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(runtime_credentials_production_tests.root_module, sqlite_lib_dir, sqlite_library);
    runtime_credentials_production_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-runtime-credentials-production", "Compile actual ordinary RuntimeCredentials before bounded Source20 agreement").dependOn(&b.addInstallArtifact(runtime_credentials_production_tests, .{}).step);
    b.step("test-native-sdk-runtime-credentials-production", "Compare genuine latest credential Source20 and pending owner graph").dependOn(&b.addRunArtifact(runtime_credentials_production_tests).step);
    const exports_tests = b.addTest(.{ .name = "sdk-session-exports-test", .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_exports_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native ordinary session exports"}, .use_llvm = use_llvm });
    linkQuickJs(b, exports_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(exports_tests.root_module, sqlite_lib_dir, sqlite_library);
    exports_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-session-exports", "Compile actual ordinary Bash exports and bug report helpers").dependOn(&b.addInstallArtifact(exports_tests, .{}).step);
    b.step("test-native-sdk-session-exports", "Compare genuine Source ordinary session exports and renderers").dependOn(&b.addRunArtifact(exports_tests).step);

    const manual_compaction_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_compaction_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native ordinary compaction"}, .use_llvm = use_llvm });
    linkQuickJs(b, manual_compaction_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(manual_compaction_tests.root_module, sqlite_lib_dir, sqlite_library);
    manual_compaction_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-session-compaction", "Compile ordinary manual compaction and shared summary orchestration").dependOn(&manual_compaction_tests.step);
    b.step("test-native-sdk-session-compaction", "Compare actual upstream manual compaction and failure cleanup").dependOn(&b.addRunArtifact(manual_compaction_tests).step);

    const auto_compaction_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_auto_compaction_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native automatic compaction"}, .use_llvm = use_llvm });
    linkQuickJs(b, auto_compaction_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(auto_compaction_tests.root_module, sqlite_lib_dir, sqlite_library);
    auto_compaction_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-session-auto-compaction", "Compile ordinary automatic compaction independently").dependOn(&auto_compaction_tests.step);
    b.step("test-native-sdk-session-auto-compaction", "Compare actual upstream automatic compaction and controller ownership").dependOn(&b.addRunArtifact(auto_compaction_tests).step);
    const validation_b06_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_tool_validation_b06_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native b06 tool validation", "private tool validation workflow", "preserves repeated schema getter order", "caught raw validation callback exceptions" }, .use_llvm = use_llvm });
    linkQuickJs(b, validation_b06_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(validation_b06_tests.root_module, sqlite_lib_dir, sqlite_library);
    validation_b06_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-tool-validation-b06", "Compile actual b06 guard and validation regressions").dependOn(&validation_b06_tests.step);
    b.step("test-native-tool-validation-b06", "Compare genuine b06 argumentsError and early validation order").dependOn(&b.addRunArtifact(validation_b06_tests).step);
    const threshold_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_compaction_threshold_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native compaction threshold", "constructor hooks match 16", "compaction utilities match original", "initialization phase matches66" }, .use_llvm = use_llvm });
    linkQuickJs(b, threshold_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(threshold_tests.root_module, sqlite_lib_dir, sqlite_library);
    threshold_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-compaction-threshold", "Compile real ordinary threshold and live hook dispatch").dependOn(&threshold_tests.step);
    b.step("test-native-sdk-compaction-threshold", "Compare genuine threshold20 and constructor hook regressions").dependOn(&b.addRunArtifact(threshold_tests).step);
    const check_compaction_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_check_compaction_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "native check compaction", "native compaction threshold matches", "compaction utilities match original" }, .use_llvm = use_llvm });
    linkQuickJs(b, check_compaction_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(check_compaction_tests.root_module, sqlite_lib_dir, sqlite_library);
    check_compaction_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-check-compaction", "Compile automatic compaction trigger and shared estimate regressions").dependOn(&check_compaction_tests.step);
    b.step("test-native-sdk-check-compaction", "Compare genuine check32 and shared threshold estimates").dependOn(&b.addRunArtifact(check_compaction_tests).step);
    const custom_message_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_custom_message_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native custom messages"}, .use_llvm = use_llvm });
    linkQuickJs(b, custom_message_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(custom_message_tests.root_module, sqlite_lib_dir, sqlite_library);
    custom_message_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-sdk-custom-message", "Compile actual custom-message delivery and GC ownership tests").dependOn(&custom_message_tests.step);
    b.step("test-native-sdk-custom-message", "Compare actual Source40 custom-message behavior and descriptors").dependOn(&b.addRunArtifact(custom_message_tests).step);
    const session_retry_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_retry_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK session retry"}, .use_llvm = use_llvm });
    linkQuickJs(b, session_retry_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(session_retry_tests.root_module, sqlite_lib_dir, sqlite_library);
    session_retry_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-retry", "Exercise original retry corpus and complete native callback sleep omission owners").dependOn(&b.addRunArtifact(session_retry_tests).step);
    b.step("build-native-sdk-session-retry", "Compile ordinary retry and classifier bodies separately from runtime deadlines").dependOn(&session_retry_tests.step);
    const sdk_message_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_message_conversion_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK public message conversion"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_message_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_message_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-message-conversion", "Replay original public message conversion and exhaust operation allocation failures").dependOn(&b.addRunArtifact(sdk_message_tests).step);
    const sdk_prepare_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_prepare_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native SDK private prepareRun"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_prepare_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_prepare_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-session-prepare", "Compare actual Source run preparation ordering without activating absent session dependencies").dependOn(&b.addRunArtifact(sdk_prepare_tests).step);
    const sdk_query_consumer_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_query_consumers_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "ToolInfo cached SDK AgentTool", "ToolInfo actual SDK default selection", "ToolInfo actual SDK explicit loadout" }, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_query_consumer_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_query_consumer_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("test-native-sdk-query-consumers", "Retain original executable AgentTool context and SDK tool-loadout identity regressions").dependOn(&b.addRunArtifact(sdk_query_consumer_tests).step);
    linkQuickJs(b, sdk_skill_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_skill_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_skill_run = b.addRunArtifact(sdk_skill_tests);
    b.step("test-native-sdk-skill-expansion", "Replay all ten genuine Source482 skill queue and error observations").dependOn(&sdk_skill_run.step);
    const sdk_ui_allocation_range = b.option(u8, "sdk-ui-allocation-range", "SDK UI exhaustive host allocation range 0..7; omit to run all indices");
    if (sdk_ui_allocation_range) |range| if (range >= 8) @panic("SDK UI allocation range must be 0..7");
    const sdk_ui_options = b.addOptions();
    sdk_ui_options.addOption(?u8, "range", sdk_ui_allocation_range);
    sdk_ui_tests.root_module.addOptions("sdk_ui_allocation_options", sdk_ui_options);
    linkQuickJs(b, sdk_ui_tests.root_module, quickjs, sqlite_lib_dir);
    sdk_ui_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_ui_run = b.addRunArtifact(sdk_ui_tests);
    b.step("test-native-sdk-ui", "Replay actual SDK UI contexts and sweep event allocation ownership").dependOn(&sdk_ui_run.step);
    test_step.dependOn(&sdk_ui_run.step);
    const provider_ticket_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_provider_tickets_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native provider tickets"}, .use_llvm = use_llvm });
    linkQuickJs(b, provider_ticket_tests.root_module, quickjs, sqlite_lib_dir);
    provider_ticket_tests.root_module.addImport("catalog_tool", catalog_tool);
    const provider_ticket_run = b.addRunArtifact(provider_ticket_tests);
    b.step("test-native-provider-tickets", "Prove four admitted native callbacks and private async invocation ownership").dependOn(&provider_ticket_run.step);
    test_step.dependOn(&provider_ticket_run.step);
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
    sdk_refresh_ownership_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_refresh_ownership_run = b.addRunArtifact(sdk_refresh_ownership_tests);
    const sdk_refresh_abort_tests = b.addTest(.{ .root_module = sdk_refresh_ownership_tests.root_module, .filters = &.{"aggregate abort matches Source"}, .use_llvm = use_llvm });
    const sdk_refresh_abort_run = b.addRunArtifact(sdk_refresh_abort_tests);
    b.step("test-sdk-refresh-abort", "Replay actual Source pre-aborted and in-flight refresh aggregate cancellation").dependOn(&sdk_refresh_abort_run.step);
    const sdk_refresh_ownership_step = b.step("test-sdk-refresh-ownership", "Exercise provider refresh publication and cancellation allocation ownership");
    sdk_refresh_ownership_step.dependOn(&sdk_refresh_ownership_run.step);
    test_step.dependOn(&sdk_refresh_ownership_run.step);
    const sdk_auth_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_auth_ownership_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "SDK auth snapshot key synchronization", "availability v2 auth status" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_auth_tests.root_module, quickjs, sqlite_lib_dir);
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
    sdk_virtual_tests.root_module.addImport("catalog_tool", catalog_tool);
    const sdk_virtual_run = b.addRunArtifact(sdk_virtual_tests);
    b.step("test-sdk-virtual-ownership", "Exercise virtual routing allocation ownership").dependOn(&sdk_virtual_run.step);
    test_step.dependOn(&sdk_virtual_run.step);
    const sdk_model_bridge_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_model_bridge_test.zig"), .target = target, .optimize = optimize });
    sdk_model_bridge_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, sdk_model_bridge_module, quickjs, sqlite_lib_dir);
    const sdk_model_bridge_tests = b.addTest(.{ .root_module = sdk_model_bridge_module, .use_llvm = use_llvm, .filters = &.{"SDK model bridge"} });
    const sdk_model_bridge_run = b.addRunArtifact(sdk_model_bridge_tests);
    b.step("test-sdk-model-bridge", "Exercise owner-only generation-leased model operations and cancellation").dependOn(&sdk_model_bridge_run.step);
    test_step.dependOn(&sdk_model_bridge_run.step);
    const sdk_session_lease_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_session_lease_test.zig"), .target = target, .optimize = optimize });
    sdk_session_lease_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, sdk_session_lease_module, quickjs, sqlite_lib_dir);
    const sdk_session_lease_tests = b.addTest(.{ .root_module = sdk_session_lease_module, .use_llvm = use_llvm, .filters = &.{"SDK session model lease"} });
    const sdk_session_lease_run = b.addRunArtifact(sdk_session_lease_tests);
    b.step("test-sdk-session-model-lease", "Exercise exact SDK session model admissions and safe lease retirement").dependOn(&sdk_session_lease_run.step);
    test_step.dependOn(&sdk_session_lease_run.step);
    const sdk_registry_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_model_registry_test.zig"), .target = target, .optimize = optimize });
    sdk_registry_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, sdk_registry_module, quickjs, sqlite_lib_dir);
    const sdk_registry_tests = b.addTest(.{ .root_module = sdk_registry_module, .use_llvm = use_llvm, .filters = &.{"SDK model registry"} });
    const sdk_registry_run = b.addRunArtifact(sdk_registry_tests);
    b.step("test-sdk-model-registry", "Exercise Source compatibility facade and exact model ownership").dependOn(&sdk_registry_run.step);
    test_step.dependOn(&sdk_registry_run.step);
    const sdk_allocation_step = b.step("test-sdk-allocation-shard", "Exercise a complete SDK allocation range with baseline and completion receipts");
    sdk_allocation_step.dependOn(&codemode_model_allocation_run.step);
    inline for (.{ sdk_virtual_run, sdk_session_lease_run, sdk_registry_run }) |run| {
        run.has_side_effects = true;
        sdk_allocation_step.dependOn(&run.step);
    }
    const sdk_settings_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_settings_ownership_test.zig"), .target = target, .optimize = optimize });
    sdk_settings_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, sdk_settings_module, quickjs, sqlite_lib_dir);
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
    const native_list_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_list_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Source6fb public SelectList"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, native_list_tests.root_module, quickjs, sqlite_lib_dir);
    const run_native_list_tests = b.addRunArtifact(native_list_tests);
    b.step("test-native-lists", "Replay Source public SelectList and SettingsList callbacks layout and lifecycle").dependOn(&run_native_list_tests.step);
    test_step.dependOn(&run_native_list_tests.step);
    const native_layout_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_layout_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"Source6fb public Text"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, native_layout_tests.root_module, quickjs, sqlite_lib_dir);
    const native_layout_run = b.addRunArtifact(native_layout_tests);
    b.step("test-native-layout", "Replay original public component layouts caches and callback lifecycle").dependOn(&native_layout_run.step);
    test_step.dependOn(&native_layout_run.step);
    const native_terminal_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_terminal_image_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"terminal capabilities pure Main detector"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, native_terminal_tests.root_module, quickjs, sqlite_lib_dir);
    const native_terminal_run = b.addRunArtifact(native_terminal_tests);
    b.step("test-native-terminal-capabilities", "Replay Source environment capability cache and admitted terminal context").dependOn(&native_terminal_run.step);
    test_step.dependOn(&native_terminal_run.step);
    const project_context_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/project_context_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const native_project_context_module = b.createModule(.{ .root_source_file = b.path("src/native_project_context_test.zig"), .target = target, .optimize = optimize });
    native_project_context_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, native_project_context_module, quickjs, sqlite_lib_dir);
    const native_project_context_tests = b.addTest(.{ .root_module = native_project_context_module, .use_llvm = use_llvm, .filters = &.{"Source f1 SDK"} });
    const project_context_step = b.step("test-project-context", "Replay current upstream context files and native SDK resource projection");
    const project_context_run = b.addRunArtifact(project_context_tests);
    const native_project_context_run = b.addRunArtifact(native_project_context_tests);
    project_context_step.dependOn(&project_context_run.step);
    project_context_step.dependOn(&native_project_context_run.step);
    test_step.dependOn(&project_context_run.step);
    test_step.dependOn(&native_project_context_run.step);
    const native_image_api_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_terminal_image_api_test.zig"), .target = target, .optimize = optimize }), .filters = &.{ "Source6fb terminal image API", "native Buffer byteLength Base64", "Source6fb terminal image home" }, .use_llvm = use_llvm });
    linkQuickJs(b, native_image_api_tests.root_module, quickjs, sqlite_lib_dir);
    const native_image_api_run = b.addRunArtifact(native_image_api_tests);
    b.step("test-native-terminal-image-api", "Replay Source terminal image APIs and native buffer sizes").dependOn(&native_image_api_run.step);
    test_step.dependOn(&native_image_api_run.step);
    const native_markdown_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_markdown_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "Source6fb native Markdown", "Source6fb native Container", "native focus containment" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, native_markdown_tests.root_module, quickjs, sqlite_lib_dir);
    const native_markdown_run = b.addRunArtifact(native_markdown_tests);
    b.step("test-native-markdown", "Replay Source Markdown and Container layout callbacks and lifecycle").dependOn(&native_markdown_run.step);
    test_step.dependOn(&native_markdown_run.step);
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
    theme_constructor_module.addImport("catalog_tool", catalog_tool);
    const theme_constructor_tests = b.addTest(.{ .root_module = theme_constructor_module, .use_llvm = use_llvm, .filters = &.{"Source6fb Theme constructor"} });
    const theme_constructor_run = b.addRunArtifact(theme_constructor_tests);
    b.step("test-theme-constructor-6fb", "Replay selected Source Theme constructors fallback slots and retained colors").dependOn(&theme_constructor_run.step);
    test_step.dependOn(&theme_constructor_run.step);
    const theme_watch_module = b.createModule(.{ .root_source_file = b.path("src/native_theme_watch_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, theme_watch_module, quickjs, sqlite_lib_dir);
    theme_watch_module.addImport("catalog_tool", catalog_tool);
    const theme_watch_tests = b.addTest(.{ .root_module = theme_watch_module, .use_llvm = use_llvm, .filters = &.{"Source6fb Theme watcher"} });
    const theme_watch_run = b.addRunArtifact(theme_watch_tests);
    b.step("test-native-theme-watchers", "Replay Source custom Theme watcher debounce lifecycle and native events").dependOn(&theme_watch_run.step);
    test_step.dependOn(&theme_watch_run.step);
    const theme_watch_process_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_theme_watch_process_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const theme_watch_process_run = b.addRunArtifact(theme_watch_process_tests);
    theme_watch_process_run.step.dependOn(&sdk_install.step);
    b.step("test-native-theme-watchers-process", "Prove retained Theme callbacks reload through the actual no-Node SDK worker").dependOn(&theme_watch_process_run.step);
    test_step.dependOn(&theme_watch_process_run.step);
    const editor_source_module = b.createModule(.{ .root_source_file = b.path("src/native_editor_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, editor_source_module, quickjs, sqlite_lib_dir);
    editor_source_module.addImport("catalog_tool", catalog_tool);
    const editor_source_tests = b.addTest(.{ .root_module = editor_source_module, .use_llvm = use_llvm, .filters = &.{"Source6fb public Editor"} });
    const editor_source_run = b.addRunArtifact(editor_source_tests);
    b.step("test-native-editor-source", "Replay Source Editor and CustomEditor fields editing rendering mouse and async lifecycle").dependOn(&editor_source_run.step);
    test_step.dependOn(&editor_source_run.step);
    const tui_public_source_module = b.createModule(.{ .root_source_file = b.path("src/native_tui_public_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, tui_public_source_module, quickjs, sqlite_lib_dir);
    tui_public_source_module.addImport("catalog_tool", catalog_tool);
    const tui_public_audit_tests = b.addTest(.{ .root_module = tui_public_source_module, .use_llvm = use_llvm, .filters = &.{"Source6fb public TUI final"} });
    const tui_public_audit_run = b.addRunArtifact(tui_public_audit_tests);
    b.step("audit-native-tui-public-source", "Audit complete Source TUI runtime namespace and prototypes").dependOn(&tui_public_audit_run.step);
    const tui_public_slice_tests = b.addTest(.{ .root_module = tui_public_source_module, .use_llvm = use_llvm, .filters = &.{"public TUI slice"} });
    const tui_public_slice_run = b.addRunArtifact(tui_public_slice_tests);
    b.step("test-native-tui-public-source", "Replay implemented Source public TUI behavior slices").dependOn(&tui_public_slice_run.step);
    test_step.dependOn(&tui_public_slice_run.step);
    const body_dependency_module = b.createModule(.{ .root_source_file = b.path("src/native_web_body_dependencies_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, body_dependency_module, quickjs, sqlite_lib_dir);
    body_dependency_module.addImport("catalog_tool", catalog_tool);
    const body_dependency_tests = b.addTest(.{ .root_module = body_dependency_module, .use_llvm = use_llvm, .filters = &.{ "Web Body dependency", "Headers Source189", "Headers native helper" } });
    b.step("build-native-web-body-dependencies", "Compile genuine Source176 shared dependency observations plus Headers189 regression").dependOn(&body_dependency_tests.step);
    const body_dependency_run = b.addRunArtifact(body_dependency_tests);
    b.step("test-native-web-body-dependencies", "Replay shared Blob File FormData WebIDL Source176 observations and Headers189 regression").dependOn(&body_dependency_run.step);
    const request_source_module = b.createModule(.{ .root_source_file = b.path("src/native_web_request_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, request_source_module, quickjs, sqlite_lib_dir);
    request_source_module.addImport("catalog_tool", catalog_tool);
    const request_source_tests = b.addTest(.{ .root_module = request_source_module, .use_llvm = use_llvm, .filters = &.{"Request "} });
    b.step("build-native-web-request", "Compile genuine Request Source176 projection and selected ownership probes").dependOn(&request_source_tests.step);
    const request_source_run = b.addRunArtifact(request_source_tests);
    b.step("test-native-web-request", "Replay immutable genuine Node24 Request55 and selected operation OOM").dependOn(&request_source_run.step);
    const multipart_module = b.createModule(.{ .root_source_file = b.path("src/native_web_multipart_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, multipart_module, quickjs, sqlite_lib_dir);
    multipart_module.addImport("catalog_tool", catalog_tool);
    const multipart_tests = b.addTest(.{ .root_module = multipart_module, .use_llvm = use_llvm, .filters = &.{"Web multipart "} });
    b.step("build-native-web-multipart", "Compile original Source176 multipart observations and selected native ownership").dependOn(&multipart_tests.step);
    const multipart_run = b.addRunArtifact(multipart_tests);
    b.step("test-native-web-multipart", "Replay original multipart Source3 observations and measured operation OOM").dependOn(&multipart_run.step);
    const fetch_source_module = b.createModule(.{ .root_source_file = b.path("src/native_web_fetch_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, fetch_source_module, quickjs, sqlite_lib_dir);
    fetch_source_module.addImport("catalog_tool", catalog_tool);
    const fetch_source_tests = b.addTest(.{ .root_module = fetch_source_module, .use_llvm = use_llvm, .filters = &.{"Web fetch Source39 "} });
    b.step("build-native-web-fetch", "Compile complete genuine Fetch39 real peer comparison").dependOn(&fetch_source_tests.step);
    const fetch_source_run = b.addRunArtifact(fetch_source_tests);
    b.step("test-native-web-fetch", "Replay all39 unchanged fetch rows against real native Request Response stream and HTTP").dependOn(&fetch_source_run.step);
    const body_full_module = b.createModule(.{ .root_source_file = b.path("src/native_web_body_full_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, body_full_module, quickjs, sqlite_lib_dir);
    body_full_module.addImport("catalog_tool", catalog_tool);
    const body_full_tests = b.addTest(.{ .root_module = body_full_module, .use_llvm = use_llvm, .filters = &.{"Web Body176 complete "} });
    b.step("build-native-web-body-full", "Compile complete immutable genuine Node24 Body176 graph comparison").dependOn(&body_full_tests.step);
    const body_full_run = b.addRunArtifact(body_full_tests);
    b.step("test-native-web-body-full", "Replay all176 original constructor descriptor body signal and GC observations").dependOn(&body_full_run.step);
    const typebox_production_module = b.createModule(.{ .root_source_file = b.path("src/native_typebox_compile_production_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, typebox_production_module, quickjs, sqlite_lib_dir);
    typebox_production_module.addImport("catalog_tool", catalog_tool);
    const typebox_production_tests = b.addTest(.{ .root_module = typebox_production_module, .use_llvm = use_llvm, .filters = &.{ "actual TypeBox ", "actual provider schemas Partial and Memory " } });
    b.step("build-native-typebox-production-source", "Compile the shared production TypeBox graph and actual Source80 Source52 Source396 replays").dependOn(&b.addInstallArtifact(typebox_production_tests, .{}).step);
    const typebox_production_run = b.addRunArtifact(typebox_production_tests);
    typebox_production_run.has_side_effects = true;
    b.step("test-native-typebox-production-source", "Replay actual compiler and provider schemas through the shared native TypeBox graph").dependOn(&typebox_production_run.step);
    const typebox_heap_module = b.createModule(.{ .root_source_file = b.path("src/native_typebox_continuation_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, typebox_heap_module, quickjs, sqlite_lib_dir);
    typebox_heap_module.addImport("catalog_tool", catalog_tool);
    const typebox_heap_tests = b.addTest(.{ .root_module = typebox_heap_module, .use_llvm = use_llvm, .filters = &.{"TypeBox heap continuation "} });
    b.step("build-native-typebox-heap-continuation", "Compile prepared exact-object synchronous heap activation controls").dependOn(&b.addInstallArtifact(typebox_heap_tests, .{}).step);
    b.step("test-native-typebox-heap-continuation", "Run private VM scheduling ownership receiver finally and reentry controls").dependOn(&b.addRunArtifact(typebox_heap_tests).step);
    const native_tla_fatal_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_tla_fatal_delivery_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native TLA fatal"}, .use_llvm = use_llvm });
    linkQuickJs(b, native_tla_fatal_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_tla_fatal_tests.root_module, sqlite_lib_dir, sqlite_library);
    native_tla_fatal_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-tla-fatal-delivery", "Compile reviewed fatal module delivery controls").dependOn(&b.addInstallArtifact(native_tla_fatal_tests, .{}).step);
    b.step("test-native-tla-fatal-delivery", "Run reviewed fatal module delivery controls").dependOn(&b.addRunArtifact(native_tla_fatal_tests).step);
    const resumed_tla_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_tla_resumed_fatal_delivery_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native TLA resumed fatal"}, .use_llvm = use_llvm });
    linkQuickJs(b, resumed_tla_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(resumed_tla_tests.root_module, sqlite_lib_dir, sqlite_library);
    resumed_tla_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-tla-resumed-fatal-delivery", "Compile reviewed resumed module and late-callback controls").dependOn(&b.addInstallArtifact(resumed_tla_tests, .{}).step);
    b.step("test-native-tla-resumed-fatal-delivery", "Run reviewed resumed module and late-callback controls").dependOn(&b.addRunArtifact(resumed_tla_tests).step);
    const native_af_resolving_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_resolving_pending_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AF resolving pending"}, .use_llvm = use_llvm });
    linkQuickJs(b, native_af_resolving_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_af_resolving_tests.root_module, sqlite_lib_dir, sqlite_library);
    native_af_resolving_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-af-resolving-pending", "Compile reviewed native AF pending-fatal resolving controls").dependOn(&b.addInstallArtifact(native_af_resolving_tests, .{}).step);
    b.step("test-native-af-resolving-pending", "Run exact metadata-selected native AF pending-fatal controls after explicit grant").dependOn(&b.addRunArtifact(native_af_resolving_tests).step);
    const native_await_inactive_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_async_await_inactive_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native AF Await inactive"}, .use_llvm = use_llvm });
    linkQuickJs(b, native_await_inactive_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(native_await_inactive_tests.root_module, sqlite_lib_dir, sqlite_library);
    native_await_inactive_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-af-await-inactive", "Compile reviewed native Await queued callback and GC control").dependOn(&b.addInstallArtifact(native_await_inactive_tests, .{}).step);
    b.step("test-native-af-await-inactive", "Run actual metadata-selected native Await lifecycle control after explicit grant").dependOn(&b.addRunArtifact(native_await_inactive_tests).step);
    const shared_thenable_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_shared_thenable_fatal_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"shared thenable fatal"}, .use_llvm = use_llvm });
    linkQuickJs(b, shared_thenable_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(shared_thenable_tests.root_module, sqlite_lib_dir, sqlite_library);
    shared_thenable_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-shared-thenable-fatal", "Compile reviewed shared thenable active-fatal controls").dependOn(&b.addInstallArtifact(shared_thenable_tests, .{}).step);
    b.step("test-native-shared-thenable-fatal", "Run actual metadata-selected shared thenable controls after explicit grant").dependOn(&b.addRunArtifact(shared_thenable_tests).step);
    const headers_source_module = b.createModule(.{ .root_source_file = b.path("src/native_headers_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, headers_source_module, quickjs, sqlite_lib_dir);
    headers_source_module.addImport("catalog_tool", catalog_tool);
    const headers_source_tests = b.addTest(.{ .root_module = headers_source_module, .use_llvm = use_llvm, .filters = &.{ "Headers Source189", "Headers native helper" } });
    b.step("build-native-headers-source", "Compile native actual Node24 Headers contract replay").dependOn(&headers_source_tests.step);
    const headers_source_run = b.addRunArtifact(headers_source_tests);
    b.step("test-native-headers-source", "Replay actual Node24 Headers contracts and ownership").dependOn(&headers_source_run.step);
    const headers_oom_tests = b.addTest(.{ .root_module = headers_source_module, .use_llvm = use_llvm, .filters = &.{"Headers full-engine exhaustive"} });
    const headers_oom_run = b.addRunArtifact(headers_oom_tests);
    b.step("test-native-headers-oom", "Exhaust native Headers full-engine allocation failures").dependOn(&headers_oom_run.step);
    const response_source_module = b.createModule(.{ .root_source_file = b.path("src/native_web_response_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, response_source_module, quickjs, sqlite_lib_dir);
    response_source_module.addImport("catalog_tool", catalog_tool);
    const response_source_tests = b.addTest(.{ .root_module = response_source_module, .use_llvm = use_llvm, .filters = &.{ "Response Source176", "Response native actual" } });
    b.step("build-native-web-response-source", "Compile actual Response Source176 projection and native ownership").dependOn(&response_source_tests.step);
    const response_source_run = b.addRunArtifact(response_source_tests);
    b.step("test-native-web-response-source", "Replay 114 genuine Node24 Response rows from Body176 and actual transport ownership").dependOn(&response_source_run.step);
    const response_transport_tests = b.addTest(.{ .root_module = response_source_module, .use_llvm = use_llvm, .filters = &.{"Response native actual"} });
    b.step("build-native-web-response-transport", "Compile genuine Response transport and ownership gates").dependOn(&response_transport_tests.step);
    const response_transport_run = b.addRunArtifact(response_transport_tests);
    b.step("test-native-web-response-transport", "Verify genuine Response at HTTP headers before body EOF and native ownership").dependOn(&response_transport_run.step);
    const response_oom_tests = b.addTest(.{ .root_module = response_source_module, .use_llvm = use_llvm, .filters = &.{"Response native selected operation OOM"} });
    b.step("build-native-web-response-oom", "Compile selected Response allocation failure ownership gates").dependOn(&response_oom_tests.step);
    const response_oom_run = b.addRunArtifact(response_oom_tests);
    b.step("test-native-web-response-oom", "Verify selected actual Response operation allocation failure ownership").dependOn(&response_oom_run.step);
    const response_byte_module = b.createModule(.{ .root_source_file = b.path("src/native_readable_byte_stream_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, response_byte_module, quickjs, sqlite_lib_dir);
    response_byte_module.addImport("catalog_tool", catalog_tool);
    const response_byte_tests = b.addTest(.{ .root_module = response_byte_module, .use_llvm = use_llvm, .filters = &.{"native readable byte Source"} });
    b.step("build-hosted-native-readable-byte-source", "Compile unchanged genuine byte stream Source12 regression").dependOn(&response_byte_tests.step);
    const response_byte_run = b.addRunArtifact(response_byte_tests);
    b.step("test-native-readable-byte-source", "Replay unchanged genuine Node24 byte stream Source12 regression").dependOn(&response_byte_run.step);
    const response_stream_oom_module = b.createModule(.{ .root_source_file = b.path("src/native_readable_stream_oom_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, response_stream_oom_module, quickjs, sqlite_lib_dir);
    response_stream_oom_module.addImport("catalog_tool", catalog_tool);
    const response_stream_oom_tests = b.addTest(.{ .root_module = response_stream_oom_module, .use_llvm = use_llvm, .filters = &.{"native readable host OOM"} });
    b.step("build-native-readable-response-host-oom", "Compile deterministic actual tee permanent host OOM retirement regression for Response composition").dependOn(&response_stream_oom_tests.step);
    const response_stream_oom_run = b.addRunArtifact(response_stream_oom_tests);
    b.step("test-native-readable-response-host-oom", "Verify Response-composed tee consumers reject native OOM and release all host storage").dependOn(&response_stream_oom_run.step);
    const tui_base_source_module = b.createModule(.{ .root_source_file = b.path("src/native_tui_base_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, tui_base_source_module, quickjs, sqlite_lib_dir);
    tui_base_source_module.addImport("catalog_tool", catalog_tool);
    const tui_base_source_tests = b.addTest(.{ .root_module = tui_base_source_module, .use_llvm = use_llvm, .filters = &.{"Source6fb internal TuiBase"} });
    const tui_base_source_run = b.addRunArtifact(tui_base_source_tests);
    b.step("test-native-tui-base-source", "Replay complete internal Source TuiBase constructor methods and startup monotonic clock").dependOn(&tui_base_source_run.step);
    const tui_main_source_module = b.createModule(.{ .root_source_file = b.path("src/native_tui_main_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, tui_main_source_module, quickjs, sqlite_lib_dir);
    tui_main_source_module.addImport("catalog_tool", catalog_tool);
    const tui_main_source_tests = b.addTest(.{ .root_module = tui_main_source_module, .use_llvm = use_llvm, .filters = &.{ "Source6fb native TuiMainScreen", "Native TuiMainScreen ordinary class" } });
    const tui_main_source_run = b.addRunArtifact(tui_main_source_tests);
    b.step("test-native-tui-main-source", "Replay genuine Source TuiMainScreen fields and complete terminal write/state transitions").dependOn(&tui_main_source_run.step);
    const tui_alt_prerequisites_module = b.createModule(.{ .root_source_file = b.path("src/native_tui_alt_prerequisites_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, tui_alt_prerequisites_module, quickjs, sqlite_lib_dir);
    tui_alt_prerequisites_module.addImport("catalog_tool", catalog_tool);
    const tui_alt_prerequisites_tests = b.addTest(.{ .root_module = tui_alt_prerequisites_module, .use_llvm = use_llvm, .filters = &.{"Source6fb alternate-screen prerequisite"} });
    const tui_alt_prerequisites_run = b.addRunArtifact(tui_alt_prerequisites_tests);
    b.step("test-native-tui-alt-prerequisites-source", "Replay genuine Source alternate-screen wheel flash and search dependencies").dependOn(&tui_alt_prerequisites_run.step);
    const tui_alt_source_module = b.createModule(.{ .root_source_file = b.path("src/native_tui_alt_source_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, tui_alt_source_module, quickjs, sqlite_lib_dir);
    tui_alt_source_module.addImport("catalog_tool", catalog_tool);
    const tui_alt_source_tests = b.addTest(.{ .root_module = tui_alt_source_module, .use_llvm = use_llvm, .filters = &.{"Sourceea native TuiAltScreen"} });
    const tui_alt_source_run = b.addRunArtifact(tui_alt_source_tests);
    b.step("test-native-tui-alt-source", "Replay genuine latest Source alternate-screen constructor layout renderer selection mouse search and clipboard").dependOn(&tui_alt_source_run.step);
    const tui_alt_allocation_tests = b.addTest(.{ .root_module = tui_alt_source_module, .use_llvm = use_llvm, .filters = &.{"Sourceea native TuiAltScreen constructor layout renderer selection and disposal release every induced allocation failure"} });
    const tui_alt_allocation_run = b.addRunArtifact(tui_alt_allocation_tests);
    b.step("test-native-tui-alt-allocation-source", "Diagnose and validate all induced alternate-screen allocation failures without reducing full Source coverage").dependOn(&tui_alt_allocation_run.step);
    const tui_public_process_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_tui_public_process_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    const tui_public_process_run = b.addRunArtifact(tui_public_process_tests);
    tui_public_process_run.step.dependOn(&sdk_install.step);
    b.step("test-native-tui-public-process", "Replay public TUI components and callback lifecycle in actual no-Node worker").dependOn(&tui_public_process_run.step);
    test_step.dependOn(&tui_public_process_run.step);
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
    const toolinfo_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_bindings_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "ToolInfo", "native catalog", "canonical builtin schemas" },
        .use_llvm = use_llvm,
    });
    toolinfo_tests.root_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, toolinfo_tests.root_module, quickjs, sqlite_lib_dir);
    const run_toolinfo_tests = b.addRunArtifact(toolinfo_tests);
    const toolinfo_test_step = b.step("test-native-toolinfo", "Check source ToolInfo references and owned native catalog generations");
    toolinfo_test_step.dependOn(&run_toolinfo_tests.step);
    test_step.dependOn(&run_toolinfo_tests.step);
    const filesystem_tests = b.addTest(.{
        .filters = &.{"extensions.node_fs."},
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_node_fs_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, filesystem_tests.root_module, quickjs, sqlite_lib_dir);
    const run_filesystem_tests = b.addRunArtifact(filesystem_tests);
    const filesystem_test_step = b.step("test-extension-filesystem", "Test native extension filesystem APIs");
    filesystem_test_step.dependOn(&run_filesystem_tests.step);
    test_step.dependOn(&run_filesystem_tests.step);
    const path_tests = b.addTest(.{
        .filters = &.{"extensions.node_path."},
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_node_path_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, path_tests.root_module, quickjs, sqlite_lib_dir);
    b.step("build-extension-path", "Compile the native cross-platform path test artifact without running tests").dependOn(&path_tests.step);
    const run_path_tests = b.addRunArtifact(path_tests);
    const path_test_step = b.step("test-extension-path", "Test native cross-platform extension path APIs");
    path_test_step.dependOn(&run_path_tests.step);
    test_step.dependOn(&run_path_tests.step);
    const url_tests = b.addTest(.{
        .filters = &.{ "extensions.node_url.", "extensions.native_url.", "extensions.url_parser.", "extensions.url_search_params.", "extensions.file_urls." },
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_node_url_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, url_tests.root_module, quickjs, sqlite_lib_dir);
    b.step("build-extension-url", "Compile every native URL file-URL parser parameter and constructor regression without execution").dependOn(&url_tests.step);
    const run_url_tests = b.addRunArtifact(url_tests);
    const url_test_step = b.step("test-extension-url", "Test native file URL conversion for extensions");
    url_test_step.dependOn(&run_url_tests.step);
    test_step.dependOn(&run_url_tests.step);
    const console_tests = b.addTest(.{
        .filters = &.{"extensions.console."},
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_console_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, console_tests.root_module, quickjs, sqlite_lib_dir);
    const run_console_tests = b.addRunArtifact(console_tests);
    const console_test_step = b.step("test-extension-console", "Test native console formatting and builtin module identity");
    console_test_step.dependOn(&run_console_tests.step);
    test_step.dependOn(&run_console_tests.step);
    const resolver_tests = b.addTest(.{
        .filters = &.{"extensions.module_resolver."},
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_module_resolver_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const run_resolver_tests = b.addRunArtifact(resolver_tests);
    const resolver_test_step = b.step("test-extension-resolver", "Test native extension package and file resolution");
    resolver_test_step.dependOn(&run_resolver_tests.step);
    test_step.dependOn(&run_resolver_tests.step);
    const encoding_tests = b.addTest(.{
        .filters = &.{"extensions.text_encoding."},
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_text_encoding_test.zig"), .target = target, .optimize = optimize }),
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
        .filters = &.{"extensions.native_worker_process_test."},
        .root_module = b.createModule(.{ .root_source_file = b.path("src/extension_native_worker_process_test_test.zig"), .target = target, .optimize = optimize }),
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
    run_native_runtime_tests.step.dependOn(&install_mcp_configured_fixture.step);
    run_native_runtime_tests.setEnvironmentVariable("PI_MCP_CONFIGURED_FIXTURE", b.getInstallPath(.bin, b.fmt("pi-mcp-configured-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    const typed_owner_process_tests = b.addTest(.{ .root_module = native_runtime_tests.root_module, .filters = &.{"native runtime typed provider owner"}, .use_llvm = use_llvm });
    const typed_owner_process_run = b.addRunArtifact(typed_owner_process_tests);
    typed_owner_process_run.step.dependOn(b.getInstallStep());
    b.step("test-typed-provider-process", "Exercise typed callbacks over the real native owner transport without Node").dependOn(&typed_owner_process_run.step);
    test_step.dependOn(&typed_owner_process_run.step);
    const native_runtime_step = b.step("test-native-runtime", "Exercise the persistent native extension runtime and host without Node");
    native_runtime_step.dependOn(&run_native_runtime_tests.step);
    const catalog_control_tests = b.addTest(.{ .root_module = native_runtime_tests.root_module, .filters = &.{ "native runtime private catalog", "native catalog control" }, .use_llvm = use_llvm });
    linkQuickJs(b, catalog_control_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, catalog_control_tests.root_module, typescript_parser);
    const catalog_control_run = b.addRunArtifact(catalog_control_tests);
    catalog_control_run.step.dependOn(&install_mcp_configured_cli.step);
    catalog_control_run.step.dependOn(&install_mcp_configured_fixture.step);
    catalog_control_run.setEnvironmentVariable("PI_MCP_CONFIGURED_FIXTURE", b.getInstallPath(.bin, b.fmt("pi-mcp-configured-fixture{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-native-catalog-control", "Exercise catalog updates during ordinary managed callbacks").dependOn(&catalog_control_run.step);
    test_step.dependOn(&catalog_control_run.step);
    const sdk_ui_process_tests = b.addTest(.{ .root_module = native_runtime_tests.root_module, .filters = &.{"native runtime SDK UI"}, .use_llvm = use_llvm });
    const sdk_ui_process_run = b.addRunArtifact(sdk_ui_process_tests);
    sdk_ui_process_run.step.dependOn(b.getInstallStep());
    b.step("test-sdk-ui-context-process", "Replay actual SDK UI service identity rebinding mode and prompt events").dependOn(&sdk_ui_process_run.step);
    test_step.dependOn(&sdk_ui_process_run.step);
    const typed_main_process_tests = b.addTest(.{ .root_module = native_runtime_tests.root_module, .filters = &.{"native runtime typed Main"}, .use_llvm = use_llvm });
    const typed_main_process_run = b.addRunArtifact(typed_main_process_tests);
    typed_main_process_run.step.dependOn(b.getInstallStep());
    b.step("test-typed-main-process", "Exercise actual Main typed registry and classifier/image/native callbacks without Node").dependOn(&typed_main_process_run.step);
    test_step.dependOn(&typed_main_process_run.step);
    const typed_ticket_process_tests = b.addTest(.{ .root_module = native_runtime_tests.root_module, .filters = &.{"native runtime typed tickets"}, .use_llvm = use_llvm });
    const typed_ticket_process_run = b.addRunArtifact(typed_ticket_process_tests);
    typed_ticket_process_run.step.dependOn(b.getInstallStep());
    b.step("test-native-ticket-process", "Prove four real callback admissions with isolated snapshots and individual abort").dependOn(&typed_ticket_process_run.step);
    test_step.dependOn(&typed_ticket_process_run.step);
    const catalog_control_process_tests = b.addTest(.{ .root_module = native_runtime_tests.root_module, .filters = &.{"native runtime private catalog control"}, .use_llvm = use_llvm });
    const catalog_control_process_run = b.addRunArtifact(catalog_control_process_tests);
    catalog_control_process_run.step.dependOn(b.getInstallStep());
    b.step("test-native-catalog-control-process", "Prove private catalog FIFO acknowledgement and rollback on a real native worker").dependOn(&catalog_control_process_run.step);
    test_step.dependOn(&catalog_control_process_run.step);
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
    const ui_overlay_ae7_process_tests = b.addTest(.{
        .root_module = fullscreen_frontend_tests.root_module,
        .filters = &.{"ae7 overlay process"},
        .use_llvm = use_llvm,
    });
    const ui_overlay_ae7_process_run = b.addRunArtifact(ui_overlay_ae7_process_tests);
    const ui_overlay_ae7_process_build = b.step("build-ui-overlay-ae7-process", "Compile exact ae7 worker terminal regression without executing it");
    ui_overlay_ae7_process_build.dependOn(&ui_overlay_ae7_process_tests.step);
    ui_overlay_ae7_process_build.dependOn(b.getInstallStep());
    ui_overlay_ae7_process_run.step.dependOn(b.getInstallStep());
    b.step("test-ui-overlay-ae7-process", "Prove concurrent custom overlay own-fence close through real native worker and terminal cells").dependOn(&ui_overlay_ae7_process_run.step);
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
    const application_fatal_module = b.createModule(.{ .root_source_file = b.path("src/native_application_fatal_test.zig"), .target = target, .optimize = optimize });
    application_fatal_module.addImport("catalog_tool", catalog_tool);
    linkQuickJs(b, application_fatal_module, quickjs, sqlite_lib_dir);
    const application_fatal_tests = b.addTest(.{ .root_module = application_fatal_module, .filters = &.{"native application fatal"}, .use_llvm = use_llvm });
    const application_fatal_run = b.addRunArtifact(application_fatal_tests);
    const application_fatal_protocol_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/extensions/native_fatal_protocol.zig"), .target = target, .optimize = optimize }), .filters = &.{"native fatal protocol"}, .use_llvm = use_llvm });
    const application_fatal_protocol_run = b.addRunArtifact(application_fatal_protocol_tests);
    const application_fatal_step = b.step("test-native-application-fatal", "Retain original rejection reasons through actual terminal release and authenticated reporting");
    application_fatal_step.dependOn(&application_fatal_run.step);
    application_fatal_step.dependOn(&application_fatal_protocol_run.step);
    run_custom_editor_frontend_tests.step.dependOn(&application_fatal_run.step);
    run_custom_editor_frontend_tests.step.dependOn(&application_fatal_protocol_run.step);
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
            ui_overlay_ae7_process_run.step.dependOn(&installation.step);
            ui_overlay_ae7_process_build.dependOn(&installation.step);
            run_custom_editor_frontend_tests.step.dependOn(&installation.step);
            run_fullscreen_frontend_tests.setEnvironmentVariable(helper.environment, b.getInstallPath(.bin, b.fmt("{s}.exe", .{helper.name})));
            ui_overlay_ae7_process_run.setEnvironmentVariable(helper.environment, b.getInstallPath(.bin, b.fmt("{s}.exe", .{helper.name})));
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

    const ui_overlay_ae7_tests = b.addTest(.{
        .root_module = test_mod,
        .filters = &.{ "ae7 extension overlays", "ae7 overlay identity", "native custom early done ignores", "fullscreen native component scene input", "component close error" },
        .use_llvm = use_llvm,
    });
    b.step("build-ui-overlay-ae7", "Compile exact original ae7 overlay contract regression without executing it").dependOn(&ui_overlay_ae7_tests.step);
    b.step("test-ui-overlay-ae7", "Exercise original ae7 custom overlay ownership through actual Manager frontend and Application").dependOn(&b.addRunArtifact(ui_overlay_ae7_tests).step);

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
    const print_mode_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/print_mode_process_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    const print_mode_run = b.addRunArtifact(print_mode_tests);
    print_mode_run.step.dependOn(b.getInstallStep());
    print_mode_run.setEnvironmentVariable("PI_TEST_BINARY", b.getInstallPath(.bin, b.fmt("pi{s}", .{target.result.os.tag.exeFileExt(target.result.cpu.arch)})));
    b.step("test-print-mode-process", "Exercise final print truncation exit status, stderr, partial stdout, JSON isolation and saved sessions").dependOn(&print_mode_run.step);
    test_step.dependOn(&print_mode_run.step);
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
        .filters = &.{"extensions.typescript."},
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/extension_typescript_test.zig"),
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

    // Isolated original30 comparison; no default test/CLI/SDK selection. Compile
    // target installs the real artifact only; runtime is separately Root-owned.
    const babel30_module = b.createModule(.{ .root_source_file = b.path("src/native_jiti_babel30_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, babel30_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, babel30_module, typescript_parser);
    const babel30_tests = b.addTest(.{ .root_module = babel30_module, .use_llvm = use_llvm, .filters = &.{"native default Babel30"} });
    b.step("build-native-jiti-babel30-backend", "Install original30 native backend comparator without executing it").dependOn(&b.addInstallArtifact(babel30_tests, .{ .dest_sub_path = "native-jiti-babel30-backend.exe" }).step);
    b.step("test-native-jiti-babel30-backend", "Compare all original30 backend records, retaining full mismatches in required owned report").dependOn(&b.addRunArtifact(babel30_tests).step);
    const babel_ast_gpa_module = b.createModule(.{ .root_source_file = b.path("src/native_jiti_babel_ast_allocation_test.zig"), .target = target, .optimize = optimize });
    linkTypeScriptParser(b, babel_ast_gpa_module, typescript_parser);
    const babel_ast_gpa = b.addTest(.{ .root_module = babel_ast_gpa_module, .use_llvm = use_llvm, .filters = &.{"native Babel AST GPA lifecycle"} });
    b.step("build-native-jiti-babel-ast-gpa", "Install separate authored native Babel AST GPA ownership control without running").dependOn(&b.addInstallArtifact(babel_ast_gpa, .{ .dest_sub_path = "native-jiti-babel-ast-gpa.exe" }).step);
    b.step("test-native-jiti-babel-ast-gpa", "Run separate actual allocation lifecycle only after an explicit Root grant").dependOn(&b.addRunArtifact(babel_ast_gpa).step);
    const babel_corrections_module = b.createModule(.{ .root_source_file = b.path("src/native_jiti_babel_corrections_test.zig"), .target = target, .optimize = optimize });
    linkQuickJs(b, babel_corrections_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, babel_corrections_module, typescript_parser);
    const babel_corrections = b.addTest(.{ .root_module = babel_corrections_module, .use_llvm = use_llvm, .filters = &.{"native Babel correction"} });
    b.step("build-native-jiti-babel-corrections", "Install separate authored Babel token/iterator correction controls without running").dependOn(&b.addInstallArtifact(babel_corrections, .{ .dest_sub_path = "native-jiti-babel-corrections.exe" }).step);
    b.step("test-native-jiti-babel-corrections", "Run actual token and iterator controls only after explicit Root grant").dependOn(&b.addRunArtifact(babel_corrections).step);

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
    // The provider module also discovers imported durable shell tests. Their
    // subprocess executable must be installed in this runner's environment.
    run_provider_contract_tests.step.dependOn(&install_durable_fixture.step);
    run_provider_contract_tests.setEnvironmentVariable("PI_DURABLE_FIXTURE", durable_fixture_path);
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
    const agent_coverage_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("tools/agent_allocation_coverage_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    b.step("test-agent-allocation-coverage", "Check each platform group's actual Agent runtime marker ingestion").dependOn(&b.addRunArtifact(agent_coverage_tests).step);
    const exhaustive_coverage_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("tools/exhaustive_allocation_coverage_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    b.step("test-exhaustive-allocation-coverage", "Verify every original failure index and fixed baseline across every platform group").dependOn(&b.addRunArtifact(exhaustive_coverage_tests).step);
    const exhaustive_helper_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/exhaustive_allocation_helper_test.zig"), .target = target, .optimize = optimize }), .use_llvm = use_llvm });
    b.step("test-exhaustive-allocation-helper", "Keep the original failing allocator behavior and complete nondivisible partitions").dependOn(&b.addRunArtifact(exhaustive_helper_tests).step);
    const exhaustive_targets = [_][]const u8{ "test-codemode-allocation", "test-native-codemode-worker-allocation", "test-native-tui-alt-allocation-source", "test-native-codemode-run" };
    const exhaustive_run = b.step("test-hosted-exhaustive-allocation", "Execute all seven original CodeMode worker and TUI failure probes in a bounded range");
    for (exhaustive_targets) |name| exhaustive_run.dependOn(&b.top_level_steps.get(name).?.step);
    addCompileOnlyGroup(b, "build-hosted-exhaustive-allocation", &exhaustive_targets);

    // Select compile/install prerequisites from the existing runtime targets.
    // Their test runners remain outside these cold-compilation steps, including
    // the nested fatal-application checks and process-fixture dependencies.
    addCompileOnlyGroup(b, "build-hosted-core-components", &.{ "test-native-codemode-sandbox", "test-native-codemode-run", "test-native-codemode-vm-worker", "test-native-codemode-controlled-binding", "test-native-durable-148622-wait-cycle", "test-native-durable-json-dto", "test-native-physical-stdio", "test-codemode-inline", "test-codemode-allocation", "test-durable-scheduler", "test-durable-json-clone" });
    addCompileOnlyGroup(b, "build-hosted-latest-components", &.{ "test-native-durable-codemode-outcome", "test-native-durable-codemode-journal-core", "test-custom-editor-frontend", "test-extension-filesystem", "test-print-mode-process", "test-mcp-runtime", "test-mcp-configured", "test-native-tui-alt-source", "test-native-tui-base-source" });
    addCompileOnlyGroup(b, "build-hosted-latest-foundation-components", &.{ "test-native-durable-codemode-outcome", "test-native-durable-codemode-journal-core", "test-extension-filesystem", "test-native-tui-alt-source", "test-native-tui-base-source" });
    addCompileOnlyGroup(b, "build-hosted-latest-application-components", &.{ "test-custom-editor-frontend", "test-print-mode-process", "test-mcp-runtime", "test-mcp-configured" });
    addCompileOnlyGroup(b, "build-hosted-model-components", &.{ "test-native-durable-codemode-model-catalog", "test-native-models-typed-services", "test-native-models-stream-regressions" });
    addCompileOnlyGroup(b, "build-native-models-context-integration", &.{ "test-native-models-typed-services", "test-native-models-stream-regressions", "test-native-ai-transcript-context" });
    addCompileOnlyGroup(b, "build-hosted-catalog-components", &.{ "test-latest-catalog", "test-maintenance", "test-exhaustive-allocation-coverage", "test-exhaustive-allocation-helper", "test-latest12-small-contracts" });
    addCompileOnlyGroup(b, "build-hosted-chord-components", &.{ "test-native-chord-context-source", "test-native-chord-resource-source", "test-native-chord-contract-source", "test-native-chord-clone-source", "test-native-chord-normalization-evaluate-source" });
    addCompileOnlyGroup(b, "build-hosted-sdk-components", &.{ "test-native-sdk-send-user", "test-native-sdk-session-queries", "test-native-sdk-query-consumers", "test-native-sdk-session-lifecycle", "test-native-sdk-message-conversion", "test-native-sdk-session-prepare" });
    addCompileOnlyGroup(b, "build-hosted-sdk-query-components", &.{ "test-native-sdk-session-queries", "test-native-sdk-query-consumers" });
    addCompileOnlyGroup(b, "build-hosted-sdk-message-components", &.{ "test-native-sdk-send-user", "test-native-sdk-message-conversion" });
    addCompileOnlyGroup(b, "build-hosted-sdk-lifecycle-components", &.{ "test-native-sdk-session-lifecycle", "test-native-sdk-session-prepare" });
    addCompileOnlyGroup(b, "build-native-sdk-estimator-regressions", &.{ "test-native-sdk-session-statistics", "test-native-sdk-session-events", "test-native-sdk-session-prepare", "test-native-sdk-session-lifecycle", "test-native-durable-generation", "test-native-durable-89-compaction" });
    addCompileOnlyGroup(b, "build-hosted-sdk-event-components", &.{"test-native-sdk-session-events"});
    addCompileOnlyGroup(b, "build-hosted-auth-components", &.{ "test-native-auth-storage-persistent", "test-native-auth-timer-controls" });
    addCompileOnlyGroup(b, "build-native-sdk-cache-warmer", &.{"test-native-sdk-cache-warmer"});
    addCompileOnlyGroup(b, "build-native-sdk-provider-attribution", &.{"test-native-sdk-provider-attribution"});
    addCompileOnlyGroup(b, "build-native-sdk-factory-provider", &.{"test-native-sdk-factory-provider"});
    addCompileOnlyGroup(b, "build-native-sdk-image-process", &.{"test-native-sdk-image-process"});
    addCompileOnlyGroup(b, "build-native-sdk-constructor-assembly", &.{ "test-native-sdk-constructor-phase", "test-native-sdk-session-values", "test-native-sdk-session-events", "test-native-sdk-tool-name-matcher" });
    addCompileOnlyGroup(b, "build-sdk-settings-ownership", &.{"test-sdk-settings-ownership"});
    addCompileOnlyGroup(b, "build-native-sdk-constructor-phase", &.{"test-native-sdk-constructor-phase"});
    addCompileOnlyGroup(b, "build-native-sdk-session-values", &.{"test-native-sdk-session-values"});
    addCompileOnlyGroup(b, "build-native-sdk-session-events", &.{"test-native-sdk-session-events"});
    addCompileOnlyGroup(b, "build-native-sdk-tool-name-matcher", &.{"test-native-sdk-tool-name-matcher"});
    // Isolated C33+9h qualification aliases install the exact selected artifact.
    // Matching cached binaries can be identified without assuming a new cache path.
    const highlight_gate_artifacts = [_]struct { name: []const u8, artifact: *std.Build.Step.Compile }{
        .{ .name = "foundation", .artifact = highlight_root55_foundation },
        .{ .name = "async26", .artifact = native_async_qualification_tests },
        .{ .name = "generator", .artifact = native_generator_tests },
        .{ .name = "generator-gpa", .artifact = native_generator_gpa_tests },
        .{ .name = "json", .artifact = ai_json_tests },
        .{ .name = "source51", .artifact = ae7_json_transform_tests },
        .{ .name = "operators", .artifact = native_binary_tests },
        .{ .name = "engine", .artifact = engine_tests },
        .{ .name = "recovery", .artifact = highlight_root463_recovery },
        .{ .name = "direct191", .artifact = highlight_complete191_direct },
        .{ .name = "host445", .artifact = highlight_complete191_host },
    };
    for (highlight_gate_artifacts) |gate| {
        const installed_name = b.fmt("highlight-root10db-{s}{s}", .{ gate.name, if (target.result.os.tag == .windows) ".exe" else "" });
        b.step(b.fmt("build-highlight-root10db-{s}", .{gate.name}), "Install exact selected C33+9h qualification artifact without running tests").dependOn(&b.addInstallArtifact(gate.artifact, .{ .dest_sub_path = installed_name }).step);
    }
    // Genuine existing controls: install-only qualification targets. They add
    // no default/runtime edge and do not execute the compile-only213 sentinel.
    const expanded213_existing_runtime = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_expanded213_existing_runtime_selector.zig"), .target = target, .optimize = optimize }),
        .filters = &.{
            "jiti nativeImport actual arrow captures physical base and queued Graph0 identity",
            "native Agent AF correction actual Promise executor marked fault escapes exact reason and wrap",
            "native Agent AF correction successful constructor ignores catchable fresh historical and lookalike data",
            "native Agent AF correction event iterator cancellation remains host fatal before next call",
            "native Agent AF correction retained first executor fatal wins later constructor completions",
            "CommonJS patched script compile only precedes arbitrary actual script execution",
            "CommonJS patched script returns a real five parameter VM function with arbitrary valid body grammar",
            "CommonJS patched script syntax failure precedes body and retains physical filename",
            "CommonJS patched script preserves raw completion and thrown object without Promise adoption",
            "CommonJS load failure fresh private native reason skips guest cache and children cleanup",
            "CommonJS load failure fresh private reason from load getter skips guest cleanup",
            "CommonJS load failure historical private reason follows ordinary finally precedence",
            "CommonJS load failure guest lookalike follows ordinary finally precedence",
            "CommonJS load failure ordinary raw reason survives successful cache and children cleanup",
            "converted CommonJS module uses actual canonical constructor cache parent paths and export snapshot",
            "converted CommonJS module cache publication precedes body and captures live paths callee first",
            "converted CommonJS module ordinary initialization failure removes actual cache and child",
            "converted CommonJS module fresh private initialization failure bypasses guest cleanup",
            "converted CommonJS module entry classifies fresh cache getter fatal without external suppression",
            "converted CommonJS module refuses forged constructor cache records and conflicting actual exports",
            "converted CommonJS provider readiness is private and lazy without cache or parent publication",
            "converted CommonJS provider actual compile selector respects format filenames and patched wrappers",
            "converted CommonJS provider real CJS initializer assigns exact backend without pretending to finish load",
            "converted CommonJS provider stops actual pending ordinary getter before callee and publication",
            "converted CommonJS provider stops actual pending fresh getter before callee and publication",
            "converted CommonJS provider stops actual pending ordinary callee before publication",
            "converted CommonJS provider stops actual pending fresh callee before publication",
        },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, expanded213_existing_runtime.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, expanded213_existing_runtime.root_module, typescript_parser);
    linkSqlite(expanded213_existing_runtime.root_module, sqlite_lib_dir, sqlite_library);
    expanded213_existing_runtime.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        expanded213_existing_runtime.root_module.linkSystemLibrary("advapi32", .{});
        expanded213_existing_runtime.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-expanded213-existing-runtime", "Install27 original runtime controls without sentinel or default activation").dependOn(&b.addInstallArtifact(expanded213_existing_runtime, .{ .dest_sub_path = b.fmt("native-expanded213-existing-runtime{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    // Reuse the actual existing TreeSitter/Zig transformer test artifact and
    // all its original tests. This alias does not select a Node TS compiler.
    b.step("build-native-expanded213-typescript-controls", "Install existing native TypeScript helper controls without running").dependOn(&b.addInstallArtifact(typescript_tests, .{ .dest_sub_path = b.fmt("native-expanded213-typescript-controls{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    // Private SDK semver supplier. Install-only and default-off: Root discovers
    // genuine metadata before any separately granted execution.
    const sdk_semver_six = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_semver_six_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"private SDK semver"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_semver_six.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_semver_six.root_module, typescript_parser);
    linkSqlite(sdk_semver_six.root_module, sqlite_lib_dir, sqlite_library);
    sdk_semver_six.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_semver_six.root_module.linkSystemLibrary("advapi32", .{}); sdk_semver_six.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-semver-six", "Install private SDK six-binding controls without execution").dependOn(&b.addInstallArtifact(sdk_semver_six, .{ .dest_sub_path = b.fmt("native-sdk-semver-six{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    const sdk_semver_original = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_semver785_package_manager_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native semver785"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_semver_original.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_semver_original.root_module, typescript_parser);
    linkSqlite(sdk_semver_original.root_module, sqlite_lib_dir, sqlite_library);
    sdk_semver_original.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_semver_original.root_module.linkSystemLibrary("advapi32", .{}); sdk_semver_original.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-semver-original", "Install genuine original-row replay and GC/fatal controls; original fixture remains required").dependOn(&b.addInstallArtifact(sdk_semver_original, .{ .dest_sub_path = b.fmt("native-sdk-semver-original{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    // Prospective install-only actual-call compile target. No Run/query edge.
    const sdk_exec_compile_only = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_exec_compile_only_root.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_exec_compile_only.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_exec_compile_only.root_module, typescript_parser);
    linkSqlite(sdk_exec_compile_only.root_module, sqlite_lib_dir, sqlite_library);
    sdk_exec_compile_only.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_exec_compile_only.root_module.linkSystemLibrary("advapi32", .{});
        sdk_exec_compile_only.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-exec-compile-only", "Compile actual SDK exec and its real controls; never run/query sentinel").dependOn(&b.addInstallArtifact(sdk_exec_compile_only, .{}).step);
    // Prospective install-only actual-call compile target. No Run/query edge.
    const sdk_git_compile_only = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_git_url_compile_only_root.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_git_compile_only.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_git_compile_only.root_module, typescript_parser);
    linkSqlite(sdk_git_compile_only.root_module, sqlite_lib_dir, sqlite_library);
    sdk_git_compile_only.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        sdk_git_compile_only.root_module.linkSystemLibrary("advapi32", .{});
        sdk_git_compile_only.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-git-url-compile-only", "Compile actual SDK Git supplier and real controls; never run/query sentinel").dependOn(&b.addInstallArtifact(sdk_git_compile_only, .{}).step);
    // Private consumed ignore supplier: install-only; runtime needs a separate Root grant.
    const sdk_ignore708_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_ignore708_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"private consumed ignore708"}, .use_llvm = use_llvm });
    linkQuickJs(b, sdk_ignore708_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_ignore708_tests.root_module, typescript_parser);
    linkSqlite(sdk_ignore708_tests.root_module, sqlite_lib_dir, sqlite_library);
    sdk_ignore708_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_ignore708_tests.root_module.linkSystemLibrary("advapi32", .{}); sdk_ignore708_tests.root_module.linkSystemLibrary("userenv", .{}); }
    const sdk_ignore708_install = b.addInstallArtifact(sdk_ignore708_tests, .{ .dest_sub_path = b.fmt("native-sdk-ignore708{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) });
    b.step("build-native-sdk-ignore708", "Install genuine private ignore708 controls without execution").dependOn(&sdk_ignore708_install.step);
    // INSTALL ONLY; no run/default activation edge. Actual metadata remains unknown.
    const session_bindings_af=b.addTest(.{
        .root_module=b.createModule(.{.root_source_file=b.path("src/native_sdk_session_bindings_af_test.zig"),.target=target,.optimize=optimize}),
        .use_llvm=use_llvm,
    });
    linkQuickJs(b,session_bindings_af.root_module,quickjs,sqlite_lib_dir);
    linkSqlite(session_bindings_af.root_module,sqlite_lib_dir,sqlite_library);
    linkTypeScriptParser(b,session_bindings_af.root_module,typescript_parser);
    session_bindings_af.root_module.addImport("catalog_tool",catalog_tool);
    if(target.result.os.tag==.windows){session_bindings_af.root_module.linkSystemLibrary("advapi32",.{});session_bindings_af.root_module.linkSystemLibrary("userenv",.{});}
    const session_bindings_af_install=b.addInstallArtifact(session_bindings_af,.{});
    b.step("build-native-sdk-session-bindings-af","Compile actual session binding AF causal controls").dependOn(&session_bindings_af_install.step);
    // Isolated VM composition. These steps install test artifacts only; they
    // neither select a default module nor attach a test runner to a build step.
    const vm_controls = b.step("build-native-vm-c4-c5-callsite-controls", "Install individual and combined query link iterator and CallSite controls without execution");
    b.step("build-native-vm-c4-c5-callsite-link-controls", "Install the reviewed VM composition controls without execution").dependOn(vm_controls);
    const vm_control_specs = [_]struct { name: []const u8, root: []const u8, filters: []const []const u8 }{
        .{ .name = "query", .root = "src/native_module_graph_tla_query_test.zig", .filters = &.{"module graph TLA query "} },
        .{ .name = "iterator", .root = "src/native_async_iterator_api_test.zig", .filters = &.{"native async iterator API "} },
        .{ .name = "callsite", .root = "src/native_callsite_visibility_test.zig", .filters = &.{"CallSite visibility "} },
        .{ .name = "link", .root = "src/native_module_link_transaction_test.zig", .filters = &.{"module link transaction"} },
        .{ .name = "combined", .root = "src/native_c3_c4_c5_callsite_test.zig", .filters = &.{ "module graph TLA query ", "native async iterator API ", "CallSite visibility ", "module link transaction", "VM query link iterator CallSite composition" } },
    };
    for (vm_control_specs) |entry| {
        const module = b.createModule(.{ .root_source_file = b.path(entry.root), .target = target, .optimize = optimize });
        module.addImport("catalog_tool", catalog_tool);
        linkQuickJs(b, module, quickjs, sqlite_lib_dir);
        linkSqlite(module, sqlite_lib_dir, sqlite_library);
        if (std.mem.eql(u8, entry.name, "link") or std.mem.eql(u8, entry.name, "combined"))
            module.addCSourceFile(.{ .file = b.path("src/native_module_link_allocator_controls.c"), .flags = &.{"-std=gnu11"} });
        const controls = b.addTest(.{ .root_module = module, .use_llvm = use_llvm, .filters = entry.filters });
        const installed_name = b.fmt("vm-c4-c5-callsite-{s}{s}", .{ entry.name, if (target.result.os.tag == .windows) ".exe" else "" });
        const install = b.addInstallArtifact(controls, .{ .dest_sub_path = installed_name });
        b.step(b.fmt("build-native-vm-c4-c5-callsite-{s}", .{entry.name}), "Install exact isolated VM controls; metadata and runtime require separate grants").dependOn(&install.step);
        vm_controls.dependOn(&install.step);
    }

    // The accepted C3 queued/binding eleven-entry addendum is separate from150.
    const vm_current11 = b.step("build-native-vm-c3-current11", "Install the unchanged current C3 queued and binding controls without execution");
    inline for (.{
        .{ "queued", "src/native_dynamic_import_graph0_test.zig", "queued Graph0 import " },
        .{ "binding", "src/native_extension_graph0_binding_test.zig", "actual Graph0 binding " },
    }) |entry| {
        const module = b.createModule(.{ .root_source_file = b.path(entry[1]), .target = target, .optimize = optimize });
        module.addImport("catalog_tool", catalog_tool);
        linkQuickJs(b, module, quickjs, sqlite_lib_dir);
        linkSqlite(module, sqlite_lib_dir, sqlite_library);
        const controls = b.addTest(.{ .root_module = module, .use_llvm = use_llvm, .filters = &.{entry[2]} });
        const installed_name = b.fmt("vm-c3-current11-{s}{s}", .{ entry[0], if (target.result.os.tag == .windows) ".exe" else "" });
        const install = b.addInstallArtifact(controls, .{ .dest_sub_path = installed_name });
        b.step(b.fmt("build-native-vm-c3-current11-{s}", .{entry[0]}), "Install one genuine queued or binding C3 selection without execution").dependOn(&install.step);
        vm_current11.dependOn(&install.step);
    }

    // Reuse the existing selected Compile objects, filters and original bodies.
    // Distinct install names preserve every group instead of overwriting test.exe.
    const vm_retained = b.step("build-native-vm-c3-retained150", "Install the original fifteen C3 regression groups without execution or qualification transfer");
    const vm_retained_groups = [_]struct { name: []const u8, artifact: *std.Build.Step.Compile }{
        .{ .name = "focused-start", .artifact = native_tla_fatal_tests },
        .{ .name = "focused-resumed", .artifact = resumed_tla_tests },
        .{ .name = "focused-resolving", .artifact = native_af_resolving_tests },
        .{ .name = "focused-inactive", .artifact = native_await_inactive_tests },
        .{ .name = "focused-shared", .artifact = shared_thenable_tests },
        .{ .name = "core-foundation", .artifact = highlight_root55_foundation },
        .{ .name = "core-async26", .artifact = native_async_qualification_tests },
        .{ .name = "core-generator", .artifact = native_generator_tests },
        .{ .name = "core-generator-gpa", .artifact = native_generator_gpa_tests },
        .{ .name = "core-json", .artifact = ai_json_tests },
        .{ .name = "core-source51", .artifact = ae7_json_transform_tests },
        .{ .name = "core-operators", .artifact = native_binary_tests },
        .{ .name = "core-engine", .artifact = engine_tests },
        .{ .name = "core-recovery", .artifact = highlight_root463_recovery },
        .{ .name = "core-sdk-boundary", .artifact = sdk_exception_boundary_tests },
    };
    for (vm_retained_groups) |group| {
        const installed_name = b.fmt("vm-c3-retained-{s}{s}", .{ group.name, if (target.result.os.tag == .windows) ".exe" else "" });
        const install = b.addInstallArtifact(group.artifact, .{ .dest_sub_path = installed_name });
        b.step(b.fmt("build-native-vm-c3-retained-{s}", .{group.name}), "Install one unchanged C3 regression selection without execution").dependOn(&install.step);
        vm_retained.dependOn(&install.step);
    }
    // Additional DATA/receiver controls remain separate from the unchanged62.
    const vm_af_receiver = b.step("build-native-vm-af-receiver-controls", "Install actual AF DATA and receiver Get controls without execution");
    inline for (.{
        .{ "af-throw", "src/native_await_rejection_data_test.zig", &[_][]const u8{"native Await DATA"} },
        .{ "receiver-get", "src/native_receiver_get_test.zig", &[_][]const u8{"receiver Get"} },
        .{ "af-receiver-combined", "src/native_af_receiver_composition_test.zig", &[_][]const u8{ "native Await DATA", "receiver Get", "VM AF receiver composition" } },
    }) |entry| {
        const module = b.createModule(.{ .root_source_file = b.path(entry[1]), .target = target, .optimize = optimize });
        module.addImport("catalog_tool", catalog_tool);
        linkQuickJs(b, module, quickjs, sqlite_lib_dir);
        linkSqlite(module, sqlite_lib_dir, sqlite_library);
        const controls = b.addTest(.{ .root_module = module, .use_llvm = use_llvm, .filters = entry[2] });
        const installed_name = b.fmt("vm-{s}{s}", .{ entry[0], if (target.result.os.tag == .windows) ".exe" else "" });
        const install = b.addInstallArtifact(controls, .{ .dest_sub_path = installed_name });
        b.step(b.fmt("build-native-vm-{s}", .{entry[0]}), "Install one actual additional VM selection without execution").dependOn(&install.step);
        vm_af_receiver.dependOn(&install.step);
    }
    // Actual shared Engine retirement controls, install-only/default-off.
    const engine_owned_retirement = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_engine_owned_retirement_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"shared Engine retirement"}, .use_llvm = use_llvm });
    linkQuickJs(b, engine_owned_retirement.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, engine_owned_retirement.root_module, typescript_parser);
    linkSqlite(engine_owned_retirement.root_module, sqlite_lib_dir, sqlite_library);
    engine_owned_retirement.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { engine_owned_retirement.root_module.linkSystemLibrary("advapi32", .{}); engine_owned_retirement.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-engine-owned-retirement", "Install actual Engine owned-retirement controls without execution").dependOn(&b.addInstallArtifact(engine_owned_retirement, .{ .dest_sub_path = b.fmt("native-engine-owned-retirement{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    // Actual Node guest-operation controls; installed only until runtime grant.
    const node_operation_boundary = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_operation_boundary_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "native Node operation", "native Node callable", "native Node constructor", "native Node Scope" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, node_operation_boundary.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_operation_boundary.root_module, typescript_parser);
    linkSqlite(node_operation_boundary.root_module, sqlite_lib_dir, sqlite_library);
    node_operation_boundary.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_operation_boundary.root_module.linkSystemLibrary("advapi32", .{});
        node_operation_boundary.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-operation-boundary", "Install Node pending/data/allocator ownership controls without running").dependOn(&b.addInstallArtifact(node_operation_boundary, .{ .dest_sub_path = b.fmt("native-node-operation-boundary{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    const chalk_ignore_guest = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_chalk_ignore_guest_guard_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{ "native private Chalk Ignore", "native genuine private Chalk Ignore" },
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, chalk_ignore_guest.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, chalk_ignore_guest.root_module, typescript_parser);
    linkSqlite(chalk_ignore_guest.root_module, sqlite_lib_dir, sqlite_library);
    chalk_ignore_guest.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        chalk_ignore_guest.root_module.linkSystemLibrary("advapi32", .{});
        chalk_ignore_guest.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-sdk-chalk-ignore-guest", "Install actual Chalk and Ignore guest operation controls").dependOn(&b.addInstallArtifact(chalk_ignore_guest, .{ .dest_sub_path = b.fmt("native-sdk-chalk-ignore-guest{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    const cjs_compiler_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_cjs_body_compiler_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native CJS compiler"}, .use_llvm = use_llvm });
    linkQuickJs(b, cjs_compiler_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(cjs_compiler_tests.root_module, sqlite_lib_dir, sqlite_library);
    cjs_compiler_tests.root_module.addImport("catalog_tool", catalog_tool);
    cjs_compiler_tests.root_module.addCSourceFile(.{ .file = b.path("src/native_cjs_allocator_controls.c"), .flags = &.{"-std=gnu11"} });
    b.step("build-native-cjs-body-compiler", "Compile direct CJS body and detached module syntax controls").dependOn(&b.addInstallArtifact(cjs_compiler_tests, .{}).step);
    const cjs_metadata_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_cjs_source_metadata_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native CJS metadata"}, .use_llvm = use_llvm });
    linkQuickJs(b, cjs_metadata_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(cjs_metadata_tests.root_module, sqlite_lib_dir, sqlite_library);
    cjs_metadata_tests.root_module.addImport("catalog_tool", catalog_tool);
    cjs_metadata_tests.root_module.addCSourceFile(.{ .file = b.path("src/native_cjs_allocator_controls.c"), .flags = &.{"-std=gnu11"} });
    b.step("build-native-cjs-source-metadata", "Compile actual lexer metadata and dual-origin ownership controls").dependOn(&b.addInstallArtifact(cjs_metadata_tests, .{}).step);
    const cjs_raw_provider_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_commonjs_body_compiler_test.zig"), .target = target, .optimize = optimize }), .filters = &.{"native CJS raw provider"}, .use_llvm = use_llvm });
    linkQuickJs(b, cjs_raw_provider_tests.root_module, quickjs, sqlite_lib_dir);
    linkSqlite(cjs_raw_provider_tests.root_module, sqlite_lib_dir, sqlite_library);
    cjs_raw_provider_tests.root_module.addImport("catalog_tool", catalog_tool);
    b.step("build-native-node-commonjs-raw-body-provider", "Compile actual raw CJS compiler adapter controls").dependOn(&b.addInstallArtifact(cjs_raw_provider_tests, .{}).step);


    const pkce_genuine_af_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_pkce_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native OAuth PKCE"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, pkce_genuine_af_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, pkce_genuine_af_tests.root_module, typescript_parser);
    linkSqlite(pkce_genuine_af_tests.root_module, sqlite_lib_dir, sqlite_library);
    pkce_genuine_af_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        pkce_genuine_af_tests.root_module.linkSystemLibrary("advapi32", .{});
        pkce_genuine_af_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-ai-oauth-pkce-genuine-af", "Install actual PKCE Source and genuine native AF controls").dependOn(&b.addInstallArtifact(pkce_genuine_af_tests, .{ .dest_sub_path = b.fmt("native-ai-oauth-pkce-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    const device_code_genuine_af_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_device_code_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native OAuth device code"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, device_code_genuine_af_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, device_code_genuine_af_tests.root_module, typescript_parser);
    linkSqlite(device_code_genuine_af_tests.root_module, sqlite_lib_dir, sqlite_library);
    device_code_genuine_af_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        device_code_genuine_af_tests.root_module.linkSystemLibrary("advapi32", .{});
        device_code_genuine_af_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-ai-oauth-device-code-genuine-af", "Install actual device code Source and genuine native controls").dependOn(&b.addInstallArtifact(device_code_genuine_af_tests, .{ .dest_sub_path = b.fmt("native-ai-oauth-device-code-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual child graph and physical spawn/wait controls. Install only: no Run
    // edge, metadata execution or descendant operation is started by this step.
    const child_frontend_genuine = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_child_frontend_genuine_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native actual child"},
    });
    linkQuickJs(b, child_frontend_genuine.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, child_frontend_genuine.root_module, typescript_parser);
    linkSqlite(child_frontend_genuine.root_module, sqlite_lib_dir, sqlite_library);
    child_frontend_genuine.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        child_frontend_genuine.root_module.linkSystemLibrary("advapi32", .{});
        child_frontend_genuine.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-child-frontend-genuine", "Install eleven declared actual child frontend and live OS waiter controls without running").dependOn(&b.addInstallArtifact(child_frontend_genuine, .{ .dest_sub_path = b.fmt("native-child-frontend-genuine{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    const ai_sleep_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_sleep_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native AI sleep"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, ai_sleep_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, ai_sleep_tests.root_module, typescript_parser);
    linkSqlite(ai_sleep_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_sleep_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        ai_sleep_tests.root_module.linkSystemLibrary("advapi32", .{});
        ai_sleep_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-ai-sleep", "Install actual Source sleep producer and timer ownership controls").dependOn(&b.addInstallArtifact(ai_sleep_tests, .{ .dest_sub_path = b.fmt("native-ai-sleep{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    const kimi_genuine_af_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_kimi_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native OAuth Kimi"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, kimi_genuine_af_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, kimi_genuine_af_tests.root_module, typescript_parser);
    linkSqlite(kimi_genuine_af_tests.root_module, sqlite_lib_dir, sqlite_library);
    kimi_genuine_af_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        kimi_genuine_af_tests.root_module.linkSystemLibrary("advapi32", .{});
        kimi_genuine_af_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-ai-oauth-kimi-genuine-af", "Install actual Kimi Source and genuine OAuth continuation controls").dependOn(&b.addInstallArtifact(kimi_genuine_af_tests, .{ .dest_sub_path = b.fmt("native-ai-oauth-kimi-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    const provider_env_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_provider_env_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native provider env"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, provider_env_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, provider_env_tests.root_module, typescript_parser);
    linkSqlite(provider_env_tests.root_module, sqlite_lib_dir, sqlite_library);
    provider_env_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        provider_env_tests.root_module.linkSystemLibrary("advapi32", .{});
        provider_env_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-provider-env", "Install actual provider environment Source and native lifetime controls").dependOn(&b.addInstallArtifact(provider_env_tests, .{ .dest_sub_path = b.fmt("native-provider-env{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual public Session helpers; install-only pending a separate native grant.
    const sdk_public_session = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_public_session_helpers_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public session"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_session.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_session.root_module, typescript_parser);
    linkSqlite(sdk_public_session.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_session.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_public_session.root_module.linkSystemLibrary("advapi32", .{}); sdk_public_session.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-public-session-helpers", "Install actual public Session helper and real owner controls without execution").dependOn(&b.addInstallArtifact(sdk_public_session, .{ .dest_sub_path = b.fmt("native-sdk-public-session-helpers{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);    // Actual Node package reader and native filesystem controls. Installation
    // Actual public model resolver caller controls; no runtime step is added.
    const sdk_public_models = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_public_model_resolver_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public model resolver"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_models.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_models.root_module, typescript_parser);
    linkSqlite(sdk_public_models.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_models.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_public_models.root_module.linkSystemLibrary("advapi32", .{}); sdk_public_models.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-public-model-resolver", "Install actual public model resolver caller controls without execution").dependOn(&b.addInstallArtifact(sdk_public_models, .{ .dest_sub_path = b.fmt("native-sdk-public-model-resolver{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual public compaction core controls; this target installs without execution.
    const sdk_public_compaction = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_public_compaction_core_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public compaction core"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_compaction.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_compaction.root_module, typescript_parser);
    linkSqlite(sdk_public_compaction.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_compaction.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_public_compaction.root_module.linkSystemLibrary("advapi32", .{}); sdk_public_compaction.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-public-compaction-core", "Install actual public compaction core and expression controls without execution").dependOn(&b.addInstallArtifact(sdk_public_compaction, .{ .dest_sub_path = b.fmt("native-sdk-public-compaction-core{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual public serializer and text owner controls; install-only target.
    const sdk_public_compaction_text = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_public_compaction_text_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public compaction text"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_compaction_text.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_compaction_text.root_module, typescript_parser);
    linkSqlite(sdk_public_compaction_text.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_compaction_text.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_public_compaction_text.root_module.linkSystemLibrary("advapi32", .{}); sdk_public_compaction_text.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-public-compaction-text", "Install actual serializer text extraction and ownership controls without execution").dependOn(&b.addInstallArtifact(sdk_public_compaction_text, .{ .dest_sub_path = b.fmt("native-sdk-public-compaction-text{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);



    // only; metadata and runtime require Root's separately bounded controller.
    const node_package_reader = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_package_reader_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native package"},
    });
    linkQuickJs(b, node_package_reader.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_package_reader.root_module, typescript_parser);
    linkSqlite(node_package_reader.root_module, sqlite_lib_dir, sqlite_library);
    node_package_reader.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_package_reader.root_module.linkSystemLibrary("advapi32", .{});
        node_package_reader.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-package-reader", "Install twenty-one declared actual package reader and native path controls without running").dependOn(&b.addInstallArtifact(node_package_reader, .{ .dest_sub_path = b.fmt("native-node-package-reader{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Real FS binding-owned stat arrays, SafeSet and internal realm. Install
    // only; no metadata, guest script or native runtime is launched here.
    const node_fs_primitives = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_fs_primitives_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native fs primitives"},
    });
    linkQuickJs(b, node_fs_primitives.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_fs_primitives.root_module, typescript_parser);
    linkSqlite(node_fs_primitives.root_module, sqlite_lib_dir, sqlite_library);
    node_fs_primitives.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_fs_primitives.root_module.linkSystemLibrary("advapi32", .{});
        node_fs_primitives.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-fs-primitives", "Install ten declared actual filesystem binding primitive controls without running").dependOn(&b.addInstallArtifact(node_fs_primitives, .{ .dest_sub_path = b.fmt("native-node-fs-primitives{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual Meta provider caller controls; install only, no runtime step.
    const meta_actual = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_meta_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native OAuth Meta"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, meta_actual.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, meta_actual.root_module, typescript_parser);
    linkSqlite(meta_actual.root_module, sqlite_lib_dir, sqlite_library);
    meta_actual.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { meta_actual.root_module.linkSystemLibrary("advapi32", .{}); meta_actual.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-ai-oauth-meta-genuine-af", "Install actual Meta OAuth caller controls without execution").dependOn(&b.addInstallArtifact(meta_actual, .{ .dest_sub_path = b.fmt("native-ai-oauth-meta-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual Xai provider caller controls; install only, no runtime step.
    const xai_actual = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_xai_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native OAuth Xai"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, xai_actual.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, xai_actual.root_module, typescript_parser);
    linkSqlite(xai_actual.root_module, sqlite_lib_dir, sqlite_library);
    xai_actual.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { xai_actual.root_module.linkSystemLibrary("advapi32", .{}); xai_actual.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-ai-oauth-xai-genuine-af", "Install actual Xai OAuth caller controls without execution").dependOn(&b.addInstallArtifact(xai_actual, .{ .dest_sub_path = b.fmt("native-ai-oauth-xai-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual OpenRouter provider caller controls; install only, no runtime step.
    const openrouter_actual = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_openrouter_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native OAuth OpenRouter"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, openrouter_actual.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, openrouter_actual.root_module, typescript_parser);
    linkSqlite(openrouter_actual.root_module, sqlite_lib_dir, sqlite_library);
    openrouter_actual.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { openrouter_actual.root_module.linkSystemLibrary("advapi32", .{}); openrouter_actual.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-ai-oauth-openrouter-genuine-af", "Install actual OpenRouter OAuth caller controls without execution").dependOn(&b.addInstallArtifact(openrouter_actual, .{ .dest_sub_path = b.fmt("native-ai-oauth-openrouter-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);



    // Actual captured Node inspector entry and provenance controls, installed
    // without running the artifact or its separately sealed Source observer.
    const node_inspect_entry = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_inspect_entry_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native actual inspect"},
    });
    linkQuickJs(b, node_inspect_entry.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_inspect_entry.root_module, typescript_parser);
    linkSqlite(node_inspect_entry.root_module, sqlite_lib_dir, sqlite_library);
    node_inspect_entry.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_inspect_entry.root_module.linkSystemLibrary("advapi32", .{});
        node_inspect_entry.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-inspect-entry", "Install thirteen declared actual inspector entry controls without running").dependOn(&b.addInstallArtifact(node_inspect_entry, .{ .dest_sub_path = b.fmt("native-node-inspect-entry{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual public file-operation controls; install-only target.
    const sdk_public_compaction_file_ops = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_public_compaction_file_ops_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public compaction file operations"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_compaction_file_ops.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_compaction_file_ops.root_module, typescript_parser);
    linkSqlite(sdk_public_compaction_file_ops.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_compaction_file_ops.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_public_compaction_file_ops.root_module.linkSystemLibrary("advapi32", .{}); sdk_public_compaction_file_ops.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-public-compaction-file-ops", "Install actual file operations array append and ownership controls without execution").dependOn(&b.addInstallArtifact(sdk_public_compaction_file_ops, .{ .dest_sub_path = b.fmt("native-sdk-public-compaction-file-ops{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Genuine shared Node argument errors and actual rest/super controls.
    // This target only installs the test artifact; no run or Source capture edge.
    const node_argument_errors = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_argument_errors_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native actual argument"},
    });
    linkQuickJs(b, node_argument_errors.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_argument_errors.root_module, typescript_parser);
    linkSqlite(node_argument_errors.root_module, sqlite_lib_dir, sqlite_library);
    node_argument_errors.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_argument_errors.root_module.linkSystemLibrary("advapi32", .{});
        node_argument_errors.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-argument-errors", "Install twenty-one declared actual Node argument owner controls without running").dependOn(&b.addInstallArtifact(node_argument_errors, .{ .dest_sub_path = b.fmt("native-node-argument-errors{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual branch collection and preparation controls; install-only target.
    const sdk_public_branch_entries = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_public_branch_entries_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public branch entries"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_branch_entries.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_branch_entries.root_module, typescript_parser);
    linkSqlite(sdk_public_branch_entries.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_branch_entries.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_public_branch_entries.root_module.linkSystemLibrary("advapi32", .{}); sdk_public_branch_entries.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-public-branch-entries", "Install actual branch collection budget preparation and ownership controls without execution").dependOn(&b.addInstallArtifact(sdk_public_branch_entries, .{ .dest_sub_path = b.fmt("native-sdk-public-branch-entries{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Genuine c268 summary/compaction and actual conversion dependencies.
    const sdk_summary_genuine_af = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_summary_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK summary genuine AF"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_summary_genuine_af.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_summary_genuine_af.root_module, typescript_parser);
    linkSqlite(sdk_summary_genuine_af.root_module, sqlite_lib_dir, sqlite_library);
    sdk_summary_genuine_af.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_summary_genuine_af.root_module.linkSystemLibrary("advapi32", .{}); sdk_summary_genuine_af.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-summary-genuine-af", "Install actual summary and compaction async controls without execution").dependOn(&b.addInstallArtifact(sdk_summary_genuine_af, .{ .dest_sub_path = b.fmt("native-sdk-summary-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Genuine branch-summary AF over the actual summary and entry owners.
    const sdk_branch_summary_genuine_af = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_branch_summary_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK branch summary genuine AF"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_branch_summary_genuine_af.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_branch_summary_genuine_af.root_module, typescript_parser);
    linkSqlite(sdk_branch_summary_genuine_af.root_module, sqlite_lib_dir, sqlite_library);
    sdk_branch_summary_genuine_af.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_branch_summary_genuine_af.root_module.linkSystemLibrary("advapi32", .{}); sdk_branch_summary_genuine_af.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-branch-summary-genuine-af", "Install actual branch summary async controls without execution").dependOn(&b.addInstallArtifact(sdk_branch_summary_genuine_af, .{ .dest_sub_path = b.fmt("native-sdk-branch-summary-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual public compaction bindings over the genuine shared AI graph.
    const sdk_public_compaction_namespace = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_public_compaction_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public compaction"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_compaction_namespace.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_compaction_namespace.root_module, typescript_parser);
    linkSqlite(sdk_public_compaction_namespace.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_compaction_namespace.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_public_compaction_namespace.root_module.linkSystemLibrary("advapi32", .{}); sdk_public_compaction_namespace.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-public-compaction", "Install actual shared compaction namespace controls without execution").dependOn(&b.addInstallArtifact(sdk_public_compaction_namespace, .{ .dest_sub_path = b.fmt("native-sdk-public-compaction{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual c268 EventBus over the genuine shared EventEmitter import.
    const sdk_event_bus_public = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_event_bus_public_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK EventBus"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_event_bus_public.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_event_bus_public.root_module, typescript_parser);
    linkSqlite(sdk_event_bus_public.root_module, sqlite_lib_dir, sqlite_library);
    sdk_event_bus_public.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_event_bus_public.root_module.linkSystemLibrary("advapi32", .{}); sdk_event_bus_public.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-event-bus-public", "Install actual EventBus factory and async controls without execution").dependOn(&b.addInstallArtifact(sdk_event_bus_public, .{ .dest_sub_path = b.fmt("native-sdk-event-bus-public{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual c268 context helpers and the shared renderer/source-info owners.
    const sdk_public_context_helpers = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_public_context_helpers_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK context helpers"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_public_context_helpers.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_public_context_helpers.root_module, typescript_parser);
    linkSqlite(sdk_public_context_helpers.root_module, sqlite_lib_dir, sqlite_library);
    sdk_public_context_helpers.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_public_context_helpers.root_module.linkSystemLibrary("advapi32", .{}); sdk_public_context_helpers.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-public-context-helpers", "Install actual c268 context helper controls without execution").dependOn(&b.addInstallArtifact(sdk_public_context_helpers, .{ .dest_sub_path = b.fmt("native-sdk-public-context-helpers{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Genuine internal/fs/utils helpers; installation has no execution edge.
    const node_fs_path_helpers = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_fs_path_helpers_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native actual fs path"},
    });
    linkQuickJs(b, node_fs_path_helpers.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_fs_path_helpers.root_module, typescript_parser);
    linkSqlite(node_fs_path_helpers.root_module, sqlite_lib_dir, sqlite_library);
    node_fs_path_helpers.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_fs_path_helpers.root_module.linkSystemLibrary("advapi32", .{});
        node_fs_path_helpers.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-fs-path-helpers", "Install eighteen declared genuine Node filesystem helper controls without running").dependOn(&b.addInstallArtifact(node_fs_path_helpers, .{ .dest_sub_path = b.fmt("native-node-fs-path-helpers{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Nineteen authored internal/url controls; installation has no execution edge.
    const node_file_url_paths = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_file_url_paths_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native actual file URL"},
    });
    linkQuickJs(b, node_file_url_paths.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_file_url_paths.root_module, typescript_parser);
    linkSqlite(node_file_url_paths.root_module, sqlite_lib_dir, sqlite_library);
    node_file_url_paths.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_file_url_paths.root_module.linkSystemLibrary("advapi32", .{});
        node_file_url_paths.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-file-url-paths", "Install nineteen declared genuine Node file URL controls without running").dependOn(&b.addInstallArtifact(node_file_url_paths, .{ .dest_sub_path = b.fmt("native-node-file-url-paths{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    const node_fs_realpath_classic = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_fs_realpath_classic_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native actual classic realpath"},
    });
    linkQuickJs(b, node_fs_realpath_classic.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_fs_realpath_classic.root_module, typescript_parser);
    linkSqlite(node_fs_realpath_classic.root_module, sqlite_lib_dir, sqlite_library);
    node_fs_realpath_classic.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_fs_realpath_classic.root_module.linkSystemLibrary("advapi32", .{});
        node_fs_realpath_classic.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-fs-realpath-classic", "Install twenty-one declared genuine Node classic realpath controls without running").dependOn(&b.addInstallArtifact(node_fs_realpath_classic, .{ .dest_sub_path = b.fmt("native-node-fs-realpath-classic{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    const node_module_creation = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_module_creation_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native actual Module creation"},
    });
    linkQuickJs(b, node_module_creation.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_module_creation.root_module, typescript_parser);
    linkSqlite(node_module_creation.root_module, sqlite_lib_dir, sqlite_library);
    node_module_creation.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_module_creation.root_module.linkSystemLibrary("advapi32", .{});
        node_module_creation.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-module-creation", "Install twenty-four declared genuine Module creation controls without running").dependOn(&b.addInstallArtifact(node_module_creation, .{ .dest_sub_path = b.fmt("native-node-module-creation{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual frontmatter and BOM call chain with the existing native YAML import.
    const sdk_frontmatter_public = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_frontmatter_public_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public frontmatter"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_frontmatter_public.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_frontmatter_public.root_module, typescript_parser);
    linkSqlite(sdk_frontmatter_public.root_module, sqlite_lib_dir, sqlite_library);
    sdk_frontmatter_public.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_frontmatter_public.root_module.linkSystemLibrary("advapi32", .{}); sdk_frontmatter_public.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-frontmatter-public", "Install actual public frontmatter controls without execution").dependOn(&b.addInstallArtifact(sdk_frontmatter_public, .{ .dest_sub_path = b.fmt("native-sdk-frontmatter-public{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    // Actual public ModelRegistry constructor, methods, and genuine auth AFs.
    const sdk_model_registry_public = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_model_registry_public_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public ModelRegistry"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_model_registry_public.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_model_registry_public.root_module, typescript_parser);
    linkSqlite(sdk_model_registry_public.root_module, sqlite_lib_dir, sqlite_library);
    sdk_model_registry_public.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_model_registry_public.root_module.linkSystemLibrary("advapi32", .{}); sdk_model_registry_public.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-model-registry-public", "Install actual public ModelRegistry controls without execution").dependOn(&b.addInstallArtifact(sdk_model_registry_public, .{ .dest_sub_path = b.fmt("native-sdk-model-registry-public{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    const node_module_search_paths = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_node_module_search_paths_test.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .filters = &.{"native actual Module search paths"},
    });
    linkQuickJs(b, node_module_search_paths.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, node_module_search_paths.root_module, typescript_parser);
    linkSqlite(node_module_search_paths.root_module, sqlite_lib_dir, sqlite_library);
    node_module_search_paths.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        node_module_search_paths.root_module.linkSystemLibrary("advapi32", .{});
        node_module_search_paths.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-node-module-search-paths", "Install twenty declared genuine Module search-path controls without running").dependOn(&b.addInstallArtifact(node_module_search_paths, .{ .dest_sub_path = b.fmt("native-node-module-search-paths{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);


    // Actual Anthropic bodies with source-derived, controlled lexical imports.
    const ai_oauth_anthropic_genuine_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_oauth_anthropic_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native OAuth Anthropic"}, .use_llvm = use_llvm,
    });
    linkQuickJs(b, ai_oauth_anthropic_genuine_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, ai_oauth_anthropic_genuine_tests.root_module, typescript_parser);
    linkSqlite(ai_oauth_anthropic_genuine_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_oauth_anthropic_genuine_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) {
        ai_oauth_anthropic_genuine_tests.root_module.linkSystemLibrary("advapi32", .{});
        ai_oauth_anthropic_genuine_tests.root_module.linkSystemLibrary("userenv", .{});
    }
    b.step("build-native-ai-oauth-anthropic-genuine-af", "Install genuine Anthropic function and ownership controls without execution").dependOn(&b.addInstallArtifact(ai_oauth_anthropic_genuine_tests, .{ .dest_sub_path = b.fmt("native-ai-oauth-anthropic-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);
    // Actual complete tool-search module and zero-Await public executor.
    const sdk_tool_search_public = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_sdk_tool_search_public_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"SDK public tool search"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, sdk_tool_search_public.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, sdk_tool_search_public.root_module, typescript_parser);
    linkSqlite(sdk_tool_search_public.root_module, sqlite_lib_dir, sqlite_library);
    sdk_tool_search_public.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { sdk_tool_search_public.root_module.linkSystemLibrary("advapi32", .{}); sdk_tool_search_public.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-sdk-tool-search-public", "Install actual public tool-search controls without execution").dependOn(&b.addInstallArtifact(sdk_tool_search_public, .{ .dest_sub_path = b.fmt("native-sdk-tool-search-public{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);


    // Exact Radius config module, including its genuine asynchronous load.
    const ai_radius_config_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_radius_config_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native Radius config"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, ai_radius_config_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, ai_radius_config_tests.root_module, typescript_parser);
    linkSqlite(ai_radius_config_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_radius_config_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { ai_radius_config_tests.root_module.linkSystemLibrary("advapi32", .{}); ai_radius_config_tests.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-ai-radius-config", "Install actual Radius config controls without execution").dependOn(&b.addInstallArtifact(ai_radius_config_tests, .{ .dest_sub_path = b.fmt("native-ai-radius-config{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

    const ai_radius_provider_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/native_ai_radius_provider_genuine_af_test.zig"), .target = target, .optimize = optimize }),
        .filters = &.{"native Radius provider"},
        .use_llvm = use_llvm,
    });
    linkQuickJs(b, ai_radius_provider_tests.root_module, quickjs, sqlite_lib_dir);
    linkTypeScriptParser(b, ai_radius_provider_tests.root_module, typescript_parser);
    linkSqlite(ai_radius_provider_tests.root_module, sqlite_lib_dir, sqlite_library);
    ai_radius_provider_tests.root_module.addImport("catalog_tool", catalog_tool);
    if (target.result.os.tag == .windows) { ai_radius_provider_tests.root_module.linkSystemLibrary("advapi32", .{}); ai_radius_provider_tests.root_module.linkSystemLibrary("userenv", .{}); }
    b.step("build-native-ai-radius-provider-genuine-af", "Install genuine Radius provider and closure controls without execution").dependOn(&b.addInstallArtifact(ai_radius_provider_tests, .{ .dest_sub_path = b.fmt("native-ai-radius-provider-genuine-af{s}", .{if (target.result.os.tag == .windows) ".exe" else ""}) }).step);

}

fn addCompileOnlyGroup(b: *std.Build, name: []const u8, runtime_names: []const []const u8) void {
    const target = b.step(name, "Compile hosted component artifacts and install fixtures without running tests");
    var visited: std.AutoHashMap(*std.Build.Step, void) = .init(b.allocator);
    defer visited.deinit();
    for (runtime_names) |runtime_name| {
        const source = &b.top_level_steps.get(runtime_name).?.step;
        addCompilePrerequisites(target, source, &visited) catch @panic("OOM");
    }
}

fn addCompilePrerequisites(target: *std.Build.Step, source: *std.Build.Step, visited: *std.AutoHashMap(*std.Build.Step, void)) !void {
    if ((try visited.getOrPut(source)).found_existing) return;
    switch (source.id) {
        .compile, .install_artifact, .install_dir, .install_file => target.dependOn(source),
        else => for (source.dependencies.items) |dependency| try addCompilePrerequisites(target, dependency, visited),
    }
}

fn linkTypeScriptParser(b: *std.Build, module: *std.Build.Module, library: *std.Build.Step.Compile) void {
    module.addIncludePath(b.path("vendor/tree-sitter/lib/include"));
    module.linkLibrary(library);
    module.link_libc = true;
}

fn linkQuickJs(b: *std.Build, module: *std.Build.Module, library: *std.Build.Step.Compile, sqlite_lib_dir: ?[]const u8) void {
    // Every VM can reach the native process owner through SDK and TUI imports.
    linkDurable(b, module);
    if (sqlite_lib_dir) |directory| module.addLibraryPath(.{ .cwd_relative = directory });
    module.addIncludePath(b.path("vendor/quickjs"));
    module.addIncludePath(b.path("vendor/libfyaml"));
    module.addIncludePath(b.path("src/extensions"));
    module.addImport("native_icu_api", b.modules.get("native_icu_api").?);
    module.addIncludePath(b.path("vendor/photon-native"));
    module.addImport("native_photon_link", b.modules.get("native_photon_link").?);
    module.addImport("native_vm_identity", b.modules.get("native_vm_identity").?);
    module.link_libcpp = true;
    module.linkLibrary(library);
    module.link_libc = true;
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
