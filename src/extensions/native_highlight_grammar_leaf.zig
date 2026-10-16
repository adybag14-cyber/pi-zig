//! Actual highlight.js10.7.3 Leaf factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "leaf", build);
}
pub fn build(engine: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Leaf"));
    const function = try b.mode(&s, "function");
    try s.put(function, "begin", try s.text("#+[A-Za-z_0-9]*\\("));
    try s.put(function, "end", try b.rx(&s, " \\{"));
    try s.put(function, "returnBegin", b.boolean(&s, true));
    try s.put(function, "excludeEnd", b.boolean(&s, true));
    const keyword = try b.mode(&s, "keyword");
    try s.put(keyword, "begin", try s.text("#+"));
    const title = try b.mode(&s, "title");
    try s.put(title, "begin", try s.text("[A-Za-z_][A-Za-z_0-9]*"));
    const params = try b.mode(&s, "params");
    try s.put(params, "begin", try s.text("\\("));
    try s.put(params, "end", try s.text("\\)"));
    try s.put(params, "endsParent", b.boolean(&s, true));
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try s.text("\""));
    try s.put(string, "end", try s.text("\""));
    const variable = try b.mode(&s, "variable");
    try s.put(variable, "begin", try s.text("[A-Za-z_][A-Za-z_0-9]*"));
    try s.put(params, "contains", try b.list(&s, &.{ string, variable }));
    try s.put(function, "contains", try b.list(&s, &.{ keyword, title, params }));
    try s.put(language, "contains", try b.list(&s, &.{function}));
    return b.c.JS_DupValue(engine.context, language);
}
