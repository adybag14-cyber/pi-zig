//! Actual highlight.js 10.7.3 static keyword inputs; native factory follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
const re = @import("native_highlight_regex.zig");
const js = @import("native_js_values.zig");
extern "c" fn JS_GetIteratorSymbol(context: ?*b.c.JSContext) b.c.JSValue;
fn spread(s: *b.Scope, target: b.c.JSValue, offset: u32, value: b.c.JSValue) !void {
    const symbol = try s.own(try s.engine.checked(JS_GetIteratorSymbol(s.engine.context)));
    var iterator = try js.Iterator.init(s.engine, value, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var i = offset;
    while (try iterator.next()) |v| {
        defer s.engine.freeValue(v);
        try s.index(target, i, v);
        i += 1;
    }
}
fn patterns(s: *b.Scope, values: []const []const u8) !b.c.JSValue {
    const a = try s.array();
    for (values, 0..) |v, i| try s.index(a, @intCast(i), try b.rx(s, v));
    return a;
}
fn alternatives(s: *b.Scope, value: b.c.JSValue) !b.c.JSValue {
    const a = try s.array();
    try spread(s, a, 0, value);
    return s.own(try re.either(s.engine, a));
}
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "applescript", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const inherit = try s.get(h, "inherit");
    const quote = try s.get(h, "QUOTE_STRING_MODE");
    const opt = try s.object();
    try s.put(opt, "illegal", b.c.pi_js_null());
    const str = try s.call(inherit, h, &.{ quote, opt });
    const params = try b.mode(&s, "params");
    try s.put(params, "begin", try b.rx(&s, "\\("));
    try s.put(params, "end", try b.rx(&s, "\\)"));
    try s.put(params, "contains", try b.list(&s, &.{ try s.text("self"), try s.get(h, "C_NUMBER_MODE"), str }));
    const cf1 = try s.get(h, "COMMENT");
    const cb1 = try b.rx(&s, "--");
    const ce1 = try b.rx(&s, "$");
    const c1 = try s.call(cf1, h, &.{ cb1, ce1 });
    const cf2 = try s.get(h, "COMMENT");
    const cb2 = try b.rx(&s, "\\(\\*");
    const ce2 = try b.rx(&s, "\\*\\)");
    const co2 = try s.object();
    try s.put(co2, "contains", try b.list(&s, &.{ try s.text("self"), c1 }));
    const c2 = try s.call(cf2, h, &.{ cb2, ce2, co2 });
    const comments = try b.list(&s, &.{ c1, c2, try s.get(h, "HASH_COMMENT_MODE") });
    const keyword_patterns = try patterns(&s, &.{ "apart from", "aside from", "instead of", "out of", "greater than", "isn't|(doesn't|does not) (equal|come before|come after|contain)", "(greater|less) than( or equal)?", "(starts?|ends|begins?) with", "contained by", "comes (before|after)", "a (ref|reference)", "POSIX (file|path)", "(date|time) string", "quoted form" });
    const builtin_patterns = try patterns(&s, &.{ "clipboard info", "the clipboard", "info for", "list (disks|folder)", "mount volume", "path to", "(close|open for) access", "(get|set) eof", "current date", "do shell script", "get volume settings", "random number", "set volume", "system attribute", "system info", "time to GMT", "(load|run|store) script", "scripting components", "ASCII (character|number)", "localized string", "choose (application|color|file|file name|folder|from list|remote application|URL)", "display (alert|dialog)" });
    const l = try s.object();
    try s.put(l, "name", try s.text("AppleScript"));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("osascript")}));
    const kw = try s.object();
    try s.put(kw, "keyword", try s.text(source_keyword));
    try s.put(kw, "literal", try s.text(source_literal));
    try s.put(kw, "built_in", try s.text(source_built_in));
    try s.put(l, "keywords", kw);
    const a = try b.list(&s, &.{ str, try s.get(h, "C_NUMBER_MODE") });
    const builtin = try b.mode(&s, "built_in");
    const bleft = try b.rx(&s, "\\b");
    const balts = try alternatives(&s, builtin_patterns);
    const bright = try b.rx(&s, "\\b");
    try s.put(builtin, "begin", try s.own(try re.concat(e, try b.list(&s, &.{ bleft, balts, bright }))));
    try s.index(a, 2, builtin);
    const ret = try b.mode(&s, "built_in");
    try s.put(ret, "begin", try b.rx(&s, "^\\s*return\\b"));
    try s.index(a, 3, ret);
    const literal = try b.mode(&s, "literal");
    try s.put(literal, "begin", try b.rx(&s, "\\b(text item delimiters|current application|missing value)\\b"));
    try s.index(a, 4, literal);
    const keyword = try b.mode(&s, "keyword");
    const kleft = try b.rx(&s, "\\b");
    const kalts = try alternatives(&s, keyword_patterns);
    const kright = try b.rx(&s, "\\b");
    try s.put(keyword, "begin", try s.own(try re.concat(e, try b.list(&s, &.{ kleft, kalts, kright }))));
    try s.index(a, 5, keyword);
    const on = try s.object();
    try s.put(on, "beginKeywords", try s.text("on"));
    try s.put(on, "illegal", try b.rx(&s, "[${=;\\n]"));
    try s.put(on, "contains", try b.list(&s, &.{ try s.get(h, "UNDERSCORE_TITLE_MODE"), params }));
    try s.index(a, 6, on);
    try spread(&s, a, 7, comments);
    try s.put(l, "contains", a);
    try s.put(l, "illegal", try b.rx(&s, "//|->|=>|\\[\\["));
    return b.c.JS_DupValue(e.context, l);
}
const source_keyword = "about above after against and around as at back before beginning behind below beneath beside between but by considering contain contains continue copy div does eighth else end equal equals error every exit fifth first for fourth from front get given global if ignoring in into is it its last local me middle mod my ninth not of on onto or over prop property put ref reference repeat returning script second set seventh since sixth some tell tenth that the|0 then third through thru timeout times to transaction try until where while whose with without";
const source_literal = "AppleScript false linefeed return pi quote result space tab true";
const source_built_in = "alias application boolean class constant date file integer list number real record string text activate beep count delay launch log offset read round run say summarize write character characters contents day frontmost id item length month name paragraph paragraphs rest reverse running time version weekday word words year";
