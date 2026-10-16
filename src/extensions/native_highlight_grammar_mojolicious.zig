//! Actual highlight.js10.7.3 Mojolicious factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "mojolicious", build);
}
pub fn build(e: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Mojolicious"));
    try s.put(language, "subLanguage", try s.text("xml"));
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("^__(END|DATA)__$"));
    const line = try s.object();
    try s.put(line, "begin", try s.text("^\\s*%{1,2}={0,2}"));
    try s.put(line, "end", try s.text("$"));
    try s.put(line, "subLanguage", try s.text("perl"));
    const block = try s.object();
    try s.put(block, "begin", try s.text("<%{1,2}={0,2}"));
    try s.put(block, "end", try s.text("={0,1}%>"));
    try s.put(block, "subLanguage", try s.text("perl"));
    try s.put(block, "excludeBegin", b.boolean(&s, true));
    try s.put(block, "excludeEnd", b.boolean(&s, true));
    try s.put(language, "contains", try b.list(&s, &.{ meta, line, block }));
    return b.c.JS_DupValue(e.context, language);
}
