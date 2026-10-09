//! Source Editor line kills, kill ring and yank over ordinary JS fields.
const std = @import("std");
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const Method = @import("native_editor_methods.zig").Method;
pub fn supports(method: Method) bool {
    return switch (method) {
        .deleteToStartOfLine, .deleteToEndOfLine, .moveToLineStart, .moveToLineEnd, .yank, .yankPop, .insertYankedText, .deleteYankedText => true,
        else => false,
    };
}
fn slice(engine: *Engine, text: c.JSValue, start: f64, end: ?f64) !c.JSValue {
    return js.invoke(engine, text, "slice", if (end) |last| &.{ v.numeric(engine, start), v.numeric(engine, last) } else &.{v.numeric(engine, start)});
}
fn joinEnds(engine: *Engine, text: c.JSValue, start: f64, end: f64) !c.JSValue {
    const before = try slice(engine, text, 0, start);
    defer engine.freeValue(before);
    const after = try slice(engine, text, end, null);
    defer engine.freeValue(after);
    return v.concat(engine, &.{ before, after });
}
fn kill(engine: *Engine, object: c.JSValue, text: c.JSValue, backward: bool) !void {
    const ring = try js.get(engine, object, "killRing");
    defer engine.freeValue(ring);
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "prepend", c.pi_js_bool(engine.context, @intFromBool(backward)));
    const action = try js.get(engine, object, "lastAction");
    defer engine.freeValue(action);
    try js.define(engine, options, "accumulate", c.pi_js_bool(engine.context, @intFromBool(try e.equalText(engine, action, "kill"))));
    try e.invokeVoid(engine, ring, "push", &.{ text, options });
    try e.setLast(engine, object, "kill");
}
fn fallbackLine(engine: *Engine, list: c.JSValue, index: f64) !c.JSValue {
    const value = try v.fieldAt(engine, list, index);
    if (v.truthy(engine, value)) return value;
    engine.freeValue(value);
    return v.text(engine, "");
}
fn merge(engine: *Engine, object: c.JSValue, backward: bool, current: c.JSValue) !void {
    const list = try e.lines(engine, object);
    defer engine.freeValue(list);
    const index = try e.cursor(engine, object, "cursorLine");
    const left_index = if (backward) index - 1 else index;
    const left = if (backward) try fallbackLine(engine, list, left_index) else c.JS_DupValue(engine.context, current);
    defer engine.freeValue(left);
    const right = if (backward) c.JS_DupValue(engine.context, current) else try fallbackLine(engine, list, left_index + 1);
    defer engine.freeValue(right);
    const combined = try v.concat(engine, &.{ left, right });
    defer engine.freeValue(combined);
    try js.setKey(engine, list, v.numeric(engine, left_index), combined);
    try e.invokeVoid(engine, list, "splice", &.{ v.numeric(engine, left_index + 1), v.numeric(engine, 1) });
    if (backward) {
        try e.setState(engine, object, "cursorLine", v.numeric(engine, (try e.cursor(engine, object, "cursorLine")) - 1));
        try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, @floatFromInt(try e.length(engine, left)))});
    }
}
fn eraseLine(engine: *Engine, object: c.JSValue, backward: bool) !void {
    try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
    const current = try e.line(engine, object);
    defer engine.freeValue(current);
    const column = try e.cursor(engine, object, "cursorCol");
    const line_length: f64 = @floatFromInt(try e.length(engine, current));
    if (if (backward) column > 0 else column < line_length) {
        try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
        const live_column = try e.cursor(engine, object, "cursorCol");
        const deleted = try slice(engine, current, if (backward) 0 else live_column, if (backward) live_column else null);
        defer engine.freeValue(deleted);
        try kill(engine, object, deleted, backward);
        const after_column = try e.cursor(engine, object, "cursorCol");
        try e.replaceLine(engine, object, if (backward) try slice(engine, current, after_column, null) else try slice(engine, current, 0, after_column));
        if (backward) try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, 0)});
    } else {
        const line_index = try e.cursor(engine, object, "cursorLine");
        const list = try e.lines(engine, object);
        defer engine.freeValue(list);
        if (if (backward) line_index > 0 else line_index < @as(f64, @floatFromInt(try e.length(engine, list))) - 1) {
            try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
            const newline = try v.text(engine, "\n");
            defer engine.freeValue(newline);
            try kill(engine, object, newline, backward);
            try merge(engine, object, backward, current);
        }
    }
    try e.notify(engine, object);
}
pub fn operation(engine: *Engine, object: c.JSValue, method: Method, args: []const c.JSValue) !?c.JSValue {
    const first = v.arg(args, 0);
    switch (method) {
        .deleteToStartOfLine => try eraseLine(engine, object, true),
        .deleteToEndOfLine => try eraseLine(engine, object, false),
        .moveToLineStart => {
            try e.setLast(engine, object, null);
            try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, 0)});
        },
        .moveToLineEnd => {
            try e.setLast(engine, object, null);
            const current = try e.line(engine, object);
            defer engine.freeValue(current);
            try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, @floatFromInt(try e.length(engine, current)))});
        },
        .yank, .yankPop => {
            if (method == .yankPop) {
                const action = try js.get(engine, object, "lastAction");
                defer engine.freeValue(action);
                if (!try e.equalText(engine, action, "yank")) return c.pi_js_undefined();
            }
            const ring = try js.get(engine, object, "killRing");
            defer engine.freeValue(ring);
            const count = try e.number(engine, ring, "length");
            if (if (method == .yank) count == 0 else count <= 1) return c.pi_js_undefined();
            try e.invokeVoid(engine, object, "pushUndoSnapshot", &.{});
            if (method == .yankPop) {
                try e.invokeVoid(engine, object, "deleteYankedText", &.{});
                const rotating_ring = try js.get(engine, object, "killRing");
                defer engine.freeValue(rotating_ring);
                try e.invokeVoid(engine, rotating_ring, "rotate", &.{});
            }
            const current_ring = try js.get(engine, object, "killRing");
            defer engine.freeValue(current_ring);
            const text = try js.invoke(engine, current_ring, "peek", &.{});
            defer engine.freeValue(text);
            try e.invokeVoid(engine, object, "insertYankedText", &.{text});
            try e.setLast(engine, object, "yank");
        },
        .insertYankedText => {
            try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
            const separator = try v.text(engine, "\n");
            defer engine.freeValue(separator);
            const items = try js.invoke(engine, first, "split", &.{separator});
            defer engine.freeValue(items);
            const count = try e.length(engine, items);
            const current = try e.line(engine, object);
            defer engine.freeValue(current);
            const column = try e.cursor(engine, object, "cursorCol");
            const before = try slice(engine, current, 0, column);
            defer engine.freeValue(before);
            const after = try slice(engine, current, column, null);
            defer engine.freeValue(after);
            if (count == 1) {
                try e.replaceLine(engine, object, try v.concat(engine, &.{ before, first, after }));
                try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, column + @as(f64, @floatFromInt(try e.length(engine, first))))});
            } else {
                const list = try e.lines(engine, object);
                defer engine.freeValue(list);
                const index = try e.cursor(engine, object, "cursorLine");
                const head = try v.fieldAt(engine, items, 0);
                defer engine.freeValue(head);
                try e.replaceLine(engine, object, try v.concat(engine, &.{ before, head }));
                for (1..count) |at| {
                    const text = try v.fieldAt(engine, items, @floatFromInt(at));
                    defer engine.freeValue(text);
                    const value = if (at == count - 1) try v.concat(engine, &.{ text, after }) else c.JS_DupValue(engine.context, text);
                    defer engine.freeValue(value);
                    try e.invokeVoid(engine, list, "splice", &.{ v.numeric(engine, index + @as(f64, @floatFromInt(at))), v.numeric(engine, 0), value });
                }
                const tail = try v.fieldAt(engine, items, @floatFromInt(count - 1));
                defer engine.freeValue(tail);
                try e.setState(engine, object, "cursorLine", v.numeric(engine, index + @as(f64, @floatFromInt(count - 1))));
                try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, @floatFromInt(try e.length(engine, tail)))});
            }
            try e.notify(engine, object);
        },
        .deleteYankedText => {
            const ring = try js.get(engine, object, "killRing");
            defer engine.freeValue(ring);
            const text = try js.invoke(engine, ring, "peek", &.{});
            defer engine.freeValue(text);
            if (!v.truthy(engine, text)) return c.pi_js_undefined();
            const separator = try v.text(engine, "\n");
            defer engine.freeValue(separator);
            const items = try js.invoke(engine, text, "split", &.{separator});
            defer engine.freeValue(items);
            const count = try e.length(engine, items);
            const current = try e.line(engine, object);
            defer engine.freeValue(current);
            const column = try e.cursor(engine, object, "cursorCol");
            if (count == 1) {
                const amount: f64 = @floatFromInt(try e.length(engine, text));
                try e.replaceLine(engine, object, try joinEnds(engine, current, column - amount, column));
                try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, column - amount)});
            } else {
                const list = try e.lines(engine, object);
                defer engine.freeValue(list);
                const start = try e.cursor(engine, object, "cursorLine") - @as(f64, @floatFromInt(count - 1));
                const initial = try v.fieldAt(engine, list, start);
                defer engine.freeValue(initial);
                const head = try v.fieldAt(engine, items, 0);
                defer engine.freeValue(head);
                const start_col: f64 = @as(f64, @floatFromInt(try e.length(engine, initial))) - @as(f64, @floatFromInt(try e.length(engine, head)));
                const before = try slice(engine, initial, 0, start_col);
                defer engine.freeValue(before);
                const after = try slice(engine, current, column, null);
                defer engine.freeValue(after);
                const merged = try v.concat(engine, &.{ before, after });
                defer engine.freeValue(merged);
                try e.invokeVoid(engine, list, "splice", &.{ v.numeric(engine, start), v.numeric(engine, @floatFromInt(count)), merged });
                try e.setState(engine, object, "cursorLine", v.numeric(engine, start));
                try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, start_col)});
            }
            try e.notify(engine, object);
        },
        else => return null,
    }
    return c.pi_js_undefined();
}
