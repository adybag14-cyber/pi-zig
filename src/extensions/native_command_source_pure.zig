//! Pure original Combined prefix/completion bodies, extracted independently
//! from preserved694. No fd, filesystem, process or full class installation.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
fn boundary(f: *Frame, text: c.JSValue) !bool {
    return f.truth(try f.method(try f.get(f.bindings, "tokenStartRegex"), "test", &.{text}));
}
fn tokenStart(f: *Frame, text: c.JSValue, index: f64) !bool {
    var start = index;
    const wrappers = try f.get(f.bindings, "pathWrappers");
    while (start > 0 and f.truth(try f.own(try js.getKey(f.engine, wrappers, try f.at(text, start - 1))))) start -= 1;
    const previous = try f.at(text, start - 1);
    if (f.truth(try f.method(try f.get(f.bindings, "pathDelimiters"), "has", &.{if (f.nullish(previous)) try f.text("") else previous}))) return true;
    return boundary(f, try f.method(text, "slice", &.{ f.num(0), f.num(start) }));
}
fn quotedPrefix(f: *Frame, text: c.JSValue) !c.JSValue {
    var in_quotes = false;
    var quote_start: f64 = -1;
    var index: f64 = 0;
    while (index < try f.n(text, "length")) : (index += 1) {
        if (try f.is(try f.at(text, index), "\"")) {
            in_quotes = !in_quotes;
            if (in_quotes) quote_start = index;
        }
    }
    if (!in_quotes) return c.pi_js_null();
    if (quote_start > 0 and try f.is(try f.at(text, quote_start - 1), "@")) {
        if (!try tokenStart(f, text, quote_start - 1)) return c.pi_js_null();
        return f.method(text, "slice", &.{f.num(quote_start - 1)});
    }
    if (!try tokenStart(f, text, quote_start)) return c.pi_js_null();
    return f.method(text, "slice", &.{f.num(quote_start)});
}
fn lastDelimiter(f: *Frame, text: c.JSValue) !f64 {
    var last: f64 = -1;
    var index: c.JSValue = f.num(0);
    var iterator = try js.Iterator.init(f.engine, text, try f.get(f.bindings, "iteratorSymbol"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |character| {
        defer f.engine.freeValue(character);
        index = try f.add(index, try f.get(character, "length"));
        if (f.truth(try f.method(try f.get(f.bindings, "pathDelimiters"), "has", &.{character})) or f.truth(try f.method(try f.get(f.bindings, "separatorRegex"), "test", &.{character}))) last = try f.number(index) - 1;
    }
    return last;
}
fn stripWrappers(f: *Frame, token: c.JSValue) !c.JSValue {
    var value = token;
    while (try f.n(value, "length") > 0) {
        const closer = try f.own(try js.getKey(f.engine, try f.get(f.bindings, "pathWrappers"), try f.at(value, 0)));
        if (!f.truth(closer) or f.truth(try f.method(value, "includes", &.{ closer, f.num(1) }))) break;
        value = try f.method(value, "slice", &.{f.num(1)});
    }
    return value;
}
pub fn prefix(f: *Frame, args: []const c.JSValue, at: bool) !c.JSValue {
    const text = a.v.arg(args, 0);
    const quoted = try quotedPrefix(f, text);
    if (at) {
        if (!f.nullish(quoted) and try has(f, quoted, "startsWith", "@\"")) return quoted;
    } else if (f.truth(quoted)) return quoted;
    const delimiter = try lastDelimiter(f, text);
    const value = try stripWrappers(f, if (delimiter == -1) text else try f.method(text, "slice", &.{f.num(delimiter + 1)}));
    if (at) return if (try has(f, value, "startsWith", "@")) value else c.pi_js_null();
    const force = a.v.arg(args, 1);
    if (!c.JS_IsUndefined(force) and f.truth(force)) return value;
    if (try has(f, value, "includes", "/") or try has(f, value, "startsWith", ".") or try has(f, value, "startsWith", "~/")) return value;
    if (try f.is(value, "") and !try f.is(text, "") and try boundary(f, text)) return value;
    return c.pi_js_null();
}
fn currentLine(f: *Frame, lines: c.JSValue, row: c.JSValue) !c.JSValue {
    const value = try f.own(try js.getKey(f.engine, lines, row));
    return if (f.truth(value)) value else f.text("");
}
fn has(f: *Frame, text: c.JSValue, method: [*:0]const u8, wanted: []const u8) !bool {
    return f.truth(try f.method(text, method, &.{try f.text(wanted)}));
}
fn result(f: *Frame, lines: c.JSValue, row: c.JSValue, col: c.JSValue) !c.JSValue {
    const value = try f.record();
    try f.define(value, "lines", lines);
    try f.define(value, "cursorLine", row);
    try f.define(value, "cursorCol", col);
    return value;
}
fn changed(f: *Frame, lines: c.JSValue, row: c.JSValue, value: c.JSValue) !c.JSValue {
    const copy = try f.copy(lines);
    try js.setKey(f.engine, copy, row, value);
    return copy;
}
fn cursorOffset(f: *Frame, item: c.JSValue, directory: bool, quoted: bool) !c.JSValue {
    const length = try f.get(try f.get(item, "value"), "length");
    return if (directory and quoted) f.num(try f.number(length) - 1) else length;
}
pub fn applyCompletion(f: *Frame, args: []const c.JSValue) anyerror!c.JSValue {
    const lines = a.v.arg(args, 0);
    const row = a.v.arg(args, 1);
    const col = a.v.arg(args, 2);
    const item = a.v.arg(args, 3);
    const completion_prefix = a.v.arg(args, 4);
    const line = try currentLine(f, lines, row);
    const slice = try f.get(line, "slice");
    const prefix_length = try f.get(completion_prefix, "length");
    const before = try f.call(slice, line, &.{ f.num(0), f.num(try f.number(col) - try f.number(prefix_length)) });
    const after = try f.method(line, "slice", &.{col});
    const quoted = try has(f, completion_prefix, "startsWith", "\"") or try has(f, completion_prefix, "startsWith", "@\"");
    const leading = try has(f, after, "startsWith", "\"");
    const trailing = try has(f, try f.get(item, "value"), "endsWith", "\"");
    const adjusted = if (quoted and trailing and leading) try f.method(after, "slice", &.{f.num(1)}) else after;
    const slash = try has(f, completion_prefix, "startsWith", "/") and try f.is(try f.method(before, "trim", &.{}), "") and !try has(f, try f.method(completion_prefix, "slice", &.{f.num(1)}), "includes", "/");
    if (slash) {
        const next = try f.concat(&.{ before, try f.text("/"), try f.get(item, "value"), try f.text(" "), adjusted });
        const copy = try changed(f, lines, row, next);
        const cursor = try f.add(try f.add(try f.get(before, "length"), try f.get(try f.get(item, "value"), "length")), f.num(2));
        return result(f, copy, row, cursor);
    }
    if (try has(f, completion_prefix, "startsWith", "@")) {
        const directory = try has(f, try f.get(item, "label"), "endsWith", "/");
        const suffix = try f.text(if (directory) "" else " ");
        const next = try f.concat(&.{ try f.add(before, try f.get(item, "value")), suffix, adjusted });
        const copy = try changed(f, lines, row, next);
        const has_quote = try has(f, try f.get(item, "value"), "endsWith", "\"");
        const offset = try cursorOffset(f, item, directory, has_quote);
        const cursor = try f.add(try f.add(try f.get(before, "length"), offset), try f.get(suffix, "length"));
        return result(f, copy, row, cursor);
    }
    const text_before = try f.method(line, "slice", &.{ f.num(0), col });
    if (try has(f, text_before, "includes", "/") and try has(f, text_before, "includes", " ")) {
        const next = try f.add(try f.add(before, try f.get(item, "value")), adjusted);
        const copy = try changed(f, lines, row, next);
        const directory = try has(f, try f.get(item, "label"), "endsWith", "/");
        const has_quote = try has(f, try f.get(item, "value"), "endsWith", "\"");
        return result(f, copy, row, try f.add(try f.get(before, "length"), try cursorOffset(f, item, directory, has_quote)));
    }
    const next = try f.add(try f.add(before, try f.get(item, "value")), adjusted);
    const copy = try changed(f, lines, row, next);
    const directory = try has(f, try f.get(item, "label"), "endsWith", "/");
    const has_quote = try has(f, try f.get(item, "value"), "endsWith", "\"");
    return result(f, copy, row, try f.add(try f.get(before, "length"), try cursorOffset(f, item, directory, has_quote)));
}
pub fn trigger(f: *Frame, args: []const c.JSValue) !c.JSValue {
    const line = try currentLine(f, a.v.arg(args, 0), a.v.arg(args, 1));
    const text = try f.method(line, "slice", &.{ f.num(0), a.v.arg(args, 2) });
    if (try has(f, try f.method(text, "trim", &.{}), "startsWith", "/") and !try has(f, try f.method(text, "trim", &.{}), "includes", " ")) return f.boolean(false);
    return f.boolean(true);
}
fn displayPath(f: *Frame, text: c.JSValue) !c.JSValue {
    return f.method(text, "replace", &.{ try f.get(f.bindings, "backslashRegex"), try f.text("/") });
}
pub fn scopedDisplay(f: *Frame, args: []const c.JSValue) !c.JSValue {
    const base = a.v.arg(args, 0);
    const relative = try displayPath(f, a.v.arg(args, 1));
    if (try f.is(base, "/")) return f.concat(&.{ try f.text("/"), relative });
    return f.concat(&.{ try displayPath(f, base), relative });
}

pub fn initialize(engine: *js.Engine, bindings: c.JSValue) !void {
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    inline for (.{ .{ "iteratorSymbol", "iterator" }, .{ "primitiveSymbol", "toPrimitive" } }) |item| try js.define(engine, bindings, item[0], try js.get(engine, symbol, item[1]));
    var f: Frame = .{ .engine = engine, .object = bindings, .bindings = bindings };
    defer f.deinit();
    try f.define(bindings, "typeErrorConstructor", try f.global("TypeError"));
    const delimiters = try f.literal(&.{ try f.text(" "), try f.text("\t"), try f.text("\""), try f.text("'"), try f.text("=") });
    try f.define(bindings, "pathDelimiters", try f.construct(try f.global("Set"), &.{delimiters}));
    const wrappers = try f.record();
    inline for (.{ .{ "(", ")" }, .{ "[", "]" }, .{ "{", "}" }, .{ "<", ">" }, .{ "`", "`" } }) |item| try f.define(wrappers, item[0], try f.text(item[1]));
    try f.define(bindings, "pathWrappers", wrappers);
    const separator = "(?:\\s|(?:(?=\\p{Punctuation})[\\p{Script_Extensions=Han}\\p{Script_Extensions=Hiragana}\\p{Script_Extensions=Katakana}\\p{Script_Extensions=Hangul}\\p{Script_Extensions=Bopomofo}]|[，．：；！？（）［］｛｝“”‘’…—]))";
    try js.define(engine, bindings, "separatorRegex", try @import("native_tui_base_utilities.zig").regexp(engine, separator, "u"));
    try js.define(engine, bindings, "tokenStartRegex", try @import("native_tui_base_utilities.zig").regexp(engine, "(?:^|" ++ separator ++ ")$", "u"));
    try js.define(engine, bindings, "backslashRegex", try @import("native_tui_base_utilities.zig").regexp(engine, "\\\\", "g"));
}
