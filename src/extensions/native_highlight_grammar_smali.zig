//! Actual highlight.js10.7.3 Smali factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
fn words(s: *b.Scope, values: []const []const u8) !b.c.JSValue {
    const array = try s.array();
    for (values, 0..) |value, index| try s.index(array, @intCast(index), try s.text(value));
    return array;
}
fn joined(s: *b.Scope, prefix: []const u8, array: b.c.JSValue, suffix: []const u8) !b.c.JSValue {
    const left = try s.text(prefix);
    const middle = try s.invoke(array, "join", &.{try s.text("|")});
    return s.concat(try s.concat(left, middle), try s.text(suffix));
}
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "smali", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const low = try words(&s, &.{ "add", "and", "cmp", "cmpg", "cmpl", "const", "div", "double", "float", "goto", "if", "int", "long", "move", "mul", "neg", "new", "nop", "not", "or", "rem", "return", "shl", "shr", "sput", "sub", "throw", "ushr", "xor" });
    const high = try words(&s, &.{ "aget", "aput", "array", "check", "execute", "fill", "filled", "goto/16", "goto/32", "iget", "instance", "invoke", "iput", "monitor", "packed", "sget", "sparse" });
    const keywords = try words(&s, &.{ "transient", "constructor", "abstract", "final", "synthetic", "public", "private", "protected", "static", "bridge", "system" });
    const language = try s.object();
    try s.put(language, "name", try s.text("Smali"));
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try s.text("\""));
    try s.put(string, "end", try s.text("\""));
    try s.put(string, "relevance", b.c.JS_NewInt32(e.context, 0));
    const comment = try s.get(hljs, "COMMENT");
    const options = try s.object();
    try s.put(options, "relevance", b.c.JS_NewInt32(e.context, 0));
    const contains = try b.list(&s, &.{ string, try s.call(comment, hljs, &.{ try s.text("#"), try s.text("$"), options }) });
    const keyword = try b.mode(&s, "keyword");
    const variants = try s.array();
    inline for (.{ "\\s*\\.end\\s[a-zA-Z0-9]*", "^[ ]*\\.[a-zA-Z]*", "\\s:[a-zA-Z_0-9]*" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        if (index > 0) try s.put(variant, "relevance", b.c.JS_NewInt32(e.context, 0));
        try s.index(variants, index, variant);
    }
    const modifier = try s.object();
    try s.put(modifier, "begin", try joined(&s, "\\s(", keywords, ")"));
    try s.index(variants, 3, modifier);
    try s.put(keyword, "variants", variants);
    try s.index(contains, 2, keyword);
    const builtin = try b.mode(&s, "built_in");
    const plain = try s.object();
    try s.put(plain, "begin", try joined(&s, "\\s(", low, ")\\s"));
    const suffixed = try s.object();
    try s.put(suffixed, "begin", try joined(&s, "\\s(", low, ")((-|/)[a-zA-Z0-9]+)+\\s"));
    try s.put(suffixed, "relevance", b.c.JS_NewInt32(e.context, 10));
    const important = try s.object();
    try s.put(important, "begin", try joined(&s, "\\s(", high, ")((-|/)[a-zA-Z0-9]+)*\\s"));
    try s.put(important, "relevance", b.c.JS_NewInt32(e.context, 10));
    try s.put(builtin, "variants", try b.list(&s, &.{ plain, suffixed, important }));
    try s.index(contains, 3, builtin);
    const class = try b.mode(&s, "class");
    try s.put(class, "begin", try s.text("L[^(;:\n]*;"));
    try s.put(class, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(contains, 4, class);
    const register = try s.object();
    try s.put(register, "begin", try s.text("[vp][0-9]+"));
    try s.index(contains, 5, register);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
