//! Complete Source highlight.js10.7.3 C and C++ factories; source-only draft.
//! Shared native construction preserves the two actual factory branches and graphs.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
const namespace = "[a-zA-Z_]\\w*::";
const template = "<[^<>]+>";
const decltype = "decltype\\(auto\\)";
const keyword_text = "int float while private char char8_t char16_t char32_t catch import module export virtual operator sizeof dynamic_cast|10 typedef const_cast|10 const for static_cast|10 union namespace unsigned long volatile static protected bool template mutable if public friend do goto auto void enum else break extern using asm case typeid wchar_t short reinterpret_cast|10 default double register explicit signed typename try this switch continue inline delete alignas alignof constexpr consteval constinit decltype concept co_await co_return co_yield requires noexcept static_assert thread_local restrict final override atomic_bool atomic_char atomic_schar atomic_uchar atomic_short atomic_ushort atomic_int atomic_uint atomic_long atomic_ulong atomic_llong atomic_ullong new throw return and and_eq bitand bitor compl not not_eq or or_eq xor xor_eq";
const c_builtins = "std string wstring cin cout cerr clog stdin stdout stderr stringstream istringstream ostringstream auto_ptr deque list queue stack vector map set pair bitset multiset multimap unordered_set unordered_map unordered_multiset unordered_multimap priority_queue make_pair array shared_ptr abort terminate abs acos asin atan2 atan calloc ceil cosh cos exit exp fabs floor fmod fprintf fputs free frexp fscanf future isalnum isalpha iscntrl isdigit isgraph islower isprint ispunct isspace isupper isxdigit tolower toupper labs ldexp log10 log malloc realloc memchr memcmp memcpy memset modf pow printf putchar puts scanf sinh sin snprintf sprintf sqrt sscanf strcat strchr strcmp strcpy strcspn strlen strncat strncmp strncpy strpbrk strrchr strspn strstr tanh tan vfprintf vprintf vsprintf endl initializer_list unique_ptr _Bool complex _Complex imaginary _Imaginary";
const cpp_hints = "asin atan2 atan calloc ceil cosh cos exit exp fabs floor fmod fprintf fputs free frexp auto_ptr deque list queue stack vector map set pair bitset multiset multimap unordered_set fscanf future isalnum isalpha iscntrl isdigit isgraph islower isprint ispunct isspace isupper isxdigit tolower toupper labs ldexp log10 log malloc realloc memchr memcmp memcpy memset modf pow printf putchar puts scanf sinh sin snprintf sprintf sqrt sscanf strcat strchr strcmp strcpy strcspn strlen strncat strncmp strncpy strpbrk strrchr strspn strstr tanh tan unordered_map unordered_multiset unordered_multimap priority_queue make_pair array shared_ptr abort terminate abs acos vfprintf vprintf vsprintf endl initializer_list unique_ptr complex imaginary std string wstring cin cout cerr clog stdin stdout stderr stringstream istringstream ostringstream";
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
fn optional(s: *Scope, value: c.JSValue) !c.JSValue {
    return concat(s, &.{ try s.text("("), value, try s.text(")?") });
}
fn lookahead(s: *Scope, value: c.JSValue) !c.JSValue {
    return concat(s, &.{ try s.text("(?="), value, try s.text(")") });
}
pub fn create(engine: *em.Engine, cpp: bool) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined(), c.JS_ToBool(host.context, roots[0]) == 1);
        }
    };
    return ordinary.create(engine, if (cpp) "cpp" else "c", 1, Adapter.invoke, &.{c.pi_js_bool(engine.context, @intFromBool(cpp))});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue, cpp: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const line_fn = try s.get(hljs, "COMMENT");
    const line_options = try s.object();
    const continuation = try s.object();
    try s.put(continuation, "begin", try literal(&s, "\\\\\\n"));
    try s.put(line_options, "contains", try list(&s, &.{continuation}));
    const line_comment = try s.call(line_fn, hljs, &.{ try s.text("//"), try s.text("$"), line_options });
    var function_type = try s.concat(try s.text("(" ++ decltype ++ "|"), try optional(&s, try s.text(namespace)));
    function_type = try s.concat(function_type, try s.text("[a-zA-Z_]\\w*"));
    function_type = try s.concat(function_type, try optional(&s, try s.text(template)));
    function_type = try s.concat(function_type, try s.text(")"));
    const primitive = try mode(&s, "keyword");
    try s.put(primitive, "begin", try s.text("\\b[a-z\\d_]*_t\\b"));
    const strings = try mode(&s, "string");
    const string_variants = try s.array();
    const quote = try s.object();
    try s.put(quote, "begin", try s.text("(u8?|U|L)?\""));
    try s.put(quote, "end", try s.text("\""));
    try s.put(quote, "illegal", try s.text("\\n"));
    try s.put(quote, "contains", try list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    try s.index(string_variants, 0, quote);
    const character = try s.object();
    try s.put(character, "begin", try s.text("(u8?|U|L)?'(\\\\(x[0-9A-Fa-f]{2}|u[0-9A-Fa-f]{4,8}|[0-7]{3}|\\S)|.)"));
    try s.put(character, "end", try s.text("'"));
    try s.put(character, "illegal", try s.text("."));
    try s.index(string_variants, 1, character);
    const same = try s.get(hljs, "END_SAME_AS_BEGIN");
    const raw = try s.object();
    try s.put(raw, "begin", try literal(&s, "(?:u8?|U|L)?R\"([^()\\\\ ]{0,16})\\("));
    try s.put(raw, "end", try literal(&s, "\\)([^()\\\\ ]{0,16})\""));
    try s.index(string_variants, 2, try s.call(same, hljs, &.{raw}));
    try s.put(strings, "variants", string_variants);
    const numbers = try mode(&s, "number");
    const numeric_variants = try s.array();
    inline for (.{ "\\b(0b[01']+)", "(-?)\\b([\\d']+(\\.[\\d']*)?|\\.[\\d']+)((ll|LL|l|L)(u|U)?|(u|U)(ll|LL|l|L)?|f|F|b|B)", "(-?)(\\b0[xX][a-fA-F0-9']+|(\\b[\\d']+(\\.[\\d']*)?|\\.[\\d']+)([eE][-+]?[\\d']+)?)" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        try s.index(numeric_variants, index, variant);
    }
    try s.put(numbers, "variants", numeric_variants);
    try s.put(numbers, "relevance", c.JS_NewInt32(engine.context, 0));
    const preprocessor = try mode(&s, "meta");
    try s.put(preprocessor, "begin", try literal(&s, "#\\s*[a-z]+\\b"));
    try s.put(preprocessor, "end", try literal(&s, "$"));
    const pre_words = try s.object();
    try s.put(pre_words, "meta-keyword", try s.text("if else elif endif define undef warning error line pragma _Pragma ifdef ifndef include"));
    try s.put(preprocessor, "keywords", pre_words);
    const pre_contains = try s.array();
    const continued = try s.object();
    try s.put(continued, "begin", try literal(&s, "\\\\\\n"));
    try s.put(continued, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(pre_contains, 0, continued);
    const inherit = try s.get(hljs, "inherit");
    const string_changes = try s.object();
    try s.put(string_changes, "className", try s.text("meta-string"));
    try s.index(pre_contains, 1, try s.call(inherit, hljs, &.{ strings, string_changes }));
    const include = try mode(&s, "meta-string");
    try s.put(include, "begin", try literal(&s, "<.*?>"));
    try s.index(pre_contains, 2, include);
    try s.index(pre_contains, 3, line_comment);
    try s.index(pre_contains, 4, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try s.put(preprocessor, "contains", pre_contains);
    const title = try mode(&s, "title");
    try s.put(title, "begin", try s.concat(try optional(&s, try s.text(namespace)), try s.get(hljs, "IDENT_RE")));
    try s.put(title, "relevance", c.JS_NewInt32(engine.context, 0));
    const function_title = try s.concat(try s.concat(try optional(&s, try s.text(namespace)), try s.get(hljs, "IDENT_RE")), try s.text("\\s*\\("));
    const hints = if (cpp) try words(&s, cpp_hints) else c.pi_js_undefined();
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text(keyword_text));
    try s.put(keywords, "built_in", try s.text(if (cpp) "_Bool _Complex _Imaginary" else c_builtins));
    if (cpp) try s.put(keywords, "_relevance_hints", hints);
    try s.put(keywords, "literal", try s.text("true false nullptr NULL"));
    const dispatch = if (cpp) try mode(&s, "function.dispatch") else c.pi_js_undefined();
    if (cpp) {
        try s.put(dispatch, "relevance", c.JS_NewInt32(engine.context, 0));
        try s.put(dispatch, "keywords", keywords);
        try s.put(dispatch, "begin", try concat(&s, &.{ try literal(&s, "\\b"), try literal(&s, "(?!decltype)"), try literal(&s, "(?!if)"), try literal(&s, "(?!for)"), try literal(&s, "(?!while)"), try s.get(hljs, "IDENT_RE"), try lookahead(&s, try literal(&s, "\\s*\\(")) }));
    }
    const expressions = try s.array();
    var index: u32 = 0;
    if (cpp) {
        try s.index(expressions, index, dispatch);
        index += 1;
    }
    try s.index(expressions, index, preprocessor);
    index += 1;
    try s.index(expressions, index, primitive);
    index += 1;
    try s.index(expressions, index, line_comment);
    index += 1;
    try s.index(expressions, index, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    index += 1;
    try s.index(expressions, index, numbers);
    index += 1;
    try s.index(expressions, index, strings);
    const context = try s.object();
    const contexts = try s.array();
    inline for (.{ .{ "=", ";" }, .{ "\\(", "\\)" } }, 0..) |entry, i| {
        const variant = try s.object();
        try s.put(variant, "begin", try literal(&s, entry[0]));
        try s.put(variant, "end", try literal(&s, entry[1]));
        try s.index(contexts, i, variant);
    }
    const expression_keywords = try s.object();
    try s.put(expression_keywords, "beginKeywords", try s.text("new throw return else"));
    try s.put(expression_keywords, "end", try literal(&s, ";"));
    try s.index(contexts, 2, expression_keywords);
    try s.put(context, "variants", contexts);
    try s.put(context, "keywords", keywords);
    const expressions_concat = try s.get(expressions, "concat");
    const nested = try s.object();
    try s.put(nested, "begin", try literal(&s, "\\("));
    try s.put(nested, "end", try literal(&s, "\\)"));
    try s.put(nested, "keywords", keywords);
    try s.put(nested, "contains", try s.invoke(expressions, "concat", &.{try list(&s, &.{try s.text("self")})}));
    try s.put(nested, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(context, "contains", try s.call(expressions_concat, expressions, &.{try list(&s, &.{nested})}));
    try s.put(context, "relevance", c.JS_NewInt32(engine.context, 0));
    const declaration = try mode(&s, "function");
    try s.put(declaration, "begin", try s.concat(try s.concat(try s.concat(try s.text("("), function_type), try s.text("[\\*&\\s]+)+")), function_title));
    try s.put(declaration, "returnBegin", c.pi_js_bool(engine.context, 1));
    try s.put(declaration, "end", try literal(&s, "[{;=]"));
    try s.put(declaration, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(declaration, "keywords", keywords);
    try s.put(declaration, "illegal", try literal(&s, "[^\\w\\s\\*&:<>.]"));
    const declaration_contains = try s.array();
    const decltype_mode = try s.object();
    try s.put(decltype_mode, "begin", try s.text(decltype));
    try s.put(decltype_mode, "keywords", keywords);
    try s.put(decltype_mode, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(declaration_contains, 0, decltype_mode);
    const title_mode = try s.object();
    try s.put(title_mode, "begin", function_title);
    try s.put(title_mode, "returnBegin", c.pi_js_bool(engine.context, 1));
    try s.put(title_mode, "contains", try list(&s, &.{title}));
    try s.put(title_mode, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(declaration_contains, 1, title_mode);
    var dindex: u32 = 2;
    if (cpp) {
        const colons = try s.object();
        try s.put(colons, "begin", try literal(&s, "::"));
        try s.put(colons, "relevance", c.JS_NewInt32(engine.context, 0));
        try s.index(declaration_contains, dindex, colons);
        dindex += 1;
        const initializers = try s.object();
        try s.put(initializers, "begin", try literal(&s, ":"));
        try s.put(initializers, "endsWithParent", c.pi_js_bool(engine.context, 1));
        try s.put(initializers, "contains", try list(&s, &.{ strings, numbers }));
        try s.index(declaration_contains, dindex, initializers);
        dindex += 1;
    }
    const params = try mode(&s, "params");
    try s.put(params, "begin", try literal(&s, "\\("));
    try s.put(params, "end", try literal(&s, "\\)"));
    try s.put(params, "keywords", keywords);
    try s.put(params, "relevance", c.JS_NewInt32(engine.context, 0));
    const param_contains = try s.array();
    try s.index(param_contains, 0, line_comment);
    try s.index(param_contains, 1, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try s.index(param_contains, 2, strings);
    try s.index(param_contains, 3, numbers);
    try s.index(param_contains, 4, primitive);
    const param_nested = try s.object();
    try s.put(param_nested, "begin", try literal(&s, "\\("));
    try s.put(param_nested, "end", try literal(&s, "\\)"));
    try s.put(param_nested, "keywords", keywords);
    try s.put(param_nested, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(param_nested, "contains", try list(&s, &.{ try s.text("self"), line_comment, try s.get(hljs, "C_BLOCK_COMMENT_MODE"), strings, numbers, primitive }));
    try s.index(param_contains, 5, param_nested);
    try s.put(params, "contains", param_contains);
    try s.index(declaration_contains, dindex, params);
    dindex += 1;
    try s.index(declaration_contains, dindex, primitive);
    dindex += 1;
    try s.index(declaration_contains, dindex, line_comment);
    dindex += 1;
    try s.index(declaration_contains, dindex, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    dindex += 1;
    try s.index(declaration_contains, dindex, preprocessor);
    try s.put(declaration, "contains", declaration_contains);
    const language = try s.object();
    try s.put(language, "name", try s.text(if (cpp) "C++" else "C"));
    try s.put(language, "aliases", if (cpp) try list(&s, &.{ try s.text("cc"), try s.text("c++"), try s.text("h++"), try s.text("hpp"), try s.text("hh"), try s.text("hxx"), try s.text("cxx") }) else try list(&s, &.{try s.text("h")}));
    try s.put(language, "keywords", keywords);
    if (!cpp) try s.put(language, "disableAutodetect", c.pi_js_bool(engine.context, 1));
    try s.put(language, "illegal", try s.text("</"));
    if (cpp) {
        const class_aliases = try s.object();
        try s.put(class_aliases, "function.dispatch", try s.text("built_in"));
        try s.put(language, "classNameAliases", class_aliases);
    }
    const empty = try s.array();
    const final_concat = try s.get(empty, "concat");
    const tail = try s.array();
    try s.index(tail, 0, preprocessor);
    const container = try s.object();
    try s.put(container, "begin", try s.text("\\b(deque|list|queue|priority_queue|pair|stack|vector|map|set|bitset|multiset|multimap|unordered_map|unordered_set|unordered_multiset|unordered_multimap|array)\\s*<"));
    try s.put(container, "end", try s.text(">"));
    try s.put(container, "keywords", keywords);
    try s.put(container, "contains", try list(&s, &.{ try s.text("self"), primitive }));
    try s.index(tail, 1, container);
    const qualified = try s.object();
    try s.put(qualified, "begin", try s.concat(try s.get(hljs, "IDENT_RE"), try s.text("::")));
    try s.put(qualified, "keywords", keywords);
    try s.index(tail, 2, qualified);
    const class_mode = try mode(&s, "class");
    try s.put(class_mode, "beginKeywords", try s.text("enum class struct union"));
    try s.put(class_mode, "end", try literal(&s, "[{;:<>=]"));
    const final = try s.object();
    try s.put(final, "beginKeywords", try s.text("final class struct"));
    try s.put(class_mode, "contains", try list(&s, &.{ final, try s.get(hljs, "TITLE_MODE") }));
    try s.index(tail, 3, class_mode);
    try s.put(language, "contains", try s.call(final_concat, empty, if (cpp) &.{ context, declaration, dispatch, expressions, tail } else &.{ context, declaration, expressions, tail }));
    const exports = try s.object();
    try s.put(exports, "preprocessor", preprocessor);
    try s.put(exports, "strings", strings);
    try s.put(exports, "keywords", keywords);
    try s.put(language, "exports", exports);
    return c.JS_DupValue(engine.context, language);
}
