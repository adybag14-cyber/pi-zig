//! Actual highlight.js10.7.3 Python REPL factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "pythonRepl", build);
}
pub fn build(e: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("pycon")}));
    const meta = try b.mode(&s, "meta");
    const separator = try s.object();
    try s.put(separator, "end", try b.rx(&s, " |$"));
    const code = try s.object();
    try s.put(code, "end", try s.text("$"));
    try s.put(code, "subLanguage", try s.text("python"));
    try s.put(separator, "starts", code);
    try s.put(meta, "starts", separator);
    const first = try s.object();
    try s.put(first, "begin", try b.rx(&s, "^>>>(?=[ ]|$)"));
    const continued = try s.object();
    try s.put(continued, "begin", try b.rx(&s, "^\\.\\.\\.(?=[ ]|$)"));
    try s.put(meta, "variants", try b.list(&s, &.{ first, continued }));
    try s.put(language, "contains", try b.list(&s, &.{meta}));
    return b.c.JS_DupValue(e.context, language);
}
