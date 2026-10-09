//! Source Editor word, grapheme, jump and cursor operations.
const std = @import("std");
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const visual = @import("native_editor_visual.zig");
const Method = @import("native_editor_methods.zig").Method;
pub fn supports(method: Method) bool {
    return switch (method) {
        .moveWordBackwards, .moveWordForwards, .jumpToChar, .moveCursor => true,
        else => false,
    };
}
fn slice(engine: *Engine, text: c.JSValue, start: f64, end: ?f64) !c.JSValue {
    return js.invoke(engine, text, "slice", if (end) |last| &.{ v.numeric(engine, start), v.numeric(engine, last) } else &.{v.numeric(engine, start)});
}
fn fieldLine(engine: *Engine, object: c.JSValue, index: f64) !c.JSValue {
    const lines = try e.lines(engine, object);
    defer engine.freeValue(lines);
    const raw = try v.fieldAt(engine, lines, index);
    if (v.truthy(engine, raw)) return raw;
    engine.freeValue(raw);
    return v.text(engine, "");
}
fn wordBoundary(engine: *Engine, constants: c.JSValue, object: c.JSValue, text: c.JSValue, column: f64, backward: bool) !f64 {
    const length: f64 = @floatFromInt(try e.length(engine, text));
    if (backward and column <= 0) return 0;
    if (!backward and column >= length) return length;
    const portion = try slice(engine, text, if (backward) 0 else column, if (backward) column else null);
    defer engine.freeValue(portion);
    const mode = try v.text(engine, "word");
    defer engine.freeValue(mode);
    const iterable = try js.invoke(engine, object, "segment", &.{ portion, mode });
    defer engine.freeValue(iterable);
    const symbol = try js.get(engine, constants, "iterator");
    defer engine.freeValue(symbol);
    var position = column;
    if (backward) {
        const parts = try js.collect(engine, iterable, symbol);
        defer engine.freeValue(parts);
        var count = try e.length(engine, parts);
        while (count > 0) {
            const last = try v.fieldAt(engine, parts, @floatFromInt(count - 1));
            defer engine.freeValue(last);
            const segment = try js.get(engine, last, "segment");
            defer engine.freeValue(segment);
            if (try visual.marker(engine, constants, segment) or !try visual.whitespace(engine, segment)) break;
            position -= @as(f64, @floatFromInt(try e.length(engine, segment)));
            count -= 1;
        }
        if (count == 0) return position;
        const last = try v.fieldAt(engine, parts, @floatFromInt(count - 1));
        defer engine.freeValue(last);
        const segment = try js.get(engine, last, "segment");
        defer engine.freeValue(segment);
        if (try visual.marker(engine, constants, segment)) return position - @as(f64, @floatFromInt(try e.length(engine, segment)));
        const word = try js.get(engine, last, "isWordLike");
        defer engine.freeValue(word);
        if (v.truthy(engine, word)) {
            const original = try js.get(engine, constants, "punctuation");
            defer engine.freeValue(original);
            const flags = try v.text(engine, "g");
            defer engine.freeValue(flags);
            const regex = try js.builtin(engine, "RegExp", &.{ original, flags });
            defer engine.freeValue(regex);
            const all = try js.invoke(engine, segment, "matchAll", &.{regex});
            defer engine.freeValue(all);
            const matches = try js.collect(engine, all, symbol);
            defer engine.freeValue(matches);
            const size = try e.length(engine, matches);
            if (size == 0) return position - @as(f64, @floatFromInt(try e.length(engine, segment)));
            const match = try v.fieldAt(engine, matches, @floatFromInt(size - 1));
            defer engine.freeValue(match);
            const matched = try v.fieldAt(engine, match, 0);
            defer engine.freeValue(matched);
            return position - (@as(f64, @floatFromInt(try e.length(engine, segment))) - (try e.number(engine, match, "index") + @as(f64, @floatFromInt(try e.length(engine, matched)))));
        }
        while (count > 0) {
            const part = try v.fieldAt(engine, parts, @floatFromInt(count - 1));
            defer engine.freeValue(part);
            const value = try js.get(engine, part, "segment");
            defer engine.freeValue(value);
            if (try visual.marker(engine, constants, value)) break;
            const is_word = try js.get(engine, part, "isWordLike");
            defer engine.freeValue(is_word);
            if (v.truthy(engine, is_word) or try visual.whitespace(engine, value)) break;
            position -= @as(f64, @floatFromInt(try e.length(engine, value)));
            count -= 1;
        }
        return position;
    }
    // Source forward navigation manually steps its iterator and does not close
    // it on an early return, unlike a for-of loop.
    var iterator = try js.Iterator.init(engine, iterable, symbol);
    defer iterator.deinit();
    var next = try iterator.next();
    defer if (next) |value| engine.freeValue(value);
    while (next) |part| {
        const segment = try js.get(engine, part, "segment");
        defer engine.freeValue(segment);
        if (try visual.marker(engine, constants, segment) or !try visual.whitespace(engine, segment)) break;
        position += @as(f64, @floatFromInt(try e.length(engine, segment)));
        engine.freeValue(part);
        next = null;
        next = try iterator.next();
    }
    const part = next orelse return position;
    const segment = try js.get(engine, part, "segment");
    defer engine.freeValue(segment);
    if (try visual.marker(engine, constants, segment)) return position + @as(f64, @floatFromInt(try e.length(engine, segment)));
    const word = try js.get(engine, part, "isWordLike");
    defer engine.freeValue(word);
    if (v.truthy(engine, word)) {
        const regex = try js.get(engine, constants, "punctuation");
        defer engine.freeValue(regex);
        const match = try js.invoke(engine, regex, "exec", &.{segment});
        defer engine.freeValue(match);
        return position + if (c.JS_IsNull(match) or c.JS_IsUndefined(match)) @as(f64, @floatFromInt(try e.length(engine, segment))) else try e.number(engine, match, "index");
    }
    while (next) |value| {
        const value_text = try js.get(engine, value, "segment");
        defer engine.freeValue(value_text);
        if (try visual.marker(engine, constants, value_text)) break;
        const is_word = try js.get(engine, value, "isWordLike");
        defer engine.freeValue(is_word);
        if (v.truthy(engine, is_word) or try visual.whitespace(engine, value_text)) break;
        position += @as(f64, @floatFromInt(try e.length(engine, value_text)));
        engine.freeValue(value);
        next = null;
        next = try iterator.next();
    }
    return position;
}
fn moveWord(engine: *Engine, constants: c.JSValue, object: c.JSValue, backward: bool) !void {
    try e.setLast(engine, object, null);
    const current = try e.line(engine, object);
    defer engine.freeValue(current);
    const column = try e.cursor(engine, object, "cursorCol");
    const length: f64 = @floatFromInt(try e.length(engine, current));
    if (if (backward) column == 0 else column >= length) {
        const row = try e.cursor(engine, object, "cursorLine");
        const lines = try e.lines(engine, object);
        defer engine.freeValue(lines);
        if (if (backward) row > 0 else row < @as(f64, @floatFromInt(try e.length(engine, lines))) - 1) {
            try e.setState(engine, object, "cursorLine", v.numeric(engine, row + if (backward) @as(f64, -1) else @as(f64, 1)));
            const previous = if (backward) try e.line(engine, object) else c.pi_js_undefined();
            defer engine.freeValue(previous);
            try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, if (backward) @floatFromInt(try e.length(engine, previous)) else 0)});
        }
        return;
    }
    try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, try wordBoundary(engine, constants, object, current, column, backward))});
}
fn moveCursor(engine: *Engine, constants: c.JSValue, object: c.JSValue, line_delta: f64, col_delta: f64) !void {
    try e.setLast(engine, object, null);
    const last_width = try js.get(engine, object, "lastWidth");
    defer engine.freeValue(last_width);
    const lines = try js.invoke(engine, object, "buildVisualLineMap", &.{last_width});
    defer engine.freeValue(lines);
    const current = try js.invoke(engine, object, "findCurrentVisualLine", &.{lines});
    defer engine.freeValue(current);
    if (line_delta != 0) {
        const target = (try v.number(engine, current)) + line_delta;
        if (target >= 0 and target < @as(f64, @floatFromInt(try e.length(engine, lines)))) try e.invokeVoid(engine, object, "moveToVisualLine", &.{ lines, current, v.numeric(engine, target) });
    }
    if (col_delta != 0) {
        const line = try e.line(engine, object);
        defer engine.freeValue(line);
        const col = try e.cursor(engine, object, "cursorCol");
        const right = col_delta > 0;
        if (if (right) col < @as(f64, @floatFromInt(try e.length(engine, line))) else col > 0) {
            const text = try slice(engine, line, if (right) col else 0, if (right) null else col);
            defer engine.freeValue(text);
            const segments = try visual.collectSegments(engine, constants, object, text);
            defer engine.freeValue(segments);
            const count = try e.length(engine, segments);
            var amount: f64 = 1;
            if (count > 0) {
                const segment = try v.fieldAt(engine, segments, if (right) 0 else @as(f64, @floatFromInt(count - 1)));
                defer engine.freeValue(segment);
                const value = try js.get(engine, segment, "segment");
                defer engine.freeValue(value);
                amount = @floatFromInt(try e.length(engine, value));
            }
            try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, (try e.cursor(engine, object, "cursorCol")) + if (right) amount else -amount)});
        } else {
            const row = try e.cursor(engine, object, "cursorLine");
            const logical = try e.lines(engine, object);
            defer engine.freeValue(logical);
            if (if (right) row < @as(f64, @floatFromInt(try e.length(engine, logical))) - 1 else row > 0) {
                try e.setState(engine, object, "cursorLine", v.numeric(engine, row + if (right) @as(f64, 1) else @as(f64, -1)));
                const previous = if (right) c.pi_js_undefined() else try e.line(engine, object);
                defer engine.freeValue(previous);
                try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, if (right) 0 else @floatFromInt(try e.length(engine, previous)))});
            } else if (right) {
                const line_info = try js.getKey(engine, lines, current);
                defer engine.freeValue(line_info);
                if (v.truthy(engine, line_info)) try e.set(engine, object, "preferredVisualCol", v.numeric(engine, (try e.cursor(engine, object, "cursorCol")) - try e.number(engine, line_info, "startCol")));
            }
        }
    }
    const active = try js.get(engine, object, "autocompleteState");
    defer engine.freeValue(active);
    if (v.truthy(engine, active)) try e.invokeVoid(engine, object, "updateAutocomplete", &.{});
}
fn jump(engine: *Engine, object: c.JSValue, char: c.JSValue, direction: c.JSValue) !void {
    try e.setLast(engine, object, null);
    const forward = try e.equalText(engine, direction, "forward");
    const lines = try e.lines(engine, object);
    defer engine.freeValue(lines);
    const end: f64 = if (forward) @floatFromInt(try e.length(engine, lines)) else -1;
    var row = try e.cursor(engine, object, "cursorLine");
    var steps: usize = 0;
    while (row != end) : (row += if (forward) @as(f64, 1) else @as(f64, -1)) {
        steps += 1;
        if (steps > 1_000_000) return error.NativeEditorStateLimit;
        const raw = try v.fieldAt(engine, lines, row);
        defer engine.freeValue(raw);
        const line = if (v.truthy(engine, raw)) c.JS_DupValue(engine.context, raw) else try v.text(engine, "");
        defer engine.freeValue(line);
        const is_current = row == try e.cursor(engine, object, "cursorLine");
        const from = if (is_current) v.numeric(engine, (try e.cursor(engine, object, "cursorCol")) + if (forward) @as(f64, 1) else @as(f64, -1)) else c.pi_js_undefined();
        const found = try js.invoke(engine, line, if (forward) "indexOf" else "lastIndexOf", &.{ char, from });
        defer engine.freeValue(found);
        if (!c.JS_IsStrictEqual(engine.context, found, v.numeric(engine, -1))) {
            try e.setState(engine, object, "cursorLine", v.numeric(engine, row));
            try e.invokeVoid(engine, object, "setCursorCol", &.{found});
            return;
        }
    }
}
pub fn operation(engine: *Engine, constants: c.JSValue, object: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .moveWordBackwards => try moveWord(engine, constants, object, true),
        .moveWordForwards => try moveWord(engine, constants, object, false),
        .moveCursor => try moveCursor(engine, constants, object, try v.number(engine, v.arg(args, 0)), try v.number(engine, v.arg(args, 1))),
        .jumpToChar => try jump(engine, object, v.arg(args, 0), v.arg(args, 1)),
        else => unreachable,
    }
    return c.pi_js_undefined();
}
