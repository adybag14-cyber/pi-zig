//! Actual highlight.js10.7.3 static keyword inputs; factory body follows.
const source_keyword = "after append apply array auto_execok auto_import auto_load auto_mkindex auto_mkindex_old auto_qualify auto_reset bgerror binary break catch cd chan clock close concat continue dde dict encoding eof error eval exec exit expr fblocked fconfigure fcopy file fileevent filename flush for foreach format gets glob global history http if incr info interp join lappend|10 lassign|10 lindex|10 linsert|10 list llength|10 load lrange|10 lrepeat|10 lreplace|10 lreverse|10 lsearch|10 lset|10 lsort|10 mathfunc mathop memory msgcat namespace open package parray pid pkg::create pkg_mkIndex platform platform::shell proc puts pwd read refchan regexp registry regsub|10 rename return safe scan seek set socket source split string subst switch tcl_endOfWord tcl_findLibrary tcl_startOfNextWord tcl_startOfPreviousWord tcl_wordBreakAfter tcl_wordBreakBefore tcltest tclvars tell time tm trace unknown unload unset update uplevel upvar variable vwait while";
const b = @import("native_highlight_lazy_batch3_values.zig");
const re = @import("native_highlight_regex.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "tcl", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const ident = try b.rx(&s, "[a-zA-Z_][a-zA-Z0-9_]*");
    const num = try b.mode(&s, "number");
    try s.put(num, "variants", try b.list(&s, &.{ try s.get(h, "BINARY_NUMBER_MODE"), try s.get(h, "C_NUMBER_MODE") }));
    const l = try s.object();
    try s.put(l, "name", try s.text("Tcl"));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("tk")}));
    try s.put(l, "keywords", try s.text(source_keyword));
    const a = try s.array();
    for ([_][]const u8{ ";[ \\t]*#", "^[ \\t]*#" }, 0..) |p, i| {
        const f = try s.get(h, "COMMENT");
        const cb = try s.text(p);
        const ce = try s.text("$");
        try s.index(a, @intCast(i), try s.call(f, h, &.{ cb, ce }));
    }
    const proc = try s.object();
    try s.put(proc, "beginKeywords", try s.text("proc"));
    try s.put(proc, "end", try s.text("[\\{]"));
    try s.put(proc, "excludeEnd", b.boolean(&s, true));
    const title = try b.mode(&s, "title");
    try s.put(title, "begin", try s.text("[ \\t\\n\\r]+(::)?[a-zA-Z_]((::)?[a-zA-Z0-9_])*"));
    try s.put(title, "end", try s.text("[ \\t\\n\\r]"));
    try s.put(title, "endsWithParent", b.boolean(&s, true));
    try s.put(title, "excludeEnd", b.boolean(&s, true));
    try s.put(proc, "contains", try b.list(&s, &.{title}));
    try s.index(a, 2, proc);
    const variable = try b.mode(&s, "variable");
    const v1 = try s.object();
    const dollar = try b.rx(&s, "\\$");
    const colon = try b.rx(&s, "::");
    const optional = try s.own(try re.concat(e, try b.list(&s, &.{ try s.text("("), colon, try s.text(")?") })));
    try s.put(v1, "begin", try s.own(try re.concat(e, try b.list(&s, &.{ dollar, optional, ident, try s.text("(::"), ident, try s.text(")*") }))));
    const v2 = try s.object();
    try s.put(v2, "begin", try s.text("\\$\\{(::)?[a-zA-Z_]((::)?[a-zA-Z0-9_])*"));
    try s.put(v2, "end", try s.text("\\}"));
    try s.put(v2, "contains", try b.list(&s, &.{num}));
    try s.put(variable, "variants", try b.list(&s, &.{ v1, v2 }));
    try s.index(a, 3, variable);
    const str = try b.mode(&s, "string");
    try s.put(str, "contains", try b.list(&s, &.{try s.get(h, "BACKSLASH_ESCAPE")}));
    const inherit = try s.get(h, "inherit");
    const quote = try s.get(h, "QUOTE_STRING_MODE");
    const opt = try s.object();
    try s.put(opt, "illegal", b.c.pi_js_null());
    try s.put(str, "variants", try b.list(&s, &.{try s.call(inherit, h, &.{ quote, opt })}));
    try s.index(a, 4, str);
    try s.index(a, 5, num);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
