//! Actual highlight.js10.7.3 Parser3 factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "parser3", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const curly_fn = try s.get(hljs, "COMMENT");
    const curly_begin = try b.rx(&s, "\\{");
    const curly_end = try b.rx(&s, "\\}");
    const curly_opts = try s.object();
    try s.put(curly_opts, "contains", try b.list(&s, &.{try s.text("self")}));
    const curly = try s.call(curly_fn, hljs, &.{ curly_begin, curly_end, curly_opts });
    const language = try s.object();
    try s.put(language, "name", try s.text("Parser3"));
    try s.put(language, "subLanguage", try s.text("xml"));
    try s.put(language, "relevance", b.c.JS_NewInt32(e.context, 0));
    const line_fn = try s.get(hljs, "COMMENT");
    const contains = try b.list(&s, &.{try s.call(line_fn, hljs, &.{ try s.text("^#"), try s.text("$") })});
    const rem_fn = try s.get(hljs, "COMMENT");
    const rem_begin = try b.rx(&s, "\\^rem\\{");
    const rem_end = try b.rx(&s, "\\}");
    const rem_opts = try s.object();
    try s.put(rem_opts, "relevance", b.c.JS_NewInt32(e.context, 10));
    try s.put(rem_opts, "contains", try b.list(&s, &.{curly}));
    try s.index(contains, 1, try s.call(rem_fn, hljs, &.{ rem_begin, rem_end, rem_opts }));
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("^@(?:BASE|USE|CLASS|OPTIONS)$"));
    try s.put(meta, "relevance", b.c.JS_NewInt32(e.context, 10));
    try s.index(contains, 2, meta);
    const title = try b.mode(&s, "title");
    try s.put(title, "begin", try s.text("@[\\w\\-]+\\[[\\w^;\\-]*\\](?:\\[[\\w^;\\-]*\\])?(?:.*)$"));
    try s.index(contains, 3, title);
    const variable = try b.mode(&s, "variable");
    try s.put(variable, "begin", try b.rx(&s, "\\$\\{?[\\w\\-.:]+\\}?"));
    try s.index(contains, 4, variable);
    const keyword = try b.mode(&s, "keyword");
    try s.put(keyword, "begin", try b.rx(&s, "\\^[\\w\\-.:]+"));
    try s.index(contains, 5, keyword);
    const number = try b.mode(&s, "number");
    try s.put(number, "begin", try s.text("\\^#[0-9a-fA-F]+"));
    try s.index(contains, 6, number);
    try s.index(contains, 7, try s.get(hljs, "C_NUMBER_MODE"));
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
