//! Actual Source theme.ts getLanguageFromPath. No highlighting approximation.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temporary = @import("native_sdk_prompt_scope.zig");
const Scope = temporary.Scope;
const c = em.c;

pub fn get(engine: *em.Engine, file_path: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const segments = try scope.invoke(file_path, "split", &.{try scope.text(".")});
    const last = try scope.invoke(segments, "pop", &.{});
    const extension = if (temporary.nullish(last)) c.pi_js_undefined() else try scope.invoke(last, "toLowerCase", &.{});
    if (!scope.truthy(extension)) return c.pi_js_undefined();
    // Source uses a fresh ordinary object, so inherited property lookup and
    // property-key coercion remain observable to caller-controlled inputs.
    const mappings = try scope.object();
    inline for (.{
        .{ "ts", "typescript" },   .{ "tsx", "typescript" }, .{ "js", "javascript" }, .{ "jsx", "javascript" },    .{ "mjs", "javascript" },        .{ "cjs", "javascript" },
        .{ "py", "python" },       .{ "rb", "ruby" },        .{ "rs", "rust" },       .{ "go", "go" },             .{ "java", "java" },             .{ "kt", "kotlin" },
        .{ "swift", "swift" },     .{ "c", "c" },            .{ "h", "c" },           .{ "cpp", "cpp" },           .{ "cc", "cpp" },                .{ "cxx", "cpp" },
        .{ "hpp", "cpp" },         .{ "cs", "csharp" },      .{ "php", "php" },       .{ "sh", "bash" },           .{ "bash", "bash" },             .{ "zsh", "bash" },
        .{ "fish", "fish" },       .{ "ps1", "powershell" }, .{ "sql", "sql" },       .{ "html", "html" },         .{ "htm", "html" },              .{ "css", "css" },
        .{ "scss", "scss" },       .{ "sass", "sass" },      .{ "less", "less" },     .{ "json", "json" },         .{ "yaml", "yaml" },             .{ "yml", "yaml" },
        .{ "toml", "toml" },       .{ "xml", "xml" },        .{ "md", "markdown" },   .{ "markdown", "markdown" }, .{ "dockerfile", "dockerfile" }, .{ "makefile", "makefile" },
        .{ "cmake", "cmake" },     .{ "lua", "lua" },        .{ "perl", "perl" },     .{ "r", "r" },               .{ "scala", "scala" },           .{ "clj", "clojure" },
        .{ "ex", "elixir" },       .{ "exs", "elixir" },     .{ "erl", "erlang" },    .{ "hs", "haskell" },        .{ "ml", "ocaml" },              .{ "vim", "vim" },
        .{ "graphql", "graphql" }, .{ "proto", "protobuf" }, .{ "tf", "hcl" },        .{ "hcl", "hcl" },
    }) |entry| try scope.put(mappings, entry[0], try scope.text(entry[1]));
    return js.getKey(engine, mappings, extension);
}

pub fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return get(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
