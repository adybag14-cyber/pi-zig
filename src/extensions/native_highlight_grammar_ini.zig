//! Actual highlight.js 10.7.3 ini factory, including its TOML alias.
//! Source-only; no separate fabricated toml factory is registered.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const regex = @import("native_highlight_regex.zig");
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
fn concat(s: *Scope, values: []const c.JSValue) !c.JSValue {
    return s.own(try regex.concat(s.engine, try list(s, values)));
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "ini", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const numbers = try s.object();
    try s.put(numbers, "className", try s.text("number"));
    try s.put(numbers, "relevance", c.JS_NewInt32(engine.context, 0));
    const number_variants = try s.array();
    const underscored = try s.object();
    try s.put(underscored, "begin", try literal(&s, "([+-]+)?[\\d]+_[\\d_]+"));
    try s.index(number_variants, 0, underscored);
    const common_number = try s.object();
    try s.put(common_number, "begin", try s.get(hljs, "NUMBER_RE"));
    try s.index(number_variants, 1, common_number);
    try s.put(numbers, "variants", number_variants);
    const comments = try s.invoke(hljs, "COMMENT", &.{});
    const comment_variants = try s.array();
    const semicolon = try s.object();
    try s.put(semicolon, "begin", try literal(&s, ";"));
    try s.put(semicolon, "end", try literal(&s, "$"));
    try s.index(comment_variants, 0, semicolon);
    const hash = try s.object();
    try s.put(hash, "begin", try literal(&s, "#"));
    try s.put(hash, "end", try literal(&s, "$"));
    try s.index(comment_variants, 1, hash);
    // Source assigns this field on COMMENT's live return object.
    try s.set(comments, "variants", comment_variants);
    const variables = try s.object();
    try s.put(variables, "className", try s.text("variable"));
    const variable_variants = try s.array();
    const variable = try s.object();
    try s.put(variable, "begin", try literal(&s, "\\$[\\w\\d\"][\\w\\d_]*"));
    try s.index(variable_variants, 0, variable);
    const braced = try s.object();
    try s.put(braced, "begin", try literal(&s, "\\$\\{(.*?)\\}"));
    try s.index(variable_variants, 1, braced);
    try s.put(variables, "variants", variable_variants);
    const literals = try s.object();
    try s.put(literals, "className", try s.text("literal"));
    try s.put(literals, "begin", try literal(&s, "\\bon|off|true|false|yes|no\\b"));
    const strings = try s.object();
    try s.put(strings, "className", try s.text("string"));
    try s.put(strings, "contains", try list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    const string_variants = try s.array();
    inline for (.{ "'''", "\"\"\"", "\"", "'" }, 0..) |delimiter, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(delimiter));
        try s.put(variant, "end", try s.text(delimiter));
        if (index < 2) try s.put(variant, "relevance", c.JS_NewInt32(engine.context, 10));
        try s.index(string_variants, index, variant);
    }
    try s.put(strings, "variants", string_variants);
    const array = try s.object();
    try s.put(array, "begin", try literal(&s, "\\["));
    try s.put(array, "end", try literal(&s, "\\]"));
    try s.put(array, "contains", try list(&s, &.{ comments, literals, variables, strings, numbers, try s.text("self") }));
    try s.put(array, "relevance", c.JS_NewInt32(engine.context, 0));
    const bare_key = try literal(&s, "[A-Za-z0-9_-]+");
    const double_key = try literal(&s, "\"(\\\\\"|[^\"])*\"");
    const single_key = try literal(&s, "'[^']*'");
    const any_key = try s.own(try regex.either(engine, try list(&s, &.{ bare_key, double_key, single_key })));
    const lookahead = try concat(&s, &.{ try s.text("(?="), try literal(&s, "\\s*=\\s*[^#\\s]"), try s.text(")") });
    const dotted_key = try concat(&s, &.{ any_key, try s.text("(\\s*\\.\\s*"), any_key, try s.text(")*"), lookahead });
    const language = try s.object();
    try s.put(language, "name", try s.text("TOML, also INI"));
    try s.put(language, "aliases", try list(&s, &.{try s.text("toml")}));
    try s.put(language, "case_insensitive", c.pi_js_bool(engine.context, 1));
    try s.put(language, "illegal", try literal(&s, "\\S"));
    const contains = try s.array();
    try s.index(contains, 0, comments);
    const section = try s.object();
    try s.put(section, "className", try s.text("section"));
    try s.put(section, "begin", try literal(&s, "\\[+"));
    try s.put(section, "end", try literal(&s, "\\]+"));
    try s.index(contains, 1, section);
    const attribute = try s.object();
    try s.put(attribute, "begin", dotted_key);
    try s.put(attribute, "className", try s.text("attr"));
    const starts = try s.object();
    try s.put(starts, "end", try literal(&s, "$"));
    try s.put(starts, "contains", try list(&s, &.{ comments, array, literals, variables, strings, numbers }));
    try s.put(attribute, "starts", starts);
    try s.index(contains, 2, attribute);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
