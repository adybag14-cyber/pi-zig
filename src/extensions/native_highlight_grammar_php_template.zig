//! Actual highlight.js10.7.3 PHP template factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "phpTemplate", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("PHP template"));
    try s.put(language, "subLanguage", try s.text("xml"));
    const php = try s.object();
    try s.put(php, "begin", try b.rx(&s, "<\\?(php|=)?"));
    try s.put(php, "end", try b.rx(&s, "\\?>"));
    try s.put(php, "subLanguage", try s.text("php"));
    const contains = try s.array();
    inline for (.{ .{ "/\\*", "\\*/" }, .{ "b\"", "\"" }, .{ "b'", "'" } }, 0..) |entry, index| {
        const skip = try s.object();
        try s.put(skip, "begin", try s.text(entry[0]));
        try s.put(skip, "end", try s.text(entry[1]));
        try s.put(skip, "skip", b.boolean(&s, true));
        try s.index(contains, index, skip);
    }
    inline for (.{ "APOS_STRING_MODE", "QUOTE_STRING_MODE" }, 0..) |name, index| {
        const inherit = try s.get(hljs, "inherit");
        const base = try s.get(hljs, name);
        const changes = try s.object();
        try s.put(changes, "illegal", b.c.pi_js_null());
        try s.put(changes, "className", b.c.pi_js_null());
        try s.put(changes, "contains", b.c.pi_js_null());
        try s.put(changes, "skip", b.boolean(&s, true));
        try s.index(contains, @intCast(index + 3), try s.call(inherit, hljs, &.{ base, changes }));
    }
    try s.put(php, "contains", contains);
    try s.put(language, "contains", try b.list(&s, &.{php}));
    return b.c.JS_DupValue(e.context, language);
}
