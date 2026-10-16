//! Actual highlight.js10.7.3 Augmented BNF factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "abnf", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const declaration = try b.rx(&s, "^[a-zA-Z][a-zA-Z0-9-]*");
    const illegal = try b.rx(&s, "[!@#$^&',?+~`|:]");
    const keywords = try s.array();
    inline for (.{ "ALPHA", "BIT", "CHAR", "CR", "CRLF", "CTL", "DIGIT", "DQUOTE", "HEXDIG", "HTAB", "LF", "LWSP", "OCTET", "SP", "VCHAR", "WSP" }, 0..) |word, index| try s.index(keywords, index, try s.text(word));
    const comment_function = try s.get(hljs, "COMMENT");
    const comment = try s.call(comment_function, hljs, &.{ try b.rx(&s, ";"), try b.rx(&s, "$") });
    const binary = try b.mode(&s, "symbol");
    try s.put(binary, "begin", try b.rx(&s, "%b[0-1]+(-[0-1]+|(\\.[0-1]+)+){0,1}"));
    const decimal = try b.mode(&s, "symbol");
    try s.put(decimal, "begin", try b.rx(&s, "%d[0-9]+(-[0-9]+|(\\.[0-9]+)+){0,1}"));
    const hex = try b.mode(&s, "symbol");
    try s.put(hex, "begin", try b.rx(&s, "%x[0-9A-F]+(-[0-9A-F]+|(\\.[0-9A-F]+)+){0,1}"));
    const sensitivity = try b.mode(&s, "symbol");
    try s.put(sensitivity, "begin", try b.rx(&s, "%[si]"));
    const rule = try b.mode(&s, "attribute");
    try s.put(rule, "begin", try s.own(try @import("native_highlight_regex.zig").concat(e, try b.list(&s, &.{ declaration, try b.rx(&s, "(?=\\s*=)") }))));
    const language = try s.object();
    try s.put(language, "name", try s.text("Augmented Backus-Naur Form"));
    try s.put(language, "illegal", illegal);
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try b.list(&s, &.{ rule, comment, binary, decimal, hex, sensitivity, try s.get(hljs, "QUOTE_STRING_MODE"), try s.get(hljs, "NUMBER_MODE") }));
    return b.c.JS_DupValue(e.context, language);
}
