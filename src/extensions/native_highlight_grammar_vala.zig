//! Actual highlight.js10.7.3 Vala factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "vala", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Vala"));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("char uchar unichar int uint long ulong short ushort int8 int16 int32 int64 uint8 uint16 uint32 uint64 float double bool struct enum string void weak unowned owned async signal static abstract interface override virtual delegate if while do for foreach else switch case break default return try catch public private protected internal using new this get set const stdout stdin stderr var"));
    try s.put(keywords, "built_in", try s.text("DBus GLib CCode Gee Object Gtk Posix"));
    try s.put(keywords, "literal", try s.text("false true null"));
    try s.put(language, "keywords", keywords);
    const class = try b.mode(&s, "class");
    try s.put(class, "beginKeywords", try s.text("class interface namespace"));
    try s.put(class, "end", try b.rx(&s, "\\{"));
    try s.put(class, "excludeEnd", b.boolean(&s, true));
    try s.put(class, "illegal", try s.text("[^,:\\n\\s\\.]"));
    try s.put(class, "contains", try b.list(&s, &.{try s.get(hljs, "UNDERSCORE_TITLE_MODE")}));
    const contains = try b.list(&s, &.{ class, try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE") });
    const triple = try b.mode(&s, "string");
    try s.put(triple, "begin", try s.text("\"\"\""));
    try s.put(triple, "end", try s.text("\"\"\""));
    try s.put(triple, "relevance", b.c.JS_NewInt32(e.context, 5));
    try s.index(contains, 3, triple);
    try s.index(contains, 4, try s.get(hljs, "APOS_STRING_MODE"));
    try s.index(contains, 5, try s.get(hljs, "QUOTE_STRING_MODE"));
    try s.index(contains, 6, try s.get(hljs, "C_NUMBER_MODE"));
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("^#"));
    try s.put(meta, "end", try s.text("$"));
    try s.put(meta, "relevance", b.c.JS_NewInt32(e.context, 2));
    try s.index(contains, 7, meta);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
