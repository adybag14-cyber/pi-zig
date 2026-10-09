//! Source Editor wrapping and visual-line geometry over ordinary JS fields.
const std = @import("std");
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const Method = @import("native_editor_methods.zig").Method;
const terminal = @import("../tui/utf16_terminal.zig");
const graphemes = @import("../tui/utf16_graphemes.zig");
pub fn supports(method: Method) bool {
    return switch (method) {
        .layoutText, .buildVisualLineMap, .findVisualLineAt, .findCurrentVisualLine, .isOnFirstVisualLine, .isOnLastVisualLine, .computeVerticalMoveColumn => true,
        else => false,
    };
}
pub fn install(engine: *Engine) !c.JSValue {
    const constants = try js.object(engine);
    errdefer engine.freeValue(constants);
    try js.define(engine, constants, "marker", try e.literalPattern(engine, "^\\[paste #(\\d+)( (\\+\\d+ lines|\\d+ chars))?\\]$", ""));
    try js.define(engine, constants, "cjk", try e.literalPattern(engine, "[\\p{Script_Extensions=Han}\\p{Script_Extensions=Hiragana}\\p{Script_Extensions=Katakana}\\p{Script_Extensions=Hangul}\\p{Script_Extensions=Bopomofo}]", "u"));
    try js.define(engine, constants, "punctuation", try e.literalPattern(engine, "[(){}[\\]<>.,;:'\"!?+\\-=*/\\\\|&%^$#@~`]", ""));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    try js.define(engine, constants, "iterator", try js.get(engine, symbol, "iterator"));
    try js.define(engine, constants, "paste", try e.literalPattern(engine, "\\[paste #(\\d+)( (\\+\\d+ lines|\\d+ chars))?\\]", "g"));
    return constants;
}
pub fn width(engine: *Engine, text: c.JSValue) !f64 {
    const units = try e.utf16.unitsAlloc(engine, text);
    defer engine.gpa.free(units);
    return @floatFromInt(try terminal.visibleWidth(engine.gpa, units));
}
pub fn testPattern(engine: *Engine, constants: c.JSValue, name: [*:0]const u8, value: c.JSValue) !bool {
    const regex = try js.get(engine, constants, name);
    defer engine.freeValue(regex);
    const result = try js.invoke(engine, regex, "test", &.{value});
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
pub fn marker(engine: *Engine, constants: c.JSValue, text: c.JSValue) !bool {
    return try e.length(engine, text) >= 10 and try testPattern(engine, constants, "marker", text);
}
pub fn whitespace(engine: *Engine, text: c.JSValue) !bool {
    const regex = try e.literalPattern(engine, "\\s", "");
    defer engine.freeValue(regex);
    const result = try js.invoke(engine, regex, "test", &.{text});
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
fn addChunk(engine: *Engine, result: c.JSValue, text: c.JSValue, start: f64, end: f64) !void {
    const chunk = try js.object(engine);
    defer engine.freeValue(chunk);
    try js.define(engine, chunk, "text", c.JS_DupValue(engine.context, text));
    try js.define(engine, chunk, "startIndex", v.numeric(engine, start));
    try js.define(engine, chunk, "endIndex", v.numeric(engine, end));
    try js.push(engine, result, chunk);
}
fn addSlice(engine: *Engine, result: c.JSValue, line: c.JSValue, start: f64, end: ?f64) !void {
    const text = try js.invoke(engine, line, "slice", if (end) |last| &.{ v.numeric(engine, start), v.numeric(engine, last) } else &.{v.numeric(engine, start)});
    defer engine.freeValue(text);
    try addChunk(engine, result, text, start, end orelse @as(f64, @floatFromInt(try e.length(engine, line))));
}
fn defaultSegments(engine: *Engine, line: c.JSValue) !c.JSValue {
    const units = try e.utf16.unitsAlloc(engine, line);
    defer engine.gpa.free(units);
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    var iterator: graphemes.Iterator = .{ .text = units };
    var index: u32 = 0;
    while (iterator.next()) |part| : (index += 1) {
        const item = try js.object(engine);
        var transferred = false;
        defer if (!transferred) engine.freeValue(item);
        try js.define(engine, item, "segment", try e.utf16.string(engine, units[part.start..part.end]));
        try js.define(engine, item, "index", v.numeric(engine, @floatFromInt(part.start)));
        try js.define(engine, item, "input", c.JS_DupValue(engine.context, line));
        transferred = true;
        if (c.JS_SetPropertyUint32(engine.context, result, index, item) < 0) return js.capture(engine);
    }
    return result;
}
fn wrap(engine: *Engine, constants: c.JSValue, line: c.JSValue, max_width: f64, supplied: c.JSValue, depth: usize) anyerror!c.JSValue {
    if (depth >= 64) return engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum call stack size exceeded"));
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    if (!v.truthy(engine, line) or max_width <= 0) {
        const empty = try v.text(engine, "");
        defer engine.freeValue(empty);
        try addChunk(engine, result, empty, 0, 0);
        return result;
    }
    if (try width(engine, line) <= max_width) {
        try addChunk(engine, result, line, 0, @floatFromInt(try e.length(engine, line)));
        return result;
    }
    const segments = if (c.JS_IsUndefined(supplied) or c.JS_IsNull(supplied)) try defaultSegments(engine, line) else c.JS_DupValue(engine.context, supplied);
    defer engine.freeValue(segments);
    var current_width: f64 = 0;
    var chunk_start: f64 = 0;
    var opportunity: f64 = -1;
    var opportunity_width: f64 = 0;
    var index: usize = 0;
    while (index < try e.length(engine, segments)) : (index += 1) {
        const segment = try v.fieldAt(engine, segments, @floatFromInt(index));
        defer engine.freeValue(segment);
        const text = try js.get(engine, segment, "segment");
        defer engine.freeValue(text);
        const text_width = try width(engine, text);
        const character = try e.number(engine, segment, "index");
        const is_ws = !try marker(engine, constants, text) and try whitespace(engine, text);
        if (current_width + text_width > max_width) {
            if (opportunity >= 0 and current_width - opportunity_width + text_width <= max_width) {
                try addSlice(engine, result, line, chunk_start, opportunity);
                chunk_start = opportunity;
                current_width -= opportunity_width;
            } else if (chunk_start < character) {
                try addSlice(engine, result, line, chunk_start, character);
                chunk_start = character;
                current_width = 0;
            }
            opportunity = -1;
        }
        if (text_width > max_width) {
            const sub = try wrap(engine, constants, text, max_width, c.pi_js_undefined(), depth + 1);
            defer engine.freeValue(sub);
            const count = try e.length(engine, sub);
            for (0..count - 1) |at| {
                const chunk = try v.fieldAt(engine, sub, @floatFromInt(at));
                defer engine.freeValue(chunk);
                const content = try js.get(engine, chunk, "text");
                defer engine.freeValue(content);
                try addChunk(engine, result, content, character + try e.number(engine, chunk, "startIndex"), character + try e.number(engine, chunk, "endIndex"));
            }
            const last = try v.fieldAt(engine, sub, @floatFromInt(count - 1));
            defer engine.freeValue(last);
            chunk_start = character + try e.number(engine, last, "startIndex");
            const last_text = try js.get(engine, last, "text");
            defer engine.freeValue(last_text);
            current_width = try width(engine, last_text);
            opportunity = -1;
            continue;
        }
        current_width += text_width;
        const next = try v.fieldAt(engine, segments, @floatFromInt(index + 1));
        defer engine.freeValue(next);
        if (v.truthy(engine, next)) {
            const next_text = try js.get(engine, next, "segment");
            defer engine.freeValue(next_text);
            if (is_ws and (try marker(engine, constants, next_text) or !try whitespace(engine, next_text))) {
                opportunity = try e.number(engine, next, "index");
                opportunity_width = current_width;
            } else if (!is_ws and !try whitespace(engine, next_text)) {
                const is_cjk = !try marker(engine, constants, text) and try testPattern(engine, constants, "cjk", text);
                const next_cjk = !try marker(engine, constants, next_text) and try testPattern(engine, constants, "cjk", next_text);
                if (is_cjk or next_cjk) {
                    opportunity = try e.number(engine, next, "index");
                    opportunity_width = current_width;
                }
            }
        }
    }
    try addSlice(engine, result, line, chunk_start, null);
    return result;
}
pub fn collectSegments(engine: *Engine, constants: c.JSValue, editor: c.JSValue, line: c.JSValue) !c.JSValue {
    const mode = try v.text(engine, "grapheme");
    defer engine.freeValue(mode);
    const iterable = try js.invoke(engine, editor, "segment", &.{ line, mode });
    defer engine.freeValue(iterable);
    const iterator = try js.get(engine, constants, "iterator");
    defer engine.freeValue(iterator);
    return js.collect(engine, iterable, iterator);
}
fn layoutItem(engine: *Engine, result: c.JSValue, text: c.JSValue, cursor: bool, position: c.JSValue) !void {
    const item = try js.object(engine);
    defer engine.freeValue(item);
    try js.define(engine, item, "text", c.JS_DupValue(engine.context, text));
    try js.define(engine, item, "hasCursor", c.pi_js_bool(engine.context, @intFromBool(cursor)));
    if (cursor) try js.define(engine, item, "cursorPos", c.JS_DupValue(engine.context, position));
    try js.push(engine, result, item);
}
fn lineCount(engine: *Engine, object: c.JSValue) !usize {
    const list = try e.lines(engine, object);
    defer engine.freeValue(list);
    return e.length(engine, list);
}
fn rawCursor(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const state = try e.state(engine, object);
    defer engine.freeValue(state);
    return js.get(engine, state, name);
}
fn mapItem(engine: *Engine, result: c.JSValue, row: usize, start: f64, length: f64) !void {
    const item = try js.object(engine);
    defer engine.freeValue(item);
    try js.define(engine, item, "logicalLine", v.numeric(engine, @floatFromInt(row)));
    try js.define(engine, item, "startCol", v.numeric(engine, start));
    try js.define(engine, item, "length", v.numeric(engine, length));
    try js.push(engine, result, item);
}
fn layout(engine: *Engine, constants: c.JSValue, object: c.JSValue, content_width: f64, mapping: bool) !c.JSValue {
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    if (!mapping) {
        var empty_editor = try lineCount(engine, object) == 0;
        if (!empty_editor and try lineCount(engine, object) == 1) {
            const list = try e.lines(engine, object);
            defer engine.freeValue(list);
            const head = try v.fieldAt(engine, list, 0);
            defer engine.freeValue(head);
            empty_editor = try e.equalText(engine, head, "");
        }
        if (empty_editor) {
            const empty = try v.text(engine, "");
            defer engine.freeValue(empty);
            try layoutItem(engine, result, empty, true, v.numeric(engine, 0));
            return result;
        }
    }
    var row: usize = 0;
    while (true) : (row += 1) {
        if (row >= try lineCount(engine, object)) break;
        const list = try e.lines(engine, object);
        defer engine.freeValue(list);
        const raw = try v.fieldAt(engine, list, @floatFromInt(row));
        defer engine.freeValue(raw);
        const line = if (v.truthy(engine, raw)) c.JS_DupValue(engine.context, raw) else try v.text(engine, "");
        defer engine.freeValue(line);
        const cursor_row = if (mapping) c.pi_js_undefined() else try rawCursor(engine, object, "cursorLine");
        defer engine.freeValue(cursor_row);
        const current = c.JS_IsStrictEqual(engine.context, cursor_row, v.numeric(engine, @floatFromInt(row)));
        const line_width = try width(engine, line);
        const length = try e.length(engine, line);
        if ((mapping and length == 0) or line_width <= content_width) {
            if (mapping) try mapItem(engine, result, row, 0, @floatFromInt(length)) else {
                const col = if (current) try rawCursor(engine, object, "cursorCol") else c.pi_js_undefined();
                defer engine.freeValue(col);
                try layoutItem(engine, result, line, current, col);
            }
        } else {
            const segments = try collectSegments(engine, constants, object, line);
            defer engine.freeValue(segments);
            const chunks = try wrap(engine, constants, line, content_width, segments, 0);
            defer engine.freeValue(chunks);
            const count = try e.length(engine, chunks);
            for (0..count) |at| {
                const chunk = try v.fieldAt(engine, chunks, @floatFromInt(at));
                defer engine.freeValue(chunk);
                const start = try e.number(engine, chunk, "startIndex");
                const end = try e.number(engine, chunk, "endIndex");
                if (mapping) {
                    try mapItem(engine, result, row, start, end - start);
                    continue;
                }
                const text = try js.get(engine, chunk, "text");
                defer engine.freeValue(text);
                const col = try e.cursor(engine, object, "cursorCol");
                const last = at == count - 1;
                const has_cursor = current and col >= start and (last or col < end);
                const adjusted = if (last) col - start else @min(col - start, @as(f64, @floatFromInt(try e.length(engine, text))));
                try layoutItem(engine, result, text, has_cursor, v.numeric(engine, adjusted));
            }
        }
    }
    return result;
}
pub fn operation(engine: *Engine, constants: c.JSValue, object: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    switch (method) {
        .layoutText, .buildVisualLineMap => return layout(engine, constants, object, try v.number(engine, first), method == .buildVisualLineMap),
        .findVisualLineAt => {
            var index: usize = 0;
            while (index < try e.length(engine, first)) : (index += 1) {
                const line = try v.fieldAt(engine, first, @floatFromInt(index));
                defer engine.freeValue(line);
                if (!v.truthy(engine, line)) continue;
                const row = try js.get(engine, line, "logicalLine");
                defer engine.freeValue(row);
                if (!c.JS_IsStrictEqual(engine.context, row, v.arg(args, 1))) continue;
                const offset = (try v.number(engine, v.arg(args, 2))) - try e.number(engine, line, "startCol");
                var last = index == try e.length(engine, first) - 1;
                if (!last) {
                    const next = try v.fieldAt(engine, first, @floatFromInt(index + 1));
                    defer engine.freeValue(next);
                    const next_row = if (c.JS_IsNull(next) or c.JS_IsUndefined(next)) c.pi_js_undefined() else try js.get(engine, next, "logicalLine");
                    defer engine.freeValue(next_row);
                    const current_row = try js.get(engine, line, "logicalLine");
                    defer engine.freeValue(current_row);
                    last = !c.JS_IsStrictEqual(engine.context, next_row, current_row);
                }
                if (offset >= 0 and (offset < try e.number(engine, line, "length") or (last and offset == try e.number(engine, line, "length")))) return v.numeric(engine, @floatFromInt(index));
            }
            return v.numeric(engine, @as(f64, @floatFromInt(try e.length(engine, first))) - 1);
        },
        .findCurrentVisualLine => {
            const line_state = try e.state(engine, object);
            defer engine.freeValue(line_state);
            const row = try js.get(engine, line_state, "cursorLine");
            defer engine.freeValue(row);
            const col_state = try e.state(engine, object);
            defer engine.freeValue(col_state);
            const col = try js.get(engine, col_state, "cursorCol");
            defer engine.freeValue(col);
            return js.invoke(engine, object, "findVisualLineAt", &.{ first, row, col });
        },
        .isOnFirstVisualLine, .isOnLastVisualLine => {
            const last_width = try js.get(engine, object, "lastWidth");
            defer engine.freeValue(last_width);
            const lines = try js.invoke(engine, object, "buildVisualLineMap", &.{last_width});
            defer engine.freeValue(lines);
            const current = try js.invoke(engine, object, "findCurrentVisualLine", &.{lines});
            defer engine.freeValue(current);
            const expected: f64 = if (method == .isOnFirstVisualLine) 0 else @as(f64, @floatFromInt(try e.length(engine, lines))) - 1;
            return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, current, v.numeric(engine, expected))));
        },
        .computeVerticalMoveColumn => {
            const preferred = try js.get(engine, object, "preferredVisualCol");
            defer engine.freeValue(preferred);
            const in_middle = (try v.number(engine, first)) < try v.number(engine, v.arg(args, 1));
            const short = (try v.number(engine, v.arg(args, 2))) < try v.number(engine, first);
            if (c.JS_IsNull(preferred) or in_middle) {
                try e.set(engine, object, "preferredVisualCol", if (short) c.JS_DupValue(engine.context, first) else c.pi_js_null());
                return c.JS_DupValue(engine.context, if (short) v.arg(args, 2) else first);
            }
            const live_preferred = try js.get(engine, object, "preferredVisualCol");
            defer engine.freeValue(live_preferred);
            if (short or (try v.number(engine, v.arg(args, 2))) < try v.number(engine, live_preferred)) return c.JS_DupValue(engine.context, v.arg(args, 2));
            const result = try js.get(engine, object, "preferredVisualCol");
            errdefer engine.freeValue(result);
            try e.set(engine, object, "preferredVisualCol", c.pi_js_null());
            return result;
        },
        else => unreachable,
    }
}
