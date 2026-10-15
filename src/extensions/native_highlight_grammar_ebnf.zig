//! Actual highlight.js10.7.3 Extended Backus-Naur Form factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "ebnf", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const comment_function = try s.get(hljs, "COMMENT");
    const comment = try s.call(comment_function, hljs, &.{ try b.rx(&s, "\\(\\*"), try b.rx(&s, "\\*\\)") });
    const non_terminal = try b.mode(&s, "attribute");
    try s.put(non_terminal, "begin", try b.rx(&s, "^[ ]*[a-zA-Z]+([\\s_-]+[a-zA-Z]+)*"));
    const special = try b.mode(&s, "meta");
    try s.put(special, "begin", try b.rx(&s, "\\?.*\\?"));
    const body = try s.object();
    try s.put(body, "begin", try b.rx(&s, "="));
    try s.put(body, "end", try b.rx(&s, "[.;]"));
    const terminals = try b.mode(&s, "string");
    const variants = try s.array();
    try s.index(variants, 0, try s.get(hljs, "APOS_STRING_MODE"));
    try s.index(variants, 1, try s.get(hljs, "QUOTE_STRING_MODE"));
    const backtick = try s.object();
    try s.put(backtick, "begin", try s.text("`"));
    try s.put(backtick, "end", try s.text("`"));
    try s.index(variants, 2, backtick);
    try s.put(terminals, "variants", variants);
    try s.put(body, "contains", try b.list(&s, &.{ comment, special, terminals }));
    const language = try s.object();
    try s.put(language, "name", try s.text("Extended Backus-Naur Form"));
    try s.put(language, "illegal", try b.rx(&s, "\\S"));
    try s.put(language, "contains", try b.list(&s, &.{ comment, non_terminal, body }));
    return b.c.JS_DupValue(engine.context, language);
}
