//! Complete Source highlight.js10.7.3 Go factory; private source-only.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
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
    return ordinary.create(engine, "go", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const words = try scope.object();
    try scope.put(words, "keyword", try scope.text("break default func interface select case map struct chan else goto package switch const fallthrough if range type continue for import return var go defer bool byte complex64 complex128 float32 float64 int8 int16 int32 int64 string uint8 uint16 uint32 uint64 int uint uintptr rune"));
    try scope.put(words, "literal", try scope.text("true false iota nil"));
    try scope.put(words, "built_in", try scope.text("append cap close complex copy imag len make new panic print println real recover delete"));
    const language = try scope.object();
    try scope.put(language, "name", try scope.text("Go"));
    try scope.put(language, "aliases", try list(&scope, &.{try scope.text("golang")}));
    try scope.put(language, "keywords", words);
    try scope.put(language, "illegal", try scope.text("</"));
    const contains = try scope.array();
    try scope.index(contains, 0, try scope.get(hljs, "C_LINE_COMMENT_MODE"));
    try scope.index(contains, 1, try scope.get(hljs, "C_BLOCK_COMMENT_MODE"));
    const string = try scope.object();
    try scope.put(string, "className", try scope.text("string"));
    const strings = try scope.array();
    try scope.index(strings, 0, try scope.get(hljs, "QUOTE_STRING_MODE"));
    try scope.index(strings, 1, try scope.get(hljs, "APOS_STRING_MODE"));
    const raw = try scope.object();
    try scope.put(raw, "begin", try scope.text("`"));
    try scope.put(raw, "end", try scope.text("`"));
    try scope.index(strings, 2, raw);
    try scope.put(string, "variants", strings);
    try scope.index(contains, 2, string);
    const number = try scope.object();
    try scope.put(number, "className", try scope.text("number"));
    const numbers = try scope.array();
    const imaginary = try scope.object();
    try scope.put(imaginary, "begin", try scope.concat(try scope.get(hljs, "C_NUMBER_RE"), try scope.text("[i]")));
    try scope.put(imaginary, "relevance", c.JS_NewInt32(engine.context, 1));
    try scope.index(numbers, 0, imaginary);
    try scope.index(numbers, 1, try scope.get(hljs, "C_NUMBER_MODE"));
    try scope.put(number, "variants", numbers);
    try scope.index(contains, 3, number);
    const assignment = try scope.object();
    try scope.put(assignment, "begin", try literal(&scope, ":="));
    try scope.index(contains, 4, assignment);
    const function = try scope.object();
    try scope.put(function, "className", try scope.text("function"));
    try scope.put(function, "beginKeywords", try scope.text("func"));
    try scope.put(function, "end", try scope.text("\\s*(\\{|$)"));
    try scope.put(function, "excludeEnd", c.pi_js_bool(engine.context, 1));
    const arguments = try scope.array();
    try scope.index(arguments, 0, try scope.get(hljs, "TITLE_MODE"));
    const params = try scope.object();
    try scope.put(params, "className", try scope.text("params"));
    try scope.put(params, "begin", try literal(&scope, "\\("));
    try scope.put(params, "end", try literal(&scope, "\\)"));
    try scope.put(params, "keywords", words);
    try scope.put(params, "illegal", try literal(&scope, "[\"']"));
    try scope.index(arguments, 1, params);
    try scope.put(function, "contains", arguments);
    try scope.index(contains, 5, function);
    try scope.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
