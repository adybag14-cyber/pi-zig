//! Source-only complete highlight.js10.7.3 JSON grammar factory.
//! Graph identities, live hljs property reads and callback dispatch follow Source.
//! No native/scanner/public qualification until the actual grammar differential.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_node_function.zig");
const c = em.c;

fn literal(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(pattern)};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn appendComment(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = try scope.invoke(roots[0], "push", &.{if (args.len > 0) args[0] else c.pi_js_undefined()});
    return c.pi_js_undefined();
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "json", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const literals = try scope.object();
    try scope.put(literals, "literal", try scope.text("true false null"));
    const comments = try scope.array();
    try scope.index(comments, 0, try scope.get(hljs, "C_LINE_COMMENT_MODE"));
    try scope.index(comments, 1, try scope.get(hljs, "C_BLOCK_COMMENT_MODE"));
    const types = try scope.array();
    try scope.index(types, 0, try scope.get(hljs, "QUOTE_STRING_MODE"));
    try scope.index(types, 1, try scope.get(hljs, "C_NUMBER_MODE"));
    const value = try scope.object();
    try scope.put(value, "end", try scope.text(","));
    try scope.put(value, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try scope.put(value, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try scope.put(value, "contains", types);
    try scope.put(value, "keywords", literals);
    const object = try scope.object();
    try scope.put(object, "begin", try literal(&scope, "\\{"));
    try scope.put(object, "end", try literal(&scope, "\\}"));
    const members = try scope.array();
    const attribute = try scope.object();
    try scope.put(attribute, "className", try scope.text("attr"));
    try scope.put(attribute, "begin", try literal(&scope, "\""));
    try scope.put(attribute, "end", try literal(&scope, "\""));
    const escapes = try scope.array();
    try scope.index(escapes, 0, try scope.get(hljs, "BACKSLASH_ESCAPE"));
    try scope.put(attribute, "contains", escapes);
    try scope.put(attribute, "illegal", try scope.text("\\n"));
    try scope.index(members, 0, attribute);
    // Source evaluates the live inherit getter before its changes-object literal.
    const inherit = try scope.get(hljs, "inherit");
    const colon = try scope.object();
    try scope.put(colon, "begin", try literal(&scope, ":"));
    try scope.index(members, 1, try scope.call(inherit, hljs, &.{ value, colon }));
    try scope.put(object, "contains", try scope.invoke(members, "concat", &.{comments}));
    try scope.put(object, "illegal", try scope.text("\\S"));
    const array = try scope.object();
    try scope.put(array, "begin", try scope.text("\\["));
    try scope.put(array, "end", try scope.text("\\]"));
    const elements = try scope.array();
    try scope.index(elements, 0, try scope.call(try scope.get(hljs, "inherit"), hljs, &.{value}));
    try scope.put(array, "contains", elements);
    try scope.put(array, "illegal", try scope.text("\\S"));
    _ = try scope.invoke(types, "push", &.{ object, array });
    const for_each = try scope.get(comments, "forEach");
    const callback = try scope.own(try ordinary.create(engine, "", 1, appendComment, &.{types}));
    _ = try scope.call(for_each, comments, &.{callback});
    const language = try scope.object();
    try scope.put(language, "name", try scope.text("JSON"));
    try scope.put(language, "contains", types);
    try scope.put(language, "keywords", literals);
    try scope.put(language, "illegal", try scope.text("\\S"));
    return c.JS_DupValue(engine.context, language);
}
