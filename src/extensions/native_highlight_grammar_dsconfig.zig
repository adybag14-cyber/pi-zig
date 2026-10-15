//! Actual highlight.js10.7.3 dsconfig factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "dsconfig", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const quoted = try b.mode(&s, "string");
    try s.put(quoted, "begin", try b.rx(&s, "\""));
    try s.put(quoted, "end", try b.rx(&s, "\""));
    const apos = try b.mode(&s, "string");
    try s.put(apos, "begin", try b.rx(&s, "'"));
    try s.put(apos, "end", try b.rx(&s, "'"));
    const unquoted = try b.mode(&s, "string");
    try s.put(unquoted, "begin", try b.rx(&s, "[\\w\\-?]+:\\w+"));
    try s.put(unquoted, "end", try b.rx(&s, "\\W"));
    try s.put(unquoted, "relevance", b.c.JS_NewInt32(engine.context, 0));
    const valueless = try b.mode(&s, "string");
    try s.put(valueless, "begin", try b.rx(&s, "\\w+(\\-\\w+)*"));
    try s.put(valueless, "end", try b.rx(&s, "(?=\\W)"));
    try s.put(valueless, "relevance", b.c.JS_NewInt32(engine.context, 0));
    const language = try s.object();
    // Source intentionally omits name; registerLanguage supplies its canonical key.
    try s.put(language, "keywords", try s.text("dsconfig"));
    const command = try b.mode(&s, "keyword");
    try s.put(command, "begin", try s.text("^dsconfig"));
    try s.put(command, "end", try b.rx(&s, "\\s"));
    try s.put(command, "excludeEnd", b.boolean(&s, true));
    try s.put(command, "relevance", b.c.JS_NewInt32(engine.context, 10));
    const operation = try b.mode(&s, "built_in");
    try s.put(operation, "begin", try b.rx(&s, "(list|create|get|set|delete)-(\\w+)"));
    try s.put(operation, "end", try b.rx(&s, "\\s"));
    try s.put(operation, "excludeEnd", b.boolean(&s, true));
    try s.put(operation, "illegal", try s.text("!@#$%^&*()"));
    try s.put(operation, "relevance", b.c.JS_NewInt32(engine.context, 10));
    const flag = try b.mode(&s, "built_in");
    try s.put(flag, "begin", try b.rx(&s, "--(\\w+)"));
    try s.put(flag, "end", try b.rx(&s, "\\s"));
    try s.put(flag, "excludeEnd", b.boolean(&s, true));
    try s.put(language, "contains", try b.list(&s, &.{ command, operation, flag, quoted, apos, unquoted, valueless, try s.get(hljs, "HASH_COMMENT_MODE") }));
    return b.c.JS_DupValue(engine.context, language);
}
