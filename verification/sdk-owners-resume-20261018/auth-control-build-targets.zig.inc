    const ai_auth_helper_genuine_af = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/native_ai_auth_helper_genuine_af_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
