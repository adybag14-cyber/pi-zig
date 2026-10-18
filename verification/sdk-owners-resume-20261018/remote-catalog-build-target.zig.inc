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
