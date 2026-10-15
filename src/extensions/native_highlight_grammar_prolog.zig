//! Actual highlight.js10.7.3 Prolog factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "prolog", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const atom = try s.object();
    try s.put(atom, "begin", try b.rx(&s, "[a-z][A-Za-z0-9_]*"));
    try s.put(atom, "relevance", b.c.JS_NewInt32(e.context, 0));
    const variable = try b.mode(&s, "symbol");
    const variants = try s.array();
    inline for (.{ "[A-Z][a-zA-Z0-9_]*", "_[A-Za-z0-9_]*" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try b.rx(&s, pattern));
        try s.index(variants, index, variant);
    }
    try s.put(variable, "variants", variants);
    try s.put(variable, "relevance", b.c.JS_NewInt32(e.context, 0));
    const parented = try s.object();
    try s.put(parented, "begin", try b.rx(&s, "\\("));
    try s.put(parented, "end", try b.rx(&s, "\\)"));
    try s.put(parented, "relevance", b.c.JS_NewInt32(e.context, 0));
    const list = try s.object();
    try s.put(list, "begin", try b.rx(&s, "\\["));
    try s.put(list, "end", try b.rx(&s, "\\]"));
    const line = try b.mode(&s, "comment");
    try s.put(line, "begin", try b.rx(&s, "%"));
    try s.put(line, "end", try b.rx(&s, "$"));
    try s.put(line, "contains", try b.list(&s, &.{try s.get(hljs, "PHRASAL_WORDS_MODE")}));
    const backtick = try b.mode(&s, "string");
    try s.put(backtick, "begin", try b.rx(&s, "`"));
    try s.put(backtick, "end", try b.rx(&s, "`"));
    try s.put(backtick, "contains", try b.list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    const char = try b.mode(&s, "string");
    try s.put(char, "begin", try b.rx(&s, "0'(\\\\'|.)"));
    const space = try b.mode(&s, "string");
    try s.put(space, "begin", try b.rx(&s, "0'\\\\s"));
    const pred = try s.object();
    try s.put(pred, "begin", try b.rx(&s, ":-"));
    const inner = try b.list(&s, &.{ atom, variable, parented, pred, list, line, try s.get(hljs, "C_BLOCK_COMMENT_MODE"), try s.get(hljs, "QUOTE_STRING_MODE"), try s.get(hljs, "APOS_STRING_MODE"), backtick, char, space, try s.get(hljs, "C_NUMBER_MODE") });
    try s.set(parented, "contains", inner);
    try s.set(list, "contains", inner);
    const language = try s.object();
    try s.put(language, "name", try s.text("Prolog"));
    const concat = try s.get(inner, "concat");
    const period = try s.object();
    try s.put(period, "begin", try b.rx(&s, "\\.$"));
    try s.put(language, "contains", try s.call(concat, inner, &.{try b.list(&s, &.{period})}));
    return b.c.JS_DupValue(e.context, language);
}
