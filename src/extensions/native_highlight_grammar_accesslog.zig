//! Actual highlight.js10.7.3 Apache access-log factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
const js = @import("native_js_values.zig");
extern "c" fn JS_GetIteratorSymbol(context: ?*b.c.JSContext) b.c.JSValue;
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "accesslog", build);
}
pub fn build(e: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const verbs = try s.array();
    inline for (.{ "GET", "POST", "HEAD", "PUT", "DELETE", "CONNECT", "OPTIONS", "PATCH", "TRACE" }, 0..) |name, index| try s.index(verbs, index, try s.text(name));
    const language = try s.object();
    try s.put(language, "name", try s.text("Apache Access Log"));
    const ip = try b.mode(&s, "number");
    try s.put(ip, "begin", try b.rx(&s, "^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}(:\\d{1,5})?\\b"));
    try s.put(ip, "relevance", b.c.JS_NewInt32(e.context, 5));
    const number = try b.mode(&s, "number");
    try s.put(number, "begin", try b.rx(&s, "\\b\\d+\\b"));
    try s.put(number, "relevance", b.c.JS_NewInt32(e.context, 0));
    const request = try b.mode(&s, "string");
    const quote = try b.rx(&s, "\"");
    const rest = try s.array();
    const symbol = try s.own(try e.checked(JS_GetIteratorSymbol(e.context)));
    var iterator = try js.Iterator.init(e, verbs, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: u32 = 0;
    while (try iterator.next()) |value| {
        defer e.freeValue(value);
        try s.index(rest, index, value);
        index += 1;
    }
    const alternatives = try s.own(try @import("native_highlight_regex.zig").either(e, rest));
    try s.put(request, "begin", try s.own(try @import("native_highlight_regex.zig").concat(e, try b.list(&s, &.{ quote, alternatives }))));
    try s.put(request, "end", try b.rx(&s, "\""));
    try s.put(request, "keywords", verbs);
    try s.put(request, "illegal", try b.rx(&s, "\\n"));
    try s.put(request, "relevance", b.c.JS_NewInt32(e.context, 5));
    const protocol = try s.object();
    try s.put(protocol, "begin", try b.rx(&s, "HTTP\\/[12]\\.\\d'"));
    try s.put(protocol, "relevance", b.c.JS_NewInt32(e.context, 5));
    try s.put(request, "contains", try b.list(&s, &.{protocol}));
    const date = try b.mode(&s, "string");
    try s.put(date, "begin", try b.rx(&s, "\\[\\d[^\\]\\n]{8,}\\]"));
    try s.put(date, "illegal", try b.rx(&s, "\\n"));
    try s.put(date, "relevance", b.c.JS_NewInt32(e.context, 1));
    const bracket = try b.mode(&s, "string");
    try s.put(bracket, "begin", try b.rx(&s, "\\["));
    try s.put(bracket, "end", try b.rx(&s, "\\]"));
    try s.put(bracket, "illegal", try b.rx(&s, "\\n"));
    try s.put(bracket, "relevance", b.c.JS_NewInt32(e.context, 0));
    const agent = try b.mode(&s, "string");
    try s.put(agent, "begin", try b.rx(&s, "\"Mozilla\\/\\d\\.\\d \\("));
    try s.put(agent, "end", try b.rx(&s, "\""));
    try s.put(agent, "illegal", try b.rx(&s, "\\n"));
    try s.put(agent, "relevance", b.c.JS_NewInt32(e.context, 3));
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try b.rx(&s, "\""));
    try s.put(string, "end", try b.rx(&s, "\""));
    try s.put(string, "illegal", try b.rx(&s, "\\n"));
    try s.put(string, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(language, "contains", try b.list(&s, &.{ ip, number, request, date, bracket, agent, string }));
    return b.c.JS_DupValue(e.context, language);
}
