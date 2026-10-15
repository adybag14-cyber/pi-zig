//! Actual highlight.js10.7.3 Nim factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "nim", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Nim"));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("addr and as asm bind block break case cast const continue converter discard distinct div do elif else end enum except export finally for from func generic if import in include interface is isnot iterator let macro method mixin mod nil not notin object of or out proc ptr raise ref return shl shr static template try tuple type using var when while with without xor yield"));
    try s.put(keywords, "literal", try s.text("shared guarded stdin stdout stderr result true false"));
    try s.put(keywords, "built_in", try s.text("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float float32 float64 bool char string cstring pointer expr stmt void auto any range array openarray varargs seq set clong culong cchar cschar cshort cint csize clonglong cfloat cdouble clongdouble cuchar cushort cuint culonglong cstringarray semistatic"));
    try s.put(language, "keywords", keywords);
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try b.rx(&s, "\\{\\."));
    try s.put(meta, "end", try b.rx(&s, "\\.\\}"));
    try s.put(meta, "relevance", b.c.JS_NewInt32(e.context, 10));
    const raw = try b.mode(&s, "string");
    try s.put(raw, "begin", try b.rx(&s, "[a-zA-Z]\\w*\""));
    try s.put(raw, "end", try b.rx(&s, "\""));
    const escape = try s.object();
    try s.put(escape, "begin", try b.rx(&s, "\"\""));
    try s.put(raw, "contains", try b.list(&s, &.{escape}));
    const triple = try b.mode(&s, "string");
    try s.put(triple, "begin", try b.rx(&s, "([a-zA-Z]\\w*)?\"\"\""));
    try s.put(triple, "end", try b.rx(&s, "\"\"\""));
    const contains = try b.list(&s, &.{ meta, raw, triple, try s.get(hljs, "QUOTE_STRING_MODE") });
    const type_name = try b.mode(&s, "type");
    try s.put(type_name, "begin", try b.rx(&s, "\\b[A-Z]\\w+\\b"));
    try s.put(type_name, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(contains, 4, type_name);
    const number = try b.mode(&s, "number");
    try s.put(number, "relevance", b.c.JS_NewInt32(e.context, 0));
    const variants = try s.array();
    inline for (.{ "\\b(0[xX][0-9a-fA-F][_0-9a-fA-F]*)('?[iIuU](8|16|32|64))?", "\\b(0o[0-7][_0-7]*)('?[iIuUfF](8|16|32|64))?", "\\b(0(b|B)[01][_01]*)('?[iIuUfF](8|16|32|64))?", "\\b(\\d[_\\d]*)('?[iIuUfF](8|16|32|64))?" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try b.rx(&s, pattern));
        try s.index(variants, index, variant);
    }
    try s.put(number, "variants", variants);
    try s.index(contains, 5, number);
    try s.index(contains, 6, try s.get(hljs, "HASH_COMMENT_MODE"));
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
