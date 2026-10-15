//! Actual highlight.js10.7.3 static keyword inputs; factory body follows.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "axapta", build);
}
fn strings(s: *b.Scope, values: []const []const u8) !b.c.JSValue {
    const a = try s.array();
    for (values, 0..) |v, i| try s.index(a, @intCast(i), try s.text(v));
    return a;
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const built = try strings(&s, &source_BUILT_IN_KEYWORDS);
    const literal = try strings(&s, &source_LITERAL_KEYWORDS);
    const normal = try strings(&s, &source_NORMAL_KEYWORDS);
    const kw = try s.object();
    try s.put(kw, "keyword", normal);
    try s.put(kw, "built_in", built);
    try s.put(kw, "literal", literal);
    const l = try s.object();
    try s.put(l, "name", try s.text("X++"));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("x++")}));
    try s.put(l, "keywords", kw);
    const a = try b.list(&s, &.{ try s.get(h, "C_LINE_COMMENT_MODE"), try s.get(h, "C_BLOCK_COMMENT_MODE"), try s.get(h, "APOS_STRING_MODE"), try s.get(h, "QUOTE_STRING_MODE"), try s.get(h, "C_NUMBER_MODE") });
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("#"));
    try s.put(meta, "end", try s.text("$"));
    try s.index(a, 5, meta);
    const cls = try b.mode(&s, "class");
    try s.put(cls, "beginKeywords", try s.text("class interface"));
    try s.put(cls, "end", try b.rx(&s, "\\{"));
    try s.put(cls, "excludeEnd", b.boolean(&s, true));
    try s.put(cls, "illegal", try s.text(":"));
    const ext = try s.object();
    try s.put(ext, "beginKeywords", try s.text("extends implements"));
    try s.put(cls, "contains", try b.list(&s, &.{ ext, try s.get(h, "UNDERSCORE_TITLE_MODE") }));
    try s.index(a, 6, cls);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
const source_NORMAL_KEYWORDS = [_][]const u8{
    "abstract",
    "as",
    "asc",
    "avg",
    "break",
    "breakpoint",
    "by",
    "byref",
    "case",
    "catch",
    "changecompany",
    "class",
    "client",
    "client",
    "common",
    "const",
    "continue",
    "count",
    "crosscompany",
    "delegate",
    "delete_from",
    "desc",
    "display",
    "div",
    "do",
    "edit",
    "else",
    "eventhandler",
    "exists",
    "extends",
    "final",
    "finally",
    "firstfast",
    "firstonly",
    "firstonly1",
    "firstonly10",
    "firstonly100",
    "firstonly1000",
    "flush",
    "for",
    "forceliterals",
    "forcenestedloop",
    "forceplaceholders",
    "forceselectorder",
    "forupdate",
    "from",
    "generateonly",
    "group",
    "hint",
    "if",
    "implements",
    "in",
    "index",
    "insert_recordset",
    "interface",
    "internal",
    "is",
    "join",
    "like",
    "maxof",
    "minof",
    "mod",
    "namespace",
    "new",
    "next",
    "nofetch",
    "notexists",
    "optimisticlock",
    "order",
    "outer",
    "pessimisticlock",
    "print",
    "private",
    "protected",
    "public",
    "readonly",
    "repeatableread",
    "retry",
    "return",
    "reverse",
    "select",
    "server",
    "setting",
    "static",
    "sum",
    "super",
    "switch",
    "this",
    "throw",
    "try",
    "ttsabort",
    "ttsbegin",
    "ttscommit",
    "unchecked",
    "update_recordset",
    "using",
    "validtimestate",
    "void",
    "where",
    "while",
};
const source_BUILT_IN_KEYWORDS = [_][]const u8{
    "anytype",
    "boolean",
    "byte",
    "char",
    "container",
    "date",
    "double",
    "enum",
    "guid",
    "int",
    "int64",
    "long",
    "real",
    "short",
    "str",
    "utcdatetime",
    "var",
};
const source_LITERAL_KEYWORDS = [_][]const u8{
    "default",
    "false",
    "null",
    "true",
};
