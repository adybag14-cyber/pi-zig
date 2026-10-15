//! Actual highlight.js10.7.3 LDIF factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "ldif", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("LDIF"));
    const contains = try s.array();
    inline for (.{ "^dn", "^\\w" }, 0..) |pattern, index| {
        const attribute = try b.mode(&s, "attribute");
        try s.put(attribute, "begin", try s.text(pattern));
        try s.put(attribute, "end", try s.text(": "));
        try s.put(attribute, "excludeEnd", b.boolean(&s, true));
        const starts = try s.object();
        try s.put(starts, "end", try s.text("$"));
        try s.put(starts, "relevance", b.c.JS_NewInt32(engine.context, 0));
        try s.put(attribute, "starts", starts);
        if (index == 0) try s.put(attribute, "relevance", b.c.JS_NewInt32(engine.context, 10));
        try s.index(contains, index, attribute);
    }
    const literal = try b.mode(&s, "literal");
    try s.put(literal, "begin", try s.text("^-"));
    try s.put(literal, "end", try s.text("$"));
    try s.index(contains, 2, literal);
    try s.index(contains, 3, try s.get(hljs, "HASH_COMMENT_MODE"));
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(engine.context, language);
}
