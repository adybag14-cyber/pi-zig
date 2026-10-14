//! Complete Source JavaScript/TypeScript factory bodies; source-only draft.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_node_function.zig");
const c = em.c;
const ident = "[A-Za-z$_][0-9A-Za-z$_]*";
const keywords_text = "as in of if for while finally var new function do return void else break catch instanceof with throw case default try switch continue typeof delete let yield const class debugger async await static import from export extends";
const literals_text = "true false null undefined NaN Infinity";
const types_text = "Intl DataView Number Math Date String RegExp Object Function Boolean Error Symbol Set Map WeakSet WeakMap Proxy Reflect JSON Promise Float64Array Int16Array Int32Array Int8Array Uint16Array Uint32Array Float32Array Array Uint8Array Uint8ClampedArray ArrayBuffer BigInt64Array BigUint64Array BigInt";
const error_types_text = "EvalError InternalError RangeError ReferenceError SyntaxError TypeError URIError";
const built_in_globals_text = "setInterval setTimeout clearInterval clearTimeout require exports eval isFinite isNaN parseFloat parseInt decodeURI decodeURIComponent encodeURI encodeURIComponent escape unescape";
const built_in_variables_text = "arguments this super console window document localStorage module global";
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
fn sourceCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("native_highlight_regex.zig").source(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn concat(s: *Scope, args: []const c.JSValue) !c.JSValue {
    const values = try list(s, args);
    const fn_value = try s.own(try s.engine.checked(c.JS_NewCFunction(s.engine.context, sourceCallback, "", 1)));
    return s.invoke(try s.invoke(values, "map", &.{fn_value}), "join", &.{try s.text("")});
}
fn lookahead(s: *Scope, value: c.JSValue) !c.JSValue {
    return concat(s, &.{ try s.text("(?="), value, try s.text(")") });
}
fn plus(s: *Scope, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 0, a, b)));
}
fn at(s: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, value, index)));
}
fn title(s: *Scope, hljs: c.JSValue) !c.JSValue {
    const inherit = try s.get(hljs, "inherit");
    const base = try s.get(hljs, "TITLE_MODE");
    const changes = try s.object();
    try s.put(changes, "begin", try s.text(ident));
    return s.call(inherit, hljs, &.{ base, changes });
}
fn xmlOpening(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return opening(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn opening(engine: *em.Engine, match: c.JSValue, response: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const after = try plus(&s, try s.get(try at(&s, match, 0), "length"), try s.get(match, "index"));
    const next = try s.own(try @import("native_js_values.zig").getKey(engine, try s.get(match, "input"), after));
    if (s.equal(next, try s.text("<"))) {
        _ = try s.invoke(response, "ignoreMatch", &.{});
        return c.pi_js_undefined();
    }
    if (s.equal(next, try s.text(">"))) {
        const tag = try s.concat(try s.text("</"), try s.invoke(try at(&s, match, 0), "slice", &.{c.JS_NewInt32(engine.context, 1)}));
        const pos = try s.invoke(try s.get(match, "input"), "indexOf", &.{ tag, after });
        if (s.equal(pos, c.JS_NewInt32(engine.context, -1))) _ = try s.invoke(response, "ignoreMatch", &.{});
    }
    return c.pi_js_undefined();
}
pub fn create(engine: *em.Engine, typescript: bool) !c.JSValue {
    const module = if (typescript) "pi-native:highlight-typescript-module" else "pi-native:highlight-javascript-module";
    if (!engine.native_module_values.contains(module)) {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const state = try s.object();
        try s.put(state, "KEYWORDS", try words(&s, keywords_text));
        try s.put(state, "LITERALS", try words(&s, literals_text));
        const types = try words(&s, types_text);
        const errors = try words(&s, error_types_text);
        const globals = try words(&s, built_in_globals_text);
        const variables = try words(&s, built_in_variables_text);
        const empty = try s.array();
        try s.put(state, "BUILT_INS", try s.invoke(empty, "concat", &.{ globals, variables, types, errors }));
        try s.put(state, "typescript", c.pi_js_bool(engine.context, @intFromBool(typescript)));
        const Adapter = struct {
            fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
                const selected = try @import("native_sdk.zig").get(host, roots[0], "typescript");
                defer host.freeValue(selected);
                return if (c.JS_ToBool(host.context, selected) == 1) buildTypeScript(host, if (args.len > 0) args[0] else c.pi_js_undefined(), roots[0]) else build(host, if (args.len > 0) args[0] else c.pi_js_undefined(), roots[0]);
            }
        };
        const exports = try s.object();
        try s.put(exports, "factory", try s.own(try ordinary.create(engine, if (typescript) "typescript" else "javascript", 1, Adapter.invoke, &.{state})));
        try engine.registerValueModule(module, exports);
    }
    return @import("native_sdk.zig").get(engine, engine.native_module_values.get(module).?, "factory");
}
fn languageTemplate(s: *Scope, hljs: c.JSValue, subst: c.JSValue, language: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "begin", try s.text(if (std.mem.eql(u8, language, "xml")) "html`" else "css`"));
    try s.put(result, "end", try s.text(""));
    const starts = try s.object();
    try s.put(starts, "end", try s.text("`"));
    try s.put(starts, "returnEnd", c.pi_js_bool(s.engine.context, 0));
    try s.put(starts, "contains", try list(s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), subst }));
    try s.put(starts, "subLanguage", try s.text(language));
    try s.put(result, "starts", starts);
    return result;
}
pub fn build(engine: *em.Engine, hljs: c.JSValue, state: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const fragment = try s.object();
    try s.put(fragment, "begin", try s.text("<>"));
    try s.put(fragment, "end", try s.text("</>"));
    const xml_tag = try s.object();
    try s.put(xml_tag, "begin", try literal(&s, "<[A-Za-z0-9\\\\._:-]+"));
    try s.put(xml_tag, "end", try literal(&s, "/[A-Za-z0-9\\\\._:-]+>|/>"));
    try s.put(xml_tag, "isTrulyOpeningTag", try s.own(try engine.checked(c.JS_NewCFunction(engine.context, xmlOpening, "isTrulyOpeningTag", 2))));
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try s.text(ident));
    try s.put(keywords, "keyword", try s.get(state, "KEYWORDS"));
    try s.put(keywords, "literal", try s.get(state, "LITERALS"));
    try s.put(keywords, "built_in", try s.get(state, "BUILT_INS"));
    const digit = "[0-9](_?[0-9])*";
    const frac = "\\.(" ++ digit ++ ")";
    const integer = "0|[1-9](_?[0-9])*|0[0-7]*[89][0-9]*";
    const number = try mode(&s, "number");
    const numbers = try s.array();
    inline for (.{ "(\\b(" ++ integer ++ ")((" ++ frac ++ ")|\\.)?|(" ++ frac ++ "))[eE][+-]?(" ++ digit ++ ")\\b", "\\b(" ++ integer ++ ")\\b((" ++ frac ++ ")\\b|\\.)?|(" ++ frac ++ ")\\b", "\\b(0|[1-9](_?[0-9])*)n\\b", "\\b0[xX][0-9a-fA-F](_?[0-9a-fA-F])*n?\\b", "\\b0[bB][0-1](_?[0-1])*n?\\b", "\\b0[oO][0-7](_?[0-7])*n?\\b", "\\b0[0-7]+n?\\b" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        try s.index(numbers, index, variant);
    }
    try s.put(number, "variants", numbers);
    try s.put(number, "relevance", c.JS_NewInt32(engine.context, 0));
    const subst = try mode(&s, "subst");
    try s.put(subst, "begin", try s.text("\\$\\{"));
    try s.put(subst, "end", try s.text("\\}"));
    try s.put(subst, "keywords", keywords);
    try s.put(subst, "contains", try s.array());
    const html = try languageTemplate(&s, hljs, subst, "xml");
    const css = try languageTemplate(&s, hljs, subst, "css");
    const template_string = try mode(&s, "string");
    try s.put(template_string, "begin", try s.text("`"));
    try s.put(template_string, "end", try s.text("`"));
    try s.put(template_string, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), subst }));
    const comment_fn = try s.get(hljs, "COMMENT");
    const jsdoc_begin = try literal(&s, "/\\*\\*(?!/)");
    const jsdoc_options = try s.object();
    try s.put(jsdoc_options, "relevance", c.JS_NewInt32(engine.context, 0));
    const doctag = try mode(&s, "doctag");
    try s.put(doctag, "begin", try s.text("@[A-Za-z]+"));
    const doc_type = try mode(&s, "type");
    try s.put(doc_type, "begin", try s.text("\\{"));
    try s.put(doc_type, "end", try s.text("\\}"));
    try s.put(doc_type, "relevance", c.JS_NewInt32(engine.context, 0));
    const doc_variable = try mode(&s, "variable");
    try s.put(doc_variable, "begin", try s.text(ident ++ "(?=\\s*(-)|$)"));
    try s.put(doc_variable, "endsParent", c.pi_js_bool(engine.context, 1));
    try s.put(doc_variable, "relevance", c.JS_NewInt32(engine.context, 0));
    const doc_space = try s.object();
    try s.put(doc_space, "begin", try literal(&s, "(?=[^\\n])\\s"));
    try s.put(doc_space, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(doctag, "contains", try list(&s, &.{ doc_type, doc_variable, doc_space }));
    try s.put(jsdoc_options, "contains", try list(&s, &.{doctag}));
    const jsdoc = try s.call(comment_fn, hljs, &.{ jsdoc_begin, try s.text("\\*/"), jsdoc_options });
    const comment = try mode(&s, "comment");
    try s.put(comment, "variants", try list(&s, &.{ jsdoc, try s.get(hljs, "C_BLOCK_COMMENT_MODE"), try s.get(hljs, "C_LINE_COMMENT_MODE") }));
    const internals = try list(&s, &.{ try s.get(hljs, "APOS_STRING_MODE"), try s.get(hljs, "QUOTE_STRING_MODE"), html, css, template_string, number, try s.get(hljs, "REGEXP_MODE") });
    const internal_concat = try s.get(internals, "concat");
    const balanced = try s.object();
    try s.put(balanced, "begin", try literal(&s, "\\{"));
    try s.put(balanced, "end", try literal(&s, "\\}"));
    try s.put(balanced, "keywords", keywords);
    try s.put(balanced, "contains", try s.invoke(try list(&s, &.{try s.text("self")}), "concat", &.{internals}));
    try s.set(subst, "contains", try s.call(internal_concat, internals, &.{balanced}));
    const subst_comments = try s.invoke(try s.array(), "concat", &.{ comment, try s.get(subst, "contains") });
    const params_concat = try s.get(subst_comments, "concat");
    const nested_parens = try s.object();
    try s.put(nested_parens, "begin", try literal(&s, "\\("));
    try s.put(nested_parens, "end", try literal(&s, "\\)"));
    try s.put(nested_parens, "keywords", keywords);
    try s.put(nested_parens, "contains", try s.invoke(try list(&s, &.{try s.text("self")}), "concat", &.{subst_comments}));
    const params_contains = try s.call(params_concat, subst_comments, &.{try list(&s, &.{nested_parens})});
    const params = try mode(&s, "params");
    try s.put(params, "begin", try literal(&s, "\\("));
    try s.put(params, "end", try literal(&s, "\\)"));
    try s.put(params, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(params, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(params, "keywords", keywords);
    try s.put(params, "contains", params_contains);
    const language = try s.object();
    try s.put(language, "name", try s.text("Javascript"));
    try s.put(language, "aliases", try list(&s, &.{ try s.text("js"), try s.text("jsx"), try s.text("mjs"), try s.text("cjs") }));
    try s.put(language, "keywords", keywords);
    const exports = try s.object();
    try s.put(exports, "PARAMS_CONTAINS", params_contains);
    try s.put(language, "exports", exports);
    try s.put(language, "illegal", try literal(&s, "#(?![$_A-z])"));
    const contains = try s.array();
    const shebang_fn = try s.get(hljs, "SHEBANG");
    const shebang_options = try s.object();
    try s.put(shebang_options, "label", try s.text("shebang"));
    try s.put(shebang_options, "binary", try s.text("node"));
    try s.put(shebang_options, "relevance", c.JS_NewInt32(engine.context, 5));
    try s.index(contains, 0, try s.call(shebang_fn, hljs, &.{shebang_options}));
    const strict = try s.object();
    try s.put(strict, "label", try s.text("use_strict"));
    try s.put(strict, "className", try s.text("meta"));
    try s.put(strict, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.put(strict, "begin", try literal(&s, "^\\s*['\"]use (strict|asm)['\"]"));
    try s.index(contains, 1, strict);
    try s.index(contains, 2, try s.get(hljs, "APOS_STRING_MODE"));
    try s.index(contains, 3, try s.get(hljs, "QUOTE_STRING_MODE"));
    try s.index(contains, 4, html);
    try s.index(contains, 5, css);
    try s.index(contains, 6, template_string);
    try s.index(contains, 7, comment);
    try s.index(contains, 8, number);
    const attrs = try s.object();
    try s.put(attrs, "begin", try concat(&s, &.{ try literal(&s, "[{,\\n]\\s*"), try lookahead(&s, try concat(&s, &.{ try literal(&s, "(((//.*$)|(/\\*(\\*[^/]|[^*])*\\*/))\\s*)*"), try s.text(ident ++ "\\s*:") })) }));
    try s.put(attrs, "relevance", c.JS_NewInt32(engine.context, 0));
    const attr = try mode(&s, "attr");
    try s.put(attr, "begin", try s.concat(try s.text(ident), try lookahead(&s, try s.text("\\s*:"))));
    try s.put(attr, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(attrs, "contains", try list(&s, &.{attr}));
    try s.index(contains, 9, attrs);
    return finish(&s, hljs, language, contains, keywords, comment, xml_tag, fragment, params, params_contains);
}
fn finish(s: *Scope, hljs: c.JSValue, language: c.JSValue, contains: c.JSValue, keywords: c.JSValue, comment: c.JSValue, xml_tag: c.JSValue, fragment: c.JSValue, params: c.JSValue, params_contains: c.JSValue) !c.JSValue {
    const engine = s.engine;
    const value = try s.object();
    try s.put(value, "begin", try s.concat(try s.concat(try s.text("("), try s.get(hljs, "RE_STARTERS_RE")), try s.text("|\\b(case|return|throw)\\b)\\s*")));
    try s.put(value, "keywords", try s.text("return throw case"));
    const value_contains = try s.array();
    try s.index(value_contains, 0, comment);
    try s.index(value_contains, 1, try s.get(hljs, "REGEXP_MODE"));
    const arrow = try mode(s, "function");
    try s.put(arrow, "begin", try s.concat(try s.concat(try s.text("(\\([^()]*(\\([^()]*(\\([^()]*\\)[^()]*)*\\)[^()]*)*\\)|"), try s.get(hljs, "UNDERSCORE_IDENT_RE")), try s.text(")\\s*=>")));
    try s.put(arrow, "returnBegin", c.pi_js_bool(engine.context, 1));
    try s.put(arrow, "end", try s.text("\\s*=>"));
    const arrow_params = try mode(s, "params");
    const arrow_variants = try s.array();
    const bare = try s.object();
    try s.put(bare, "begin", try s.get(hljs, "UNDERSCORE_IDENT_RE"));
    try s.put(bare, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(arrow_variants, 0, bare);
    const empty = try s.object();
    try s.put(empty, "className", c.pi_js_null());
    try s.put(empty, "begin", try literal(s, "\\(\\s*\\)"));
    try s.put(empty, "skip", c.pi_js_bool(engine.context, 1));
    try s.index(arrow_variants, 1, empty);
    const actual = try s.object();
    try s.put(actual, "begin", try literal(s, "\\("));
    try s.put(actual, "end", try literal(s, "\\)"));
    try s.put(actual, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(actual, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(actual, "keywords", keywords);
    try s.put(actual, "contains", params_contains);
    try s.index(arrow_variants, 2, actual);
    try s.put(arrow_params, "variants", arrow_variants);
    try s.put(arrow, "contains", try list(s, &.{arrow_params}));
    try s.index(value_contains, 2, arrow);
    const comma = try s.object();
    try s.put(comma, "begin", try literal(s, ","));
    try s.put(comma, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(value_contains, 3, comma);
    const space = try mode(s, "");
    try s.put(space, "begin", try literal(s, "\\s"));
    try s.put(space, "end", try literal(s, "\\s*"));
    try s.put(space, "skip", c.pi_js_bool(engine.context, 1));
    try s.index(value_contains, 4, space);
    const jsx = try s.object();
    const fragment_variant = try s.object();
    try s.put(fragment_variant, "begin", try s.get(fragment, "begin"));
    try s.put(fragment_variant, "end", try s.get(fragment, "end"));
    const tag_variant = try s.object();
    try s.put(tag_variant, "begin", try s.get(xml_tag, "begin"));
    try s.put(tag_variant, "on:begin", try s.get(xml_tag, "isTrulyOpeningTag"));
    try s.put(tag_variant, "end", try s.get(xml_tag, "end"));
    try s.put(jsx, "variants", try list(s, &.{ fragment_variant, tag_variant }));
    try s.put(jsx, "subLanguage", try s.text("xml"));
    const inner_tag = try s.object();
    try s.put(inner_tag, "begin", try s.get(xml_tag, "begin"));
    try s.put(inner_tag, "end", try s.get(xml_tag, "end"));
    try s.put(inner_tag, "skip", c.pi_js_bool(engine.context, 1));
    try s.put(inner_tag, "contains", try list(s, &.{try s.text("self")}));
    try s.put(jsx, "contains", try list(s, &.{inner_tag}));
    try s.index(value_contains, 5, jsx);
    try s.put(value, "contains", value_contains);
    try s.put(value, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 10, value);
    const declaration = try mode(s, "function");
    try s.put(declaration, "beginKeywords", try s.text("function"));
    try s.put(declaration, "end", try literal(s, "[{;]"));
    try s.put(declaration, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(declaration, "keywords", keywords);
    try s.put(declaration, "contains", try list(s, &.{ try s.text("self"), try title(s, hljs), params }));
    try s.put(declaration, "illegal", try literal(s, "%"));
    try s.index(contains, 11, declaration);
    const condition = try s.object();
    try s.put(condition, "beginKeywords", try s.text("while if switch catch for"));
    try s.index(contains, 12, condition);
    const method = try mode(s, "function");
    try s.put(method, "begin", try s.concat(try s.get(hljs, "UNDERSCORE_IDENT_RE"), try s.text("\\([^()]*(\\([^()]*(\\([^()]*\\)[^()]*)*\\)[^()]*)*\\)\\s*\\{")));
    try s.put(method, "returnBegin", c.pi_js_bool(engine.context, 1));
    try s.put(method, "contains", try list(s, &.{ params, try title(s, hljs) }));
    try s.index(contains, 13, method);
    const nonkeyword = try s.object();
    const variants = try s.array();
    inline for (.{ "\\.", "\\$" }, 0..) |prefix, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(prefix ++ ident));
        try s.index(variants, index, variant);
    }
    try s.put(nonkeyword, "variants", variants);
    try s.put(nonkeyword, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 14, nonkeyword);
    const class_mode = try mode(s, "class");
    try s.put(class_mode, "beginKeywords", try s.text("class"));
    try s.put(class_mode, "end", try literal(s, "[{;=]"));
    try s.put(class_mode, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(class_mode, "illegal", try literal(s, "[:\"[\\]]"));
    const extends = try s.object();
    try s.put(extends, "beginKeywords", try s.text("extends"));
    try s.put(class_mode, "contains", try list(s, &.{ extends, try s.get(hljs, "UNDERSCORE_TITLE_MODE") }));
    try s.index(contains, 15, class_mode);
    const constructor = try s.object();
    try s.put(constructor, "begin", try literal(s, "\\b(?=constructor)"));
    try s.put(constructor, "end", try literal(s, "[{;]"));
    try s.put(constructor, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(constructor, "contains", try list(s, &.{ try title(s, hljs), try s.text("self"), params }));
    try s.index(contains, 16, constructor);
    const access = try s.object();
    try s.put(access, "begin", try s.text("(get|set)\\s+(?=" ++ ident ++ "\\()"));
    try s.put(access, "end", try literal(s, "\\{"));
    try s.put(access, "keywords", try s.text("get set"));
    const empty_params = try s.object();
    try s.put(empty_params, "begin", try literal(s, "\\(\\)"));
    try s.put(access, "contains", try list(s, &.{ try title(s, hljs), empty_params, params }));
    try s.index(contains, 17, access);
    const jquery = try s.object();
    try s.put(jquery, "begin", try literal(s, "\\$[(.]"));
    try s.index(contains, 18, jquery);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
fn findCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return findValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic, roots[0]) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn findValue(engine: *em.Engine, value: c.JSValue, kind: c_int, label: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(s.equal(try s.get(value, if (kind == 0) "label" else "className"), label)));
}
fn swap(s: *Scope, language: c.JSValue, label: []const u8, replacement: c.JSValue) !void {
    var roots = [_]c.JSValue{try s.text(label)};
    const fn_value = try s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, findCallback, "", 1, 0, roots.len, &roots)));
    const index = try s.invoke(try s.get(language, "contains"), "findIndex", &.{fn_value});
    if (s.equal(index, c.JS_NewInt32(s.engine.context, -1))) {
        var args = [_]c.JSValue{try s.text("can not find mode to replace")};
        const error_value = try s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, try s.global("Error"), args.len, &args)));
        _ = c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, error_value));
        return @import("native_js_values.zig").capture(s.engine);
    }
    _ = try s.invoke(try s.get(language, "contains"), "splice", &.{ index, c.JS_NewInt32(s.engine.context, 1), replacement });
}
fn buildTypeScript(engine: *em.Engine, hljs: c.JSValue, state: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const namespace = try s.object();
    try s.put(namespace, "beginKeywords", try s.text("namespace"));
    try s.put(namespace, "end", try literal(&s, "\\{"));
    try s.put(namespace, "excludeEnd", c.pi_js_bool(engine.context, 1));
    const interface = try s.object();
    try s.put(interface, "beginKeywords", try s.text("interface"));
    try s.put(interface, "end", try literal(&s, "\\{"));
    try s.put(interface, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(interface, "keywords", try s.text("interface extends"));
    const strict = try mode(&s, "meta");
    try s.put(strict, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.put(strict, "begin", try literal(&s, "^\\s*['\"]use strict['\"]"));
    const types = try words(&s, "any void number boolean string object never enum");
    const specific = try words(&s, "type namespace typedef interface public private protected implements declare abstract readonly");
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try s.text(ident));
    try s.put(keywords, "keyword", try s.invoke(try s.get(state, "KEYWORDS"), "concat", &.{specific}));
    try s.put(keywords, "literal", try s.get(state, "LITERALS"));
    try s.put(keywords, "built_in", try s.invoke(try s.get(state, "BUILT_INS"), "concat", &.{types}));
    const decorator = try mode(&s, "meta");
    try s.put(decorator, "begin", try s.text("@" ++ ident));
    const language = try s.own(try build(engine, hljs, state));
    _ = try s.invoke(try s.global("Object"), "assign", &.{ try s.get(language, "keywords"), keywords });
    _ = try s.invoke(try s.get(try s.get(language, "exports"), "PARAMS_CONTAINS"), "push", &.{decorator});
    try s.set(language, "contains", try s.invoke(try s.get(language, "contains"), "concat", &.{try list(&s, &.{ decorator, namespace, interface })}));
    try swap(&s, language, "shebang", try s.call(try s.get(hljs, "SHEBANG"), hljs, &.{}));
    try swap(&s, language, "use_strict", strict);
    var roots = [_]c.JSValue{try s.text("function")};
    const predicate = try s.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, findCallback, "", 1, 1, roots.len, &roots)));
    const declaration = try s.invoke(try s.get(language, "contains"), "find", &.{predicate});
    try s.set(declaration, "relevance", c.JS_NewInt32(engine.context, 0));
    const changes = try s.object();
    try s.put(changes, "name", try s.text("TypeScript"));
    try s.put(changes, "aliases", try list(&s, &.{ try s.text("ts"), try s.text("tsx") }));
    _ = try s.invoke(try s.global("Object"), "assign", &.{ language, changes });
    return c.JS_DupValue(engine.context, language);
}
