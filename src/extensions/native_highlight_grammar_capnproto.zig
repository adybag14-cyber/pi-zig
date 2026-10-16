//! Actual highlight.js10.7.3 Cap'n Proto factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "capnproto", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Cap’n Proto"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("capnp")}));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("struct enum interface union group import using const annotation extends in of on as with from fixed"));
    try s.put(keywords, "built_in", try s.text("Void Bool Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64 Float32 Float64 Text Data AnyPointer AnyStruct Capability List"));
    try s.put(keywords, "literal", try s.text("true false"));
    try s.put(language, "keywords", keywords);
    const contains = try b.list(&s, &.{ try s.get(hljs, "QUOTE_STRING_MODE"), try s.get(hljs, "NUMBER_MODE"), try s.get(hljs, "HASH_COMMENT_MODE") });
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try b.rx(&s, "@0x[\\w\\d]{16};"));
    try s.put(meta, "illegal", try b.rx(&s, "\\n"));
    try s.index(contains, 3, meta);
    const symbol = try b.mode(&s, "symbol");
    try s.put(symbol, "begin", try b.rx(&s, "@\\d+\\b"));
    try s.index(contains, 4, symbol);
    inline for (.{ "struct enum", "interface" }, 0..) |words, index| {
        const class = try b.mode(&s, "class");
        try s.put(class, "beginKeywords", try s.text(words));
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
        try s.index(contains, @intCast(index + 5), class);
    }
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
