//! Native Source Markdown object and rendering callbacks. Development admission
//! remains separate from public pi-tui installation until Source replays pass.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const Method = enum(c_int) { setText, invalidate, render, applyDefaultStyle, getDefaultStylePrefix, getStylePrefix, getDefaultInlineStyleContext, renderToken, renderInlineTokens, getOrderedListMarker, getUnorderedListMarker, renderList, getLongestWordWidth, wrapCellText, renderTable };
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Markdown: %s", @as([*:0]const u8, @errorName(err)));
}
fn empty(engine: *Engine) !c.JSValue {
    return v.text(engine, "");
}
fn append(engine: *Engine, array: c.JSValue, owned: c.JSValue) !void {
    defer engine.freeValue(owned);
    try js.push(engine, array, owned);
}
fn repeat(engine: *Engine, text: []const u8, count: f64) !c.JSValue {
    const value = try v.text(engine, text);
    defer engine.freeValue(value);
    return js.invoke(engine, value, "repeat", &.{v.numeric(engine, count)});
}
fn concat(engine: *Engine, parts: []const c.JSValue) !c.JSValue {
    return v.concat(engine, parts);
}
fn theme(engine: *Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const value = try js.get(engine, object, "theme");
    defer engine.freeValue(value);
    return js.invoke(engine, value, name, args);
}
fn option(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const options = try js.get(engine, object, "options");
    defer engine.freeValue(options);
    return js.get(engine, options, name);
}
fn kind(engine: *Engine, token: c.JSValue, name: []const u8) !bool {
    if (c.JS_IsUndefined(token) or c.JS_IsNull(token)) return false;
    const value = try js.get(engine, token, "type");
    defer engine.freeValue(value);
    const expected = try v.text(engine, name);
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn defaultStyle(engine: *Engine, object: c.JSValue, source: c.JSValue) !c.JSValue {
    var styled = c.JS_DupValue(engine.context, source);
    errdefer engine.freeValue(styled);
    const style = try js.get(engine, object, "defaultTextStyle");
    defer engine.freeValue(style);
    if (!v.truthy(engine, style)) return styled;
    const color_style = try js.get(engine, object, "defaultTextStyle");
    defer engine.freeValue(color_style);
    const color = try js.get(engine, color_style, "color");
    defer engine.freeValue(color);
    if (v.truthy(engine, color)) {
        const current_style = try js.get(engine, object, "defaultTextStyle");
        defer engine.freeValue(current_style);
        const next = try js.invoke(engine, current_style, "color", &.{styled});
        engine.freeValue(styled);
        styled = next;
    }
    inline for (.{ "bold", "italic", "strikethrough", "underline" }) |name| {
        const current_style = try js.get(engine, object, "defaultTextStyle");
        defer engine.freeValue(current_style);
        const flag = try js.get(engine, current_style, name);
        defer engine.freeValue(flag);
        if (v.truthy(engine, flag)) {
            const next = try theme(engine, object, name, &.{styled});
            engine.freeValue(styled);
            styled = next;
        }
    }
    return styled;
}
const Style = enum(c_int) { default_style, heading_one, heading_other, quote, identity };
fn styleCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return styleValue(engine, data[0], @enumFromInt(magic), if (argc == 0) c.pi_js_undefined() else argv[0]) catch |err| fail(engine, err);
}
fn styleValue(engine: *Engine, object: c.JSValue, style: Style, text: c.JSValue) !c.JSValue {
    if (style == .identity) return c.JS_DupValue(engine.context, text);
    if (style == .default_style) return js.invoke(engine, object, "applyDefaultStyle", &.{text});
    if (style == .quote) {
        const italic = try theme(engine, object, "italic", &.{text});
        defer engine.freeValue(italic);
        return theme(engine, object, "quote", &.{italic});
    }
    const underlined = if (style == .heading_one) try theme(engine, object, "underline", &.{text}) else c.JS_DupValue(engine.context, text);
    defer engine.freeValue(underlined);
    const bold = try theme(engine, object, "bold", &.{underlined});
    defer engine.freeValue(bold);
    return theme(engine, object, "heading", &.{bold});
}
fn styleFunction(engine: *Engine, object: c.JSValue, style: Style) !c.JSValue {
    var data = [_]c.JSValue{object};
    const name: [*:0]const u8 = switch (style) {
        .heading_one, .heading_other => "headingStyleFn",
        .quote => "quoteStyle",
        else => "applyText",
    };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, styleCall, name, 1, @intFromEnum(style), 1, &data));
}
fn stylePrefix(engine: *Engine, function: c.JSValue) !c.JSValue {
    const sentinel = try v.text(engine, "\x00");
    defer engine.freeValue(sentinel);
    const styled = try js.call(engine, function, c.pi_js_undefined(), &.{sentinel});
    defer engine.freeValue(styled);
    const index_value = try js.invoke(engine, styled, "indexOf", &.{sentinel});
    defer engine.freeValue(index_value);
    const index = try v.number(engine, index_value);
    return if (index >= 0) js.invoke(engine, styled, "slice", &.{ v.numeric(engine, 0), index_value }) else empty(engine);
}
fn contextValue(engine: *Engine, object: c.JSValue, style: Style) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    const function = try styleFunction(engine, object, style);
    defer engine.freeValue(function);
    try js.define(engine, result, "applyText", c.JS_DupValue(engine.context, function));
    try js.define(engine, result, "stylePrefix", if (style == .identity) try empty(engine) else if (style == .default_style) try js.invoke(engine, object, "getDefaultStylePrefix", &.{}) else try js.invoke(engine, object, "getStylePrefix", &.{function}));
    return result;
}
fn wrap(engine: *Engine, value: c.JSValue, width: f64) !c.JSValue {
    const units = try utf16.unitsAlloc(engine, value);
    defer engine.gpa.free(units);
    const lines = try @import("native_utf16_wrap.zig").wrap(engine, units, width);
    defer {
        for (lines) |line| engine.gpa.free(line);
        engine.gpa.free(lines);
    }
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    for (lines) |line| try append(engine, result, try utf16.string(engine, line));
    return result;
}
fn extend(engine: *Engine, destination: c.JSValue, array: c.JSValue) !void {
    var at: f64 = 0;
    while (at < try v.numberField(engine, array, "length")) : (at += 1) try append(engine, destination, try v.fieldAt(engine, array, at));
}
fn textLines(engine: *Engine, text: c.JSValue, context: c.JSValue) !c.JSValue {
    const newline = try v.text(engine, "\n");
    defer engine.freeValue(newline);
    const lines = try js.invoke(engine, text, "split", &.{newline});
    defer engine.freeValue(lines);
    const output = try js.array(engine);
    defer engine.freeValue(output);
    const function = try js.get(engine, context, "applyText");
    defer engine.freeValue(function);
    var index: f64 = 0;
    while (index < try v.numberField(engine, lines, "length")) : (index += 1) {
        const line = try v.fieldAt(engine, lines, index);
        defer engine.freeValue(line);
        try append(engine, output, try js.call(engine, function, c.pi_js_undefined(), &.{line}));
    }
    return js.invoke(engine, output, "join", &.{newline});
}
fn math(engine: *Engine, object: c.JSValue, token: c.JSValue, display: bool) !c.JSValue {
    const raw = try js.get(engine, token, "raw");
    defer engine.freeValue(raw);
    const fallback = if (display) try js.invoke(engine, raw, "trim", &.{}) else c.JS_DupValue(engine.context, raw);
    errdefer engine.freeValue(fallback);
    const pending = try js.get(engine, token, "pending");
    defer engine.freeValue(pending);
    const enabled = try option(engine, object, "renderLatex");
    defer engine.freeValue(enabled);
    if (v.truthy(engine, pending) or c.JS_IsStrictEqual(engine.context, enabled, c.pi_js_bool(engine.context, 0))) return fallback;
    const text = try js.get(engine, token, "text");
    defer engine.freeValue(text);
    const bytes = try engine.toString(text);
    defer engine.gpa.free(bytes);
    if (try @import("../tui/latex.zig").renderLatex(engine.gpa, bytes, .{ .display = display })) |rendered| {
        defer engine.gpa.free(rendered);
        const result = try v.text(engine, rendered);
        engine.freeValue(fallback);
        return result;
    }
    return fallback;
}
fn nestedTokens(engine: *Engine, token: c.JSValue) !c.JSValue {
    const children = try js.get(engine, token, "tokens");
    if (v.truthy(engine, children)) return children;
    engine.freeValue(children);
    return js.array(engine);
}
fn inlineTokens(engine: *Engine, object: c.JSValue, tokens: c.JSValue, supplied: c.JSValue, helpers: c.JSValue, iterator_symbol: c.JSValue) anyerror!c.JSValue {
    const context = if (c.JS_IsUndefined(supplied) or c.JS_IsNull(supplied)) try js.invoke(engine, object, "getDefaultInlineStyleContext", &.{}) else c.JS_DupValue(engine.context, supplied);
    defer engine.freeValue(context);
    const prefix = try js.get(engine, context, "stylePrefix");
    defer engine.freeValue(prefix);
    var result = try empty(engine);
    errdefer engine.freeValue(result);
    var iterator = try js.Iterator.init(engine, tokens, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |token| {
        defer engine.freeValue(token);
        var piece: c.JSValue = undefined;
        if (try kind(engine, token, "latex")) {
            const rendered = try math(engine, object, token, false);
            defer engine.freeValue(rendered);
            piece = try textLines(engine, rendered, context);
        } else if (try kind(engine, token, "br")) {
            piece = try v.text(engine, "\n");
        } else if (try kind(engine, token, "strong") or try kind(engine, token, "em") or try kind(engine, token, "del") or try kind(engine, token, "codespan")) {
            const span = try kind(engine, token, "codespan");
            const content = if (span) try js.get(engine, token, "text") else blk: {
                const children = try nestedTokens(engine, token);
                defer engine.freeValue(children);
                break :blk try js.invoke(engine, object, "renderInlineTokens", &.{ children, context });
            };
            defer engine.freeValue(content);
            const styled = try theme(engine, object, if (span) "code" else if (try kind(engine, token, "strong")) "bold" else if (try kind(engine, token, "em")) "italic" else "strikethrough", &.{content});
            defer engine.freeValue(styled);
            piece = try concat(engine, &.{ styled, prefix });
        } else if (try kind(engine, token, "link")) {
            const children = try nestedTokens(engine, token);
            defer engine.freeValue(children);
            const content = try js.invoke(engine, object, "renderInlineTokens", &.{ children, context });
            defer engine.freeValue(content);
            const underlined = try theme(engine, object, "underline", &.{content});
            defer engine.freeValue(underlined);
            const styled = try theme(engine, object, "link", &.{underlined});
            defer engine.freeValue(styled);
            const caps = try js.invoke(engine, helpers, "getCapabilities", &.{});
            defer engine.freeValue(caps);
            const hyperlinks = try js.get(engine, caps, "hyperlinks");
            defer engine.freeValue(hyperlinks);
            const href = try js.get(engine, token, "href");
            defer engine.freeValue(href);
            if (v.truthy(engine, hyperlinks)) {
                const linked = try js.invoke(engine, helpers, "hyperlink", &.{ styled, href });
                defer engine.freeValue(linked);
                piece = try concat(engine, &.{ linked, prefix });
            } else {
                const mailto = try v.text(engine, "mailto:");
                defer engine.freeValue(mailto);
                const starts = try js.invoke(engine, href, "startsWith", &.{mailto});
                defer engine.freeValue(starts);
                const comparison = if (v.truthy(engine, starts)) try js.invoke(engine, href, "slice", &.{v.numeric(engine, 7)}) else c.JS_DupValue(engine.context, href);
                defer engine.freeValue(comparison);
                const text = try js.get(engine, token, "text");
                defer engine.freeValue(text);
                if (c.JS_IsStrictEqual(engine.context, text, href) or c.JS_IsStrictEqual(engine.context, text, comparison)) {
                    piece = try concat(engine, &.{ styled, prefix });
                } else {
                    const open = try v.text(engine, " (");
                    defer engine.freeValue(open);
                    const close = try v.text(engine, ")");
                    defer engine.freeValue(close);
                    const url = try concat(engine, &.{ open, href, close });
                    defer engine.freeValue(url);
                    const themed_url = try theme(engine, object, "linkUrl", &.{url});
                    defer engine.freeValue(themed_url);
                    piece = try concat(engine, &.{ styled, themed_url, prefix });
                }
            }
        } else if (try kind(engine, token, "paragraph") or try kind(engine, token, "text")) {
            const children = try js.get(engine, token, "tokens");
            defer engine.freeValue(children);
            if (v.truthy(engine, children) and try v.numberField(engine, children, "length") > 0) {
                piece = try js.invoke(engine, object, "renderInlineTokens", &.{ children, context });
            } else if (try kind(engine, token, "paragraph")) {
                piece = try empty(engine);
            } else {
                const text = try js.get(engine, token, "text");
                defer engine.freeValue(text);
                piece = try textLines(engine, text, context);
            }
        } else {
            const preserve = if (try kind(engine, token, "escape")) try option(engine, object, "preserveBackslashEscapes") else c.pi_js_undefined();
            defer engine.freeValue(preserve);
            const text = try js.get(engine, token, if (try kind(engine, token, "html") or v.truthy(engine, preserve)) "raw" else "text");
            defer engine.freeValue(text);
            piece = if (c.JS_IsString(text)) try textLines(engine, text, context) else try empty(engine);
        }
        defer engine.freeValue(piece);
        const next = try concat(engine, &.{ result, piece });
        engine.freeValue(result);
        result = next;
    }
    while (v.truthy(engine, prefix)) {
        const ends = try js.invoke(engine, result, "endsWith", &.{prefix});
        defer engine.freeValue(ends);
        if (!v.truthy(engine, ends)) break;
        const length = try v.numberField(engine, prefix, "length");
        const next = try js.invoke(engine, result, "slice", &.{ v.numeric(engine, 0), v.numeric(engine, -length) });
        engine.freeValue(result);
        result = next;
    }
    return result;
}
fn spacing(engine: *Engine, next: c.JSValue, paragraph: bool) !bool {
    if (!v.truthy(engine, next)) return false;
    const space = try v.text(engine, "space");
    defer engine.freeValue(space);
    if (c.JS_IsStrictEqual(engine.context, next, space)) return false;
    if (paragraph) {
        const list = try v.text(engine, "list");
        defer engine.freeValue(list);
        if (c.JS_IsStrictEqual(engine.context, next, list)) return false;
    }
    return true;
}
fn renderToken(engine: *Engine, object: c.JSValue, token: c.JSValue, width: c.JSValue, next: c.JSValue, context: c.JSValue, iterator_symbol: c.JSValue) anyerror!c.JSValue {
    const lines = try js.array(engine);
    errdefer engine.freeValue(lines);
    if (try kind(engine, token, "heading")) {
        const depth = try v.numberField(engine, token, "depth");
        const style = try styleFunction(engine, object, if (depth == 1) .heading_one else .heading_other);
        defer engine.freeValue(style);
        const heading_context = try js.object(engine);
        defer engine.freeValue(heading_context);
        try js.define(engine, heading_context, "applyText", c.JS_DupValue(engine.context, style));
        try js.define(engine, heading_context, "stylePrefix", try js.invoke(engine, object, "getStylePrefix", &.{style}));
        const children = try nestedTokens(engine, token);
        defer engine.freeValue(children);
        const text = try js.invoke(engine, object, "renderInlineTokens", &.{ children, heading_context });
        defer engine.freeValue(text);
        if (depth >= 3) {
            const hashes = try repeat(engine, "#", depth);
            defer engine.freeValue(hashes);
            const space = try v.text(engine, " ");
            defer engine.freeValue(space);
            const prefix = try concat(engine, &.{ hashes, space });
            defer engine.freeValue(prefix);
            const styled = try js.call(engine, style, c.pi_js_undefined(), &.{prefix});
            defer engine.freeValue(styled);
            try append(engine, lines, try concat(engine, &.{ styled, text }));
        } else try js.push(engine, lines, text);
        if (try spacing(engine, next, false)) try append(engine, lines, try empty(engine));
    } else if (try kind(engine, token, "paragraph")) {
        const children = try nestedTokens(engine, token);
        defer engine.freeValue(children);
        try append(engine, lines, try js.invoke(engine, object, "renderInlineTokens", &.{ children, context }));
        if (try spacing(engine, next, true)) try append(engine, lines, try empty(engine));
    } else if (try kind(engine, token, "text")) {
        const singleton = try js.array(engine);
        defer engine.freeValue(singleton);
        try js.push(engine, singleton, token);
        try append(engine, lines, try js.invoke(engine, object, "renderInlineTokens", &.{ singleton, context }));
    } else if (try kind(engine, token, "latexBlock")) {
        const rendered = try math(engine, object, token, true);
        defer engine.freeValue(rendered);
        const newline = try v.text(engine, "\n");
        defer engine.freeValue(newline);
        const split = try js.invoke(engine, rendered, "split", &.{newline});
        defer engine.freeValue(split);
        var line_iterator = try js.Iterator.init(engine, split, iterator_symbol);
        defer line_iterator.deinit();
        errdefer line_iterator.closePreserving();
        while (try line_iterator.next()) |line| {
            defer engine.freeValue(line);
            try append(engine, lines, try js.invoke(engine, object, "applyDefaultStyle", &.{line}));
        }
        if (try spacing(engine, next, false)) try append(engine, lines, try empty(engine));
    } else if (try kind(engine, token, "code")) {
        const current_theme = try js.get(engine, object, "theme");
        defer engine.freeValue(current_theme);
        const raw_indent = try js.get(engine, current_theme, "codeBlockIndent");
        defer engine.freeValue(raw_indent);
        const indent = if (c.JS_IsNull(raw_indent) or c.JS_IsUndefined(raw_indent)) try v.text(engine, "  ") else c.JS_DupValue(engine.context, raw_indent);
        defer engine.freeValue(indent);
        const lang = try js.get(engine, token, "lang");
        defer engine.freeValue(lang);
        const language = if (v.truthy(engine, lang)) c.JS_DupValue(engine.context, lang) else try empty(engine);
        defer engine.freeValue(language);
        const fence = try v.text(engine, "```");
        defer engine.freeValue(fence);
        const opening = try concat(engine, &.{ fence, language });
        defer engine.freeValue(opening);
        try append(engine, lines, try theme(engine, object, "codeBlockBorder", &.{opening}));
        const highlight_theme = try js.get(engine, object, "theme");
        defer engine.freeValue(highlight_theme);
        const highlight = try js.get(engine, highlight_theme, "highlightCode");
        defer engine.freeValue(highlight);
        const text = try js.get(engine, token, "text");
        defer engine.freeValue(text);
        const newline = try v.text(engine, "\n");
        defer engine.freeValue(newline);
        const split = if (v.truthy(engine, highlight)) try theme(engine, object, "highlightCode", &.{ text, lang }) else try js.invoke(engine, text, "split", &.{newline});
        defer engine.freeValue(split);
        var line_iterator = try js.Iterator.init(engine, split, iterator_symbol);
        defer line_iterator.deinit();
        errdefer line_iterator.closePreserving();
        while (try line_iterator.next()) |line| {
            defer engine.freeValue(line);
            const styled = if (v.truthy(engine, highlight)) c.JS_DupValue(engine.context, line) else try theme(engine, object, "codeBlock", &.{line});
            defer engine.freeValue(styled);
            try append(engine, lines, try concat(engine, &.{ indent, styled }));
        }
        try append(engine, lines, try theme(engine, object, "codeBlockBorder", &.{fence}));
        if (try spacing(engine, next, false)) try append(engine, lines, try empty(engine));
    } else if (try kind(engine, token, "list")) {
        const rendered = try js.invoke(engine, object, "renderList", &.{ token, v.numeric(engine, 0), width, context });
        defer engine.freeValue(rendered);
        try extend(engine, lines, rendered);
    } else if (try kind(engine, token, "table")) {
        const rendered = try js.invoke(engine, object, "renderTable", &.{ token, width, next, context });
        defer engine.freeValue(rendered);
        try extend(engine, lines, rendered);
    } else if (try kind(engine, token, "blockquote")) {
        const quote = try styleFunction(engine, object, .quote);
        defer engine.freeValue(quote);
        const prefix = try js.invoke(engine, object, "getStylePrefix", &.{quote});
        defer engine.freeValue(prefix);
        const quote_context = try contextValue(engine, object, .identity);
        defer engine.freeValue(quote_context);
        try v.set(engine, quote_context, "stylePrefix", c.JS_DupValue(engine.context, prefix));
        const content_width = v.numeric(engine, v.maximum(1, try v.number(engine, width) - 2));
        const children = try nestedTokens(engine, token);
        defer engine.freeValue(children);
        const rendered = try js.array(engine);
        defer engine.freeValue(rendered);
        var index: f64 = 0;
        while (index < try v.numberField(engine, children, "length")) : (index += 1) {
            const child = try v.fieldAt(engine, children, index);
            defer engine.freeValue(child);
            const following = try v.fieldAt(engine, children, index + 1);
            defer engine.freeValue(following);
            const next_kind = if (c.JS_IsUndefined(following)) c.pi_js_undefined() else try js.get(engine, following, "type");
            defer engine.freeValue(next_kind);
            const part = try js.invoke(engine, object, "renderToken", &.{ child, content_width, next_kind, quote_context });
            defer engine.freeValue(part);
            try extend(engine, rendered, part);
        }
        while (try v.numberField(engine, rendered, "length") > 0) {
            const last = try js.invoke(engine, rendered, "at", &.{v.numeric(engine, -1)});
            defer engine.freeValue(last);
            const blank = try empty(engine);
            defer engine.freeValue(blank);
            if (!c.JS_IsStrictEqual(engine.context, last, blank)) break;
            try v.invokeVoid(engine, rendered, "pop", &.{});
        }
        const reset = try v.text(engine, "\x1b[0m");
        defer engine.freeValue(reset);
        const replacement = try concat(engine, &.{ reset, prefix });
        defer engine.freeValue(replacement);
        index = 0;
        while (index < try v.numberField(engine, rendered, "length")) : (index += 1) {
            const line = try v.fieldAt(engine, rendered, index);
            defer engine.freeValue(line);
            const reapplied = if (v.truthy(engine, prefix)) try js.invoke(engine, line, "replaceAll", &.{ reset, replacement }) else c.JS_DupValue(engine.context, line);
            defer engine.freeValue(reapplied);
            const styled = try js.call(engine, quote, c.pi_js_undefined(), &.{reapplied});
            defer engine.freeValue(styled);
            const wrapped = try wrap(engine, styled, try v.number(engine, content_width));
            defer engine.freeValue(wrapped);
            var at: f64 = 0;
            while (at < try v.numberField(engine, wrapped, "length")) : (at += 1) {
                const fragment = try v.fieldAt(engine, wrapped, at);
                defer engine.freeValue(fragment);
                const border_text = try v.text(engine, "│ ");
                defer engine.freeValue(border_text);
                const quote_border = try theme(engine, object, "quoteBorder", &.{border_text});
                defer engine.freeValue(quote_border);
                try append(engine, lines, try concat(engine, &.{ quote_border, fragment }));
            }
        }
        if (try spacing(engine, next, false)) try append(engine, lines, try empty(engine));
    } else if (try kind(engine, token, "hr")) {
        const line = try repeat(engine, "─", v.minimum(try v.number(engine, width), 80));
        defer engine.freeValue(line);
        try append(engine, lines, try theme(engine, object, "hr", &.{line}));
        if (try spacing(engine, next, false)) try append(engine, lines, try empty(engine));
    } else if (try kind(engine, token, "space")) {
        try append(engine, lines, try empty(engine));
    } else {
        const html = try kind(engine, token, "html");
        const text = try js.get(engine, token, if (html) "raw" else "text");
        defer engine.freeValue(text);
        if (c.JS_IsString(text)) {
            if (html) {
                const trimmed = try js.invoke(engine, text, "trim", &.{});
                defer engine.freeValue(trimmed);
                try append(engine, lines, try js.invoke(engine, object, "applyDefaultStyle", &.{trimmed}));
            } else try js.push(engine, lines, text);
        }
    }
    return lines;
}
fn renderList(engine: *Engine, object: c.JSValue, token: c.JSValue, depth: c.JSValue, width: c.JSValue, context: c.JSValue, iterator_symbol: c.JSValue) !c.JSValue {
    const lines = try js.array(engine);
    errdefer engine.freeValue(lines);
    const indent = try repeat(engine, "    ", try v.number(engine, depth));
    defer engine.freeValue(indent);
    const raw_start = try js.get(engine, token, "start");
    defer engine.freeValue(raw_start);
    const start = if (c.JS_IsNumber(raw_start)) try v.number(engine, raw_start) else 1;
    const items = try js.get(engine, token, "items");
    defer engine.freeValue(items);
    var index: f64 = 0;
    while (index < try v.numberField(engine, items, "length")) : (index += 1) {
        const item = try v.fieldAt(engine, items, index);
        defer engine.freeValue(item);
        const ordered = try js.get(engine, token, "ordered");
        defer engine.freeValue(ordered);
        const preserve = try option(engine, object, "preserveOrderedListMarkers");
        defer engine.freeValue(preserve);
        const original_marker = if (v.truthy(engine, preserve)) try js.invoke(engine, object, if (v.truthy(engine, ordered)) "getOrderedListMarker" else "getUnorderedListMarker", &.{item}) else c.pi_js_undefined();
        defer engine.freeValue(original_marker);
        const bullet = if (!c.JS_IsUndefined(original_marker) and !c.JS_IsNull(original_marker)) c.JS_DupValue(engine.context, original_marker) else if (v.truthy(engine, ordered)) blk: {
            const number = v.numeric(engine, start + index);
            const suffix = try v.text(engine, ". ");
            defer engine.freeValue(suffix);
            break :blk try concat(engine, &.{ number, suffix });
        } else try v.text(engine, "- ");
        defer engine.freeValue(bullet);
        const task = try js.get(engine, item, "task");
        defer engine.freeValue(task);
        const checked = try js.get(engine, item, "checked");
        defer engine.freeValue(checked);
        const task_marker = try v.text(engine, if (v.truthy(engine, task)) if (v.truthy(engine, checked)) "[x] " else "[ ] " else "");
        defer engine.freeValue(task_marker);
        const marker = try concat(engine, &.{ bullet, task_marker });
        defer engine.freeValue(marker);
        const styled = try theme(engine, object, "listBullet", &.{marker});
        defer engine.freeValue(styled);
        const first = try concat(engine, &.{ indent, styled });
        defer engine.freeValue(first);
        const spaces = try repeat(engine, " ", try v.width(engine, marker));
        defer engine.freeValue(spaces);
        const continuation = try concat(engine, &.{ indent, spaces });
        defer engine.freeValue(continuation);
        const item_width = v.numeric(engine, v.maximum(1, try v.number(engine, width) - try v.width(engine, first)));
        var any = false;
        const tokens = try js.get(engine, item, "tokens");
        defer engine.freeValue(tokens);
        var child_iterator = try js.Iterator.init(engine, tokens, iterator_symbol);
        defer child_iterator.deinit();
        errdefer child_iterator.closePreserving();
        while (try child_iterator.next()) |child| {
            defer engine.freeValue(child);
            if (try kind(engine, child, "list")) {
                const nested = try js.invoke(engine, object, "renderList", &.{ child, v.numeric(engine, try v.number(engine, depth) + 1), width, context });
                defer engine.freeValue(nested);
                try extend(engine, lines, nested);
                any = true;
                continue;
            }
            const rendered = try js.invoke(engine, object, "renderToken", &.{ child, item_width, c.pi_js_undefined(), context });
            defer engine.freeValue(rendered);
            var line_index: f64 = 0;
            while (line_index < try v.numberField(engine, rendered, "length")) : (line_index += 1) {
                const line = try v.fieldAt(engine, rendered, line_index);
                defer engine.freeValue(line);
                const wrapped = try wrap(engine, line, try v.number(engine, item_width));
                defer engine.freeValue(wrapped);
                var wrap_index: f64 = 0;
                while (wrap_index < try v.numberField(engine, wrapped, "length")) : (wrap_index += 1) {
                    const fragment = try v.fieldAt(engine, wrapped, wrap_index);
                    defer engine.freeValue(fragment);
                    try append(engine, lines, try concat(engine, &.{ if (any) continuation else first, fragment }));
                    any = true;
                }
            }
        }
        if (!any) try js.push(engine, lines, first);
        const loose = try js.get(engine, token, "loose");
        defer engine.freeValue(loose);
        if (v.truthy(engine, loose) and index != try v.numberField(engine, items, "length") - 1) try append(engine, lines, try empty(engine));
    }
    return lines;
}
fn cellText(engine: *Engine, object: c.JSValue, cell: c.JSValue, context: c.JSValue) !c.JSValue {
    const children = try js.get(engine, cell, "tokens");
    defer engine.freeValue(children);
    const tokens = if (v.truthy(engine, children)) c.JS_DupValue(engine.context, children) else try js.array(engine);
    defer engine.freeValue(tokens);
    return js.invoke(engine, object, "renderInlineTokens", &.{ tokens, context });
}
fn border(engine: *Engine, widths: []const f64, left: []const u8, middle: []const u8, right: []const u8) !c.JSValue {
    const cells = try js.array(engine);
    defer engine.freeValue(cells);
    for (widths) |width| try append(engine, cells, try repeat(engine, "─", width));
    const joiner = try v.text(engine, middle);
    defer engine.freeValue(joiner);
    const joined = try js.invoke(engine, cells, "join", &.{joiner});
    defer engine.freeValue(joined);
    const start = try v.text(engine, left);
    defer engine.freeValue(start);
    const end = try v.text(engine, right);
    defer engine.freeValue(end);
    return concat(engine, &.{ start, joined, end });
}
fn tableRow(engine: *Engine, object: c.JSValue, row: c.JSValue, widths: []const f64, context: c.JSValue, header: bool, output: c.JSValue) !void {
    const cells = try js.array(engine);
    defer engine.freeValue(cells);
    const prefix = if (c.JS_IsUndefined(context) or c.JS_IsNull(context)) c.pi_js_undefined() else try js.get(engine, context, "stylePrefix");
    defer engine.freeValue(prefix);
    var height: f64 = 0;
    var index: f64 = 0;
    while (index < try v.numberField(engine, row, "length")) : (index += 1) {
        if (index >= @as(f64, @floatFromInt(widths.len))) return error.NativeMarkdownTableShape;
        const cell = try v.fieldAt(engine, row, index);
        defer engine.freeValue(cell);
        const text = try cellText(engine, object, cell, context);
        defer engine.freeValue(text);
        const lines = try js.invoke(engine, object, "wrapCellText", &.{ text, v.numeric(engine, widths[@intFromFloat(index)]), prefix });
        defer engine.freeValue(lines);
        height = v.maximum(height, try v.numberField(engine, lines, "length"));
        try js.push(engine, cells, lines);
    }
    const separator = try v.text(engine, " │ ");
    defer engine.freeValue(separator);
    const left = try v.text(engine, "│ ");
    defer engine.freeValue(left);
    const right = try v.text(engine, " │");
    defer engine.freeValue(right);
    var line_index: f64 = 0;
    while (line_index < height) : (line_index += 1) {
        const parts = try js.array(engine);
        defer engine.freeValue(parts);
        index = 0;
        while (index < try v.numberField(engine, cells, "length")) : (index += 1) {
            const cell_lines = try v.fieldAt(engine, cells, index);
            defer engine.freeValue(cell_lines);
            const maybe_text = try v.fieldAt(engine, cell_lines, line_index);
            defer engine.freeValue(maybe_text);
            const text = if (v.truthy(engine, maybe_text)) c.JS_DupValue(engine.context, maybe_text) else try empty(engine);
            defer engine.freeValue(text);
            const padding = try repeat(engine, " ", v.maximum(0, widths[@intFromFloat(index)] - try v.width(engine, text)));
            defer engine.freeValue(padding);
            const padded = try concat(engine, &.{ text, padding });
            defer engine.freeValue(padded);
            try append(engine, parts, if (header) try theme(engine, object, "bold", &.{padded}) else c.JS_DupValue(engine.context, padded));
        }
        const joined = try js.invoke(engine, parts, "join", &.{separator});
        defer engine.freeValue(joined);
        try append(engine, output, try concat(engine, &.{ left, joined, right }));
    }
}
fn renderTable(engine: *Engine, object: c.JSValue, token: c.JSValue, width_value: c.JSValue, next: c.JSValue, context: c.JSValue) !c.JSValue {
    const lines = try js.array(engine);
    errdefer engine.freeValue(lines);
    const header = try js.get(engine, token, "header");
    defer engine.freeValue(header);
    const count: usize = @intFromFloat(try v.numberField(engine, header, "length"));
    if (count == 0) return lines;
    if (count > 4096) return error.NativeMarkdownTableShape;
    const width = try v.number(engine, width_value);
    const overhead: f64 = @floatFromInt(3 * count + 1);
    const available = width - overhead;
    if (available < @as(f64, @floatFromInt(count))) {
        const raw = try js.get(engine, token, "raw");
        defer engine.freeValue(raw);
        if (v.truthy(engine, raw)) {
            const fallback = try wrap(engine, raw, width);
            defer engine.freeValue(fallback);
            try extend(engine, lines, fallback);
        }
        if (try spacing(engine, next, false)) try append(engine, lines, try empty(engine));
        return lines;
    }
    const natural = try engine.gpa.alloc(f64, count);
    defer engine.gpa.free(natural);
    const words = try engine.gpa.alloc(f64, count);
    defer engine.gpa.free(words);
    const minimum = try engine.gpa.alloc(f64, count);
    defer engine.gpa.free(minimum);
    const widths = try engine.gpa.alloc(f64, count);
    defer engine.gpa.free(widths);
    for (0..count) |index| {
        const cell = try v.fieldAt(engine, header, @floatFromInt(index));
        defer engine.freeValue(cell);
        const text = try cellText(engine, object, cell, context);
        defer engine.freeValue(text);
        natural[index] = try v.width(engine, text);
        const longest = try js.invoke(engine, object, "getLongestWordWidth", &.{ text, v.numeric(engine, 30) });
        defer engine.freeValue(longest);
        words[index] = v.maximum(1, try v.number(engine, longest));
    }
    const rows = try js.get(engine, token, "rows");
    defer engine.freeValue(rows);
    var row_index: f64 = 0;
    while (row_index < try v.numberField(engine, rows, "length")) : (row_index += 1) {
        const row = try v.fieldAt(engine, rows, row_index);
        defer engine.freeValue(row);
        var col: f64 = 0;
        while (col < try v.numberField(engine, row, "length")) : (col += 1) {
            const index: usize = @intFromFloat(col);
            if (index >= count) return error.NativeMarkdownTableShape;
            const cell = try v.fieldAt(engine, row, col);
            defer engine.freeValue(cell);
            const text = try cellText(engine, object, cell, context);
            defer engine.freeValue(text);
            natural[index] = v.maximum(natural[index], try v.width(engine, text));
            const longest = try js.invoke(engine, object, "getLongestWordWidth", &.{ text, v.numeric(engine, 30) });
            defer engine.freeValue(longest);
            words[index] = v.maximum(words[index], try v.number(engine, longest));
        }
    }
    @memcpy(minimum, words);
    var sum_min: f64 = 0;
    for (minimum) |value| sum_min += value;
    if (sum_min > available) {
        @memset(minimum, 1);
        const remaining = available - @as(f64, @floatFromInt(count));
        if (remaining > 0) {
            var total_weight: f64 = 0;
            for (words) |value| total_weight += v.maximum(0, value - 1);
            var allocated: f64 = 0;
            for (words, minimum) |word, *slot| {
                const growth = if (total_weight > 0) @floor(v.maximum(0, word - 1) / total_weight * remaining) else 0;
                slot.* += growth;
                allocated += growth;
            }
            var leftover = remaining - allocated;
            for (minimum) |*slot| {
                if (leftover <= 0) break;
                slot.* += 1;
                leftover -= 1;
            }
        }
        sum_min = 0;
        for (minimum) |value| sum_min += value;
    }
    var sum_natural: f64 = overhead;
    for (natural) |value| sum_natural += value;
    if (sum_natural <= width) {
        for (widths, natural, minimum) |*slot, value, min| slot.* = v.maximum(value, min);
    } else {
        var potential: f64 = 0;
        for (natural, minimum) |value, min| potential += v.maximum(0, value - min);
        const extra = v.maximum(0, available - sum_min);
        for (widths, natural, minimum) |*slot, value, min| slot.* = min + if (potential > 0) @floor(v.maximum(0, value - min) / potential * extra) else 0;
        var allocated: f64 = 0;
        for (widths) |value| allocated += value;
        var remaining = available - allocated;
        while (remaining > 0) {
            var grew = false;
            for (widths, natural) |*slot, max| {
                if (remaining <= 0) break;
                if (slot.* < max) {
                    slot.* += 1;
                    remaining -= 1;
                    grew = true;
                }
            }
            if (!grew) break;
        }
    }
    try append(engine, lines, try border(engine, widths, "┌─", "─┬─", "─┐"));
    try tableRow(engine, object, header, widths, context, true, lines);
    const separator = try border(engine, widths, "├─", "─┼─", "─┤");
    defer engine.freeValue(separator);
    try js.push(engine, lines, separator);
    row_index = 0;
    while (row_index < try v.numberField(engine, rows, "length")) : (row_index += 1) {
        const row = try v.fieldAt(engine, rows, row_index);
        defer engine.freeValue(row);
        try tableRow(engine, object, row, widths, context, false, lines);
        if (row_index < try v.numberField(engine, rows, "length") - 1) try js.push(engine, lines, separator);
    }
    try append(engine, lines, try border(engine, widths, "└─", "─┴─", "─┘"));
    if (try spacing(engine, next, false)) try append(engine, lines, try empty(engine));
    return lines;
}
fn cache(engine: *Engine, object: c.JSValue, width: c.JSValue, lines: c.JSValue) !void {
    try v.set(engine, object, "cachedText", try js.get(engine, object, "text"));
    try v.set(engine, object, "cachedWidth", c.JS_DupValue(engine.context, width));
    try v.set(engine, object, "cachedLines", c.JS_DupValue(engine.context, lines));
}
fn render(engine: *Engine, object: c.JSValue, width_value: c.JSValue, helpers: c.JSValue, iterator: c.JSValue) !c.JSValue {
    const cached = try js.get(engine, object, "cachedLines");
    defer engine.freeValue(cached);
    if (v.truthy(engine, cached)) {
        const cached_text = try js.get(engine, object, "cachedText");
        defer engine.freeValue(cached_text);
        const text = try js.get(engine, object, "text");
        defer engine.freeValue(text);
        if (c.JS_IsStrictEqual(engine.context, cached_text, text)) {
            const cached_width = try js.get(engine, object, "cachedWidth");
            defer engine.freeValue(cached_width);
            if (c.JS_IsStrictEqual(engine.context, cached_width, width_value)) return js.get(engine, object, "cachedLines");
        }
    }
    const content_width = v.maximum(1, try v.number(engine, width_value) - try v.numberField(engine, object, "paddingX") * 2);
    const options = try js.get(engine, object, "options");
    defer engine.freeValue(options);
    const transform = try js.get(engine, options, "transform");
    defer engine.freeValue(transform);
    const original = try js.get(engine, object, "text");
    defer engine.freeValue(original);
    const transformed = if (c.JS_IsUndefined(transform) or c.JS_IsNull(transform)) c.JS_DupValue(engine.context, original) else try js.call(engine, transform, options, &.{ original, v.numeric(engine, content_width) });
    defer engine.freeValue(transformed);
    const text = if (c.JS_IsUndefined(transformed) or c.JS_IsNull(transformed)) try js.get(engine, object, "text") else c.JS_DupValue(engine.context, transformed);
    defer engine.freeValue(text);
    var blank = !v.truthy(engine, text);
    if (!blank) {
        const trimmed = try js.invoke(engine, text, "trim", &.{});
        defer engine.freeValue(trimmed);
        const empty_text = try empty(engine);
        defer engine.freeValue(empty_text);
        blank = c.JS_IsStrictEqual(engine.context, trimmed, empty_text);
    }
    if (blank) {
        const result = try js.array(engine);
        errdefer engine.freeValue(result);
        try cache(engine, object, width_value, result);
        return result;
    }
    const units = try utf16.unitsAlloc(engine, text);
    defer engine.gpa.free(units);
    var normalized: std.ArrayList(u16) = .empty;
    defer normalized.deinit(engine.gpa);
    for (units) |unit| if (unit == '\t') {
        try normalized.appendNTimes(engine.gpa, ' ', 3);
    } else try normalized.append(engine.gpa, unit);
    const source = try utf16.string(engine, normalized.items);
    defer engine.freeValue(source);
    const weak = try js.get(engine, object, "cachedTokens");
    defer engine.freeValue(weak);
    const cached_tokens = if (v.truthy(engine, weak)) try js.invoke(engine, weak, "deref", &.{}) else c.pi_js_undefined();
    defer engine.freeValue(cached_tokens);
    const cached_source = if (c.JS_IsUndefined(cached_tokens) or c.JS_IsNull(cached_tokens)) c.pi_js_undefined() else try js.get(engine, cached_tokens, "source");
    defer engine.freeValue(cached_source);
    var tokens = if (c.JS_IsStrictEqual(engine.context, cached_source, source)) try js.get(engine, cached_tokens, "tokens") else c.pi_js_undefined();
    defer engine.freeValue(tokens);
    if (!v.truthy(engine, tokens)) {
        var lexer = try @import("native_markdown_lexer.zig").Lexer.init(engine);
        defer lexer.deinit();
        const fresh = try lexer.lex(normalized.items);
        engine.freeValue(tokens);
        tokens = fresh;
        const holder = try js.object(engine);
        defer engine.freeValue(holder);
        try js.define(engine, holder, "source", c.JS_DupValue(engine.context, source));
        try js.define(engine, holder, "tokens", c.JS_DupValue(engine.context, tokens));
        try v.set(engine, object, "cachedTokens", try js.builtin(engine, "WeakRef", &.{holder}));
    }
    const rendered = try js.array(engine);
    defer engine.freeValue(rendered);
    var index: f64 = 0;
    while (index < try v.numberField(engine, tokens, "length")) : (index += 1) {
        const token = try v.fieldAt(engine, tokens, index);
        defer engine.freeValue(token);
        const following = try v.fieldAt(engine, tokens, index + 1);
        defer engine.freeValue(following);
        const next = if (c.JS_IsUndefined(following) or c.JS_IsNull(following)) c.pi_js_undefined() else try js.get(engine, following, "type");
        defer engine.freeValue(next);
        const lines = try js.invoke(engine, object, "renderToken", &.{ token, v.numeric(engine, content_width), next });
        defer engine.freeValue(lines);
        try extend(engine, rendered, lines);
    }
    const wrapped = try js.array(engine);
    defer engine.freeValue(wrapped);
    index = 0;
    while (index < try v.numberField(engine, rendered, "length")) : (index += 1) {
        const line = try v.fieldAt(engine, rendered, index);
        defer engine.freeValue(line);
        const image = try js.invoke(engine, helpers, "isImageLine", &.{line});
        defer engine.freeValue(image);
        if (v.truthy(engine, image)) try js.push(engine, wrapped, line) else {
            const pieces = try wrap(engine, line, content_width);
            defer engine.freeValue(pieces);
            try extend(engine, wrapped, pieces);
        }
    }
    const left = try repeat(engine, " ", try v.numberField(engine, object, "paddingX"));
    defer engine.freeValue(left);
    const right = try repeat(engine, " ", try v.numberField(engine, object, "paddingX"));
    defer engine.freeValue(right);
    const default_style = try js.get(engine, object, "defaultTextStyle");
    defer engine.freeValue(default_style);
    const background = if (c.JS_IsUndefined(default_style) or c.JS_IsNull(default_style)) c.pi_js_undefined() else try js.get(engine, default_style, "bgColor");
    defer engine.freeValue(background);
    const content = try js.array(engine);
    defer engine.freeValue(content);
    index = 0;
    while (index < try v.numberField(engine, wrapped, "length")) : (index += 1) {
        const line = try v.fieldAt(engine, wrapped, index);
        defer engine.freeValue(line);
        const image = try js.invoke(engine, helpers, "isImageLine", &.{line});
        defer engine.freeValue(image);
        if (v.truthy(engine, image)) {
            try js.push(engine, content, line);
            continue;
        }
        const margins = try concat(engine, &.{ left, line, right });
        defer engine.freeValue(margins);
        const padding = try repeat(engine, " ", v.maximum(0, try v.number(engine, width_value) - try v.width(engine, margins)));
        defer engine.freeValue(padding);
        const padded = try concat(engine, &.{ margins, padding });
        defer engine.freeValue(padded);
        try append(engine, content, if (v.truthy(engine, background)) try js.call(engine, background, c.pi_js_undefined(), &.{padded}) else c.JS_DupValue(engine.context, padded));
    }
    const empty_line = try repeat(engine, " ", try v.number(engine, width_value));
    defer engine.freeValue(empty_line);
    const empty_lines = try js.array(engine);
    defer engine.freeValue(empty_lines);
    index = 0;
    while (index < try v.numberField(engine, object, "paddingY")) : (index += 1) {
        if (index >= 4096) return error.NativeComponentFrameLimit;
        try append(engine, empty_lines, if (v.truthy(engine, background)) try js.call(engine, background, c.pi_js_undefined(), &.{empty_line}) else c.JS_DupValue(engine.context, empty_line));
    }
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    for ([_]c.JSValue{ empty_lines, content, empty_lines }) |part| try extend(engine, result, part);
    try @import("native_text_component.zig").flattenLines(engine, result, iterator);
    try cache(engine, object, width_value, result);
    if (try v.numberField(engine, result, "length") == 0) {
        const fallback = try js.array(engine);
        errdefer engine.freeValue(fallback);
        try append(engine, fallback, try empty(engine));
        engine.freeValue(result);
        return fallback;
    }
    return result;
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return method(engine, object, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)], data[0], data[1]) catch |err| fail(engine, err);
}
fn method(engine: *Engine, object: c.JSValue, operation: Method, args: []const c.JSValue, helpers: c.JSValue, iterator: c.JSValue) !c.JSValue {
    switch (operation) {
        .setText => {
            try v.set(engine, object, "text", c.JS_DupValue(engine.context, v.arg(args, 0)));
            try v.invokeVoid(engine, object, "invalidate", &.{});
        },
        .invalidate => inline for (.{ "cachedText", "cachedWidth", "cachedLines" }) |name| try v.set(engine, object, name, c.pi_js_undefined()),
        .render => return render(engine, object, v.arg(args, 0), helpers, iterator),
        .applyDefaultStyle => return defaultStyle(engine, object, v.arg(args, 0)),
        .getDefaultStylePrefix => {
            const style = try js.get(engine, object, "defaultTextStyle");
            defer engine.freeValue(style);
            if (!v.truthy(engine, style)) return empty(engine);
            const cached = try js.get(engine, object, "defaultStylePrefix");
            defer engine.freeValue(cached);
            if (!c.JS_IsUndefined(cached)) return c.JS_DupValue(engine.context, cached);
            const sentinel = try v.text(engine, "\x00");
            defer engine.freeValue(sentinel);
            const styled = try defaultStyle(engine, object, sentinel);
            defer engine.freeValue(styled);
            const at = try js.invoke(engine, styled, "indexOf", &.{sentinel});
            defer engine.freeValue(at);
            const prefix = if (try v.number(engine, at) >= 0) try js.invoke(engine, styled, "slice", &.{ v.numeric(engine, 0), at }) else try empty(engine);
            errdefer engine.freeValue(prefix);
            try v.set(engine, object, "defaultStylePrefix", c.JS_DupValue(engine.context, prefix));
            return prefix;
        },
        .getStylePrefix => return stylePrefix(engine, v.arg(args, 0)),
        .getDefaultInlineStyleContext => return contextValue(engine, object, .default_style),
        .renderInlineTokens => return inlineTokens(engine, object, v.arg(args, 0), v.arg(args, 1), helpers, iterator),
        .renderToken => return renderToken(engine, object, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2), v.arg(args, 3), iterator),
        .renderList => return renderList(engine, object, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2), v.arg(args, 3), iterator),
        .renderTable => return renderTable(engine, object, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2), v.arg(args, 3)),
        .getOrderedListMarker, .getUnorderedListMarker => {
            const raw = try js.get(engine, v.arg(args, 0), "raw");
            defer engine.freeValue(raw);
            const units = try utf16.unitsAlloc(engine, raw);
            defer engine.gpa.free(units);
            var grammar = try @import("native_markdown_regex.zig").Grammar.init(engine);
            defer grammar.deinit();
            var matched = try grammar.match(if (operation == .getOrderedListMarker) "^(?: {0,3})(\\d{1,9}[.)])[ \\t]+" else "^(?: {0,3})([-+*])(?:[ \\t]+|(?=\\r?\\n|$))", "", units, 0);
            if (matched) |*cap| {
                defer cap.deinit();
                const marker = try utf16.string(engine, cap.group(units, 1));
                defer engine.freeValue(marker);
                const space = try v.text(engine, " ");
                defer engine.freeValue(space);
                return concat(engine, &.{ marker, space });
            }
        },
        .getLongestWordWidth => {
            const source = try utf16.unitsAlloc(engine, v.arg(args, 0));
            defer engine.gpa.free(source);
            var longest: f64 = 0;
            var start: usize = 0;
            for (source, 0..) |unit, at| if (@import("../tui/utf16_input.zig").State.whitespace(unit)) {
                if (at > start) {
                    const word = try utf16.string(engine, source[start..at]);
                    defer engine.freeValue(word);
                    longest = v.maximum(longest, try v.width(engine, word));
                }
                start = at + 1;
            };
            if (start < source.len) {
                const word = try utf16.string(engine, source[start..]);
                defer engine.freeValue(word);
                longest = v.maximum(longest, try v.width(engine, word));
            }
            return v.numeric(engine, if (c.JS_IsUndefined(v.arg(args, 1))) longest else v.minimum(longest, try v.number(engine, v.arg(args, 1))));
        },
        .wrapCellText => {
            const lines = try wrap(engine, v.arg(args, 0), v.maximum(1, try v.number(engine, v.arg(args, 1))));
            defer engine.freeValue(lines);
            const prefix = if (c.JS_IsUndefined(v.arg(args, 2))) try empty(engine) else c.JS_DupValue(engine.context, v.arg(args, 2));
            defer engine.freeValue(prefix);
            const result = try js.array(engine);
            errdefer engine.freeValue(result);
            var index: f64 = 0;
            while (index < try v.numberField(engine, lines, "length")) : (index += 1) {
                const line = try v.fieldAt(engine, lines, index);
                defer engine.freeValue(line);
                const reset = try v.text(engine, if (index < try v.numberField(engine, lines, "length") - 1) "\x1b[22;23;24;25;27;28;29;39m" else "");
                defer engine.freeValue(reset);
                try append(engine, result, try concat(engine, &.{ line, reset, prefix }));
            }
            return result;
        },
    }
    return c.pi_js_undefined();
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    inline for (.{ "text", "paddingX", "paddingY", "defaultTextStyle", "theme", "options", "defaultStylePrefix", "cachedText", "cachedWidth", "cachedLines", "cachedTokens" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    inline for (.{ .{ "text", 0 }, .{ "paddingX", 1 }, .{ "paddingY", 2 }, .{ "theme", 3 }, .{ "defaultTextStyle", 4 } }) |field| try v.set(engine, object, field[0], c.JS_DupValue(engine.context, v.arg(args, field[1])));
    try v.set(engine, object, "options", if (v.truthy(engine, v.arg(args, 5))) try js.spread(engine, v.arg(args, 5)) else try js.object(engine));
    return object;
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    const iterator = try js.get(engine, symbol, "iterator");
    defer engine.freeValue(iterator);
    inline for (std.meta.fields(Method)) |field| {
        const operation: Method = @enumFromInt(field.value);
        const name: [:0]const u8 = field.name;
        const arity: c_int = switch (operation) {
            .invalidate, .getDefaultStylePrefix, .getDefaultInlineStyleContext => 0,
            .renderToken, .renderList, .renderTable => 4,
            .renderInlineTokens, .getLongestWordWidth, .wrapCellText => 2,
            else => 1,
        };
        var data = [_]c.JSValue{ exports, iterator };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, arity, @intCast(field.value), 2, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try js.define(engine, exports, "Markdown", try @import("native_class.zig").constructor(engine, "Markdown", 6, prototype, construct, &.{}));
}
test "Source6fb native Markdown component original layouts callbacks cache and public shape" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const exports = try js.object(engine);
    defer engine.freeValue(exports);
    try @import("native_terminal_image.zig").install(engine, exports);
    try install(engine, exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "Markdown", try js.get(engine, exports, "Markdown"));
    try js.define(engine, global, "setCapabilities", try js.get(engine, exports, "setCapabilities"));
    const bytes = @embedFile("fixtures/markdown-component-original-6fb.json");
    try js.define(engine, global, "markdownFixture", try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "markdown-component-original-6fb.json")));
    const source_tests = @embedFile("fixtures/markdown-source-tests-original-6fb.json");
    try js.define(engine, global, "markdownSourceTests", try engine.checked(c.JS_ParseJSON(engine.context, source_tests.ptr, source_tests.len, "markdown-source-tests-original-6fb.json")));
    const adversarial = @embedFile("fixtures/markdown-adversarial-original-6fb.json");
    try js.define(engine, global, "markdownAdversarial", try engine.checked(c.JS_ParseJSON(engine.context, adversarial.ptr, adversarial.len, "markdown-adversarial-original-6fb.json")));
    const callbacks = @embedFile("fixtures/markdown-callbacks-original-6fb.json");
    try js.define(engine, global, "markdownCallbacks", try engine.checked(c.JS_ParseJSON(engine.context, callbacks.ptr, callbacks.len, "markdown-callbacks-original-6fb.json")));
    const result = engine.evalModule(
        \\const names=['heading','link','linkUrl','code','codeBlock','codeBlockBorder','quote','quoteBorder','hr','listBullet','bold','italic','strikethrough','underline'],codes=[36,34,90,33,32,90,3,90,90,36,1,3,9,4];for(const[index,item]of markdownFixture.cases.entries()){setCapabilities({images:null,trueColor:true,hyperlinks:item.hyperlinks});const calls=[],theme=Object.fromEntries(names.map((name,i)=>[name,function(text){calls.push({name,text,receiver:this===theme});return '\x1b['+codes[i]+'m'+text+'\x1b[0m'}])),instance=new Markdown(item.text,item.paddingX,item.paddingY,theme,undefined,item.options),lines=instance.render(item.width),actual={lines,calls,same:instance.render(item.width)===lines},expected={lines:item.lines,calls:item.calls,same:item.same};if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index,text:item.text,actual,expected}));}
        \\for(const[index,item]of markdownSourceTests.cases.entries()){if(item.calls.length===0)continue;setCapabilities({images:null,trueColor:true,hyperlinks:item.hyperlinks});let at=0;const theme={...item.themeProps},style=item.hasDefaultStyle?{...item.styleProps}:undefined,options={...item.options},callback=name=>function(...args){const expected=item.calls[at++];if(!expected||expected.name!==name||JSON.stringify(args)!==JSON.stringify(expected.args))throw Error(JSON.stringify({sourceTest:index,text:item.text,callback:at-1,name,args,expected}));return expected.result};for(const name of new Set([...names,...item.calls.map(c=>c.name).filter(n=>!n.includes(':'))]))theme[name]=callback(name);for(const name of new Set(item.calls.map(c=>c.name).filter(n=>n.includes(':')))){if(name.startsWith('style:'))style[name.slice(6)]=callback(name);else if(name==='option:transform')options.transform=callback(name)}const instance=new Markdown(item.text,item.paddingX,item.paddingY,theme,style,options),actual=instance.render(item.width);if(JSON.stringify(actual)!==JSON.stringify(item.lines)||at!==item.calls.length)throw Error(JSON.stringify({sourceTest:index,text:item.text,actual,expected:item.lines,at,calls:item.calls.length}));}
        \\setCapabilities({images:null,trueColor:true,hyperlinks:false});for(const[index,item]of markdownAdversarial.cases.entries()){const calls=[],theme=Object.fromEntries(names.map(name=>[name,function(text){calls.push({name,text,receiver:this===theme});return text}])),instance=new Markdown(item.text,0,0,theme),lines=instance.render(80);if(JSON.stringify(lines)!==JSON.stringify(item.lines)||JSON.stringify(calls)!==JSON.stringify(item.calls))throw Error(JSON.stringify({adversarial:index,text:item.text,lines,calls,expected:item}));}
        \\const identityTheme=Object.fromEntries(names.map(name=>[name,text=>text]));for(const[index,item]of [...markdownFixture.structural,...markdownCallbacks.cases].entries()){let actual;try{actual=new Function('Markdown','identityTheme','"use strict";'+item.script)(Markdown,identityTheme)}catch(e){if(e.name===item.errorName&&e.message===item.errorMessage)continue;throw e}if(item.errorName||JSON.stringify(actual)!==JSON.stringify(item.result))throw Error(JSON.stringify({structural:index,actual,expected:item}));}const shape={name:Markdown.name,length:Markdown.length,own:Object.keys(new Markdown('',0,0,identityTheme)),methods:Object.fromEntries(Object.getOwnPropertyNames(Markdown.prototype).filter(k=>k!=='constructor').map(k=>[k,{name:Markdown.prototype[k].name,length:Markdown.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(Markdown.prototype,k).enumerable}]))};if(JSON.stringify(shape)!==JSON.stringify(markdownFixture.shape))throw Error(JSON.stringify({shape,expected:markdownFixture.shape}));
    , "native-markdown-component-original.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native Markdown component: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const exports = try js.object(engine);
    defer engine.freeValue(exports);
    try @import("native_terminal_image.zig").install(engine, exports);
    try install(engine, exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "Markdown", try js.get(engine, exports, "Markdown"));
    try js.define(engine, root, "setCapabilities", try js.get(engine, exports, "setCapabilities"));
    const original_allocator = engine.gpa;
    engine.gpa = gpa;
    defer engine.gpa = original_allocator;
    defer engine.beginInvocation();
    const result = engine.eval(
        \\(()=>{setCapabilities({images:null,trueColor:true,hyperlinks:true});const names=['heading','link','linkUrl','code','codeBlock','codeBlockBorder','quote','quoteBorder','hr','listBullet','bold','italic','strikethrough','underline'],theme=Object.fromEntries(names.map(name=>[name,text=>'\x1b[1m'+text+'\x1b[0m'])),text='# Heading\n\n> words **bold**\n\n- [x] first\n  - child\n\n| A | B |\n| - | - |\n| long words | 界😀 |\n\n[link](/target) $x^2$\n\n```js\nvalue\n``',md=new Markdown(text,1,1,theme,{color:text=>'FG('+text+')',bgColor:text=>'BG('+text+')',bold:true});const first=md.render(24);if(first!==md.render(24))throw Error('render cache identity');const tree=md.cachedTokens.deref();md.invalidate();md.render(16);if(md.cachedTokens.deref()!==tree)throw Error('weak token burst identity');md.setText('next');md.render(10);return true})()
    , "markdown-owned-allocation.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return @import("native_text_component.zig").allocationError(engine, err);
    engine.freeValue(result);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "Source6fb native Markdown all allocation failures release token graphs callbacks and weak holders" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
