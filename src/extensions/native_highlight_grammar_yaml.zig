//! Actual highlight.js 10.7.3 YAML factory; source-only pending differential.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;

fn literal(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn mode(s: *Scope, class_name: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "className", try s.text(class_name));
    return result;
}
fn stringVariants(s: *Scope, tail: []const u8) !c.JSValue {
    const result = try s.array();
    inline for (.{ "'", "\"" }, 0..) |delimiter, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try literal(s, delimiter));
        try s.put(variant, "end", try literal(s, delimiter));
        try s.index(result, index, variant);
    }
    const unquoted = try s.object();
    try s.put(unquoted, "begin", try literal(s, tail));
    try s.index(result, 2, unquoted);
    return result;
}
fn arraySpread(s: *Scope, iterable: c.JSValue) !c.JSValue {
    const result = try s.array();
    const symbol = try s.own(try s.engine.checked(JS_GetIteratorSymbol(s.engine.context)));
    var iterator = try js.Iterator.init(s.engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: u32 = 0;
    while (try iterator.next()) |value| {
        defer s.engine.freeValue(value);
        try s.index(result, index, value);
        index += 1;
    }
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "yaml", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const literal_words = "true false yes no null";
    const uri_characters = "[\\w#;/?:@&=+$,.~*'()[\\]]+";
    const key = try mode(&s, "attr");
    const key_variants = try s.array();
    inline for (.{ "\\w[\\w :\\/.-]*:(?=[ \t]|$)", "\"\\w[\\w :\\/.-]*\":(?=[ \t]|$)", "'\\w[\\w :\\/.-]*':(?=[ \t]|$)" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        try s.index(key_variants, index, variant);
    }
    try s.put(key, "variants", key_variants);
    const template = try mode(&s, "template-variable");
    const template_variants = try s.array();
    const jinja = try s.object();
    try s.put(jinja, "begin", try literal(&s, "\\{\\{"));
    try s.put(jinja, "end", try literal(&s, "\\}\\}"));
    try s.index(template_variants, 0, jinja);
    const ruby = try s.object();
    try s.put(ruby, "begin", try literal(&s, "%\\{"));
    try s.put(ruby, "end", try literal(&s, "\\}"));
    try s.index(template_variants, 1, ruby);
    try s.put(template, "variants", template_variants);
    const string = try mode(&s, "string");
    try s.put(string, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(string, "variants", try stringVariants(&s, "\\S+"));
    try s.put(string, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), template }));
    const inherit = try s.get(hljs, "inherit");
    const container_changes = try s.object();
    try s.put(container_changes, "variants", try stringVariants(&s, "[^\\s,{}[\\]]+"));
    const container_string = try s.call(inherit, hljs, &.{ string, container_changes });
    const timestamp = try mode(&s, "number");
    try s.put(timestamp, "begin", try s.text("\\b" ++ "[0-9]{4}(-[0-9][0-9]){0,2}" ++ "([Tt \\t][0-9][0-9]?(:[0-9][0-9]){2})?" ++ "(\\.[0-9]*)?" ++ "([ \\t])*(Z|[-+][0-9][0-9]?(:[0-9][0-9])?)?" ++ "\\b"));
    const value_container = try s.object();
    try s.put(value_container, "end", try s.text(","));
    try s.put(value_container, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try s.put(value_container, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(value_container, "keywords", try s.text(literal_words));
    try s.put(value_container, "relevance", c.JS_NewInt32(engine.context, 0));
    const object = try s.object();
    try s.put(object, "begin", try literal(&s, "\\{"));
    try s.put(object, "end", try literal(&s, "\\}"));
    try s.put(object, "contains", try list(&s, &.{value_container}));
    try s.put(object, "illegal", try s.text("\\n"));
    try s.put(object, "relevance", c.JS_NewInt32(engine.context, 0));
    const array = try s.object();
    try s.put(array, "begin", try s.text("\\["));
    try s.put(array, "end", try s.text("\\]"));
    try s.put(array, "contains", try list(&s, &.{value_container}));
    try s.put(array, "illegal", try s.text("\\n"));
    try s.put(array, "relevance", c.JS_NewInt32(engine.context, 0));
    const modes = try s.array();
    try s.index(modes, 0, key);
    const document_start = try mode(&s, "meta");
    try s.put(document_start, "begin", try s.text("^---\\s*$"));
    try s.put(document_start, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.index(modes, 1, document_start);
    const multiline = try mode(&s, "string");
    try s.put(multiline, "begin", try s.text("[\\|>]([1-9]?[+-])?[ ]*\\n( +)[^ ][^\\n]*\\n(\\2[^\\n]+\\n?)*"));
    try s.index(modes, 2, multiline);
    const erb = try s.object();
    try s.put(erb, "begin", try s.text("<%[%=-]?"));
    try s.put(erb, "end", try s.text("[%-]?%>"));
    try s.put(erb, "subLanguage", try s.text("ruby"));
    try s.put(erb, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(erb, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(erb, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(modes, 3, erb);
    inline for (.{ "!\\w+!" ++ uri_characters, "!<" ++ uri_characters ++ ">", "!" ++ uri_characters, "!!" ++ uri_characters }, 0..) |pattern, index| {
        const tag = try mode(&s, "type");
        try s.put(tag, "begin", try s.text(pattern));
        try s.index(modes, @intCast(index + 4), tag);
    }
    const fragment = try mode(&s, "meta");
    const fragment_prefix = try s.text("&");
    const fragment_ident = try s.get(hljs, "UNDERSCORE_IDENT_RE");
    try s.put(fragment, "begin", try s.concat(try s.concat(fragment_prefix, fragment_ident), try s.text("$")));
    try s.index(modes, 8, fragment);
    const reference = try mode(&s, "meta");
    const reference_prefix = try s.text("\\*");
    const reference_ident = try s.get(hljs, "UNDERSCORE_IDENT_RE");
    try s.put(reference, "begin", try s.concat(try s.concat(reference_prefix, reference_ident), try s.text("$")));
    try s.index(modes, 9, reference);
    const bullet = try mode(&s, "bullet");
    try s.put(bullet, "begin", try s.text("-(?=[ ]|$)"));
    try s.put(bullet, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(modes, 10, bullet);
    try s.index(modes, 11, try s.get(hljs, "HASH_COMMENT_MODE"));
    const literals = try s.object();
    try s.put(literals, "beginKeywords", try s.text(literal_words));
    const literal_keywords = try s.object();
    try s.put(literal_keywords, "literal", try s.text(literal_words));
    try s.put(literals, "keywords", literal_keywords);
    try s.index(modes, 12, literals);
    try s.index(modes, 13, timestamp);
    const number = try mode(&s, "number");
    try s.put(number, "begin", try s.concat(try s.get(hljs, "C_NUMBER_RE"), try s.text("\\b")));
    try s.put(number, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(modes, 14, number);
    try s.index(modes, 15, object);
    try s.index(modes, 16, array);
    try s.index(modes, 17, string);
    // Source uses [...MODES], not slice/concat or calls to Array.prototype.push.
    const value_modes = try arraySpread(&s, modes);
    _ = try s.invoke(value_modes, "pop", &.{});
    _ = try s.invoke(value_modes, "push", &.{container_string});
    try s.set(value_container, "contains", value_modes);
    const language = try s.object();
    try s.put(language, "name", try s.text("YAML"));
    try s.put(language, "case_insensitive", c.pi_js_bool(engine.context, 1));
    try s.put(language, "aliases", try list(&s, &.{try s.text("yml")}));
    try s.put(language, "contains", modes);
    return c.JS_DupValue(engine.context, language);
}
