//! Actual highlight.js10.7.3 Pony factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "pony", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("actor addressof and as be break class compile_error compile_intrinsic consume continue delegate digestof do else elseif embed end error for fun if ifdef in interface is isnt lambda let match new not object or primitive recover repeat return struct then trait try type until use var where while with xor"));
    try s.put(keywords, "meta", try s.text("iso val tag trn box ref"));
    try s.put(keywords, "literal", try s.text("this false true"));
    const triple = try b.mode(&s, "string");
    try s.put(triple, "begin", try s.text("\"\"\""));
    try s.put(triple, "end", try s.text("\"\"\""));
    try s.put(triple, "relevance", b.c.JS_NewInt32(e.context, 10));
    const quoted = try b.mode(&s, "string");
    try s.put(quoted, "begin", try s.text("\""));
    try s.put(quoted, "end", try s.text("\""));
    try s.put(quoted, "contains", try b.list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    const char = try b.mode(&s, "string");
    try s.put(char, "begin", try s.text("'"));
    try s.put(char, "end", try s.text("'"));
    try s.put(char, "contains", try b.list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    try s.put(char, "relevance", b.c.JS_NewInt32(e.context, 0));
    const type_name = try b.mode(&s, "type");
    try s.put(type_name, "begin", try s.text("\\b_?[A-Z][\\w]*"));
    try s.put(type_name, "relevance", b.c.JS_NewInt32(e.context, 0));
    const primed = try s.object();
    try s.put(primed, "begin", try s.concat(try s.get(hljs, "IDENT_RE"), try s.text("'")));
    try s.put(primed, "relevance", b.c.JS_NewInt32(e.context, 0));
    const number = try b.mode(&s, "number");
    try s.put(number, "begin", try s.text("(-?)(\\b0[xX][a-fA-F0-9]+|\\b0[bB][01]+|(\\b\\d+(_\\d+)?(\\.\\d*)?|\\.\\d+)([eE][-+]?\\d+)?)"));
    try s.put(number, "relevance", b.c.JS_NewInt32(e.context, 0));
    const language = try s.object();
    try s.put(language, "name", try s.text("Pony"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try b.list(&s, &.{ type_name, triple, quoted, char, primed, number, try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE") }));
    return b.c.JS_DupValue(e.context, language);
}
