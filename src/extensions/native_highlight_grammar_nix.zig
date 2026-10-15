//! Complete Source highlight.js10.7.3 Nix factory; private source-only.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
fn literal(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(pattern)};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(scope: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try scope.array();
    for (values, 0..) |value, index| try scope.index(result, @intCast(index), value);
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "nix", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const words = try scope.object();
    try scope.put(words, "keyword", try scope.text("rec with let in inherit assert if else then"));
    try scope.put(words, "literal", try scope.text("true false or and null"));
    try scope.put(words, "built_in", try scope.text("import abort baseNameOf dirOf isNull builtins map removeAttrs throw toString derivation"));
    const antiquote = try scope.object();
    try scope.put(antiquote, "className", try scope.text("subst"));
    try scope.put(antiquote, "begin", try literal(&scope, "\\$\\{"));
    try scope.put(antiquote, "end", try literal(&scope, "\\}"));
    try scope.put(antiquote, "keywords", words);
    const attrs = try scope.object();
    try scope.put(attrs, "begin", try literal(&scope, "[a-zA-Z0-9-_]+(\\s*=)"));
    try scope.put(attrs, "returnBegin", c.pi_js_bool(engine.context, 1));
    try scope.put(attrs, "relevance", c.JS_NewInt32(engine.context, 0));
    const attr = try scope.object();
    try scope.put(attr, "className", try scope.text("attr"));
    try scope.put(attr, "begin", try literal(&scope, "\\S+"));
    try scope.put(attrs, "contains", try list(&scope, &.{attr}));
    const string = try scope.object();
    try scope.put(string, "className", try scope.text("string"));
    try scope.put(string, "contains", try list(&scope, &.{antiquote}));
    const variants = try scope.array();
    inline for (.{ "''", "\"" }, 0..) |delimiter, index| {
        const variant = try scope.object();
        try scope.put(variant, "begin", try scope.text(delimiter));
        try scope.put(variant, "end", try scope.text(delimiter));
        try scope.index(variants, index, variant);
    }
    try scope.put(string, "variants", variants);
    const expressions = try scope.array();
    try scope.index(expressions, 0, try scope.get(hljs, "NUMBER_MODE"));
    try scope.index(expressions, 1, try scope.get(hljs, "HASH_COMMENT_MODE"));
    try scope.index(expressions, 2, try scope.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try scope.index(expressions, 3, string);
    try scope.index(expressions, 4, attrs);
    try scope.set(antiquote, "contains", expressions);
    const language = try scope.object();
    try scope.put(language, "name", try scope.text("Nix"));
    try scope.put(language, "aliases", try list(&scope, &.{try scope.text("nixos")}));
    try scope.put(language, "keywords", words);
    try scope.put(language, "contains", expressions);
    return c.JS_DupValue(engine.context, language);
}
