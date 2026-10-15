//! Actual highlight.js 10.7.3 Dockerfile factory; pending genuine differential.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;

fn literal(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "dockerfile", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Dockerfile"));
    try s.put(language, "aliases", try list(&s, &.{try s.text("docker")}));
    try s.put(language, "case_insensitive", c.pi_js_bool(engine.context, 1));
    try s.put(language, "keywords", try s.text("from maintainer expose env arg user onbuild stopsignal"));
    const contains = try s.array();
    try s.index(contains, 0, try s.get(hljs, "HASH_COMMENT_MODE"));
    try s.index(contains, 1, try s.get(hljs, "APOS_STRING_MODE"));
    try s.index(contains, 2, try s.get(hljs, "QUOTE_STRING_MODE"));
    try s.index(contains, 3, try s.get(hljs, "NUMBER_MODE"));
    const instruction = try s.object();
    try s.put(instruction, "beginKeywords", try s.text("run cmd entrypoint volume add copy workdir label healthcheck shell"));
    const starts = try s.object();
    try s.put(starts, "end", try literal(&s, "[^\\\\]$"));
    try s.put(starts, "subLanguage", try s.text("bash"));
    try s.put(instruction, "starts", starts);
    try s.index(contains, 4, instruction);
    try s.put(language, "contains", contains);
    try s.put(language, "illegal", try s.text("</"));
    return c.JS_DupValue(engine.context, language);
}
