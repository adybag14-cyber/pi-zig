//! Actual highlight.js10.7.3 Ceylon factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "ceylon", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const keywords = "assembly module package import alias class interface object given value assign void function new of extends satisfies abstracts in out return break continue throw assert dynamic if else switch case for while try catch finally then let this outer super is exists nonempty";
    const modifiers = "shared abstract formal default actual variable late native deprecated final sealed annotation suppressWarnings small";
    const subst = try b.mode(&s, "subst");
    try s.put(subst, "excludeBegin", b.boolean(&s, true));
    try s.put(subst, "excludeEnd", b.boolean(&s, true));
    try s.put(subst, "begin", try b.rx(&s, "``"));
    try s.put(subst, "end", try b.rx(&s, "``"));
    try s.put(subst, "keywords", try s.text(keywords));
    try s.put(subst, "relevance", b.c.JS_NewInt32(e.context, 10));
    const triple = try b.mode(&s, "string");
    try s.put(triple, "begin", try s.text("\"\"\""));
    try s.put(triple, "end", try s.text("\"\"\""));
    try s.put(triple, "relevance", b.c.JS_NewInt32(e.context, 10));
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try s.text("\""));
    try s.put(string, "end", try s.text("\""));
    try s.put(string, "contains", try b.list(&s, &.{subst}));
    const char = try b.mode(&s, "string");
    try s.put(char, "begin", try s.text("'"));
    try s.put(char, "end", try s.text("'"));
    const number = try b.mode(&s, "number");
    try s.put(number, "begin", try s.text("#[0-9a-fA-F_]+|\\$[01_]+|[0-9_]+(?:\\.[0-9_](?:[eE][+-]?\\d+)?)?[kMGTPmunpf]?"));
    try s.put(number, "relevance", b.c.JS_NewInt32(e.context, 0));
    const expressions = try b.list(&s, &.{ triple, string, char, number });
    try s.set(subst, "contains", expressions);
    const language = try s.object();
    try s.put(language, "name", try s.text("Ceylon"));
    const words = try s.object();
    try s.put(words, "keyword", try s.text(keywords ++ " " ++ modifiers));
    try s.put(words, "meta", try s.text("doc by license see throws tagged"));
    try s.put(language, "keywords", words);
    try s.put(language, "illegal", try s.text("\\$[^01]|#[^0-9a-fA-F]"));
    const contains = try b.list(&s, &.{try s.get(hljs, "C_LINE_COMMENT_MODE")});
    const comment_function = try s.get(hljs, "COMMENT");
    const options = try s.object();
    try s.put(options, "contains", try b.list(&s, &.{try s.text("self")}));
    try s.index(contains, 1, try s.call(comment_function, hljs, &.{ try s.text("/\\*"), try s.text("\\*/"), options }));
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("@[a-z]\\w*(?::\"[^\"]*\")?"));
    try s.index(contains, 2, meta);
    try s.put(language, "contains", try s.invoke(contains, "concat", &.{expressions}));
    return b.c.JS_DupValue(e.context, language);
}
