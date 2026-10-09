//! Source Editor borders and rendering over the authoritative JS state.
const e = @import("native_editor_values.zig");
const js = e.js;
const c = e.c;
const v = e.v;
const Engine = e.Engine;
const visual = @import("native_editor_visual.zig");
const Method = @import("native_editor_methods.zig").Method;
pub fn supports(method: Method) bool {
    return method == .render or method == .renderTopBorder or method == .renderBottomBorder;
}
fn repeat(engine: *Engine, text: []const u8, count: f64) !c.JSValue {
    const value = try v.text(engine, text);
    defer engine.freeValue(value);
    return js.invoke(engine, value, "repeat", &.{v.numeric(engine, count)});
}
fn scrollBorder(engine: *Engine, direction: []const u8, hidden: c.JSValue, requested: f64) !c.JSValue {
    const available = @max(0, requested);
    const space = try v.text(engine, " ");
    defer engine.freeValue(space);
    const arrow = try v.text(engine, direction);
    defer engine.freeValue(arrow);
    const ending = try v.text(engine, " more ");
    defer engine.freeValue(ending);
    const label = try v.concat(engine, &.{ space, arrow, space, hidden, ending });
    defer engine.freeValue(label);
    const label_width = try visual.width(engine, label);
    if (label_width + 2 <= available) {
        const left_width = @floor((available - label_width) / 2);
        const left = try repeat(engine, "─", left_width);
        defer engine.freeValue(left);
        const right = try repeat(engine, "─", available - left_width - label_width);
        defer engine.freeValue(right);
        return v.concat(engine, &.{ left, label, right });
    }
    const prefix = try v.text(engine, "─── ");
    defer engine.freeValue(prefix);
    const indicator = try v.concat(engine, &.{ prefix, arrow, space, hidden, ending });
    defer engine.freeValue(indicator);
    const remaining = available - try visual.width(engine, indicator);
    if (remaining >= 0) {
        const right = try repeat(engine, "─", remaining);
        defer engine.freeValue(right);
        return v.concat(engine, &.{ indicator, right });
    }
    const dots = try v.text(engine, "...");
    defer engine.freeValue(dots);
    const ellipsis = try js.invoke(engine, dots, "slice", &.{ v.numeric(engine, 0), v.numeric(engine, available) });
    defer engine.freeValue(ellipsis);
    const indicator_width = available - try visual.width(engine, ellipsis);
    const units = try e.utf16.unitsAlloc(engine, indicator);
    defer engine.gpa.free(units);
    const clipped = try @import("../tui/utf16_terminal.zig").sliceAlloc(engine.gpa, units, 0, @intFromFloat(@max(0, indicator_width)));
    defer engine.gpa.free(clipped);
    const text = try e.utf16.string(engine, clipped);
    defer engine.freeValue(text);
    return v.concat(engine, &.{ text, ellipsis });
}
fn hasCursorCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return js.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "hasCursor") catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowOutOfMemory(context);
    };
}
fn render(engine: *Engine, constants: c.JSValue, object: c.JSValue, requested: c.JSValue) !c.JSValue {
    const requested_width = try v.number(engine, requested);
    const max_padding = @max(0, @floor((requested_width - 1) / 2));
    const padding_x = @min(try e.number(engine, object, "paddingX"), max_padding);
    const content_width = @max(1, requested_width - padding_x * 2);
    const layout_width = @max(1, content_width - if (padding_x != 0) @as(f64, 0) else @as(f64, 1));
    try e.set(engine, object, "lastWidth", v.numeric(engine, layout_width));
    const lines = try js.invoke(engine, object, "layoutText", &.{v.numeric(engine, layout_width)});
    defer engine.freeValue(lines);
    const tui = try js.get(engine, object, "tui");
    defer engine.freeValue(tui);
    const terminal_object = try js.get(engine, tui, "terminal");
    defer engine.freeValue(terminal_object);
    const maximum = @max(5, @floor((try e.number(engine, terminal_object, "rows")) * 0.3));
    const predicate = try engine.checked(c.pi_js_function_magic(engine.context, hasCursorCallback, "", 1, 0));
    defer engine.freeValue(predicate);
    const found = try js.invoke(engine, lines, "findIndex", &.{predicate});
    defer engine.freeValue(found);
    const cursor_line = if (c.JS_IsStrictEqual(engine.context, found, v.numeric(engine, -1))) @as(f64, 0) else try v.number(engine, found);
    var scroll = try e.number(engine, object, "scrollOffset");
    if (cursor_line < scroll) try e.set(engine, object, "scrollOffset", v.numeric(engine, cursor_line)) else if (cursor_line >= scroll + maximum) try e.set(engine, object, "scrollOffset", v.numeric(engine, cursor_line - maximum + 1));
    const max_scroll = @max(0, @as(f64, @floatFromInt(try e.length(engine, lines))) - maximum);
    scroll = @max(0, @min(try e.number(engine, object, "scrollOffset"), max_scroll));
    try e.set(engine, object, "scrollOffset", v.numeric(engine, scroll));
    const visible = try js.invoke(engine, lines, "slice", &.{ v.numeric(engine, scroll), v.numeric(engine, scroll + maximum) });
    defer engine.freeValue(visible);
    try e.set(engine, object, "renderedVisibleLineCount", v.numeric(engine, @floatFromInt(try e.length(engine, visible))));
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    const left_padding = try repeat(engine, " ", padding_x);
    defer engine.freeValue(left_padding);
    const top = try js.invoke(engine, object, "renderTopBorder", &.{ requested, v.numeric(engine, scroll) });
    defer engine.freeValue(top);
    try js.push(engine, result, top);
    const focused = try js.get(engine, object, "focused");
    defer engine.freeValue(focused);
    const hardware = try v.text(engine, if (v.truthy(engine, focused)) @import("../tui/cursor_markers.zig").cursor else "");
    defer engine.freeValue(hardware);
    const fake_start = try v.text(engine, @import("../tui/cursor_markers.zig").fake_start);
    defer engine.freeValue(fake_start);
    const fake_end = try v.text(engine, @import("../tui/cursor_markers.zig").fake_end);
    defer engine.freeValue(fake_end);
    const iterator_symbol = try js.get(engine, constants, "iterator");
    defer engine.freeValue(iterator_symbol);
    var iterator = try js.Iterator.init(engine, visible, iterator_symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |line| {
        defer engine.freeValue(line);
        var display = try js.get(engine, line, "text");
        defer engine.freeValue(display);
        var line_width = try visual.width(engine, display);
        var cursor_in_padding = false;
        const has_cursor = try js.get(engine, line, "hasCursor");
        defer engine.freeValue(has_cursor);
        if (v.truthy(engine, has_cursor)) {
            const position = try js.get(engine, line, "cursorPos");
            defer engine.freeValue(position);
            if (!c.JS_IsUndefined(position)) {
                const before = try js.invoke(engine, display, "slice", &.{ v.numeric(engine, 0), position });
                defer engine.freeValue(before);
                const after = try js.invoke(engine, display, "slice", &.{position});
                defer engine.freeValue(after);
                var next: c.JSValue = undefined;
                if (try e.length(engine, after) > 0) {
                    const segments = try visual.collectSegments(engine, constants, object, after);
                    defer engine.freeValue(segments);
                    const first = try v.fieldAt(engine, segments, 0);
                    defer engine.freeValue(first);
                    const raw = if (c.JS_IsUndefined(first) or c.JS_IsNull(first)) c.pi_js_undefined() else try js.get(engine, first, "segment");
                    defer engine.freeValue(raw);
                    const grapheme = if (v.truthy(engine, raw)) c.JS_DupValue(engine.context, raw) else try v.text(engine, "");
                    defer engine.freeValue(grapheme);
                    const rest = try js.invoke(engine, after, "slice", &.{v.numeric(engine, @floatFromInt(try e.length(engine, grapheme)))});
                    defer engine.freeValue(rest);
                    next = try v.concat(engine, &.{ before, hardware, fake_start, grapheme, fake_end, rest });
                } else {
                    const space = try v.text(engine, " ");
                    defer engine.freeValue(space);
                    next = try v.concat(engine, &.{ before, hardware, fake_start, space, fake_end });
                    line_width += 1;
                    cursor_in_padding = line_width > content_width and padding_x > 0;
                }
                engine.freeValue(display);
                display = next;
            }
        }
        const fill = try repeat(engine, " ", @max(0, content_width - line_width));
        defer engine.freeValue(fill);
        const right = if (cursor_in_padding) try js.invoke(engine, left_padding, "slice", &.{v.numeric(engine, 1)}) else c.JS_DupValue(engine.context, left_padding);
        defer engine.freeValue(right);
        const text = try v.concat(engine, &.{ left_padding, display, fill, right });
        defer engine.freeValue(text);
        try js.push(engine, result, text);
    }
    const below = @as(f64, @floatFromInt(try e.length(engine, lines))) - (try e.number(engine, object, "scrollOffset") + @as(f64, @floatFromInt(try e.length(engine, visible))));
    const bottom = try js.invoke(engine, object, "renderBottomBorder", &.{ requested, v.numeric(engine, below) });
    defer engine.freeValue(bottom);
    try js.push(engine, result, bottom);
    try e.set(engine, object, "renderedAutocompleteHeight", v.numeric(engine, 0));
    const state = try js.get(engine, object, "autocompleteState");
    defer engine.freeValue(state);
    if (v.truthy(engine, state)) {
        const list = try js.get(engine, object, "autocompleteList");
        defer engine.freeValue(list);
        if (v.truthy(engine, list)) {
            const auto = try js.invoke(engine, list, "render", &.{v.numeric(engine, content_width)});
            defer engine.freeValue(auto);
            try e.set(engine, object, "renderedAutocompleteHeight", v.numeric(engine, @floatFromInt(try e.length(engine, auto))));
            var auto_iterator = try js.Iterator.init(engine, auto, iterator_symbol);
            defer auto_iterator.deinit();
            errdefer auto_iterator.closePreserving();
            while (try auto_iterator.next()) |line| {
                defer engine.freeValue(line);
                const fill = try repeat(engine, " ", @max(0, content_width - try visual.width(engine, line)));
                defer engine.freeValue(fill);
                const text = try v.concat(engine, &.{ left_padding, line, fill, left_padding });
                defer engine.freeValue(text);
                try js.push(engine, result, text);
            }
        }
    }
    return result;
}
pub fn operation(engine: *Engine, constants: c.JSValue, object: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const first = v.arg(args, 0);
    if (method == .render) return render(engine, constants, object, first);
    const border = if (try v.number(engine, v.arg(args, 1)) > 0) try scrollBorder(engine, if (method == .renderTopBorder) "↑" else "↓", v.arg(args, 1), try v.number(engine, first)) else try repeat(engine, "─", try v.number(engine, first));
    defer engine.freeValue(border);
    return js.invoke(engine, object, "borderColor", &.{border});
}
