//! Actual highlight.js10.7.3 Python profiler factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "profile", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Python profiler"));
    const contains = try s.array();
    try s.index(contains, 0, try s.get(hljs, "C_NUMBER_MODE"));
    const filename = try s.object();
    try s.put(filename, "begin", try s.text("[a-zA-Z_][\\da-zA-Z_]+\\.[\\da-zA-Z_]{1,3}"));
    try s.put(filename, "end", try s.text(":"));
    try s.put(filename, "excludeEnd", b.boolean(&s, true));
    try s.index(contains, 1, filename);
    const header = try s.object();
    try s.put(header, "begin", try s.text("(ncalls|tottime|cumtime)"));
    try s.put(header, "end", try s.text("$"));
    try s.put(header, "keywords", try s.text("ncalls tottime|10 cumtime|10 filename"));
    try s.put(header, "relevance", b.c.JS_NewInt32(engine.context, 10));
    try s.index(contains, 2, header);
    const calls = try s.object();
    try s.put(calls, "begin", try s.text("function calls"));
    try s.put(calls, "end", try s.text("$"));
    try s.put(calls, "contains", try b.list(&s, &.{try s.get(hljs, "C_NUMBER_MODE")}));
    try s.put(calls, "relevance", b.c.JS_NewInt32(engine.context, 10));
    try s.index(contains, 3, calls);
    try s.index(contains, 4, try s.get(hljs, "APOS_STRING_MODE"));
    try s.index(contains, 5, try s.get(hljs, "QUOTE_STRING_MODE"));
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try s.text("\\("));
    try s.put(string, "end", try s.text("\\)$"));
    try s.put(string, "excludeBegin", b.boolean(&s, true));
    try s.put(string, "excludeEnd", b.boolean(&s, true));
    try s.put(string, "relevance", b.c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 6, string);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(engine.context, language);
}
