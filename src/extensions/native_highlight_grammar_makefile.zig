//! Actual highlight.js 10.7.3 Makefile factory; source-only.
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
    return ordinary.create(engine, "makefile", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const variable = try s.object();
    try s.put(variable, "className", try s.text("variable"));
    const variable_variants = try s.array();
    const simple = try s.object();
    const prefix = try s.text("\\$\\(");
    const ident = try s.get(hljs, "UNDERSCORE_IDENT_RE");
    const variable_begin = try s.concat(try s.concat(prefix, ident), try s.text("\\)"));
    try s.put(simple, "begin", variable_begin);
    try s.put(simple, "contains", try list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    try s.index(variable_variants, 0, simple);
    const special = try s.object();
    try s.put(special, "begin", try literal(&s, "\\$[@%<?\\^\\+\\*]"));
    try s.index(variable_variants, 1, special);
    try s.put(variable, "variants", variable_variants);
    const quoted = try s.object();
    try s.put(quoted, "className", try s.text("string"));
    try s.put(quoted, "begin", try literal(&s, "\""));
    try s.put(quoted, "end", try literal(&s, "\""));
    try s.put(quoted, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), variable }));
    const function = try s.object();
    try s.put(function, "className", try s.text("variable"));
    try s.put(function, "begin", try literal(&s, "\\$\\([\\w-]+\\s"));
    try s.put(function, "end", try literal(&s, "\\)"));
    const function_keywords = try s.object();
    try s.put(function_keywords, "built_in", try s.text("subst patsubst strip findstring filter filter-out sort word wordlist firstword lastword dir notdir suffix basename addsuffix addprefix join wildcard realpath abspath error warning shell origin flavor foreach if or and call eval file value"));
    try s.put(function, "keywords", function_keywords);
    try s.put(function, "contains", try list(&s, &.{variable}));
    const assignment = try s.object();
    const assignment_prefix = try s.text("^");
    const assignment_ident = try s.get(hljs, "UNDERSCORE_IDENT_RE");
    try s.put(assignment, "begin", try s.concat(try s.concat(assignment_prefix, assignment_ident), try s.text("\\s*(?=[:+?]?=)")));
    const meta = try s.object();
    try s.put(meta, "className", try s.text("meta"));
    try s.put(meta, "begin", try literal(&s, "^\\.PHONY:"));
    try s.put(meta, "end", try literal(&s, "$"));
    const meta_keywords = try s.object();
    try s.put(meta_keywords, "$pattern", try literal(&s, "[\\.\\w]+"));
    try s.put(meta_keywords, "meta-keyword", try s.text(".PHONY"));
    try s.put(meta, "keywords", meta_keywords);
    const target = try s.object();
    try s.put(target, "className", try s.text("section"));
    try s.put(target, "begin", try literal(&s, "^[^\\s]+:"));
    try s.put(target, "end", try literal(&s, "$"));
    try s.put(target, "contains", try list(&s, &.{variable}));
    const language = try s.object();
    try s.put(language, "name", try s.text("Makefile"));
    try s.put(language, "aliases", try list(&s, &.{ try s.text("mk"), try s.text("mak"), try s.text("make") }));
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try literal(&s, "[\\w-]+"));
    try s.put(keywords, "keyword", try s.text("define endef undefine ifdef ifndef ifeq ifneq else endif include -include sinclude override export unexport private vpath"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try list(&s, &.{ try s.get(hljs, "HASH_COMMENT_MODE"), variable, quoted, function, assignment, meta, target }));
    return c.JS_DupValue(engine.context, language);
}
