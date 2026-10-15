//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "cos", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const str = try b.mode(&s, "string");
    const sm = try s.object();
    try s.put(sm, "begin", try s.text("\""));
    try s.put(sm, "end", try s.text("\""));
    const escape = try s.object();
    try s.put(escape, "begin", try s.text("\"\""));
    try s.put(escape, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(sm, "contains", try b.list(&s, &.{escape}));
    try s.put(str, "variants", try b.list(&s, &.{sm}));
    const num = try b.mode(&s, "number");
    try s.put(num, "begin", try s.text("\\b(\\d+(\\.\\d*)?|\\.\\d+)"));
    try s.put(num, "relevance", b.c.JS_NewInt32(e.context, 0));
    const l = try s.object();
    try s.put(l, "name", try s.text("Caché Object Script"));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("cls")}));
    try s.put(l, "keywords", try s.text(source_text));
    const a = try b.list(&s, &.{ num, str, try s.get(h, "C_LINE_COMMENT_MODE"), try s.get(h, "C_BLOCK_COMMENT_MODE") });
    const comment = try b.mode(&s, "comment");
    try s.put(comment, "begin", try b.rx(&s, ";"));
    try s.put(comment, "end", try s.text("$"));
    try s.put(comment, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 4, comment);
    for ([_][2][]const u8{ .{ "built_in", "(?:\\$\\$?|\\.\\.)\\^?[a-zA-Z]+" }, .{ "built_in", "\\$\\$\\$[a-zA-Z]+" }, .{ "built_in", "%[a-z]+(?:\\.[a-z]+)*" }, .{ "symbol", "\\^%?[a-zA-Z][\\w]*" }, .{ "keyword", "##class|##super|#define|#dim" } }, 5..) |p, i| {
        const m = try b.mode(&s, p[0]);
        try s.put(m, "begin", try b.rx(&s, p[1]));
        try s.index(a, @intCast(i), m);
    }
    for ([_][3][]const u8{ .{ "&sql\\(", "\\)", "sql" }, .{ "&(js|jscript|javascript)<", ">", "javascript" }, .{ "&html<\\s*<", ">\\s*>", "xml" } }, 10..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try b.rx(&s, p[0]));
        try s.put(m, "end", try b.rx(&s, p[1]));
        if (i != 12) {
            try s.put(m, "excludeBegin", b.boolean(&s, true));
            try s.put(m, "excludeEnd", b.boolean(&s, true));
        }
        try s.put(m, "subLanguage", try s.text(p[2]));
        try s.index(a, @intCast(i), m);
    }
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_text = "property parameter class classmethod clientmethod extends as break catch close continue do d|0 else elseif for goto halt hang h|0 if job j|0 kill k|0 lock l|0 merge new open quit q|0 read r|0 return set s|0 tcommit throw trollback try tstart use view while write w|0 xecute x|0 zkill znspace zn ztrap zwrite zw zzdump zzwrite print zbreak zinsert zload zprint zremove zsave zzprint mv mvcall mvcrt mvdim mvprint zquit zsync ascii";
