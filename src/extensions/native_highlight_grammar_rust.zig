//! Complete Source highlight.js10.7.3 Rust factory body; private source-only.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
const keywords = "abstract as async await become box break const continue crate do dyn else enum extern false final fn for if impl in let loop macro match mod move mut override priv pub ref return self Self static struct super trait true try type typeof unsafe unsized use virtual where while yield";
const builtins = "drop i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 str char bool Box Option Result String Vec Copy Send Sized Sync Drop Fn FnMut FnOnce ToOwned Clone Debug PartialEq PartialOrd Eq Ord AsRef AsMut Into From Default Iterator Extend IntoIterator DoubleEndedIterator ExactSizeIterator SliceConcatExt ToString assert! assert_eq! bitflags! bytes! cfg! col! concat! concat_idents! debug_assert! debug_assert_eq! env! panic! file! format! format_args! include_bin! include_str! line! local_data_key! module_path! option_env! print! println! select! stringify! try! unimplemented! unreachable! vec! write! writeln! macro_rules! assert_ne! debug_assert_ne!";
const suffix = "([ui](8|16|32|64|128|size)|f(32|64))?";
fn list(scope: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try scope.array();
    for (values, 0..) |value, index| try scope.index(result, @intCast(index), value);
    return result;
}
fn literal(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(pattern)};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn classMode(scope: *Scope, name: []const u8) !c.JSValue {
    const mode = try scope.object();
    try scope.put(mode, "className", try scope.text(name));
    return mode;
}
fn title(scope: *Scope, hljs: c.JSValue) !c.JSValue {
    const inherit = try scope.get(hljs, "inherit");
    const base = try scope.get(hljs, "UNDERSCORE_TITLE_MODE");
    const changes = try scope.object();
    try scope.put(changes, "endsParent", c.pi_js_bool(scope.engine.context, 1));
    return scope.call(inherit, hljs, &.{ base, changes });
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "rust", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const language = try scope.object();
    try scope.put(language, "name", try scope.text("Rust"));
    try scope.put(language, "aliases", try list(&scope, &.{try scope.text("rs")}));
    const words = try scope.object();
    try scope.put(words, "$pattern", try scope.concat(try scope.get(hljs, "IDENT_RE"), try scope.text("!?")));
    try scope.put(words, "keyword", try scope.text(keywords));
    try scope.put(words, "literal", try scope.text("true false Some None Ok Err"));
    try scope.put(words, "built_in", try scope.text(builtins));
    try scope.put(language, "keywords", words);
    try scope.put(language, "illegal", try scope.text("</"));
    const contains = try scope.array();
    try scope.index(contains, 0, try scope.get(hljs, "C_LINE_COMMENT_MODE"));
    const comment = try scope.get(hljs, "COMMENT");
    const comment_options = try scope.object();
    try scope.put(comment_options, "contains", try list(&scope, &.{try scope.text("self")}));
    try scope.index(contains, 1, try scope.call(comment, hljs, &.{ try scope.text("/\\*"), try scope.text("\\*/"), comment_options }));
    const inherit = try scope.get(hljs, "inherit");
    const quote = try scope.get(hljs, "QUOTE_STRING_MODE");
    const quote_changes = try scope.object();
    try scope.put(quote_changes, "begin", try literal(&scope, "b?\""));
    try scope.put(quote_changes, "illegal", c.pi_js_null());
    try scope.index(contains, 2, try scope.call(inherit, hljs, &.{ quote, quote_changes }));
    const strings = try classMode(&scope, "string");
    const variants = try scope.array();
    inline for (.{ "r(#*)\"(.|\\n)*?\"\\1(?!#)", "b?'\\\\?(x\\w{2}|u\\w{4}|U\\w{8}|.)'" }, 0..) |pattern, index| {
        const variant = try scope.object();
        try scope.put(variant, "begin", try literal(&scope, pattern));
        try scope.index(variants, index, variant);
    }
    try scope.put(strings, "variants", variants);
    try scope.index(contains, 3, strings);
    const symbol = try classMode(&scope, "symbol");
    try scope.put(symbol, "begin", try literal(&scope, "'[a-zA-Z_][a-zA-Z0-9_]*"));
    try scope.index(contains, 4, symbol);
    const number = try classMode(&scope, "number");
    const numbers = try scope.array();
    inline for (.{ "\\b0b([01_]+)" ++ suffix, "\\b0o([0-7_]+)" ++ suffix, "\\b0x([A-Fa-f0-9_]+)" ++ suffix, "\\b(\\d[\\d_]*(\\.[0-9_]+)?([eE][+-]?[0-9_]+)?)" ++ suffix }, 0..) |pattern, index| {
        const variant = try scope.object();
        try scope.put(variant, "begin", try scope.text(pattern));
        try scope.index(numbers, index, variant);
    }
    try scope.put(number, "variants", numbers);
    try scope.put(number, "relevance", c.JS_NewInt32(engine.context, 0));
    try scope.index(contains, 5, number);
    const function = try classMode(&scope, "function");
    try scope.put(function, "beginKeywords", try scope.text("fn"));
    try scope.put(function, "end", try scope.text("(\\(|<)"));
    try scope.put(function, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try scope.put(function, "contains", try list(&scope, &.{try scope.get(hljs, "UNDERSCORE_TITLE_MODE")}));
    try scope.index(contains, 6, function);
    const meta = try classMode(&scope, "meta");
    try scope.put(meta, "begin", try scope.text("#!?\\["));
    try scope.put(meta, "end", try scope.text("\\]"));
    const meta_string = try classMode(&scope, "meta-string");
    try scope.put(meta_string, "begin", try literal(&scope, "\""));
    try scope.put(meta_string, "end", try literal(&scope, "\""));
    try scope.put(meta, "contains", try list(&scope, &.{meta_string}));
    try scope.index(contains, 7, meta);
    const type_mode = try classMode(&scope, "class");
    try scope.put(type_mode, "beginKeywords", try scope.text("type"));
    try scope.put(type_mode, "end", try scope.text(";"));
    try scope.put(type_mode, "contains", try list(&scope, &.{try title(&scope, hljs)}));
    try scope.put(type_mode, "illegal", try scope.text("\\S"));
    try scope.index(contains, 8, type_mode);
    const declaration = try classMode(&scope, "class");
    try scope.put(declaration, "beginKeywords", try scope.text("trait enum struct union"));
    try scope.put(declaration, "end", try literal(&scope, "\\{"));
    try scope.put(declaration, "contains", try list(&scope, &.{try title(&scope, hljs)}));
    try scope.put(declaration, "illegal", try scope.text("[\\w\\d]"));
    try scope.index(contains, 9, declaration);
    const namespace = try scope.object();
    try scope.put(namespace, "begin", try scope.concat(try scope.get(hljs, "IDENT_RE"), try scope.text("::")));
    const namespace_words = try scope.object();
    try scope.put(namespace_words, "built_in", try scope.text(builtins));
    try scope.put(namespace, "keywords", namespace_words);
    try scope.index(contains, 10, namespace);
    const arrow = try scope.object();
    try scope.put(arrow, "begin", try scope.text("->"));
    try scope.index(contains, 11, arrow);
    try scope.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
