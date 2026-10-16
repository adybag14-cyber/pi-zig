//! Actual highlight.js 10.7.3 VBScript HTML factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "vbscriptHtml", build);
}
pub fn build(e: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const l = try s.object();
    try s.put(l, "name", try s.text("VBScript in HTML"));
    try s.put(l, "subLanguage", try s.text("xml"));
    const mode = try s.object();
    try s.put(mode, "begin", try s.text("<%"));
    try s.put(mode, "end", try s.text("%>"));
    try s.put(mode, "subLanguage", try s.text("vbscript"));
    try s.put(l, "contains", try b.list(&s, &.{mode}));
    return b.c.JS_DupValue(e.context, l);
}
