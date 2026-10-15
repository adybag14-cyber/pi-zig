//! Actual highlight.js10.7.3 DOS batch factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "dos", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const comment_function = try s.get(hljs, "COMMENT");
    const begin = try b.rx(&s, "^\\s*@?rem\\b");
    const end = try b.rx(&s, "$");
    const options = try s.object();
    try s.put(options, "relevance", b.c.JS_NewInt32(e.context, 10));
    const comment = try s.call(comment_function, hljs, &.{ begin, end, options });
    const label = try b.mode(&s, "symbol");
    try s.put(label, "begin", try s.text("^\\s*[A-Za-z._?][A-Za-z0-9_$#@~.?]*(:|\\s+label)"));
    try s.put(label, "relevance", b.c.JS_NewInt32(e.context, 0));
    const language = try s.object();
    try s.put(language, "name", try s.text("Batch file (DOS)"));
    try s.put(language, "aliases", try b.list(&s, &.{ try s.text("bat"), try s.text("cmd") }));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    try s.put(language, "illegal", try b.rx(&s, "\\/\\*"));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("if else goto for in do call exit not exist errorlevel defined equ neq lss leq gtr geq"));
    try s.put(keywords, "built_in", try s.text("prn nul lpt3 lpt2 lpt1 con com4 com3 com2 com1 aux shift cd dir echo setlocal endlocal set pause copy append assoc at attrib break cacls cd chcp chdir chkdsk chkntfs cls cmd color comp compact convert date dir diskcomp diskcopy doskey erase fs find findstr format ftype graftabl help keyb label md mkdir mode more move path pause print popd pushd promt rd recover rem rename replace restore rmdir shift sort start subst time title tree type ver verify vol ping net ipconfig taskkill xcopy ren del"));
    try s.put(language, "keywords", keywords);
    const variable = try b.mode(&s, "variable");
    try s.put(variable, "begin", try b.rx(&s, "%%[^ ]|%[^ ]+?%|![^ ]+?!"));
    const function = try b.mode(&s, "function");
    try s.put(function, "begin", try s.get(label, "begin"));
    try s.put(function, "end", try s.text("goto:eof"));
    const inherit = try s.get(hljs, "inherit");
    const title = try s.get(hljs, "TITLE_MODE");
    const changes = try s.object();
    try s.put(changes, "begin", try s.text("([_a-zA-Z]\\w*\\.)*([_a-zA-Z]\\w*:)?[_a-zA-Z]\\w*"));
    try s.put(function, "contains", try b.list(&s, &.{ try s.call(inherit, hljs, &.{ title, changes }), comment }));
    const number = try b.mode(&s, "number");
    try s.put(number, "begin", try s.text("\\b\\d+"));
    try s.put(number, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(language, "contains", try b.list(&s, &.{ variable, function, number, comment }));
    return b.c.JS_DupValue(e.context, language);
}
