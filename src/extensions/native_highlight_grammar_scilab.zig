//! Actual highlight.js10.7.3 Scilab factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "scilab", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const common = try b.list(&s, &.{try s.get(hljs, "C_NUMBER_MODE")});
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try s.text("'|\""));
    try s.put(string, "end", try s.text("'|\""));
    const children = try b.list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")});
    const escaped = try s.object();
    try s.put(escaped, "begin", try s.text("''"));
    try s.index(children, 1, escaped);
    try s.put(string, "contains", children);
    try s.index(common, 1, string);
    const language = try s.object();
    try s.put(language, "name", try s.text("Scilab"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("sci")}));
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try b.rx(&s, "%?\\w+"));
    try s.put(keywords, "keyword", try s.text("abort break case clear catch continue do elseif else endfunction end for function global if pause return resume select try then while"));
    try s.put(keywords, "literal", try s.text("%f %F %t %T %pi %eps %inf %nan %e %i %z %s"));
    try s.put(keywords, "built_in", try s.text("abs and acos asin atan ceil cd chdir clearglobal cosh cos cumprod deff disp error exec execstr exists exp eye gettext floor fprintf fread fsolve imag isdef isempty isinfisnan isvector lasterror length load linspace list listfiles log10 log2 log max min msprintf mclose mopen ones or pathconvert poly printf prod pwd rand real round sinh sin size gsort sprintf sqrt strcat strcmps tring sum system tanh tan type typename warning zeros matrix"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "illegal", try s.text("(\"|#|/\\*|\\s+/\\w+)"));
    const function = try b.mode(&s, "function");
    try s.put(function, "beginKeywords", try s.text("function"));
    try s.put(function, "end", try s.text("$"));
    const function_contains = try b.list(&s, &.{try s.get(hljs, "UNDERSCORE_TITLE_MODE")});
    const params = try b.mode(&s, "params");
    try s.put(params, "begin", try s.text("\\("));
    try s.put(params, "end", try s.text("\\)"));
    try s.index(function_contains, 1, params);
    try s.put(function, "contains", function_contains);
    const guard = try s.object();
    try s.put(guard, "begin", try s.text("[a-zA-Z_][a-zA-Z_0-9]*[\\.']+"));
    try s.put(guard, "relevance", b.c.JS_NewInt32(e.context, 0));
    const matrix = try s.object();
    try s.put(matrix, "begin", try s.text("\\["));
    try s.put(matrix, "end", try s.text("\\][\\.']*"));
    try s.put(matrix, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(matrix, "contains", common);
    const comment = try s.get(hljs, "COMMENT");
    const contains = try b.list(&s, &.{ function, guard, matrix, try s.call(comment, hljs, &.{ try s.text("//"), try s.text("$") }) });
    try s.put(language, "contains", try s.invoke(contains, "concat", &.{common}));
    return b.c.JS_DupValue(e.context, language);
}
