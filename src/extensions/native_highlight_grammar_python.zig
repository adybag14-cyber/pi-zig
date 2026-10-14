//! Complete Source highlight.js10.7.3 Python grammar graph; source-only draft.
//! Includes actual private concat/lookahead callback dispatch; differential pending.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_node_function.zig");
const c = em.c;
const digit = "[0-9](_?[0-9])*";
const point = "(\\b(" ++ digit ++ "))?\\.(" ++ digit ++ ")|\\b(" ++ digit ++ ")\\.";
fn literal(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(pattern)};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(scope: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try scope.array();
    for (values, 0..) |value, index| try scope.index(result, @intCast(index), value);
    return result;
}
fn words(scope: *Scope, text: []const u8) !c.JSValue {
    const result = try scope.array();
    var pieces = std.mem.splitScalar(u8, text, ' ');
    var index: u32 = 0;
    while (pieces.next()) |piece| : (index += 1) try scope.index(result, index, try scope.text(piece));
    return result;
}
fn sourceCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("native_highlight_regex.zig").source(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn typeLookahead(scope: *Scope) !c.JSValue {
    const arguments = try list(scope, &.{ try scope.text("(?="), try literal(scope, "# type:"), try scope.text(")") });
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, sourceCallback, "", 1)));
    return scope.invoke(try scope.invoke(arguments, "map", &.{callback}), "join", &.{try scope.text("")});
}
fn mode(scope: *Scope, name: []const u8) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "className", try scope.text(name));
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "python", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const reserved = try words(&scope, "and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal|10 not or pass raise return try while with yield");
    const builtins = try words(&scope, "__import__ abs all any ascii bin bool breakpoint bytearray bytes callable chr classmethod compile complex delattr dict dir divmod enumerate eval exec filter float format frozenset getattr globals hasattr hash help hex id input int isinstance issubclass iter len list locals map max memoryview min next object oct open ord pow print property range repr reversed round set setattr slice sorted staticmethod str sum super tuple type vars zip");
    const literals = try words(&scope, "__debug__ Ellipsis False None NotImplemented True");
    const types = try words(&scope, "Any Callable Coroutine Dict List Literal Generic Optional Sequence Set Tuple Type Union");
    const keywords = try scope.object();
    try scope.put(keywords, "$pattern", try literal(&scope, "[A-Za-z]\\w+|__\\w+__"));
    try scope.put(keywords, "keyword", reserved);
    try scope.put(keywords, "built_in", builtins);
    try scope.put(keywords, "literal", literals);
    try scope.put(keywords, "type", types);
    const prompt = try mode(&scope, "meta");
    try scope.put(prompt, "begin", try literal(&scope, "^(>>>|\\.\\.\\.) "));
    const subst = try mode(&scope, "subst");
    try scope.put(subst, "begin", try literal(&scope, "\\{"));
    try scope.put(subst, "end", try literal(&scope, "\\}"));
    try scope.put(subst, "keywords", keywords);
    try scope.put(subst, "illegal", try literal(&scope, "#"));
    const bracket = try scope.object();
    try scope.put(bracket, "begin", try literal(&scope, "\\{\\{"));
    try scope.put(bracket, "relevance", c.JS_NewInt32(engine.context, 0));
    const string = try mode(&scope, "string");
    try scope.put(string, "contains", try list(&scope, &.{try scope.get(hljs, "BACKSLASH_ESCAPE")}));
    const strings = try scope.array();
    inline for (.{
        .{ "([uU]|[bB]|[rR]|[bB][rR]|[rR][bB])?'''", "'''", 0 }, .{ "([uU]|[bB]|[rR]|[bB][rR]|[rR][bB])?\"\"\"", "\"\"\"", 0 },
        .{ "([fF][rR]|[rR][fF]|[fF])'''", "'''", 1 },            .{ "([fF][rR]|[rR][fF]|[fF])\"\"\"", "\"\"\"", 1 },
        .{ "([uU]|[rR])'", "'", 2 },                             .{ "([uU]|[rR])\"", "\"", 2 },
        .{ "([bB]|[bB][rR]|[rR][bB])'", "'", 3 },                .{ "([bB]|[bB][rR]|[rR][bB])\"", "\"", 3 },
        .{ "([fF][rR]|[rR][fF]|[fF])'", "'", 4 },                .{ "([fF][rR]|[rR][fF]|[fF])\"", "\"", 4 },
    }, 0..) |entry, index| {
        const variant = try scope.object();
        try scope.put(variant, "begin", try literal(&scope, entry[0]));
        try scope.put(variant, "end", try literal(&scope, entry[1]));
        if (entry[2] == 0) {
            try scope.put(variant, "contains", try list(&scope, &.{ try scope.get(hljs, "BACKSLASH_ESCAPE"), prompt }));
            try scope.put(variant, "relevance", c.JS_NewInt32(engine.context, 10));
        }
        if (entry[2] == 1) try scope.put(variant, "contains", try list(&scope, &.{ try scope.get(hljs, "BACKSLASH_ESCAPE"), prompt, bracket, subst }));
        if (entry[2] == 2) try scope.put(variant, "relevance", c.JS_NewInt32(engine.context, 10));
        if (entry[2] == 4) try scope.put(variant, "contains", try list(&scope, &.{ try scope.get(hljs, "BACKSLASH_ESCAPE"), bracket, subst }));
        try scope.index(strings, index, variant);
    }
    try scope.index(strings, 10, try scope.get(hljs, "APOS_STRING_MODE"));
    try scope.index(strings, 11, try scope.get(hljs, "QUOTE_STRING_MODE"));
    try scope.put(string, "variants", strings);
    const number = try mode(&scope, "number");
    try scope.put(number, "relevance", c.JS_NewInt32(engine.context, 0));
    const numbers = try scope.array();
    inline for (.{ "(\\b(" ++ digit ++ ")|(" ++ point ++ "))[eE][+-]?(" ++ digit ++ ")[jJ]?\\b", "(" ++ point ++ ")[jJ]?", "\\b([1-9](_?[0-9])*|0+(_?0)*)[lLjJ]?\\b", "\\b0[bB](_?[01])+[lL]?\\b", "\\b0[oO](_?[0-7])+[lL]?\\b", "\\b0[xX](_?[0-9a-fA-F])+[lL]?\\b", "\\b(" ++ digit ++ ")[jJ]\\b" }, 0..) |pattern, index| {
        const variant = try scope.object();
        try scope.put(variant, "begin", try scope.text(pattern));
        try scope.index(numbers, index, variant);
    }
    try scope.put(number, "variants", numbers);
    const comment = try mode(&scope, "comment");
    try scope.put(comment, "begin", try typeLookahead(&scope));
    try scope.put(comment, "end", try literal(&scope, "$"));
    try scope.put(comment, "keywords", keywords);
    const type_prefix = try scope.object();
    try scope.put(type_prefix, "begin", try literal(&scope, "# type:"));
    const nested_comment = try scope.object();
    try scope.put(nested_comment, "begin", try literal(&scope, "#"));
    try scope.put(nested_comment, "end", try literal(&scope, "\\b\\B"));
    try scope.put(nested_comment, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try scope.put(comment, "contains", try list(&scope, &.{ type_prefix, nested_comment }));
    const params = try mode(&scope, "params");
    const empty_params = try mode(&scope, "");
    try scope.put(empty_params, "begin", try literal(&scope, "\\(\\s*\\)"));
    try scope.put(empty_params, "skip", c.pi_js_bool(engine.context, 1));
    const real_params = try scope.object();
    try scope.put(real_params, "begin", try literal(&scope, "\\("));
    try scope.put(real_params, "end", try literal(&scope, "\\)"));
    try scope.put(real_params, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try scope.put(real_params, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try scope.put(real_params, "keywords", keywords);
    try scope.put(real_params, "contains", try list(&scope, &.{ try scope.text("self"), prompt, number, string, try scope.get(hljs, "HASH_COMMENT_MODE") }));
    try scope.put(params, "variants", try list(&scope, &.{ empty_params, real_params }));
    try scope.set(subst, "contains", try list(&scope, &.{ string, number, prompt }));
    const language = try scope.object();
    try scope.put(language, "name", try scope.text("Python"));
    try scope.put(language, "aliases", try list(&scope, &.{ try scope.text("py"), try scope.text("gyp"), try scope.text("ipython") }));
    try scope.put(language, "keywords", keywords);
    try scope.put(language, "illegal", try literal(&scope, "(</|->|\\?)|=>"));
    const contains = try scope.array();
    try scope.index(contains, 0, prompt);
    try scope.index(contains, 1, number);
    const self = try scope.object();
    try scope.put(self, "begin", try literal(&scope, "\\bself\\b"));
    try scope.index(contains, 2, self);
    const conditional = try scope.object();
    try scope.put(conditional, "beginKeywords", try scope.text("if"));
    try scope.put(conditional, "relevance", c.JS_NewInt32(engine.context, 0));
    try scope.index(contains, 3, conditional);
    try scope.index(contains, 4, string);
    try scope.index(contains, 5, comment);
    try scope.index(contains, 6, try scope.get(hljs, "HASH_COMMENT_MODE"));
    const definition = try scope.object();
    const definitions = try scope.array();
    inline for (.{ .{ "function", "def" }, .{ "class", "class" } }, 0..) |entry, index| {
        const variant = try mode(&scope, entry[0]);
        try scope.put(variant, "beginKeywords", try scope.text(entry[1]));
        try scope.index(definitions, index, variant);
    }
    try scope.put(definition, "variants", definitions);
    try scope.put(definition, "end", try literal(&scope, ":"));
    try scope.put(definition, "illegal", try literal(&scope, "[${=;\\n,]"));
    const title = try scope.get(hljs, "UNDERSCORE_TITLE_MODE");
    const returns = try scope.object();
    try scope.put(returns, "begin", try literal(&scope, "->"));
    try scope.put(returns, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try scope.put(returns, "keywords", keywords);
    try scope.put(definition, "contains", try list(&scope, &.{ title, params, returns }));
    try scope.index(contains, 7, definition);
    const decorator = try mode(&scope, "meta");
    try scope.put(decorator, "begin", try literal(&scope, "^[\\t ]*@"));
    try scope.put(decorator, "end", try literal(&scope, "(?=#)|$"));
    try scope.put(decorator, "contains", try list(&scope, &.{ number, params, string }));
    try scope.index(contains, 8, decorator);
    try scope.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
