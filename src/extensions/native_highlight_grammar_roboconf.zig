//! Actual highlight.js10.7.3 Roboconf factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "roboconf", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const ident = "[a-zA-Z-_][^\\n{]+\\{";
    const property = try b.mode(&s, "attribute");
    try s.put(property, "begin", try b.rx(&s, "[a-zA-Z-_]+"));
    try s.put(property, "end", try b.rx(&s, "\\s*:"));
    try s.put(property, "excludeEnd", b.boolean(&s, true));
    const starts = try s.object();
    try s.put(starts, "end", try s.text(";"));
    try s.put(starts, "relevance", b.c.JS_NewInt32(e.context, 0));
    const variable = try b.mode(&s, "variable");
    try s.put(variable, "begin", try b.rx(&s, "\\.[a-zA-Z-_]+"));
    const optional = try b.mode(&s, "keyword");
    try s.put(optional, "begin", try b.rx(&s, "\\(optional\\)"));
    try s.put(starts, "contains", try b.list(&s, &.{ variable, optional }));
    try s.put(property, "starts", starts);
    const language = try s.object();
    try s.put(language, "name", try s.text("Roboconf"));
    try s.put(language, "aliases", try b.list(&s, &.{ try s.text("graph"), try s.text("instances") }));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    try s.put(language, "keywords", try s.text("import"));
    const facet = try s.object();
    try s.put(facet, "begin", try s.text("^facet " ++ ident));
    try s.put(facet, "end", try b.rx(&s, "\\}"));
    try s.put(facet, "keywords", try s.text("facet"));
    try s.put(facet, "contains", try b.list(&s, &.{ property, try s.get(hljs, "HASH_COMMENT_MODE") }));
    const instance = try s.object();
    try s.put(instance, "begin", try s.text("^\\s*instance of " ++ ident));
    try s.put(instance, "end", try b.rx(&s, "\\}"));
    try s.put(instance, "keywords", try s.text("name count channels instance-data instance-state instance of"));
    try s.put(instance, "illegal", try b.rx(&s, "\\S"));
    try s.put(instance, "contains", try b.list(&s, &.{ try s.text("self"), property, try s.get(hljs, "HASH_COMMENT_MODE") }));
    const component = try s.object();
    try s.put(component, "begin", try s.text("^" ++ ident));
    try s.put(component, "end", try b.rx(&s, "\\}"));
    try s.put(component, "contains", try b.list(&s, &.{ property, try s.get(hljs, "HASH_COMMENT_MODE") }));
    try s.put(language, "contains", try b.list(&s, &.{ facet, instance, component, try s.get(hljs, "HASH_COMMENT_MODE") }));
    return b.c.JS_DupValue(e.context, language);
}
