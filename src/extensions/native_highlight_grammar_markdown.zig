//! Actual highlight.js 10.7.3 Markdown factory; source-only.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const regex = @import("native_highlight_regex.zig");
const c = em.c;

fn literal(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn mode(s: *Scope, class_name: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "className", try s.text(class_name));
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "markdown", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, _: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const inline_html = try s.object();
    try s.put(inline_html, "begin", try literal(&s, "<\\/?[A-Za-z_]"));
    try s.put(inline_html, "end", try s.text(">"));
    try s.put(inline_html, "subLanguage", try s.text("xml"));
    try s.put(inline_html, "relevance", c.JS_NewInt32(engine.context, 0));
    const horizontal = try s.object();
    try s.put(horizontal, "begin", try s.text("^[-\\*]{3,}"));
    try s.put(horizontal, "end", try s.text("$"));
    const code = try mode(&s, "code");
    const code_variants = try s.array();
    inline for (.{ "(`{3,})[^`](.|\\n)*?\\1`*[ ]*", "(~{3,})[^~](.|\\n)*?\\1~*[ ]*" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        try s.index(code_variants, index, variant);
    }
    inline for (.{ .{ "```", "```+[ ]*$" }, .{ "~~~", "~~~+[ ]*$" } }, 0..) |pair, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pair[0]));
        try s.put(variant, "end", try s.text(pair[1]));
        try s.index(code_variants, @intCast(index + 2), variant);
    }
    const inline_code = try s.object();
    try s.put(inline_code, "begin", try s.text("`.+?`"));
    try s.index(code_variants, 4, inline_code);
    const indented = try s.object();
    try s.put(indented, "begin", try s.text("(?=^( {4}|\\t))"));
    const indent_line = try s.object();
    try s.put(indent_line, "begin", try s.text("^( {4}|\\t)"));
    try s.put(indent_line, "end", try s.text("(\\n)$"));
    try s.put(indented, "contains", try list(&s, &.{indent_line}));
    try s.put(indented, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(code_variants, 5, indented);
    try s.put(code, "variants", code_variants);
    const bullet = try mode(&s, "bullet");
    try s.put(bullet, "begin", try s.text("^[ \t]*([*+-]|(\\d+\\.))(?=\\s+)"));
    try s.put(bullet, "end", try s.text("\\s+"));
    try s.put(bullet, "excludeEnd", c.pi_js_bool(engine.context, 1));
    const link_reference = try s.object();
    try s.put(link_reference, "begin", try literal(&s, "^\\[[^\\n]+\\]:"));
    try s.put(link_reference, "returnBegin", c.pi_js_bool(engine.context, 1));
    const reference_symbol = try mode(&s, "symbol");
    try s.put(reference_symbol, "begin", try literal(&s, "\\["));
    try s.put(reference_symbol, "end", try literal(&s, "\\]"));
    try s.put(reference_symbol, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(reference_symbol, "excludeEnd", c.pi_js_bool(engine.context, 1));
    const reference_link = try mode(&s, "link");
    try s.put(reference_link, "begin", try literal(&s, ":\\s*"));
    try s.put(reference_link, "end", try literal(&s, "$"));
    try s.put(reference_link, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(link_reference, "contains", try list(&s, &.{ reference_symbol, reference_link }));
    const url_scheme = try literal(&s, "[A-Za-z][A-Za-z0-9+.-]*");
    const link = try s.object();
    const link_variants = try s.array();
    const link_reference_variant = try s.object();
    try s.put(link_reference_variant, "begin", try literal(&s, "\\[.+?\\]\\[.*?\\]"));
    try s.put(link_reference_variant, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(link_variants, 0, link_reference_variant);
    const popular = try s.object();
    try s.put(popular, "begin", try literal(&s, "\\[.+?\\]\\(((data|javascript|mailto):|(?:http|ftp)s?:\\/\\/).*?\\)"));
    try s.put(popular, "relevance", c.JS_NewInt32(engine.context, 2));
    try s.index(link_variants, 1, popular);
    const scheme = try s.object();
    try s.put(scheme, "begin", try s.own(try regex.concat(engine, try list(&s, &.{ try literal(&s, "\\[.+?\\]\\("), url_scheme, try literal(&s, ":\\/\\/.*?\\)") }))));
    try s.put(scheme, "relevance", c.JS_NewInt32(engine.context, 2));
    try s.index(link_variants, 2, scheme);
    const relative = try s.object();
    try s.put(relative, "begin", try literal(&s, "\\[.+?\\]\\([./?&#].*?\\)"));
    try s.put(relative, "relevance", c.JS_NewInt32(engine.context, 1));
    try s.index(link_variants, 3, relative);
    const other = try s.object();
    try s.put(other, "begin", try literal(&s, "\\[.+?\\]\\(.*?\\)"));
    try s.put(other, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(link_variants, 4, other);
    try s.put(link, "variants", link_variants);
    try s.put(link, "returnBegin", c.pi_js_bool(engine.context, 1));
    const link_contains = try s.array();
    inline for (.{ .{ "string", "\\[", "\\]" }, .{ "link", "\\]\\(", "\\)" }, .{ "symbol", "\\]\\[", "\\]" } }, 0..) |entry, index| {
        const child = try mode(&s, entry[0]);
        try s.put(child, "relevance", c.JS_NewInt32(engine.context, 0));
        try s.put(child, "begin", try s.text(entry[1]));
        try s.put(child, "end", try s.text(entry[2]));
        try s.put(child, "excludeBegin", c.pi_js_bool(engine.context, 1));
        if (index == 0) try s.put(child, "returnEnd", c.pi_js_bool(engine.context, 1)) else try s.put(child, "excludeEnd", c.pi_js_bool(engine.context, 1));
        try s.index(link_contains, index, child);
    }
    try s.put(link, "contains", link_contains);
    const bold = try mode(&s, "strong");
    try s.put(bold, "contains", try s.array());
    const bold_variants = try s.array();
    inline for (.{ "_{2}", "\\*{2}" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try literal(&s, pattern));
        try s.put(variant, "end", try literal(&s, pattern));
        try s.index(bold_variants, index, variant);
    }
    try s.put(bold, "variants", bold_variants);
    const italic = try mode(&s, "emphasis");
    try s.put(italic, "contains", try s.array());
    const italic_variants = try s.array();
    inline for (.{ .{ "\\*(?!\\*)", "\\*" }, .{ "_(?!_)", "_" } }, 0..) |pair, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try literal(&s, pair[0]));
        try s.put(variant, "end", try literal(&s, pair[1]));
        if (index == 1) try s.put(variant, "relevance", c.JS_NewInt32(engine.context, 0));
        try s.index(italic_variants, index, variant);
    }
    try s.put(italic, "variants", italic_variants);
    _ = try s.invoke(try s.get(bold, "contains"), "push", &.{italic});
    _ = try s.invoke(try s.get(italic, "contains"), "push", &.{bold});
    var containable = try list(&s, &.{ inline_html, link });
    try s.set(bold, "contains", try s.invoke(try s.get(bold, "contains"), "concat", &.{containable}));
    try s.set(italic, "contains", try s.invoke(try s.get(italic, "contains"), "concat", &.{containable}));
    containable = try s.invoke(containable, "concat", &.{ bold, italic });
    const header = try mode(&s, "section");
    const header_variants = try s.array();
    const hashes = try s.object();
    try s.put(hashes, "begin", try s.text("^#{1,6}"));
    try s.put(hashes, "end", try s.text("$"));
    try s.put(hashes, "contains", containable);
    try s.index(header_variants, 0, hashes);
    const underline = try s.object();
    try s.put(underline, "begin", try s.text("(?=^.+?\\n[=-]{2,}$)"));
    const underline_line = try s.object();
    try s.put(underline_line, "begin", try s.text("^[=-]*$"));
    const header_line = try s.object();
    try s.put(header_line, "begin", try s.text("^"));
    try s.put(header_line, "end", try s.text("\\n"));
    try s.put(header_line, "contains", containable);
    try s.put(underline, "contains", try list(&s, &.{ underline_line, header_line }));
    try s.index(header_variants, 1, underline);
    try s.put(header, "variants", header_variants);
    const blockquote = try mode(&s, "quote");
    try s.put(blockquote, "begin", try s.text("^>\\s+"));
    try s.put(blockquote, "contains", containable);
    try s.put(blockquote, "end", try s.text("$"));
    const language = try s.object();
    try s.put(language, "name", try s.text("Markdown"));
    try s.put(language, "aliases", try list(&s, &.{ try s.text("md"), try s.text("mkdown"), try s.text("mkd") }));
    try s.put(language, "contains", try list(&s, &.{ header, inline_html, bullet, bold, italic, blockquote, code, horizontal, link, link_reference }));
    return c.JS_DupValue(engine.context, language);
}
