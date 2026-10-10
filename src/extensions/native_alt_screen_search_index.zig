//! Native Source transcript corpus, cell spans and ordinary mutable search cache.
//! Grapheme boundaries use the existing Unicode17 native engine; case-insensitive
//! Unicode matching is delegated to the embedded ECMAScript RegExp engine.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const graphemes = @import("../tui/utf16_graphemes.zig");
const arithmetic = @import("native_tui_value_arithmetic.zig");
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native alternate-screen search: %s", @as([*:0]const u8, @errorName(err)));
}
fn imported(engine: *js.Engine, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try js.get(engine, bindings, name);
    defer engine.freeValue(function);
    return js.call(engine, function, c.pi_js_undefined(), args);
}
fn pattern(engine: *js.Engine, source: []const u8, flags: []const u8) !c.JSValue {
    return @import("native_editor_values.zig").literalPattern(engine, source, flags);
}
const Corpus = struct {
    engine: *js.Engine,
    bindings: c.JSValue,
    chunks: c.JSValue,
    spans: c.JSValue,
    text_length: f64 = 0,
    pending_separator: bool = false,
    fn separator(self: *Corpus) !void {
        if (!self.pending_separator) return;
        const space = try v.text(self.engine, " ");
        defer self.engine.freeValue(space);
        try js.push(self.engine, self.chunks, space);
        self.text_length += 1;
        self.pending_separator = false;
    }
    fn append(self: *Corpus, text: c.JSValue, row: f64, column: f64, width: f64, linear: bool) !void {
        const engine = self.engine;
        try self.separator();
        try js.push(engine, self.chunks, text);
        const length = try v.numberField(engine, text, "length");
        const span = try js.object(engine);
        defer engine.freeValue(span);
        try js.define(engine, span, "textStart", v.numeric(engine, self.text_length));
        try js.define(engine, span, "textEnd", v.numeric(engine, self.text_length + length));
        try js.define(engine, span, "row", v.numeric(engine, row));
        try js.define(engine, span, "startCol", v.numeric(engine, column));
        try js.define(engine, span, "endCol", v.numeric(engine, column + width));
        try js.define(engine, span, "linearColumns", c.pi_js_bool(engine.context, @intFromBool(linear)));
        try js.push(engine, self.spans, span);
        self.text_length += length;
    }
};
fn code(engine: *js.Engine, line: c.JSValue, offset: f64) !f64 {
    const value = try js.invoke(engine, line, "charCodeAt", &.{v.numeric(engine, offset)});
    defer engine.freeValue(value);
    return v.number(engine, value);
}
fn buildCorpus(engine: *js.Engine, bindings: c.JSValue, lines: c.JSValue) !c.JSValue {
    var corpus: Corpus = .{ .engine = engine, .bindings = bindings, .chunks = try js.array(engine), .spans = undefined };
    defer engine.freeValue(corpus.chunks);
    corpus.spans = try js.array(engine);
    defer engine.freeValue(corpus.spans);
    const ascii = try js.get(engine, bindings, "printableAscii");
    defer engine.freeValue(ascii);
    var row: f64 = 0;
    while (row < try v.numberField(engine, lines, "length")) : (row += 1) {
        const strip = try js.get(engine, bindings, "stripTerminalSequences");
        defer engine.freeValue(strip);
        const raw = try js.getKey(engine, lines, v.numeric(engine, row));
        defer engine.freeValue(raw);
        const input = if (c.JS_IsNull(raw) or c.JS_IsUndefined(raw)) try v.text(engine, "") else c.JS_DupValue(engine.context, raw);
        defer engine.freeValue(input);
        const line = try js.call(engine, strip, c.pi_js_undefined(), &.{input});
        defer engine.freeValue(line);
        var column: f64 = 0;
        const printable = try js.invoke(engine, ascii, "test", &.{line});
        defer engine.freeValue(printable);
        if (v.truthy(engine, printable)) {
            var offset: f64 = 0;
            while (offset < try v.numberField(engine, line, "length")) {
                if (try code(engine, line, offset) == 0x20) {
                    if (corpus.text_length > 0) corpus.pending_separator = true;
                    column += 1;
                    offset += 1;
                    continue;
                }
                var end = offset + 1;
                while (end < try v.numberField(engine, line, "length") and try code(engine, line, end) != 0x20) end += 1;
                // Source appendSeparator precedes even the observable slice.
                try corpus.separator();
                const text = try js.invoke(engine, line, "slice", &.{ v.numeric(engine, offset), v.numeric(engine, end) });
                defer engine.freeValue(text);
                const length = try v.numberField(engine, text, "length");
                try corpus.append(text, row, column, length, true);
                column += length;
                offset = end;
            }
        } else {
            const units = try utf16.unitsAlloc(engine, line);
            defer engine.gpa.free(units);
            var iterator: graphemes.Iterator = .{ .text = units };
            while (iterator.next()) |part| {
                const text = try utf16.string(engine, units[part.start..part.end]);
                defer engine.freeValue(text);
                const width_value = try imported(engine, bindings, "visibleWidth", &.{text});
                defer engine.freeValue(width_value);
                const width = try v.number(engine, width_value);
                const whitespace = try pattern(engine, "^\\s+$", "u");
                defer engine.freeValue(whitespace);
                const blank = try js.invoke(engine, whitespace, "test", &.{text});
                defer engine.freeValue(blank);
                if (v.truthy(engine, blank)) {
                    if (corpus.text_length > 0) corpus.pending_separator = true;
                    column += width;
                    continue;
                }
                try corpus.append(text, row, column, width, false);
                column += width;
            }
        }
        if (corpus.text_length > 0) corpus.pending_separator = true;
    }
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    const empty = try v.text(engine, "");
    defer engine.freeValue(empty);
    try js.define(engine, result, "text", try js.invoke(engine, corpus.chunks, "join", &.{empty}));
    try js.define(engine, result, "spans", c.JS_DupValue(engine.context, corpus.spans));
    return result;
}
fn normalize(engine: *js.Engine, query: c.JSValue) !c.JSValue {
    const regex = try pattern(engine, "\\s+", "gu");
    defer engine.freeValue(regex);
    const space = try v.text(engine, " ");
    defer engine.freeValue(space);
    const replaced = try js.invoke(engine, query, "replace", &.{ regex, space });
    defer engine.freeValue(replaced);
    return js.invoke(engine, replaced, "trim", &.{});
}
fn math(engine: *js.Engine, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const object = try js.global(engine, "Math");
    defer engine.freeValue(object);
    return js.invoke(engine, object, name, args);
}
fn spanAt(engine: *js.Engine, corpus: c.JSValue, index: f64) !c.JSValue {
    const spans = try js.get(engine, corpus, "spans");
    defer engine.freeValue(spans);
    return js.getKey(engine, spans, v.numeric(engine, index));
}
fn spanCount(engine: *js.Engine, corpus: c.JSValue) !f64 {
    const spans = try js.get(engine, corpus, "spans");
    defer engine.freeValue(spans);
    return v.numberField(engine, spans, "length");
}
fn stringField(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return engine.checked(c.JS_ToString(engine.context, value));
}
fn findMatches(engine: *js.Engine, bindings: c.JSValue, corpus: c.JSValue, query: c.JSValue) !c.JSValue {
    if (!v.truthy(engine, query)) return js.array(engine);
    const regexp = try js.global(engine, "RegExp");
    defer engine.freeValue(regexp);
    const escape = try pattern(engine, "[.*+?^${}()|[\\]\\\\]", "g");
    defer engine.freeValue(escape);
    const replacement = try v.text(engine, "\\$&");
    defer engine.freeValue(replacement);
    const escaped = try js.invoke(engine, query, "replace", &.{ escape, replacement });
    defer engine.freeValue(escaped);
    const flags = try v.text(engine, "giu");
    defer engine.freeValue(flags);
    var arguments = [_]c.JSValue{ escaped, flags };
    const expression = try engine.checked(c.JS_CallConstructor(engine.context, regexp, arguments.len, &arguments));
    defer engine.freeValue(expression);
    const matches = try js.array(engine);
    errdefer engine.freeValue(matches);
    const text = try js.get(engine, corpus, "text");
    defer engine.freeValue(text);
    const iterable = try js.invoke(engine, text, "matchAll", &.{expression});
    defer engine.freeValue(iterable);
    const symbol = try js.get(engine, bindings, "iteratorSymbol");
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var span_index: f64 = 0;
    while (try iterator.next()) |match| {
        defer engine.freeValue(match);
        const start = try v.numberField(engine, match, "index");
        const whole = try js.getKey(engine, match, c.JS_NewInt32(engine.context, 0));
        defer engine.freeValue(whole);
        const end = start + try v.numberField(engine, whole, "length");
        while (span_index < try spanCount(engine, corpus)) {
            const span = try spanAt(engine, corpus, span_index);
            defer engine.freeValue(span);
            if (!(try v.numberField(engine, span, "textEnd") <= start)) break;
            span_index += 1;
        }
        const segments = try js.array(engine);
        defer engine.freeValue(segments);
        var index = span_index;
        while (index < try spanCount(engine, corpus)) : (index += 1) {
            const span = try spanAt(engine, corpus, index);
            defer engine.freeValue(span);
            if (try v.numberField(engine, span, "textStart") >= end) break;
            if (try v.numberField(engine, span, "textEnd") <= start) continue;
            const linear = try js.get(engine, span, "linearColumns");
            defer engine.freeValue(linear);
            const start_column = if (v.truthy(engine, linear)) blk: {
                const base = try v.numberField(engine, span, "startCol");
                const text_start = try js.get(engine, span, "textStart");
                defer engine.freeValue(text_start);
                const maximum = try math(engine, "max", &.{ v.numeric(engine, start), text_start });
                defer engine.freeValue(maximum);
                break :blk base + try v.number(engine, maximum) - try v.numberField(engine, span, "textStart");
            } else try v.numberField(engine, span, "startCol");
            const linear_end = try js.get(engine, span, "linearColumns");
            defer engine.freeValue(linear_end);
            const end_column = if (v.truthy(engine, linear_end)) blk: {
                const base = try v.numberField(engine, span, "startCol");
                const text_end = try js.get(engine, span, "textEnd");
                defer engine.freeValue(text_end);
                const minimum = try math(engine, "min", &.{ v.numeric(engine, end), text_end });
                defer engine.freeValue(minimum);
                break :blk base + try v.number(engine, minimum) - try v.numberField(engine, span, "textStart");
            } else try v.numberField(engine, span, "endCol");
            const previous = try js.getKey(engine, segments, v.numeric(engine, try v.numberField(engine, segments, "length") - 1));
            defer engine.freeValue(previous);
            const previous_row = if (v.truthy(engine, previous)) try js.get(engine, previous, "row") else c.pi_js_undefined();
            defer engine.freeValue(previous_row);
            const row = try js.get(engine, span, "row");
            defer engine.freeValue(row);
            if (v.truthy(engine, previous) and c.JS_IsStrictEqual(engine.context, previous_row, row) and start_column <= try v.numberField(engine, previous, "endCol")) {
                const last_end = try js.get(engine, previous, "endCol");
                defer engine.freeValue(last_end);
                try v.set(engine, previous, "endCol", try math(engine, "max", &.{ last_end, v.numeric(engine, end_column) }));
            } else {
                const segment = try js.object(engine);
                defer engine.freeValue(segment);
                try js.define(engine, segment, "row", c.JS_DupValue(engine.context, row));
                try js.define(engine, segment, "startCol", v.numeric(engine, start_column));
                try js.define(engine, segment, "endCol", v.numeric(engine, end_column));
                try js.push(engine, segments, segment);
            }
        }
        while (span_index < try spanCount(engine, corpus)) {
            const span = try spanAt(engine, corpus, span_index);
            defer engine.freeValue(span);
            if (!(try v.numberField(engine, span, "textEnd") <= end)) break;
            span_index += 1;
        }
        if (try v.numberField(engine, segments, "length") > 0) {
            const result = try js.object(engine);
            defer engine.freeValue(result);
            try js.define(engine, result, "segments", c.JS_DupValue(engine.context, segments));
            try js.push(engine, matches, result);
        }
    }
    return matches;
}
fn search(engine: *js.Engine, object: c.JSValue, bindings: c.JSValue, lines: c.JSValue, query: c.JSValue) !c.JSValue {
    const source_lines = try js.get(engine, object, "sourceLines");
    defer engine.freeValue(source_lines);
    const source_length = if (c.JS_IsNull(source_lines) or c.JS_IsUndefined(source_lines)) c.pi_js_undefined() else try js.get(engine, source_lines, "length");
    defer engine.freeValue(source_length);
    const input_length = try js.get(engine, lines, "length");
    defer engine.freeValue(input_length);
    var source_changed = !c.JS_IsStrictEqual(engine.context, source_length, input_length);
    if (!source_changed) {
        const current = try js.get(engine, object, "sourceLines");
        defer engine.freeValue(current);
        if (v.truthy(engine, current)) {
            var index: f64 = 0;
            while (index < try v.numberField(engine, lines, "length")) : (index += 1) {
                const previous = try js.get(engine, object, "sourceLines");
                defer engine.freeValue(previous);
                const before = try js.getKey(engine, previous, v.numeric(engine, index));
                defer engine.freeValue(before);
                const after = try js.getKey(engine, lines, v.numeric(engine, index));
                defer engine.freeValue(after);
                if (c.JS_IsStrictEqual(engine.context, before, after)) continue;
                source_changed = true;
                break;
            }
        }
    }
    const old_corpus = if (!source_changed) try js.get(engine, object, "corpus") else c.pi_js_undefined();
    defer engine.freeValue(old_corpus);
    if (source_changed or !v.truthy(engine, old_corpus)) {
        const array = try js.global(engine, "Array");
        defer engine.freeValue(array);
        try v.set(engine, object, "sourceLines", try js.invoke(engine, array, "from", &.{lines}));
        try v.set(engine, object, "corpus", try buildCorpus(engine, bindings, lines));
    }
    const normalized = try normalize(engine, query);
    defer engine.freeValue(normalized);
    const previous_query = if (!source_changed) try js.get(engine, object, "normalizedQuery") else c.pi_js_undefined();
    defer engine.freeValue(previous_query);
    const changed = source_changed or !c.JS_IsStrictEqual(engine.context, normalized, previous_query);
    if (changed) {
        try v.set(engine, object, "normalizedQuery", c.JS_DupValue(engine.context, normalized));
        const corpus = try js.get(engine, object, "corpus");
        defer engine.freeValue(corpus);
        try v.set(engine, object, "matches", try findMatches(engine, bindings, corpus, normalized));
    }
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "matches", try js.get(engine, object, "matches"));
    try js.define(engine, result, "changed", c.pi_js_bool(engine.context, @intFromBool(changed)));
    return result;
}
fn construct(engine: *js.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    inline for (.{ "sourceLines", "corpus", "normalizedQuery" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    try js.define(engine, object, "matches", try js.array(engine));
    return object;
}
const Function = enum(c_int) { search, findAltScreenSearchMatches, getAltScreenSearchMatchKey };
fn invoke(engine: *js.Engine, object: c.JSValue, bindings: c.JSValue, function: Function, args: []const c.JSValue) !c.JSValue {
    switch (function) {
        .search => return search(engine, object, bindings, v.arg(args, 0), v.arg(args, 1)),
        .findAltScreenSearchMatches => {
            const query = try normalize(engine, v.arg(args, 1));
            defer engine.freeValue(query);
            if (!v.truthy(engine, query)) return js.array(engine);
            const corpus = try buildCorpus(engine, bindings, v.arg(args, 0));
            defer engine.freeValue(corpus);
            return findMatches(engine, bindings, corpus, query);
        },
        .getAltScreenSearchMatchKey => {
            const match = v.arg(args, 0);
            const first_segments = try js.get(engine, match, "segments");
            defer engine.freeValue(first_segments);
            const first = try js.getKey(engine, first_segments, c.JS_NewInt32(engine.context, 0));
            defer engine.freeValue(first);
            const last_segments = try js.get(engine, match, "segments");
            defer engine.freeValue(last_segments);
            const length_segments = try js.get(engine, match, "segments");
            defer engine.freeValue(length_segments);
            const last = try js.getKey(engine, last_segments, v.numeric(engine, try v.numberField(engine, length_segments, "length") - 1));
            defer engine.freeValue(last);
            if (!v.truthy(engine, first) or !v.truthy(engine, last)) return v.text(engine, "");
            const first_row = try stringField(engine, first, "row");
            defer engine.freeValue(first_row);
            const first_column = try stringField(engine, first, "startCol");
            defer engine.freeValue(first_column);
            const last_row = try stringField(engine, last, "row");
            defer engine.freeValue(last_row);
            const last_column = try stringField(engine, last, "endCol");
            defer engine.freeValue(last_column);
            const colon = try v.text(engine, ":");
            defer engine.freeValue(colon);
            return v.concat(engine, &.{ first_row, colon, first_column, colon, last_row, colon, last_column });
        },
    }
}
fn call(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, object, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
pub fn create(engine: *js.Engine, exports: c.JSValue) !c.JSValue {
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    inline for (.{ "stripTerminalSequences", "visibleWidth" }) |name| try js.define(engine, bindings, name, try js.get(engine, exports, name));
    try js.define(engine, bindings, "printableAscii", try pattern(engine, "^[\\x20-\\x7e]*$", ""));
    const symbols = try js.global(engine, "Symbol");
    defer engine.freeValue(symbols);
    try js.define(engine, bindings, "iteratorSymbol", try js.get(engine, symbols, "iterator"));
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    var data = [_]c.JSValue{bindings};
    const method = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, "search", 2, @intFromEnum(Function.search), 1, &data));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "search", method, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "AltScreenSearchIndex", try @import("native_class.zig").constructor(engine, "AltScreenSearchIndex", 0, prototype, construct, &.{}));
    inline for (.{ Function.findAltScreenSearchMatches, Function.getAltScreenSearchMatchKey }) |function| {
        const name = @tagName(function);
        const length: c_int = if (function == .findAltScreenSearchMatches) 2 else 1;
        try js.define(engine, result, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, call, name, length, @intFromEnum(function), 1, &data)));
    }
    return result;
}
