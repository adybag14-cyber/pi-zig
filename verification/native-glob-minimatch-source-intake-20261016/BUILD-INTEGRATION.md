# Later native compile integration; no execution

This note is prospective only. The minimal14 patch changes no build file and
creates no native test target or expected output. The private result tree cannot
compile until the exact three prerequisite files listed in dependencies.json
are separately intaken. The original codec4300/glob911 and BD9 amendment seal
are preserved without adaptation to Root.

The smallest later compile subject is a dedicated
`src/native_node_glob_test.zig` harness which constructs an actual Engine,
installs the actual node:path provider with real IO and calls
`native_node_glob_sync.create` using its genuine namespace. The harness must
call the factory from a test body so lazy declaration import cannot substitute
for compiling the actual callback/traversal. It should then replay genuine
original25 and supplemental8 observations after their separate original capture
is granted and sealed. Do not create expected outputs to make compilation work:
the existing crypto pattern reads its expected JSON at runtime rather than
embedding an absent file at compile time. No such harness is authored here.

Follow the adjacent SHA256 target in Root build.zig, retaining its native
linkage and module inputs. Proposed future snippet, to add only after the real
harness and prerequisites are ready:

```zig
const node_glob_tests = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/native_node_glob_test.zig"),
        .target = target,
        .optimize = optimize,
    }),
    .filters = &.{"native node glob"},
    .use_llvm = use_llvm,
});
linkQuickJs(b, node_glob_tests.root_module, quickjs, sqlite_lib_dir);
linkSqlite(node_glob_tests.root_module, sqlite_lib_dir, sqlite_library);
node_glob_tests.root_module.addImport("catalog_tool", catalog_tool);
b.step("build-native-node-glob", "Compile actual native glob traversal independently")
    .dependOn(&node_glob_tests.step);
b.step("build-native-node-glob-artifact", "Install the compiled glob test artifact independently")
    .dependOn(&b.addInstallArtifact(node_glob_tests, .{}).step);
b.step("test-native-node-glob", "Replay genuine original Node/Pi glob observations")
    .dependOn(&b.addRunArtifact(node_glob_tests).step);
```

An eventual compile-only command uses the canonical pinned Zig0.16 executable,
`build build-native-node-glob -Doptimize=Debug -j1`, under Root's explicit grant,
resource admission and complete seals. No command was run. Keep the actual
Root linkQuickJs/linkSqlite settings, including their current native library,
identity, ICU, photon, libc/libcpp and process-probe dependencies. No source-SHA
only cache reuse or changed C approval is implied by this preparation.

Actual default SDK/module integration is separate. Engine.defaultExports
snapshots enumerable named exports when registerDefaultModule runs. Install
glob on the actual filesystem export object before that registration if named
`node:fs`/`fs` import support is selected later; adding a property afterward does
not recreate the named export table. For explicit PackageManager assembly, pass
the retained real filesystem namespace containing this function. Do not edit or
replace the stream owner's installation-mode/writer logic. This packet neither
registers nor activates the restricted glob function.

All broader grammar, public Dirent/Stats hook, URL/array/exclude/Dirent-result,
async and invalid-native-name gaps remain explicit. Neither compilation nor
runtime qualification can be inferred from a clean virtual Git application.
