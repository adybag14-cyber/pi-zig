//! Actual highlight.js10.7.3 Tagger Script factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "taggerscript", build);
}
pub fn build(engine: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const comment = try b.mode(&s, "comment");
    try s.put(comment, "begin", try b.rx(&s, "\\$noop\\("));
    try s.put(comment, "end", try b.rx(&s, "\\)"));
    const nested = try s.object();
    try s.put(nested, "begin", try b.rx(&s, "\\("));
    try s.put(nested, "end", try b.rx(&s, "\\)"));
    const nested_escape = try s.object();
    try s.put(nested_escape, "begin", try b.rx(&s, "\\\\."));
    try s.put(nested, "contains", try b.list(&s, &.{ try s.text("self"), nested_escape }));
    try s.put(comment, "contains", try b.list(&s, &.{nested}));
    try s.put(comment, "relevance", b.c.JS_NewInt32(engine.context, 10));
    const function = try b.mode(&s, "keyword");
    try s.put(function, "begin", try b.rx(&s, "\\$(?!noop)[a-zA-Z][_a-zA-Z0-9]*"));
    try s.put(function, "end", try b.rx(&s, "\\("));
    try s.put(function, "excludeEnd", b.boolean(&s, true));
    const variable = try b.mode(&s, "variable");
    try s.put(variable, "begin", try b.rx(&s, "%[_a-zA-Z0-9:]*"));
    try s.put(variable, "end", try s.text("%"));
    const escape = try b.mode(&s, "symbol");
    try s.put(escape, "begin", try b.rx(&s, "\\\\."));
    const language = try s.object();
    try s.put(language, "name", try s.text("Tagger Script"));
    try s.put(language, "contains", try b.list(&s, &.{ comment, function, variable, escape }));
    return b.c.JS_DupValue(engine.context, language);
}
