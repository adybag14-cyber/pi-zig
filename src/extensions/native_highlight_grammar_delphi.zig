//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "delphi", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const kw = try s.text(source_text);
    const comments = try b.list(&s, &.{try s.get(h, "C_LINE_COMMENT_MODE")});
    for ([_][2][]const u8{ .{ "\\{", "\\}" }, .{ "\\(\\*", "\\*\\)" } }, 1..) |p, i| {
        const f = try s.get(h, "COMMENT");
        const cb = try b.rx(&s, p[0]);
        const ce = try b.rx(&s, p[1]);
        const opt = try s.object();
        try s.put(opt, "relevance", b.c.JS_NewInt32(e.context, if (i == 1) 0 else 10));
        try s.index(comments, @intCast(i), try s.call(f, h, &.{ cb, ce, opt }));
    }
    const directive = try b.mode(&s, "meta");
    const variants = try s.array();
    for ([_][2][]const u8{ .{ "\\{\\$", "\\}" }, .{ "\\(\\*\\$", "\\*\\)" } }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try b.rx(&s, p[0]));
        try s.put(m, "end", try b.rx(&s, p[1]));
        try s.index(variants, @intCast(i), m);
    }
    try s.put(directive, "variants", variants);
    const str = try b.mode(&s, "string");
    try s.put(str, "begin", try b.rx(&s, "'"));
    try s.put(str, "end", try b.rx(&s, "'"));
    const escape = try s.object();
    try s.put(escape, "begin", try b.rx(&s, "''"));
    try s.put(str, "contains", try b.list(&s, &.{escape}));
    const num = try b.mode(&s, "number");
    try s.put(num, "relevance", b.c.JS_NewInt32(e.context, 0));
    const nv = try s.array();
    for ([_][]const u8{ "\\$[0-9A-Fa-f]+", "&[0-7]+", "%[01]+" }, 0..) |p, i| {
        const m = try s.object();
        try s.put(m, "begin", try s.text(p));
        try s.index(nv, @intCast(i), m);
    }
    try s.put(num, "variants", nv);
    const char = try b.mode(&s, "string");
    try s.put(char, "begin", try b.rx(&s, "(#\\d+)+"));
    const cls = try s.object();
    try s.put(cls, "begin", try s.concat(try s.get(h, "IDENT_RE"), try s.text("\\s*=\\s*class\\s*\\(")));
    try s.put(cls, "returnBegin", b.boolean(&s, true));
    try s.put(cls, "contains", try b.list(&s, &.{try s.get(h, "TITLE_MODE")}));
    const fun = try b.mode(&s, "function");
    try s.put(fun, "beginKeywords", try s.text("function constructor destructor procedure"));
    try s.put(fun, "end", try b.rx(&s, "[:;]"));
    try s.put(fun, "keywords", try s.text("function constructor|10 destructor|10 procedure|10"));
    const fc = try b.list(&s, &.{try s.get(h, "TITLE_MODE")});
    const params = try b.mode(&s, "params");
    try s.put(params, "begin", try b.rx(&s, "\\("));
    try s.put(params, "end", try b.rx(&s, "\\)"));
    try s.put(params, "keywords", kw);
    try s.put(params, "contains", try s.invoke(try b.list(&s, &.{ str, char, directive }), "concat", &.{comments}));
    try s.index(fc, 1, params);
    try s.index(fc, 2, directive);
    try s.put(fun, "contains", try s.invoke(fc, "concat", &.{comments}));
    const l = try s.object();
    try s.put(l, "name", try s.text("Delphi"));
    const aliases = try s.array();
    for ([_][]const u8{ "dpr", "dfm", "pas", "pascal", "freepascal", "lazarus", "lpr", "lfm" }, 0..) |p, i| try s.index(aliases, @intCast(i), try s.text(p));
    try s.put(l, "aliases", aliases);
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    try s.put(l, "keywords", kw);
    try s.put(l, "illegal", try b.rx(&s, "\"|\\$[G-Zg-z]|/\\*|</|\\|"));
    try s.put(l, "contains", try s.invoke(try b.list(&s, &.{ str, char, try s.get(h, "NUMBER_MODE"), num, cls, fun, directive }), "concat", &.{comments}));
    return b.c.JS_DupValue(e.context, l);
}
const source_text = "exports register file shl array record property for mod while set ally label uses raise not stored class safecall var interface or private static exit index inherited to else stdcall override shr asm far resourcestring finalization packed virtual out and protected library do xorwrite goto near function end div overload object unit begin string on inline repeat until destructor write message program with read initialization except default nil if case cdecl in downto threadvar of try pascal const external constructor type public then implementation finally published procedure absolute reintroduce operator as is abstract alias assembler bitpacked break continue cppdecl cvar enumerator experimental platform deprecated unimplemented dynamic export far16 forward generic helper implements interrupt iochecks local name nodefault noreturn nostackframe oldfpccall otherwise saveregisters softfloat specialize strict unaligned varargs ";
