//! Actual highlight.js10.7.3 FIX factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "fix", build);
}
pub fn build(engine: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("FIX"));
    const field = try s.object();
    try s.put(field, "begin", try b.rx(&s, "[^\\u2401\\u0001]+"));
    try s.put(field, "end", try b.rx(&s, "[\\u2401\\u0001]"));
    try s.put(field, "excludeEnd", b.boolean(&s, true));
    try s.put(field, "returnBegin", b.boolean(&s, true));
    try s.put(field, "returnEnd", b.boolean(&s, false));
    const attribute = try s.object();
    try s.put(attribute, "begin", try b.rx(&s, "([^\\u2401\\u0001=]+)"));
    try s.put(attribute, "end", try b.rx(&s, "=([^\\u2401\\u0001=]+)"));
    try s.put(attribute, "returnEnd", b.boolean(&s, true));
    try s.put(attribute, "returnBegin", b.boolean(&s, false));
    try s.put(attribute, "className", try s.text("attr"));
    const string = try s.object();
    try s.put(string, "begin", try b.rx(&s, "="));
    try s.put(string, "end", try b.rx(&s, "([\\u2401\\u0001])"));
    try s.put(string, "excludeEnd", b.boolean(&s, true));
    try s.put(string, "excludeBegin", b.boolean(&s, true));
    try s.put(string, "className", try s.text("string"));
    try s.put(field, "contains", try b.list(&s, &.{ attribute, string }));
    try s.put(language, "contains", try b.list(&s, &.{field}));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    return b.c.JS_DupValue(engine.context, language);
}
