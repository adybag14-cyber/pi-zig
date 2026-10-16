//! Actual highlight.js 10.7.3 Julia REPL factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "juliaRepl", build);
}
pub fn build(e: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const l = try s.object();
    try s.put(l, "name", try s.text("Julia REPL"));
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try b.rx(&s, "^julia>"));
    try s.put(meta, "relevance", b.c.JS_NewInt32(e.context, 10));
    const starts = try s.object();
    try s.put(starts, "end", try b.rx(&s, "^(?![ ]{6})"));
    try s.put(starts, "subLanguage", try s.text("julia"));
    try s.put(meta, "starts", starts);
    try s.put(meta, "aliases", try b.list(&s, &.{try s.text("jldoctest")}));
    try s.put(l, "contains", try b.list(&s, &.{meta}));
    return b.c.JS_DupValue(e.context, l);
}
