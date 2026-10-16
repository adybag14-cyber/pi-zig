//! Actual highlight.js10.7.3 Clean factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "clean", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Clean"));
    try s.put(language, "aliases", try b.list(&s, &.{ try s.text("icl"), try s.text("dcl") }));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("if let in with where case of class instance otherwise implementation definition system module from import qualified as special code inline foreign export ccall stdcall generic derive infix infixl infixr"));
    try s.put(keywords, "built_in", try s.text("Int Real Char Bool"));
    try s.put(keywords, "literal", try s.text("True False"));
    try s.put(language, "keywords", keywords);
    const contains = try s.array();
    try s.index(contains, 0, try s.get(hljs, "C_LINE_COMMENT_MODE"));
    try s.index(contains, 1, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try s.index(contains, 2, try s.get(hljs, "APOS_STRING_MODE"));
    try s.index(contains, 3, try s.get(hljs, "QUOTE_STRING_MODE"));
    try s.index(contains, 4, try s.get(hljs, "C_NUMBER_MODE"));
    const booster = try s.object();
    try s.put(booster, "begin", try s.text("->|<-[|:]?|#!?|>>=|\\{\\||\\|\\}|:==|=:|<>"));
    try s.index(contains, 5, booster);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(engine.context, language);
}
