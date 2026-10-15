//! Actual highlight.js10.7.3 R factory and compiler extension; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
fn concat(s: *b.Scope, values: []const b.c.JSValue) !b.c.JSValue {
    return s.own(try @import("native_highlight_regex.zig").concat(s.engine, try b.list(s, values)));
}
fn deleteProperty(e: *b.Engine, object: b.c.JSValue, key: b.c.JSValue) !void {
    const atom = try js.atom(e, key);
    defer b.c.JS_FreeAtom(e.context, atom);
    if (b.c.JS_DeleteProperty(e.context, object, atom, 0) < 0) return js.capture(e);
}
fn deleteKey(context: ?*b.c.JSContext, _: b.c.JSValue, argc: c_int, argv: [*c]b.c.JSValue, _: c_int, roots: [*c]b.c.JSValue) callconv(.c) b.c.JSValue {
    const e = b.Engine.fromContext(context.?);
    deleteProperty(e, roots[0], if (argc > 0) argv[0] else b.c.pi_js_undefined()) catch |err| return sdk.fail(e, err);
    return b.c.pi_js_undefined();
}
fn applyBeforeMatch(e: *b.Engine, mode: b.c.JSValue) !void {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    if (!s.truthy(try s.get(mode, "beforeMatch"))) return;
    if (s.truthy(try s.get(mode, "starts"))) {
        const ctor = try s.global("Error");
        var args = [_]b.c.JSValue{try s.text("beforeMatch cannot be used with starts")};
        const reason = try s.own(try e.checked(b.c.JS_CallConstructor(e.context, ctor, args.len, &args)));
        _ = b.c.JS_Throw(e.context, b.c.JS_DupValue(e.context, reason));
        return js.capture(e);
    }
    const object = try s.global("Object");
    const assign = try s.get(object, "assign");
    const original = try s.call(assign, object, &.{ try s.object(), mode });
    const keys_object = try s.global("Object");
    const keys = try s.invoke(keys_object, "keys", &.{mode});
    const each = try s.get(keys, "forEach");
    var roots = [_]b.c.JSValue{mode};
    const callback = try s.own(try e.checked(b.c.JS_NewCFunctionData2(e.context, deleteKey, "", 1, 0, roots.len, &roots)));
    _ = try s.call(each, keys, &.{callback});
    const qualifier = try s.get(original, "beforeMatch");
    const begin = try s.get(original, "begin");
    const ahead = try concat(&s, &.{ try s.text("(?="), begin, try s.text(")") });
    try s.set(mode, "begin", try concat(&s, &.{ qualifier, ahead }));
    const starts = try s.object();
    try s.put(starts, "relevance", b.c.JS_NewInt32(e.context, 0));
    const assign_object = try s.global("Object");
    const assign_inner = try s.get(assign_object, "assign");
    const changes = try s.object();
    try s.put(changes, "endsParent", b.boolean(&s, true));
    const child = try s.call(assign_inner, assign_object, &.{ original, changes });
    try s.put(starts, "contains", try b.list(&s, &.{child}));
    try s.set(mode, "starts", starts);
    try s.set(mode, "relevance", b.c.JS_NewInt32(e.context, 0));
    try deleteProperty(e, original, try s.text("beforeMatch"));
}
fn compilerExtension(context: ?*b.c.JSContext, _: b.c.JSValue, argc: c_int, argv: [*c]b.c.JSValue) callconv(.c) b.c.JSValue {
    const e = b.Engine.fromContext(context.?);
    applyBeforeMatch(e, if (argc > 0) argv[0] else b.c.pi_js_undefined()) catch |err| return sdk.fail(e, err);
    return b.c.pi_js_undefined();
}
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "r", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const ident = try b.rx(&s, "(?:(?:[a-zA-Z]|\\.[._a-zA-Z])[._a-zA-Z0-9]*)|\\.(?!\\d)");
    const simple = try b.rx(&s, "[a-zA-Z][a-zA-Z_0-9]*");
    const language = try s.object();
    try s.put(language, "name", try s.text("R"));
    try s.put(language, "illegal", try b.rx(&s, "->"));
    const keywords = try s.object();
    try s.put(keywords, "$pattern", ident);
    try s.put(keywords, "keyword", try s.text(source_keyword));
    try s.put(keywords, "literal", try s.text(source_literal));
    try s.put(keywords, "built_in", try s.text(source_built_in));
    try s.put(language, "keywords", keywords);
    const extension = try s.own(try e.checked(b.c.JS_NewCFunction(e.context, compilerExtension, "", 2)));
    try s.put(language, "compilerExtensions", try b.list(&s, &.{extension}));
    const roxygen = try s.get(hljs, "COMMENT");
    const roxygen_begin = try b.rx(&s, "#'");
    const roxygen_end = try b.rx(&s, "$");
    const options = try s.object();
    const examples = try b.mode(&s, "doctag");
    try s.put(examples, "begin", try s.text("@examples"));
    const example_starts = try s.object();
    const newline = try s.object();
    try s.put(newline, "begin", try b.rx(&s, "\\n"));
    const next_tag = try s.object();
    try s.put(next_tag, "begin", try b.rx(&s, "#'\\s*(?=@[a-zA-Z]+)"));
    try s.put(next_tag, "endsParent", b.boolean(&s, true));
    const example_line = try s.object();
    try s.put(example_line, "begin", try b.rx(&s, "#'"));
    try s.put(example_line, "end", try b.rx(&s, "$"));
    try s.put(example_line, "excludeBegin", b.boolean(&s, true));
    try s.put(example_starts, "contains", try b.list(&s, &.{ newline, next_tag, example_line }));
    try s.put(examples, "starts", example_starts);
    const param = try b.mode(&s, "doctag");
    try s.put(param, "begin", try s.text("@param"));
    try s.put(param, "end", try b.rx(&s, "$"));
    const variable = try b.mode(&s, "variable");
    const plain = try s.object();
    try s.put(plain, "begin", ident);
    const quoted_id = try s.object();
    try s.put(quoted_id, "begin", try b.rx(&s, "`(?:\\\\.|[^`\\\\])+`"));
    try s.put(variable, "variants", try b.list(&s, &.{ plain, quoted_id }));
    try s.put(variable, "endsParent", b.boolean(&s, true));
    try s.put(param, "contains", try b.list(&s, &.{variable}));
    const tag = try b.mode(&s, "doctag");
    try s.put(tag, "begin", try b.rx(&s, "@[a-zA-Z]+"));
    const markup = try b.mode(&s, "meta-keyword");
    try s.put(markup, "begin", try b.rx(&s, "\\\\[a-zA-Z]+"));
    try s.put(options, "contains", try b.list(&s, &.{ examples, param, tag, markup }));
    const contains = try b.list(&s, &.{ try s.call(roxygen, hljs, &.{ roxygen_begin, roxygen_end, options }), try s.get(hljs, "HASH_COMMENT_MODE") });
    const string = try b.mode(&s, "string");
    try s.put(string, "contains", try b.list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    const variants = try s.array();
    inline for (.{ .{ "[rR]\"(-*)\\(", "\\)(-*)\"" }, .{ "[rR]\"(-*)\\{", "\\}(-*)\"" }, .{ "[rR]\"(-*)\\[", "\\](-*)\"" }, .{ "[rR]'(-*)\\(", "\\)(-*)'" }, .{ "[rR]'(-*)\\{", "\\}(-*)'" }, .{ "[rR]'(-*)\\[", "\\](-*)'" } }, 0..) |pair, index| {
        const same = try s.get(hljs, "END_SAME_AS_BEGIN");
        const mode = try s.object();
        try s.put(mode, "begin", try b.rx(&s, pair[0]));
        try s.put(mode, "end", try b.rx(&s, pair[1]));
        try s.index(variants, index, try s.call(same, hljs, &.{mode}));
    }
    inline for (.{ "\"", "'" }, 0..) |delimiter, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(delimiter));
        try s.put(variant, "end", try s.text(delimiter));
        try s.put(variant, "relevance", b.c.JS_NewInt32(e.context, 0));
        try s.index(variants, @intCast(index + 6), variant);
    }
    try s.put(string, "variants", variants);
    try s.index(contains, 2, string);
    const number = try b.mode(&s, "number");
    try s.put(number, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(number, "beforeMatch", try b.rx(&s, "([^a-zA-Z0-9._])"));
    const numbers = try s.array();
    inline for (.{ "0[xX][0-9a-fA-F]+\\.[0-9a-fA-F]*[pP][+-]?\\d+i?", "0[xX][0-9a-fA-F]+([pP][+-]?\\d+)?[Li]?", "(\\d+(\\.\\d*)?|\\.\\d+)([eE][+-]?\\d+)?[Li]?" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "match", try b.rx(&s, pattern));
        try s.index(numbers, index, variant);
    }
    try s.put(number, "variants", numbers);
    try s.index(contains, 3, number);
    const infix = try s.object();
    try s.put(infix, "begin", try s.text("%"));
    try s.put(infix, "end", try s.text("%"));
    try s.index(contains, 4, infix);
    const assignment = try s.object();
    try s.put(assignment, "begin", try concat(&s, &.{ simple, try s.text("\\s+<-\\s+") }));
    try s.index(contains, 5, assignment);
    const escaped_id = try s.object();
    try s.put(escaped_id, "begin", try s.text("`"));
    try s.put(escaped_id, "end", try s.text("`"));
    const escaped = try s.object();
    try s.put(escaped, "begin", try b.rx(&s, "\\\\."));
    try s.put(escaped_id, "contains", try b.list(&s, &.{escaped}));
    try s.index(contains, 6, escaped_id);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
const source_keyword = "function if in break next repeat else for while";
const source_literal = "NULL NA TRUE FALSE Inf NaN NA_integer_|10 NA_real_|10 NA_character_|10 NA_complex_|10";
const source_built_in = "LETTERS letters month.abb month.name pi T F abs acos acosh all any anyNA Arg as.call as.character as.complex as.double as.environment as.integer as.logical as.null.default as.numeric as.raw asin asinh atan atanh attr attributes baseenv browser c call ceiling class Conj cos cosh cospi cummax cummin cumprod cumsum digamma dim dimnames emptyenv exp expression floor forceAndCall gamma gc.time globalenv Im interactive invisible is.array is.atomic is.call is.character is.complex is.double is.environment is.expression is.finite is.function is.infinite is.integer is.language is.list is.logical is.matrix is.na is.name is.nan is.null is.numeric is.object is.pairlist is.raw is.recursive is.single is.symbol lazyLoadDBfetch length lgamma list log max min missing Mod names nargs nzchar oldClass on.exit pos.to.env proc.time prod quote range Re rep retracemem return round seq_along seq_len seq.int sign signif sin sinh sinpi sqrt standardGeneric substitute sum switch tan tanh tanpi tracemem trigamma trunc unclass untracemem UseMethod xtfrm";
