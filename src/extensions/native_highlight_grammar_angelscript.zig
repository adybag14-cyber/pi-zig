//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "angelscript", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const builtin = try b.mode(&s, "built_in");
    try s.put(builtin, "begin", try s.text("\\b(void|bool|int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|string|ref|array|double|float|auto|dictionary)"));
    const handle = try b.mode(&s, "symbol");
    try s.put(handle, "begin", try s.text("[a-zA-Z0-9_]+@"));
    const generic = try b.mode(&s, "keyword");
    try s.put(generic, "begin", try s.text("<"));
    try s.put(generic, "end", try s.text(">"));
    try s.put(generic, "contains", try b.list(&s, &.{ builtin, handle }));
    try s.set(builtin, "contains", try b.list(&s, &.{generic}));
    try s.set(handle, "contains", try b.list(&s, &.{generic}));
    const l = try s.object();
    try s.put(l, "name", try s.text("AngelScript"));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("asc")}));
    try s.put(l, "keywords", try s.text(source_text));
    try s.put(l, "illegal", try s.text("(^using\\s+[A-Za-z0-9_\\.]+;$|\\bfunction\\s*[^\\(])"));
    const a = try s.array();
    for ([_][]const u8{ "'", "\"\"\"", "\"" }, 0..) |p, i| {
        const m = try b.mode(&s, "string");
        try s.put(m, "begin", try s.text(p));
        try s.put(m, "end", try s.text(p));
        if (i != 1) {
            try s.put(m, "illegal", try s.text("\\n"));
            try s.put(m, "contains", try b.list(&s, &.{try s.get(h, "BACKSLASH_ESCAPE")}));
            try s.put(m, "relevance", b.c.JS_NewInt32(e.context, 0));
        }
        try s.index(a, @intCast(i), m);
    }
    try s.index(a, 3, try s.get(h, "C_LINE_COMMENT_MODE"));
    try s.index(a, 4, try s.get(h, "C_BLOCK_COMMENT_MODE"));
    const metadata = try b.mode(&s, "string");
    try s.put(metadata, "begin", try s.text("^\\s*\\["));
    try s.put(metadata, "end", try s.text("\\]"));
    try s.index(a, 5, metadata);
    const ns = try s.object();
    try s.put(ns, "beginKeywords", try s.text("interface namespace"));
    try s.put(ns, "end", try b.rx(&s, "\\{"));
    try s.put(ns, "illegal", try s.text("[;.\\-]"));
    const nsname = try b.mode(&s, "symbol");
    try s.put(nsname, "begin", try s.text("[a-zA-Z0-9_]+"));
    try s.put(ns, "contains", try b.list(&s, &.{nsname}));
    try s.index(a, 6, ns);
    const cls = try s.object();
    try s.put(cls, "beginKeywords", try s.text("class"));
    try s.put(cls, "end", try b.rx(&s, "\\{"));
    try s.put(cls, "illegal", try s.text("[;.\\-]"));
    const name = try b.mode(&s, "symbol");
    try s.put(name, "begin", try s.text("[a-zA-Z0-9_]+"));
    const ext = try s.object();
    try s.put(ext, "begin", try s.text("[:,]\\s*"));
    const ename = try b.mode(&s, "symbol");
    try s.put(ename, "begin", try s.text("[a-zA-Z0-9_]+"));
    try s.put(ext, "contains", try b.list(&s, &.{ename}));
    try s.put(name, "contains", try b.list(&s, &.{ext}));
    try s.put(cls, "contains", try b.list(&s, &.{name}));
    try s.index(a, 7, cls);
    try s.index(a, 8, builtin);
    try s.index(a, 9, handle);
    const literal = try b.mode(&s, "literal");
    try s.put(literal, "begin", try s.text("\\b(null|true|false)"));
    try s.index(a, 10, literal);
    const num = try b.mode(&s, "number");
    try s.put(num, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(num, "begin", try s.text("(-?)(\\b0[xXbBoOdD][a-fA-F0-9]+|(\\b\\d+(\\.\\d*)?f?|\\.\\d+f?)([eE][-+]?\\d+f?)?)"));
    try s.index(a, 11, num);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_text = "for in|0 break continue while do|0 return if else case switch namespace is cast or and xor not get|0 in inout|10 out override set|0 private public const default|0 final shared external mixin|10 enum typedef funcdef this super import from interface abstract|0 try catch protected explicit property";
