//! Actual canonical highlight.js 10.7.3 plaintext factory, not a fallback alias.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "plaintext", build);
}
pub fn build(e: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const l = try s.object();
    try s.put(l, "name", try s.text("Plain text"));
    try s.put(l, "aliases", try b.list(&s, &.{ try s.text("text"), try s.text("txt") }));
    try s.put(l, "disableAutodetect", b.boolean(&s, true));
    return b.c.JS_DupValue(e.context, l);
}
