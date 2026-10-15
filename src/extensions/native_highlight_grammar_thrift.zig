//! Actual highlight.js10.7.3 Thrift factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "thrift", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const types = "bool byte i16 i32 i64 double string binary";
    const language = try s.object();
    try s.put(language, "name", try s.text("Thrift"));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("namespace const typedef struct enum service exception void oneway set list map required optional"));
    try s.put(keywords, "built_in", try s.text(types));
    try s.put(keywords, "literal", try s.text("true false"));
    try s.put(language, "keywords", keywords);
    const contains = try b.list(&s, &.{ try s.get(hljs, "QUOTE_STRING_MODE"), try s.get(hljs, "NUMBER_MODE"), try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE") });
    const class = try b.mode(&s, "class");
    try s.put(class, "beginKeywords", try s.text("struct enum service exception"));
    try s.put(class, "end", try b.rx(&s, "\\{"));
    try s.put(class, "illegal", try b.rx(&s, "\\n"));
    const inherit = try s.get(hljs, "inherit");
    const title = try s.get(hljs, "TITLE_MODE");
    const changes = try s.object();
    const starts = try s.object();
    try s.put(starts, "endsWithParent", b.boolean(&s, true));
    try s.put(starts, "excludeEnd", b.boolean(&s, true));
    try s.put(changes, "starts", starts);
    try s.put(class, "contains", try b.list(&s, &.{try s.call(inherit, hljs, &.{ title, changes })}));
    try s.index(contains, 4, class);
    const collection = try s.object();
    try s.put(collection, "begin", try s.text("\\b(set|list|map)\\s*<"));
    try s.put(collection, "end", try s.text(">"));
    try s.put(collection, "keywords", try s.text(types));
    try s.put(collection, "contains", try b.list(&s, &.{try s.text("self")}));
    try s.index(contains, 5, collection);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(engine.context, language);
}
