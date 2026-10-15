//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
const re = @import("native_highlight_regex.zig");
const js = @import("native_js_values.zig");
extern "c" fn JS_GetIteratorSymbol(context: ?*b.c.JSContext) b.c.JSValue;
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "vbscript", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const functions = try s.invoke(try s.text(source_functions), "split", &.{try s.text(" ")});
    const objects = try s.array();
    for ([_][]const u8{ "server", "response", "request", "scriptengine", "scriptenginebuildversion", "scriptengineminorversion", "scriptenginemajorversion" }, 0..) |p, i| try s.index(objects, @intCast(i), try s.text(p));
    const call = try s.object();
    const rest = try s.array();
    const symbol = try s.own(try e.checked(JS_GetIteratorSymbol(e.context)));
    var iterator = try js.Iterator.init(e, functions, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: u32 = 0;
    while (try iterator.next()) |v| {
        defer e.freeValue(v);
        try s.index(rest, index, v);
        index += 1;
    }
    const alternatives = try s.own(try re.either(e, rest));
    try s.put(call, "begin", try s.own(try re.concat(e, try b.list(&s, &.{ alternatives, try s.text("\\s*\\(") }))));
    try s.put(call, "relevance", b.c.JS_NewInt32(e.context, 0));
    const ck = try s.object();
    try s.put(ck, "built_in", functions);
    try s.put(call, "keywords", ck);
    const l = try s.object();
    try s.put(l, "name", try s.text("VBScript"));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("vbs")}));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    const kw = try s.object();
    try s.put(kw, "keyword", try s.text(source_keyword));
    try s.put(kw, "built_in", objects);
    try s.put(kw, "literal", try s.text(source_literal));
    try s.put(l, "keywords", kw);
    try s.put(l, "illegal", try s.text("//"));
    const a = try b.list(&s, &.{call});
    const inherit = try s.get(h, "inherit");
    const quote = try s.get(h, "QUOTE_STRING_MODE");
    const opt = try s.object();
    const escape = try s.object();
    try s.put(escape, "begin", try s.text("\"\""));
    try s.put(opt, "contains", try b.list(&s, &.{escape}));
    try s.index(a, 1, try s.call(inherit, h, &.{ quote, opt }));
    const f = try s.get(h, "COMMENT");
    const cb = try b.rx(&s, "'");
    const ce = try b.rx(&s, "$");
    const co = try s.object();
    try s.put(co, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(a, 2, try s.call(f, h, &.{ cb, ce, co }));
    try s.index(a, 3, try s.get(h, "C_NUMBER_MODE"));
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_keyword = "call class const dim do loop erase execute executeglobal exit for each next function if then else on error option explicit new private property let get public randomize redim rem select case set stop sub while wend with end to elseif is or xor and not class_initialize class_terminate default preserve in me byval byref step resume goto";
const source_literal = "true false null nothing empty";
const source_functions = "lcase month vartype instrrev ubound setlocale getobject rgb getref string weekdayname rnd dateadd monthname now day minute isarray cbool round formatcurrency conversions csng timevalue second year space abs clng timeserial fixs len asc isempty maths dateserial atn timer isobject filter weekday datevalue ccur isdate instr datediff formatdatetime replace isnull right sgn array snumeric log cdbl hex chr lbound msgbox ucase getlocale cos cdate cbyte rtrim join hour oct typename trim strcomp int createobject loadpicture tan formatnumber mid split  cint sin datepart ltrim sqr time derived eval date formatpercent exp inputbox left ascw chrw regexp cstr err";
