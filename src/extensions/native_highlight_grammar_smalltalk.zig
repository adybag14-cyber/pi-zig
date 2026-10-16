//! Actual highlight.js10.7.3 Smalltalk factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "smalltalk", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const ident = "[a-z][a-zA-Z0-9_]*";
    const char = try b.mode(&s, "string");
    try s.put(char, "begin", try s.text("\\$.{1}"));
    const symbol = try b.mode(&s, "symbol");
    try s.put(symbol, "begin", try s.concat(try s.text("#"), try s.get(hljs, "UNDERSCORE_IDENT_RE")));
    const language = try s.object();
    try s.put(language, "name", try s.text("Smalltalk"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("st")}));
    try s.put(language, "keywords", try s.text("self super nil true false thisContext"));
    const comment_function = try s.get(hljs, "COMMENT");
    const contains = try b.list(&s, &.{ try s.call(comment_function, hljs, &.{ try s.text("\""), try s.text("\"") }), try s.get(hljs, "APOS_STRING_MODE") });
    const type_mode = try b.mode(&s, "type");
    try s.put(type_mode, "begin", try s.text("\\b[A-Z][A-Za-z0-9_]*"));
    try s.put(type_mode, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(contains, 2, type_mode);
    const method = try s.object();
    try s.put(method, "begin", try s.text(ident ++ ":"));
    try s.put(method, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.index(contains, 3, method);
    try s.index(contains, 4, try s.get(hljs, "C_NUMBER_MODE"));
    try s.index(contains, 5, symbol);
    try s.index(contains, 6, char);
    const locals = try s.object();
    try s.put(locals, "begin", try s.text("\\|[ ]*" ++ ident ++ "([ ]+" ++ ident ++ ")*[ ]*\\|"));
    try s.put(locals, "returnBegin", b.boolean(&s, true));
    try s.put(locals, "end", try b.rx(&s, "\\|"));
    try s.put(locals, "illegal", try b.rx(&s, "\\S"));
    const local = try s.object();
    try s.put(local, "begin", try s.text("(\\|[ ]*)?" ++ ident));
    try s.put(locals, "contains", try b.list(&s, &.{local}));
    try s.index(contains, 7, locals);
    const array = try s.object();
    try s.put(array, "begin", try s.text("#\\("));
    try s.put(array, "end", try s.text("\\)"));
    try s.put(array, "contains", try b.list(&s, &.{ try s.get(hljs, "APOS_STRING_MODE"), char, try s.get(hljs, "C_NUMBER_MODE"), symbol }));
    try s.index(contains, 8, array);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
