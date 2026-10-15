//! Actual highlight.js10.7.3 G-code factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "gcode", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try s.text("[A-Z_][A-Z0-9_.]*"));
    try s.put(keywords, "keyword", try s.text("IF DO WHILE ENDWHILE CALL ENDIF SUB ENDSUB GOTO REPEAT ENDREPEAT EQ LT GT NE GE LE OR XOR"));
    const start = try b.mode(&s, "meta");
    try s.put(start, "begin", try s.text("([O])([0-9]+)"));
    const inherit_number = try s.get(hljs, "inherit");
    const base_number = try s.get(hljs, "C_NUMBER_MODE");
    const changes = try s.object();
    const prefix = try s.text("([-+]?((\\.\\d+)|(\\d+)(\\.\\d*)?))|");
    try s.put(changes, "begin", try s.concat(prefix, try s.get(hljs, "C_NUMBER_RE")));
    const number = try s.call(inherit_number, hljs, &.{ base_number, changes });
    const code = try b.list(&s, &.{ try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE") });
    const comment_function = try s.get(hljs, "COMMENT");
    try s.index(code, 2, try s.call(comment_function, hljs, &.{ try b.rx(&s, "\\("), try b.rx(&s, "\\)") }));
    try s.index(code, 3, number);
    inline for (.{ "APOS_STRING_MODE", "QUOTE_STRING_MODE" }, 0..) |name, index| {
        const inherit = try s.get(hljs, "inherit");
        const base = try s.get(hljs, name);
        const options = try s.object();
        try s.put(options, "illegal", b.c.pi_js_null());
        try s.index(code, @intCast(index + 4), try s.call(inherit, hljs, &.{ base, options }));
    }
    inline for (.{ "([G])([0-9]+\\.?[0-9]?)", "([M])([0-9]+\\.?[0-9]?)" }, 0..) |pattern, index| {
        const name = try b.mode(&s, "name");
        try s.put(name, "begin", try s.text(pattern));
        try s.index(code, @intCast(index + 6), name);
    }
    const variable = try b.mode(&s, "attr");
    try s.put(variable, "begin", try s.text("(VC|VS|#)"));
    try s.put(variable, "end", try s.text("(\\d+)"));
    try s.index(code, 8, variable);
    const offset = try b.mode(&s, "attr");
    try s.put(offset, "begin", try s.text("(VZOFX|VZOFY|VZOFZ)"));
    try s.index(code, 9, offset);
    const function = try b.mode(&s, "built_in");
    try s.put(function, "begin", try s.text("(ATAN|ABS|ACOS|ASIN|SIN|COS|EXP|FIX|FUP|ROUND|LN|TAN)(\\[)"));
    try s.put(function, "contains", try b.list(&s, &.{number}));
    try s.put(function, "end", try s.text("\\]"));
    try s.index(code, 10, function);
    const symbol = try b.mode(&s, "symbol");
    const variant = try s.object();
    try s.put(variant, "begin", try s.text("N"));
    try s.put(variant, "end", try s.text("\\d+"));
    try s.put(variant, "illegal", try s.text("\\W"));
    try s.put(symbol, "variants", try b.list(&s, &.{variant}));
    try s.index(code, 11, symbol);
    const language = try s.object();
    try s.put(language, "name", try s.text("G-code (ISO 6983)"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("nc")}));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    try s.put(language, "keywords", keywords);
    const end = try b.mode(&s, "meta");
    try s.put(end, "begin", try s.text("%"));
    const contains = try b.list(&s, &.{ end, start });
    try s.put(language, "contains", try s.invoke(contains, "concat", &.{code}));
    return b.c.JS_DupValue(e.context, language);
}
