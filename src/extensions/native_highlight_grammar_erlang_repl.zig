//! Actual highlight.js 10.7.3 Erlang REPL factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
const re = @import("native_highlight_regex.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "erlangRepl", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const l = try s.object();
    try s.put(l, "name", try s.text("Erlang REPL"));
    const kw = try s.object();
    try s.put(kw, "built_in", try s.text("spawn spawn_link self"));
    try s.put(kw, "keyword", try s.text("after and andalso|10 band begin bnot bor bsl bsr bxor case catch cond div end fun if let not of or orelse|10 query receive rem try when xor"));
    try s.put(l, "keywords", kw);
    const a = try s.array();
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("^[0-9]+> "));
    try s.put(meta, "relevance", b.c.JS_NewInt32(e.context, 10));
    try s.index(a, 0, meta);
    const f = try s.get(h, "COMMENT");
    const cb = try s.text("%");
    const ce = try s.text("$");
    try s.index(a, 1, try s.call(f, h, &.{ cb, ce }));
    const num = try b.mode(&s, "number");
    try s.put(num, "begin", try s.text("\\b(\\d+(_\\d+)*#[a-fA-F0-9]+(_[a-fA-F0-9]+)*|\\d+(_\\d+)*(\\.\\d+(_\\d+)*)?([eE][-+]?\\d+)?)"));
    try s.put(num, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 2, num);
    try s.index(a, 3, try s.get(h, "APOS_STRING_MODE"));
    try s.index(a, 4, try s.get(h, "QUOTE_STRING_MODE"));
    const macro = try s.object();
    const r1 = try b.rx(&s, "\\?(::)?");
    const r2 = try b.rx(&s, "([A-Z]\\w*)");
    const r3 = try b.rx(&s, "((::)[A-Z]\\w*)*");
    try s.put(macro, "begin", try s.own(try re.concat(e, try b.list(&s, &.{ r1, r2, r3 }))));
    try s.index(a, 5, macro);
    for ([_][]const u8{ "->", "ok", "!" }, 6..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p));
        try s.index(a, @intCast(i), m);
    }
    for ([_][]const u8{ "(\\b[a-z'][a-zA-Z0-9_']*:[a-z'][a-zA-Z0-9_']*)|(\\b[a-z'][a-zA-Z0-9_']*)", "[A-Z][a-zA-Z0-9_']*" }, 9..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p));
        try s.put(m, "relevance", b.c.JS_NewInt32(e.context, 0));
        try s.index(a, @intCast(i), m);
    }
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
