//! Actual highlight.js10.7.3 Flix factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "flix", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const char = try b.mode(&s, "string");
    try s.put(char, "begin", try b.rx(&s, "'(.|\\\\[xXuU][a-zA-Z0-9]+)'"));
    const string = try b.mode(&s, "string");
    const quoted = try s.object();
    try s.put(quoted, "begin", try s.text("\""));
    try s.put(quoted, "end", try s.text("\""));
    try s.put(string, "variants", try b.list(&s, &.{quoted}));
    const name = try b.mode(&s, "title");
    try s.put(name, "relevance", b.c.JS_NewInt32(engine.context, 0));
    try s.put(name, "begin", try b.rx(&s, "[^0-9\\n\\t \"'(),.`{}\\[\\]:;][^\\n\\t \"'(),.`{}\\[\\]:;]+|[^0-9\\n\\t \"'(),.`{}\\[\\]:;=]"));
    const method = try b.mode(&s, "function");
    try s.put(method, "beginKeywords", try s.text("def"));
    try s.put(method, "end", try b.rx(&s, "[:={\\[(\\n;]"));
    try s.put(method, "excludeEnd", b.boolean(&s, true));
    try s.put(method, "contains", try b.list(&s, &.{name}));
    const language = try s.object();
    try s.put(language, "name", try s.text("Flix"));
    const keywords = try s.object();
    try s.put(keywords, "literal", try s.text("true false"));
    try s.put(keywords, "keyword", try s.text("case class def else enum if impl import in lat rel index let match namespace switch type yield with"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try b.list(&s, &.{ try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE"), char, string, method, try s.get(hljs, "C_NUMBER_MODE") }));
    return b.c.JS_DupValue(engine.context, language);
}
