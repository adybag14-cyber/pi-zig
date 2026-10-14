//! Complete Source highlight.js10.7.3 C# grammar factory; source-only draft.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn words(s: *Scope, text: []const u8) !c.JSValue {
    const result = try s.array();
    var parts = std.mem.splitScalar(u8, text, ' ');
    var index: u32 = 0;
    while (parts.next()) |part| : (index += 1) try s.index(result, index, try s.text(part));
    return result;
}
fn literal(s: *Scope, text: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(text)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn mode(s: *Scope, name: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "className", try s.text(name));
    return result;
}
fn begin(s: *Scope, pattern: []const u8, regexp: bool) !c.JSValue {
    const result = try s.object();
    try s.put(result, "begin", if (regexp) try literal(s, pattern) else try s.text(pattern));
    return result;
}
fn inherited(s: *Scope, hljs: c.JSValue, base: c.JSValue, changes: c.JSValue) !c.JSValue {
    return s.call(try s.get(hljs, "inherit"), hljs, &.{ base, changes });
}
fn noLf(s: *Scope, hljs: c.JSValue, base: c.JSValue) !c.JSValue {
    const fn_value = try s.get(hljs, "inherit");
    const changes = try s.object();
    try s.put(changes, "illegal", try literal(s, "\\n"));
    return s.call(fn_value, hljs, &.{ base, changes });
}
fn declaration(s: *Scope, hljs: c.JSValue, name: []const u8, illegal: []const u8, title: c.JSValue, generic: c.JSValue) !c.JSValue {
    const result = try s.object();
    try s.put(result, "beginKeywords", try s.text(name));
    try s.put(result, "relevance", c.JS_NewInt32(s.engine.context, 0));
    try s.put(result, "end", try literal(s, "[{;=]"));
    try s.put(result, "illegal", try literal(s, illegal));
    const children = try s.array();
    var index: u32 = 0;
    if (std.mem.eql(u8, name, "class interface")) {
        const where = try s.object();
        try s.put(where, "beginKeywords", try s.text("where class"));
        try s.index(children, index, where);
        index += 1;
    }
    try s.index(children, index, title);
    index += 1;
    if (!std.mem.eql(u8, name, "namespace")) {
        try s.index(children, index, generic);
        index += 1;
    }
    try s.index(children, index, try s.get(hljs, "C_LINE_COMMENT_MODE"));
    index += 1;
    try s.index(children, index, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try s.put(result, "contains", children);
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "csharp", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const builtins = try words(&s, "bool byte char decimal delegate double dynamic enum float int long nint nuint object sbyte short string ulong uint ushort");
    const modifiers = try words(&s, "public private protected static internal protected abstract async extern override unsafe virtual new sealed partial");
    const literals = try words(&s, "default false null true");
    const normal = try words(&s, "abstract as base break case class const continue do else event explicit extern finally fixed for foreach goto if implicit in interface internal is lock namespace new operator out override params private protected public readonly record ref return sealed sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using virtual void volatile while");
    const contextual = try words(&s, "add alias and ascending async await by descending equals from get global group init into join let nameof not notnull on or orderby partial remove select set unmanaged value|0 var when where with yield");
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.invoke(normal, "concat", &.{contextual}));
    try s.put(keywords, "built_in", builtins);
    try s.put(keywords, "literal", literals);
    const inherit = try s.get(hljs, "inherit");
    const title_base = try s.get(hljs, "TITLE_MODE");
    const title_changes = try s.object();
    try s.put(title_changes, "begin", try s.text("[a-zA-Z](\\.?\\w)*"));
    const title = try s.call(inherit, hljs, &.{ title_base, title_changes });
    const numbers = try mode(&s, "number");
    const variants = try s.array();
    inline for (.{ "\\b(0b[01']+)", "(-?)\\b([\\d']+(\\.[\\d']*)?|\\.[\\d']+)(u|U|l|L|ul|UL|f|F|b|B)", "(-?)(\\b0[xX][a-fA-F0-9']+|(\\b[\\d']+(\\.[\\d']*)?|\\.[\\d']+)([eE][-+]?[\\d']+)?)" }, 0..) |pattern, index| try s.index(variants, index, try begin(&s, pattern, false));
    try s.put(numbers, "variants", variants);
    try s.put(numbers, "relevance", c.JS_NewInt32(engine.context, 0));
    const verbatim = try mode(&s, "string");
    try s.put(verbatim, "begin", try s.text("@\""));
    try s.put(verbatim, "end", try s.text("\""));
    try s.put(verbatim, "contains", try list(&s, &.{try begin(&s, "\"\"", false)}));
    const verbatim_no_lf = try noLf(&s, hljs, verbatim);
    const subst = try mode(&s, "subst");
    try s.put(subst, "begin", try literal(&s, "\\{"));
    try s.put(subst, "end", try literal(&s, "\\}"));
    try s.put(subst, "keywords", keywords);
    const subst_no_lf = try noLf(&s, hljs, subst);
    const interpolated = try mode(&s, "string");
    try s.put(interpolated, "begin", try literal(&s, "\\$\""));
    try s.put(interpolated, "end", try s.text("\""));
    try s.put(interpolated, "illegal", try literal(&s, "\\n"));
    try s.put(interpolated, "contains", try list(&s, &.{ try begin(&s, "\\{\\{", true), try begin(&s, "\\}\\}", true), try s.get(hljs, "BACKSLASH_ESCAPE"), subst_no_lf }));
    const interpolated_verbatim = try mode(&s, "string");
    try s.put(interpolated_verbatim, "begin", try literal(&s, "\\$@\""));
    try s.put(interpolated_verbatim, "end", try s.text("\""));
    try s.put(interpolated_verbatim, "contains", try list(&s, &.{ try begin(&s, "\\{\\{", true), try begin(&s, "\\}\\}", true), try begin(&s, "\"\"", false), subst }));
    const no_lf_inherit = try s.get(hljs, "inherit");
    const no_lf_changes = try s.object();
    try s.put(no_lf_changes, "illegal", try literal(&s, "\\n"));
    try s.put(no_lf_changes, "contains", try list(&s, &.{ try begin(&s, "\\{\\{", true), try begin(&s, "\\}\\}", true), try begin(&s, "\"\"", false), subst_no_lf }));
    const interpolated_verbatim_no_lf = try s.call(no_lf_inherit, hljs, &.{ interpolated_verbatim, no_lf_changes });
    try s.set(subst, "contains", try list(&s, &.{ interpolated_verbatim, interpolated, verbatim, try s.get(hljs, "APOS_STRING_MODE"), try s.get(hljs, "QUOTE_STRING_MODE"), numbers, try s.get(hljs, "C_BLOCK_COMMENT_MODE") }));
    const subst_children = try s.array();
    try s.index(subst_children, 0, interpolated_verbatim_no_lf);
    try s.index(subst_children, 1, interpolated);
    try s.index(subst_children, 2, verbatim_no_lf);
    try s.index(subst_children, 3, try s.get(hljs, "APOS_STRING_MODE"));
    try s.index(subst_children, 4, try s.get(hljs, "QUOTE_STRING_MODE"));
    try s.index(subst_children, 5, numbers);
    const block_inherit = try s.get(hljs, "inherit");
    const block = try s.get(hljs, "C_BLOCK_COMMENT_MODE");
    const block_changes = try s.object();
    try s.put(block_changes, "illegal", try literal(&s, "\\n"));
    try s.index(subst_children, 6, try s.call(block_inherit, hljs, &.{ block, block_changes }));
    try s.set(subst_no_lf, "contains", subst_children);
    const string = try s.object();
    try s.put(string, "variants", try list(&s, &.{ interpolated_verbatim, interpolated, verbatim, try s.get(hljs, "APOS_STRING_MODE"), try s.get(hljs, "QUOTE_STRING_MODE") }));
    const generic = try s.object();
    try s.put(generic, "begin", try s.text("<"));
    try s.put(generic, "end", try s.text(">"));
    const variance = try s.object();
    try s.put(variance, "beginKeywords", try s.text("in out"));
    try s.put(generic, "contains", try list(&s, &.{ variance, title }));
    var type_ident = try s.concat(try s.get(hljs, "IDENT_RE"), try s.text("(<"));
    type_ident = try s.concat(type_ident, try s.get(hljs, "IDENT_RE"));
    type_ident = try s.concat(type_ident, try s.text("(\\s*,\\s*"));
    type_ident = try s.concat(type_ident, try s.get(hljs, "IDENT_RE"));
    type_ident = try s.concat(type_ident, try s.text(")*>)?(\\[\\])?"));
    const at_identifier = try s.object();
    try s.put(at_identifier, "begin", try s.concat(try s.text("@"), try s.get(hljs, "IDENT_RE")));
    try s.put(at_identifier, "relevance", c.JS_NewInt32(engine.context, 0));
    const language = try s.object();
    try s.put(language, "name", try s.text("C#"));
    try s.put(language, "aliases", try list(&s, &.{ try s.text("cs"), try s.text("c#") }));
    try s.put(language, "keywords", keywords);
    try s.put(language, "illegal", try literal(&s, "::"));
    const contains = try s.array();
    const comment = try s.get(hljs, "COMMENT");
    const comment_options = try s.object();
    try s.put(comment_options, "returnBegin", c.pi_js_bool(engine.context, 1));
    const doc = try mode(&s, "doctag");
    const doc_variants = try s.array();
    const slash = try begin(&s, "///", false);
    try s.put(slash, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(doc_variants, 0, slash);
    try s.index(doc_variants, 1, try begin(&s, "<!--|-->", false));
    const tag = try begin(&s, "</?", false);
    try s.put(tag, "end", try s.text(">"));
    try s.index(doc_variants, 2, tag);
    try s.put(doc, "variants", doc_variants);
    try s.put(comment_options, "contains", try list(&s, &.{doc}));
    try s.index(contains, 0, try s.call(comment, hljs, &.{ try s.text("///"), try s.text("$"), comment_options }));
    try s.index(contains, 1, try s.get(hljs, "C_LINE_COMMENT_MODE"));
    try s.index(contains, 2, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    const meta = try mode(&s, "meta");
    try s.put(meta, "begin", try s.text("#"));
    try s.put(meta, "end", try s.text("$"));
    const meta_words = try s.object();
    try s.put(meta_words, "meta-keyword", try s.text("if else elif endif define undef warning error line region endregion pragma checksum"));
    try s.put(meta, "keywords", meta_words);
    try s.index(contains, 3, meta);
    try s.index(contains, 4, string);
    try s.index(contains, 5, numbers);
    try s.index(contains, 6, try declaration(&s, hljs, "class interface", "[^\\s:,]", title, generic));
    try s.index(contains, 7, try declaration(&s, hljs, "namespace", "[^\\s:]", title, generic));
    try s.index(contains, 8, try declaration(&s, hljs, "record", "[^\\s:]", title, generic));
    const attribute = try mode(&s, "meta");
    try s.put(attribute, "begin", try s.text("^\\s*\\["));
    try s.put(attribute, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(attribute, "end", try s.text("\\]"));
    try s.put(attribute, "excludeEnd", c.pi_js_bool(engine.context, 1));
    const meta_string = try mode(&s, "meta-string");
    try s.put(meta_string, "begin", try literal(&s, "\""));
    try s.put(meta_string, "end", try literal(&s, "\""));
    try s.put(attribute, "contains", try list(&s, &.{meta_string}));
    try s.index(contains, 9, attribute);
    const expression = try s.object();
    try s.put(expression, "beginKeywords", try s.text("new return throw await else"));
    try s.put(expression, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 10, expression);
    const function = try mode(&s, "function");
    var function_begin = try s.concat(try s.concat(try s.text("("), type_ident), try s.text("\\s+)+"));
    function_begin = try s.concat(function_begin, try s.get(hljs, "IDENT_RE"));
    function_begin = try s.concat(function_begin, try s.text("\\s*(<.+>\\s*)?\\("));
    try s.put(function, "begin", function_begin);
    try s.put(function, "returnBegin", c.pi_js_bool(engine.context, 1));
    try s.put(function, "end", try literal(&s, "\\s*[{;=]"));
    try s.put(function, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(function, "keywords", keywords);
    const function_children = try s.array();
    const modifier = try s.object();
    try s.put(modifier, "beginKeywords", try s.invoke(modifiers, "join", &.{try s.text(" ")}));
    try s.put(modifier, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(function_children, 0, modifier);
    const call = try s.object();
    try s.put(call, "begin", try s.concat(try s.get(hljs, "IDENT_RE"), try s.text("\\s*(<.+>\\s*)?\\(")));
    try s.put(call, "returnBegin", c.pi_js_bool(engine.context, 1));
    try s.put(call, "contains", try list(&s, &.{ try s.get(hljs, "TITLE_MODE"), generic }));
    try s.put(call, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(function_children, 1, call);
    const params = try mode(&s, "params");
    try s.put(params, "begin", try literal(&s, "\\("));
    try s.put(params, "end", try literal(&s, "\\)"));
    try s.put(params, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(params, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(params, "keywords", keywords);
    try s.put(params, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(params, "contains", try list(&s, &.{ string, numbers, try s.get(hljs, "C_BLOCK_COMMENT_MODE") }));
    try s.index(function_children, 2, params);
    try s.index(function_children, 3, try s.get(hljs, "C_LINE_COMMENT_MODE"));
    try s.index(function_children, 4, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try s.put(function, "contains", function_children);
    try s.index(contains, 11, function);
    try s.index(contains, 12, at_identifier);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
