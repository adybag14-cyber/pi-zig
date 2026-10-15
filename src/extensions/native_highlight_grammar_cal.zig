//! Actual highlight.js10.7.3 C/AL factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "cal", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const words = "div mod in and or not xor asserterror begin case do downto else end exit for if of repeat then to until while with var";
    const comments = try b.list(&s, &.{try s.get(hljs, "C_LINE_COMMENT_MODE")});
    inline for (.{ .{ "\\{", "\\}", 0 }, .{ "\\(\\*", "\\*\\)", 10 } }, 0..) |entry, index| {
        const comment = try s.get(hljs, "COMMENT");
        const begin = try b.rx(&s, entry[0]);
        const end = try b.rx(&s, entry[1]);
        const options = try s.object();
        try s.put(options, "relevance", b.c.JS_NewInt32(e.context, entry[2]));
        try s.index(comments, @intCast(index + 1), try s.call(comment, hljs, &.{ begin, end, options }));
    }
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try b.rx(&s, "'"));
    try s.put(string, "end", try b.rx(&s, "'"));
    const escape = try s.object();
    try s.put(escape, "begin", try b.rx(&s, "''"));
    try s.put(string, "contains", try b.list(&s, &.{escape}));
    const char = try b.mode(&s, "string");
    try s.put(char, "begin", try b.rx(&s, "(#\\d+)+"));
    const date = try b.mode(&s, "number");
    try s.put(date, "begin", try s.text("\\b\\d+(\\.\\d+)?(DT|D|T)"));
    try s.put(date, "relevance", b.c.JS_NewInt32(e.context, 0));
    const quoted = try b.mode(&s, "string");
    try s.put(quoted, "begin", try s.text("\""));
    try s.put(quoted, "end", try s.text("\""));
    const procedure = try b.mode(&s, "function");
    try s.put(procedure, "beginKeywords", try s.text("procedure"));
    try s.put(procedure, "end", try b.rx(&s, "[:;]"));
    try s.put(procedure, "keywords", try s.text("procedure|10"));
    const procedure_contains = try b.list(&s, &.{try s.get(hljs, "TITLE_MODE")});
    const params = try b.mode(&s, "params");
    try s.put(params, "begin", try b.rx(&s, "\\("));
    try s.put(params, "end", try b.rx(&s, "\\)"));
    try s.put(params, "keywords", try s.text(words));
    try s.put(params, "contains", try b.list(&s, &.{ string, char }));
    try s.index(procedure_contains, 1, params);
    try s.put(procedure, "contains", try s.invoke(procedure_contains, "concat", &.{comments}));
    const object = try b.mode(&s, "class");
    try s.put(object, "begin", try s.text("OBJECT (Table|Form|Report|Dataport|Codeunit|XMLport|MenuSuite|Page|Query) (\\d+) ([^\\r\\n]+)"));
    try s.put(object, "returnBegin", b.boolean(&s, true));
    try s.put(object, "contains", try b.list(&s, &.{ try s.get(hljs, "TITLE_MODE"), procedure }));
    const language = try s.object();
    try s.put(language, "name", try s.text("C/AL"));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text(words));
    try s.put(keywords, "literal", try s.text("false true"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "illegal", try b.rx(&s, "\\/\\*"));
    try s.put(language, "contains", try b.list(&s, &.{ string, char, date, quoted, try s.get(hljs, "NUMBER_MODE"), object, procedure }));
    return b.c.JS_DupValue(e.context, language);
}
