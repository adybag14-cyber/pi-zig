//! Source Editor mouse hit testing and visual navigation.
const std = @import("std");
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const visual = @import("native_editor_visual.zig");
const Method = @import("native_editor_methods.zig").Method;
threadlocal var move_depth: usize = 0;
pub fn supports(method: Method) bool {
    return switch (method) {
        .handleMouse, .moveToVisualLine, .pageScroll => true,
        else => false,
    };
}
fn rawCursor(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const state = try e.state(engine, object);
    defer engine.freeValue(state);
    return js.get(engine, state, name);
}
fn focused(engine: *Engine) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "handled", c.pi_js_bool(engine.context, 1));
    try js.define(engine, result, "focus", c.pi_js_bool(engine.context, 1));
    return result;
}
fn lastSegment(engine: *Engine, lines: c.JSValue, index: f64, line: c.JSValue) !bool {
    if (index == @as(f64, @floatFromInt(try e.length(engine, lines))) - 1) return true;
    const next = try v.fieldAt(engine, lines, index + 1);
    defer engine.freeValue(next);
    const next_row = if (c.JS_IsNull(next) or c.JS_IsUndefined(next)) c.pi_js_undefined() else try js.get(engine, next, "logicalLine");
    defer engine.freeValue(next_row);
    const row = try js.get(engine, line, "logicalLine");
    defer engine.freeValue(row);
    return !c.JS_IsStrictEqual(engine.context, next_row, row);
}
fn mouse(engine: *Engine, constants: c.JSValue, object: c.JSValue, event: c.JSValue) !c.JSValue {
    const auto_start = try e.number(engine, object, "renderedVisibleLineCount") + 2;
    const auto_state = try js.get(engine, object, "autocompleteState");
    defer engine.freeValue(auto_state);
    if (v.truthy(engine, auto_state)) {
        const list = try js.get(engine, object, "autocompleteList");
        defer engine.freeValue(list);
        if (v.truthy(engine, list)) {
            const y = try e.number(engine, event, "y");
            if (y >= auto_start and y < auto_start + try e.number(engine, object, "renderedAutocompleteHeight")) {
                const event_width = try e.number(engine, event, "width");
                const padding = @min(try e.number(engine, object, "paddingX"), @max(0, @floor((event_width - 1) / 2)));
                const content_width = @max(1, event_width - padding * 2);
                const method = try js.get(engine, list, "handleMouse");
                defer engine.freeValue(method);
                if (c.JS_IsNull(method) or c.JS_IsUndefined(method)) return c.pi_js_undefined();
                const adjusted = try js.spread(engine, event);
                defer engine.freeValue(adjusted);
                try js.define(engine, adjusted, "x", v.numeric(engine, (try e.number(engine, event, "x")) - padding));
                try js.define(engine, adjusted, "y", v.numeric(engine, (try e.number(engine, event, "y")) - auto_start));
                try js.define(engine, adjusted, "width", v.numeric(engine, content_width));
                try js.define(engine, adjusted, "height", try js.get(engine, object, "renderedAutocompleteHeight"));
                const result = try js.call(engine, method, list, &.{adjusted});
                defer engine.freeValue(result);
                if (!v.truthy(engine, result)) return c.pi_js_undefined();
                const output = try js.spread(engine, result);
                errdefer engine.freeValue(output);
                try js.define(engine, output, "focus", c.pi_js_bool(engine.context, 1));
                return output;
            }
        }
    }
    const kind = try js.get(engine, event, "type");
    defer engine.freeValue(kind);
    if (!try e.equalText(engine, kind, "click")) return c.pi_js_undefined();
    const button = try js.get(engine, event, "button");
    defer engine.freeValue(button);
    if (!try e.equalText(engine, button, "left")) return c.pi_js_undefined();
    const y = try e.number(engine, event, "y");
    if (y <= 0 or y > try e.number(engine, object, "renderedVisibleLineCount")) return focused(engine);
    const last_width = try js.get(engine, object, "lastWidth");
    defer engine.freeValue(last_width);
    const lines = try js.invoke(engine, object, "buildVisualLineMap", &.{last_width});
    defer engine.freeValue(lines);
    const index = try e.number(engine, object, "scrollOffset") + (try e.number(engine, event, "y")) - 1;
    const line = try v.fieldAt(engine, lines, index);
    defer engine.freeValue(line);
    if (!v.truthy(engine, line)) return focused(engine);
    const row = try js.get(engine, line, "logicalLine");
    defer engine.freeValue(row);
    const logical_lines = try e.lines(engine, object);
    defer engine.freeValue(logical_lines);
    const raw = try js.getKey(engine, logical_lines, row);
    defer engine.freeValue(raw);
    const logical = if (c.JS_IsNull(raw) or c.JS_IsUndefined(raw)) try v.text(engine, "") else c.JS_DupValue(engine.context, raw);
    defer engine.freeValue(logical);
    const start = try e.number(engine, line, "startCol");
    const chunk = try js.invoke(engine, logical, "slice", &.{ v.numeric(engine, start), v.numeric(engine, start + try e.number(engine, line, "length")) });
    defer engine.freeValue(chunk);
    const event_width = try e.number(engine, event, "width");
    const padding = @min(try e.number(engine, object, "paddingX"), @max(0, @floor((event_width - 1) / 2)));
    const target = @max(0, (try e.number(engine, event, "x")) - padding);
    var visible: f64 = 0;
    var target_index: f64 = @floatFromInt(try e.length(engine, chunk));
    var last_grapheme: f64 = 0;
    const mode = try v.text(engine, "grapheme");
    defer engine.freeValue(mode);
    const segments = try js.invoke(engine, object, "segment", &.{ chunk, mode });
    defer engine.freeValue(segments);
    const iterator_symbol = try js.get(engine, constants, "iterator");
    defer engine.freeValue(iterator_symbol);
    var iterator = try js.Iterator.init(engine, segments, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |grapheme| {
        defer engine.freeValue(grapheme);
        const text = try js.get(engine, grapheme, "segment");
        defer engine.freeValue(text);
        const next = visible + try visual.width(engine, text);
        last_grapheme = try e.number(engine, grapheme, "index");
        if (target < next) {
            target_index = last_grapheme;
            try iterator.close();
            break;
        }
        visible = next;
    }
    const chunk_length: f64 = @floatFromInt(try e.length(engine, chunk));
    if (!try lastSegment(engine, lines, index, line) and target_index == chunk_length and chunk_length > 0) target_index = last_grapheme;
    try e.setState(engine, object, "cursorLine", c.JS_DupValue(engine.context, row));
    try e.invokeVoid(engine, object, "setCursorCol", &.{v.numeric(engine, start + target_index)});
    try e.setLast(engine, object, null);
    try e.invokeVoid(engine, object, "exitHistoryBrowsing", &.{});
    const active = try js.get(engine, object, "autocompleteState");
    defer engine.freeValue(active);
    if (v.truthy(engine, active)) try e.invokeVoid(engine, object, "updateAutocomplete", &.{});
    return focused(engine);
}
fn moveVisual(engine: *Engine, constants: c.JSValue, object: c.JSValue, lines: c.JSValue, current: f64, target: f64, depth: usize) anyerror!void {
    if (depth >= 64) {
        _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum call stack size exceeded"));
        unreachable;
    }
    const source = try v.fieldAt(engine, lines, current);
    defer engine.freeValue(source);
    const destination = try v.fieldAt(engine, lines, target);
    defer engine.freeValue(destination);
    if (!v.truthy(engine, source) or !v.truthy(engine, destination)) return;
    const snapped = try js.get(engine, object, "snappedFromCursorCol");
    defer engine.freeValue(snapped);
    var current_col: f64 = undefined;
    if (!c.JS_IsNull(snapped)) {
        const row = try js.get(engine, source, "logicalLine");
        defer engine.freeValue(row);
        const index = try js.invoke(engine, object, "findVisualLineAt", &.{ lines, row, snapped });
        defer engine.freeValue(index);
        const resolved = try js.getKey(engine, lines, index);
        defer engine.freeValue(resolved);
        current_col = (try v.number(engine, snapped)) - try e.number(engine, resolved, "startCol");
    } else current_col = (try e.cursor(engine, object, "cursorCol")) - try e.number(engine, source, "startCol");
    const source_length = try e.number(engine, source, "length");
    const source_max = if (try lastSegment(engine, lines, current, source)) source_length else @max(0, source_length - 1);
    const target_length = try e.number(engine, destination, "length");
    const target_max = if (try lastSegment(engine, lines, target, destination)) target_length else @max(0, target_length - 1);
    const moved = try js.invoke(engine, object, "computeVerticalMoveColumn", &.{ v.numeric(engine, current_col), v.numeric(engine, source_max), v.numeric(engine, target_max) });
    defer engine.freeValue(moved);
    const target_row = try js.get(engine, destination, "logicalLine");
    defer engine.freeValue(target_row);
    try e.setState(engine, object, "cursorLine", c.JS_DupValue(engine.context, target_row));
    const target_col = (try e.number(engine, destination, "startCol")) + (try v.number(engine, moved));
    const logical_lines = try e.lines(engine, object);
    defer engine.freeValue(logical_lines);
    const raw = try js.getKey(engine, logical_lines, target_row);
    defer engine.freeValue(raw);
    const logical = if (v.truthy(engine, raw)) c.JS_DupValue(engine.context, raw) else try v.text(engine, "");
    defer engine.freeValue(logical);
    try e.setState(engine, object, "cursorCol", v.numeric(engine, @min(target_col, @as(f64, @floatFromInt(try e.length(engine, logical))))));
    const segments = try visual.collectSegments(engine, constants, object, logical);
    defer engine.freeValue(segments);
    for (0..try e.length(engine, segments)) |at| {
        const segment = try v.fieldAt(engine, segments, @floatFromInt(at));
        defer engine.freeValue(segment);
        const start = try e.number(engine, segment, "index");
        if (start > try e.cursor(engine, object, "cursorCol")) break;
        const text = try js.get(engine, segment, "segment");
        defer engine.freeValue(text);
        const length: f64 = @floatFromInt(try e.length(engine, text));
        if (length <= 1) continue;
        if (try e.cursor(engine, object, "cursorCol") < start + length) {
            if (start < try e.number(engine, destination, "startCol") and target > current) {
                var next = target + 1;
                while (next < @as(f64, @floatFromInt(try e.length(engine, lines)))) : (next += 1) {
                    const candidate = try v.fieldAt(engine, lines, next);
                    defer engine.freeValue(candidate);
                    const row = try js.get(engine, candidate, "logicalLine");
                    defer engine.freeValue(row);
                    if (!c.JS_IsStrictEqual(engine.context, row, target_row) or try e.number(engine, candidate, "startCol") >= start + length) break;
                }
                if (next < @as(f64, @floatFromInt(try e.length(engine, lines)))) {
                    // Preserve the actual virtual recursive dispatch.
                    try e.invokeVoid(engine, object, "moveToVisualLine", &.{ lines, v.numeric(engine, current), v.numeric(engine, next) });
                    return;
                }
            }
            try e.set(engine, object, "snappedFromCursorCol", try rawCursor(engine, object, "cursorCol"));
            try e.setState(engine, object, "cursorCol", v.numeric(engine, start));
            return;
        }
    }
    try e.set(engine, object, "snappedFromCursorCol", c.pi_js_null());
}
pub fn operation(engine: *Engine, constants: c.JSValue, object: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .handleMouse => return mouse(engine, constants, object, v.arg(args, 0)),
        .moveToVisualLine => {
            if (move_depth >= 64) return engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum call stack size exceeded"));
            move_depth += 1;
            defer move_depth -= 1;
            try moveVisual(engine, constants, object, v.arg(args, 0), try v.number(engine, v.arg(args, 1)), try v.number(engine, v.arg(args, 2)), move_depth);
        },
        .pageScroll => {
            try e.setLast(engine, object, null);
            const tui = try js.get(engine, object, "tui");
            defer engine.freeValue(tui);
            const terminal = try js.get(engine, tui, "terminal");
            defer engine.freeValue(terminal);
            const page = @max(5, @floor((try e.number(engine, terminal, "rows")) * 0.3));
            const last_width = try js.get(engine, object, "lastWidth");
            defer engine.freeValue(last_width);
            const lines = try js.invoke(engine, object, "buildVisualLineMap", &.{last_width});
            defer engine.freeValue(lines);
            const current = try js.invoke(engine, object, "findCurrentVisualLine", &.{lines});
            defer engine.freeValue(current);
            const target = @max(0, @min(@as(f64, @floatFromInt(try e.length(engine, lines))) - 1, (try v.number(engine, current)) + (try v.number(engine, v.arg(args, 0))) * page));
            try e.invokeVoid(engine, object, "moveToVisualLine", &.{ lines, current, v.numeric(engine, target) });
        },
        else => unreachable,
    }
    return c.pi_js_undefined();
}
