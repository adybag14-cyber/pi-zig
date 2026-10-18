//! Actual c268 theme.ts getLanguageFromPath over scoped live guest operations.
const v = @import("native_public_values.zig");
const sdk = @import("native_sdk.zig");
const c = v.c;
const Scope = v.Scope;
const Engine = v.em.Engine;

pub fn get(engine: *Engine, file_path: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, getBody(&s, file_path));
}
fn getBody(s: *Scope, file_path: c.JSValue) !c.JSValue {
    const extension = try v.own(s, try extensionOwned(s.engine, file_path));
    if (!v.truthy(s, extension)) return c.pi_js_undefined();
    // Source creates an ordinary mapping on each call. Inherited lookup and
    // ToPropertyKey therefore remain observable to non-string path methods.
    const mappings = try v.object(s);
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
    }) |entry| try v.put(s, mappings, entry[0], try v.text(s, entry[1]));
    return v.duplicate(s, try v.key(s, mappings, extension));
}
fn extensionOwned(engine: *Engine, file_path: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, extensionBody(&s, file_path));
}
fn extensionBody(s: *Scope, file_path: c.JSValue) !c.JSValue {
    const last = try v.own(s, try lastOwned(s.engine, file_path));
    if (v.nullish(last)) return c.pi_js_undefined();
    return v.invokeOwned(s.engine, last, "toLowerCase", &.{});
}
fn lastOwned(engine: *Engine, file_path: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, lastBody(&s, file_path));
}
fn lastBody(s: *Scope, file_path: c.JSValue) !c.JSValue {
    const segments = try v.own(s, try v.invokeTextOwned(s.engine, file_path, "split", "."));
    return v.invokeOwned(s.engine, segments, "pop", &.{});
}

pub fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return get(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
