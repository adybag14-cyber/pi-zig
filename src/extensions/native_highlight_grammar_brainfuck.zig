//! Actual highlight.js10.7.3 Brainfuck factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "brainfuck", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const literal = try b.mode(&s, "literal");
    try s.put(literal, "begin", try b.rx(&s, "[+-]"));
    try s.put(literal, "relevance", b.c.JS_NewInt32(e.context, 0));
    const language = try s.object();
    try s.put(language, "name", try s.text("Brainfuck"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("bf")}));
    const comment_function = try s.get(hljs, "COMMENT");
    const comment_begin = try s.text("[^\\[\\]\\.,\\+\\-<> \r\n]");
    const comment_end = try s.text("[\\[\\]\\.,\\+\\-<> \r\n]");
    const changes = try s.object();
    try s.put(changes, "returnEnd", b.boolean(&s, true));
    try s.put(changes, "relevance", b.c.JS_NewInt32(e.context, 0));
    const comment = try s.call(comment_function, hljs, &.{ comment_begin, comment_end, changes });
    const title = try b.mode(&s, "title");
    try s.put(title, "begin", try s.text("[\\[\\]]"));
    try s.put(title, "relevance", b.c.JS_NewInt32(e.context, 0));
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try s.text("[\\.,]"));
    try s.put(string, "relevance", b.c.JS_NewInt32(e.context, 0));
    const booster = try s.object();
    try s.put(booster, "begin", try b.rx(&s, "(?:\\+\\+|--)"));
    try s.put(booster, "contains", try b.list(&s, &.{literal}));
    try s.put(language, "contains", try b.list(&s, &.{ comment, title, string, booster, literal }));
    return b.c.JS_DupValue(e.context, language);
}
