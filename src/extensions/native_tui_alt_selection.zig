//! Source Unicode word/line/character selection, auto-scroll and clipboard promises.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
const v = a.v;
const callbacks = @import("native_tui_alt_callbacks.zig");
pub const Method = enum(c_int) { getScrollSelectionPoint, getSelectionPoint, getSelectionSourceLine, getWordSelection, getLineSelection, updateSelectionFocus, getClickCount, updateSelectionAutoScroll, autoScrollSelection, stopSelectionAutoScroll, handleSelectionMouseEvent, getSelectionBounds, getSelectionColumns, getActiveSelectionText, copyActiveSelectionToClipboard, copySelectionToClipboard, copyTextToClipboard, applySelectionHighlight, applySelection };
fn endpoint(f: *Frame, point: c.JSValue, column: f64, boundary: bool) !c.JSValue {
    const output = try f.spread(point);
    try f.define(output, "col", f.num(column));
    if (boundary) try f.define(output, "boundary", f.boolean(true));
    return output;
}
fn range(f: *Frame, start: c.JSValue, end: c.JSValue) !c.JSValue {
    const output = try f.record();
    try f.define(output, "start", start);
    try f.define(output, "end", end);
    return output;
}
fn optional(f: *Frame, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (f.nullish(object)) c.pi_js_undefined() else f.get(object, name);
}
fn sourceLine(f: *Frame, point: c.JSValue) !c.JSValue {
    if (f.truth(try f.get(point, "scrollView")) and f.truth(try f.field("currentLayout"))) {
        const box = try f.imported("getScrollViewBox", &.{ try f.field("currentLayout"), try f.get(point, "scrollView") });
        const lines = try optional(f, box, "scrollContentLines");
        if (f.truth(lines)) return f.emptyLine(lines, try f.n(point, "row"));
    }
    return f.emptyLine(try f.field("previousScreen"), try f.n(point, "row"));
}
fn scrollPoint(f: *Frame, scroll: c.JSValue, x: f64, y: f64) !c.JSValue {
    if (!f.truth(try f.field("currentLayout"))) return c.pi_js_undefined();
    const box = try f.imported("getScrollViewBox", &.{ try f.field("currentLayout"), scroll });
    if (!f.truth(box)) return c.pi_js_undefined();
    const area = try f.get(box, "rect");
    const clip = try f.get(box, "clip");
    if (try f.n(area, "height") <= 0 or try f.n(clip, "height") <= 0) return c.pi_js_undefined();
    const top = try f.math("max", &.{ f.num(0), try f.get(area, "y"), try f.get(clip, "y") });
    const bottom = try f.math("min", &.{ f.num(try f.n(try f.field("terminal"), "rows") - 1), f.num(try f.n(area, "y") + try f.n(area, "height") - 1), f.num(try f.n(clip, "y") + try f.n(clip, "height") - 1) });
    if (bottom < top) return c.pi_js_undefined();
    const pointer = try f.math("max", &.{ f.num(top), f.num(try f.math("min", &.{ f.num(bottom), f.num(y) })) });
    const lines = try f.get(box, "scrollContentLines");
    const length = if (f.nullish(lines)) 1 else try f.n(lines, "length");
    const max_row = try f.math("max", &.{ f.num(0), f.num(length - 1) });
    const output = try f.record();
    try f.define(output, "row", f.num(try f.math("max", &.{ f.num(0), f.num(try f.math("min", &.{ f.num(max_row), f.num(try f.n(scroll, "scrollTop") + pointer - try f.n(area, "y")) })) })));
    try f.define(output, "col", f.num(try f.math("max", &.{ f.num(0), f.num(try f.math("min", &.{ f.num(try f.n(area, "width") - 1), f.num(x - try f.n(area, "x")) })) })));
    try f.define(output, "scrollView", scroll);
    return output;
}
fn selectionPoint(f: *Frame, event: c.JSValue, scroll: c.JSValue) !c.JSValue {
    if (f.truth(scroll)) {
        const point = try f.invoke("getScrollSelectionPoint", &.{ scroll, try f.get(event, "x"), try f.get(event, "y") });
        if (f.truth(point)) return point;
    }
    const output = try f.record();
    try f.define(output, "row", f.num(try f.math("max", &.{ f.num(0), f.num(try f.math("min", &.{ f.num(try f.n(try f.field("terminal"), "rows") - 1), try f.get(event, "y") })) })));
    try f.define(output, "col", f.num(try f.math("max", &.{ f.num(0), f.num(try f.math("min", &.{ f.num(try f.n(try f.field("terminal"), "columns") - 1), try f.get(event, "x") })) })));
    return output;
}
fn word(f: *Frame, point: c.JSValue) !c.JSValue {
    const line = try f.imported("stripTerminalSequences", &.{try f.invoke("getSelectionSourceLine", &.{point})});
    const units = try @import("native_utf16.zig").unitsAlloc(f.engine, line);
    defer f.engine.gpa.free(units);
    const pieces = try @import("../tui/utf16_words.zig").segmentsAlloc(f.engine.gpa, units);
    defer f.engine.gpa.free(pieces);
    const segments = try f.array();
    var start: f64 = 0;
    for (pieces) |piece| {
        const text = try f.own(try @import("native_utf16.zig").string(f.engine, units[piece.start..piece.end]));
        const end = start + try f.width(text);
        const joiner = try f.method(try f.get(f.bindings, "wordJoiners"), "has", &.{text});
        const segment = try f.record();
        try f.define(segment, "start", f.num(start));
        try f.define(segment, "end", f.num(end));
        try f.define(segment, "selectable", if (piece.word) f.boolean(true) else joiner);
        try f.define(segment, "joiner", joiner);
        try f.push(segments, segment);
        start = end;
    }
    const find = try f.get(segments, "findIndex");
    const index = try f.number(try f.call(find, segments, &.{try callbacks.create(f, .clickedSegment, point)}));
    if (index < 0) return c.pi_js_undefined();
    var selection_start = try f.n(try f.at(segments, index), "start");
    var selection_end = try f.n(try f.at(segments, index), "end");
    var left = index;
    while (left > 0) {
        const previous = try f.at(segments, left - 1);
        const current = try f.at(segments, left);
        if (!(f.truth(try f.get(previous, "selectable")) and f.truth(try f.get(current, "selectable")) and (f.truth(try f.get(previous, "joiner")) or f.truth(try f.get(current, "joiner"))))) break;
        selection_start = try f.n(try f.at(segments, left - 1), "start");
        left -= 1;
    }
    var right = index;
    while (right < try f.n(segments, "length") - 1) {
        const current = try f.at(segments, right);
        const next = try f.at(segments, right + 1);
        if (!(f.truth(try f.get(current, "selectable")) and f.truth(try f.get(next, "selectable")) and (f.truth(try f.get(current, "joiner")) or f.truth(try f.get(next, "joiner"))))) break;
        selection_end = try f.n(try f.at(segments, right + 1), "end");
        right += 1;
    }
    return range(f, try endpoint(f, point, selection_start, false), try endpoint(f, point, selection_end, true));
}
fn updateFocus(f: *Frame, point: c.JSValue) !void {
    if (try f.is(try f.field("selectionGranularity"), "character") or !f.truth(try f.field("selectionInitialRange"))) {
        try f.put("selectionFocus", point);
        return;
    }
    const selected = try f.invoke(if (try f.is(try f.field("selectionGranularity"), "word")) "getWordSelection" else "getLineSelection", &.{point});
    if (!f.truth(selected)) return;
    const initial = try f.field("selectionInitialRange");
    const start = try f.get(selected, "start");
    const base = try f.get(initial, "start");
    const before = try f.n(start, "row") < try f.n(base, "row") or (f.equal(try f.get(start, "row"), try f.get(base, "row")) and try f.n(start, "col") < try f.n(base, "col"));
    try f.put("selectionAnchor", try f.get(initial, if (before) "end" else "start"));
    try f.put("selectionFocus", try f.get(selected, if (before) "start" else "end"));
}
fn click(f: *Frame, point: c.JSValue, selected: c.JSValue) !c.JSValue {
    const now = try f.method(try f.global("Date"), "now", &.{});
    const previous = try f.field("lastClick");
    var count: f64 = 1;
    if (f.truth(selected) and f.truth(previous) and try f.number(now) - try f.n(previous, "timestamp") <= 500 and f.equal(try f.get(previous, "row"), try f.get(point, "row")) and f.equal(try f.get(previous, "scrollView"), try f.get(point, "scrollView")) and f.equal(try f.get(previous, "wordStart"), try f.get(try f.get(selected, "start"), "col")) and f.equal(try f.get(previous, "wordEnd"), try f.get(try f.get(selected, "end"), "col"))) count = @mod(try f.n(previous, "count"), 3) + 1;
    var next: c.JSValue = c.pi_js_undefined();
    if (f.truth(selected)) {
        next = try f.record();
        try f.define(next, "timestamp", now);
        try f.define(next, "count", f.num(count));
        try f.define(next, "row", try f.get(point, "row"));
        try f.define(next, "scrollView", try f.get(point, "scrollView"));
        try f.define(next, "wordStart", try f.get(try f.get(selected, "start"), "col"));
        try f.define(next, "wordEnd", try f.get(try f.get(selected, "end"), "col"));
    }
    try f.put("lastClick", next);
    return f.num(count);
}
fn updateAuto(f: *Frame, event: c.JSValue) !void {
    const scroll = try optional(f, try f.field("selectionAnchor"), "scrollView");
    if (!f.truth(scroll) or !f.truth(try f.field("currentLayout"))) {
        _ = try f.invoke("stopSelectionAutoScroll", &.{});
        return;
    }
    const box = try f.imported("getScrollViewBox", &.{ try f.field("currentLayout"), scroll });
    if (!f.truth(box)) {
        _ = try f.invoke("stopSelectionAutoScroll", &.{});
        return;
    }
    const area = try f.get(box, "rect");
    const clip = try f.get(box, "clip");
    if (try f.n(area, "height") <= 0 or try f.n(clip, "height") <= 0) {
        _ = try f.invoke("stopSelectionAutoScroll", &.{});
        return;
    }
    const top = try f.math("max", &.{ f.num(0), try f.get(area, "y"), try f.get(clip, "y") });
    const bottom = try f.math("min", &.{ f.num(try f.n(try f.field("terminal"), "rows") - 1), f.num(try f.n(area, "y") + try f.n(area, "height") - 1), f.num(try f.n(clip, "y") + try f.n(clip, "height") - 1) });
    const pointer = try f.record();
    try f.define(pointer, "x", try f.get(event, "x"));
    try f.define(pointer, "y", try f.get(event, "y"));
    try f.put("selectionDragPointer", pointer);
    try f.put("selectionAutoScrollDirection", f.num(if (try f.n(event, "y") <= top) -1 else if (try f.n(event, "y") >= bottom) 1 else 0));
    if (f.equal(try f.field("selectionAutoScrollDirection"), f.num(0))) {
        _ = try f.invoke("stopSelectionAutoScroll", &.{});
        return;
    }
    if (f.truth(try f.field("selectionAutoScrollTimer"))) return;
    try f.put("selectionAutoScrollTimer", try f.call(try f.global("setInterval"), c.pi_js_undefined(), &.{ try @import("native_tui_alt_state.zig").autoScrollClosure(f), f.num(50) }));
    _ = try f.method(try f.field("selectionAutoScrollTimer"), "unref", &.{});
}
fn bounds(f: *Frame) !c.JSValue {
    if (!f.truth(try f.field("selectionAnchor")) or !f.truth(try f.field("selectionFocus"))) return c.pi_js_undefined();
    const anchor = try f.field("selectionAnchor");
    const focus = try f.field("selectionFocus");
    if (!f.equal(try f.get(anchor, "scrollView"), try f.get(focus, "scrollView"))) return c.pi_js_undefined();
    const before = try f.n(anchor, "row") < try f.n(focus, "row") or (f.equal(try f.get(anchor, "row"), try f.get(focus, "row")) and try f.n(anchor, "col") < try f.n(focus, "col"));
    if (f.equal(try f.get(anchor, "row"), try f.get(focus, "row")) and f.equal(try f.get(anchor, "col"), try f.get(focus, "col"))) return c.pi_js_undefined();
    return range(f, if (before) anchor else focus, if (before) focus else anchor);
}
fn columns(f: *Frame, args: []const c.JSValue) !c.JSValue {
    const line = v.arg(args, 0);
    const row = v.arg(args, 1);
    const selected = v.arg(args, 2);
    const minimum = if (c.JS_IsUndefined(v.arg(args, 3))) f.num(0) else v.arg(args, 3);
    const maximum = if (c.JS_IsUndefined(v.arg(args, 4))) f.num(try f.width(line)) else v.arg(args, 4);
    const width = try f.width(line);
    var start = try f.math("max", &.{ f.num(0), minimum });
    var end = try f.math("min", &.{ f.num(width), maximum });
    const begin = try f.get(selected, "start");
    const finish = try f.get(selected, "end");
    if (f.equal(row, try f.get(begin, "row"))) {
        const grapheme = try f.imported("getGraphemeCellRange", &.{ line, try f.get(begin, "col") });
        const position = try optional(f, grapheme, "start");
        start = if (f.nullish(position)) try f.math("min", &.{ try f.get(begin, "col"), f.num(width) }) else try f.number(position);
    }
    if (f.equal(row, try f.get(finish, "row"))) {
        if (f.truth(try f.get(finish, "boundary"))) end = try f.math("min", &.{ try f.get(finish, "col"), f.num(width) }) else {
            const grapheme = try f.imported("getGraphemeCellRange", &.{ line, try f.get(finish, "col") });
            const position = try optional(f, grapheme, "end");
            end = if (f.nullish(position)) try f.math("min", &.{ try f.add(try f.get(finish, "col"), f.num(1)), f.num(width) }) else try f.number(position);
        }
    }
    const result = try f.record();
    try f.define(result, "start", f.num(try f.math("max", &.{ minimum, f.num(start) })));
    try f.define(result, "end", f.num(try f.math("min", &.{ maximum, f.num(end) })));
    return result;
}
fn activeText(f: *Frame) !c.JSValue {
    const selected = try f.invoke("getSelectionBounds", &.{});
    if (!f.truth(selected)) return c.pi_js_undefined();
    var source = try f.field("previousScreen");
    const start = try f.get(selected, "start");
    const scroll = try f.get(start, "scrollView");
    if (f.truth(scroll)) {
        if (!f.truth(try f.field("currentLayout"))) return c.pi_js_undefined();
        const box = try f.imported("getScrollViewBox", &.{ try f.field("currentLayout"), try f.get(try f.get(selected, "start"), "scrollView") });
        if (!f.truth(try optional(f, box, "scrollContentLines"))) return c.pi_js_undefined();
        source = try f.get(box, "scrollContentLines");
    }
    const lines = try f.array();
    var row = try f.n(try f.get(selected, "start"), "row");
    while (row <= try f.n(try f.get(selected, "end"), "row")) : (row += 1) {
        const line = try f.emptyLine(source, row);
        const cols = try f.invoke("getSelectionColumns", &.{ line, f.num(row), selected });
        const cut = try f.imported("sliceByColumn", &.{ line, try f.get(cols, "start"), f.num(try f.math("max", &.{ f.num(0), f.num(try f.n(cols, "end") - try f.n(cols, "start")) })), f.boolean(true) });
        try f.push(lines, try f.method(try f.imported("stripTerminalSequences", &.{cut}), "trimEnd", &.{}));
    }
    const text = try f.method(lines, "join", &.{try f.text("\n")});
    return if (f.equal(try f.get(text, "length"), f.num(0))) c.pi_js_undefined() else text;
}
fn copied(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = data[0], .bindings = data[1] };
    defer f.deinit();
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    const ok = f.equal(value, f.boolean(true));
    const message = if (ok) f.text("Copied!") else if (c.JS_IsString(value)) value else f.text("Copy failed");
    const text = message catch |err| return a.fail(engine, err);
    _ = f.invoke("flash", &.{ text, if (ok) c.pi_js_undefined() else f.num(5000) }) catch |err| return a.fail(engine, err);
    return f.boolean(ok);
}
pub fn resolved(f: *Frame, value: c.JSValue) !c.JSValue {
    var capabilities: [2]c.JSValue = undefined;
    const created = try f.engine.checked(c.JS_NewPromiseCapability(f.engine.context, &capabilities));
    defer for (capabilities) |function| f.engine.freeValue(function);
    const promise = try f.own(created);
    _ = try f.call(capabilities[0], c.pi_js_undefined(), &.{value});
    return promise;
}
fn copyText(f: *Frame, text: c.JSValue) !c.JSValue {
    if (f.truth(try f.field("copySelection"))) {
        const value = try f.invoke("copySelection", &.{text});
        const promise = try resolved(f, value);
        var data = [_]c.JSValue{ f.object, f.bindings };
        const handler = try f.own(try f.engine.checked(c.JS_NewCFunctionData2(f.engine.context, copied, "", 1, 0, 2, &data)));
        return f.own(try f.engine.checked(c.JS_PromiseThen(f.engine.context, promise, handler, c.pi_js_undefined())));
    }
    const buffer = try f.method(try f.global("Buffer"), "from", &.{text});
    const encoded = try f.method(buffer, "toString", &.{try f.text("base64")});
    try f.write(try f.concat(&.{ try f.text("\x1b]52;c;"), encoded, try f.text("\x07") }));
    _ = try f.invoke("flash", &.{try f.text("Copied!")});
    return f.boolean(true);
}
fn selectionHighlight(f: *Frame, text: c.JSValue) !c.JSValue {
    var result = try f.text("\x1b[7m");
    var index: f64 = 0;
    while (index < try f.n(text, "length")) {
        const ansi = try f.imported("extractAnsiCode", &.{ text, f.num(index) });
        if (!f.truth(ansi)) {
            result = try f.add(result, try f.at(text, index));
            index += 1;
            continue;
        }
        result = try f.add(result, try f.get(ansi, "code"));
        if (f.truth(try f.method(try f.get(ansi, "code"), "endsWith", &.{try f.text("m")}))) result = try f.add(result, try f.text("\x1b[7m"));
        index += try f.n(ansi, "length");
    }
    return f.concat(&.{ result, try f.text("\x1b[27m") });
}
fn applySelection(f: *Frame, screen: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const layout = if (c.JS_IsUndefined(supplied)) try f.field("currentLayout") else supplied;
    const selected = try f.invoke("getSelectionBounds", &.{});
    if (!f.truth(selected)) return screen;
    var screen_selection = selected;
    var min_row: f64 = 0;
    var max_row = try f.n(screen, "length") - 1;
    var min_col: f64 = 0;
    var max_col = try f.n(try f.field("terminal"), "columns");
    const start = try f.get(selected, "start");
    const scroll = try f.get(start, "scrollView");
    if (f.truth(scroll)) {
        if (!f.truth(layout)) return screen;
        const box = try f.imported("getScrollViewBox", &.{ layout, try f.get(try f.get(selected, "start"), "scrollView") });
        if (!f.truth(box)) return screen;
        const area = try f.get(box, "rect");
        const clip = try f.get(box, "clip");
        min_row = try f.math("max", &.{ f.num(0), try f.get(area, "y"), try f.get(clip, "y") });
        max_row = try f.math("min", &.{ f.num(try f.n(screen, "length") - 1), f.num(try f.n(area, "y") + try f.n(area, "height") - 1), f.num(try f.n(clip, "y") + try f.n(clip, "height") - 1) });
        min_col = try f.math("max", &.{ f.num(0), try f.get(area, "x"), try f.get(clip, "x") });
        max_col = try f.math("min", &.{ try f.get(try f.field("terminal"), "columns"), f.num(try f.n(area, "x") + try f.n(area, "width")), f.num(try f.n(clip, "x") + try f.n(clip, "width")) });
        const first = try f.spread(try f.get(selected, "start"));
        const last = try f.spread(try f.get(selected, "end"));
        try f.define(first, "row", f.num(try f.n(area, "y") + try f.n(try f.get(selected, "start"), "row") - try f.n(scroll, "scrollTop")));
        try f.define(first, "col", f.num(try f.n(area, "x") + try f.n(try f.get(selected, "start"), "col")));
        try f.define(last, "row", f.num(try f.n(area, "y") + try f.n(try f.get(selected, "end"), "row") - try f.n(scroll, "scrollTop")));
        try f.define(last, "col", f.num(try f.n(area, "x") + try f.n(try f.get(selected, "end"), "col")));
        screen_selection = try range(f, first, last);
    }
    const capture = try f.record();
    try f.define(capture, "selection", screen_selection);
    try f.define(capture, "minRow", f.num(min_row));
    try f.define(capture, "maxRow", f.num(max_row));
    try f.define(capture, "minColumn", f.num(min_col));
    try f.define(capture, "maxColumn", f.num(max_col));
    return callbacks.map(f, screen, .selectionLine, capture);
}
pub fn selectionLine(f: *Frame, line: c.JSValue, raw_row: c.JSValue, capture: c.JSValue) anyerror!c.JSValue {
    const selected = try f.get(capture, "selection");
    if (try f.number(raw_row) < try f.n(capture, "minRow") or try f.number(raw_row) > try f.n(capture, "maxRow") or try f.number(raw_row) < try f.n(try f.get(selected, "start"), "row") or try f.number(raw_row) > try f.n(try f.get(selected, "end"), "row") or f.truth(try f.imported("isImageLine", &.{line}))) return line;
    const width = try f.width(line);
    const cols = try f.invoke("getSelectionColumns", &.{ line, raw_row, selected, try f.get(capture, "minColumn"), try f.get(capture, "maxColumn") });
    const start = try f.n(cols, "start");
    const end = try f.n(cols, "end");
    if (end <= start) return line;
    const before = try f.imported("sliceByColumn", &.{ line, f.num(0), f.num(start), f.boolean(true) });
    const middle = try f.imported("sliceByColumn", &.{ line, f.num(start), f.num(end - start), f.boolean(true) });
    const after = try f.imported("sliceByColumn", &.{ line, f.num(end), f.num(try f.math("max", &.{ f.num(0), f.num(width - end) })), f.boolean(true) });
    return f.concat(&.{ before, try f.invoke("applySelectionHighlight", &.{middle}), after });
}
fn handleEvent(f: *Frame, event: c.JSValue) !void {
    const button = try @import("native_tui_alt_mouse.zig").bits(f, try f.get(event, "button")) & 3;
    if (button != 0 and !(f.truth(try f.get(event, "release")) and button == 3)) return;
    const scroll = try optional(f, try f.field("selectionAnchor"), "scrollView");
    const point = try f.invoke("getSelectionPoint", &.{ event, scroll });
    if (f.truth(try f.get(event, "release"))) {
        if (!f.truth(try f.field("selectionPressActive"))) return;
        try f.put("selectionPressActive", f.boolean(false));
        _ = try f.invoke("stopSelectionAutoScroll", &.{});
        if (!f.truth(try f.field("selectionAnchor"))) return;
        _ = try f.invoke("updateSelectionFocus", &.{point});
        const anchor = try f.field("selectionAnchor");
        const is_click = !f.truth(try f.field("selectionDragged")) and f.equal(try f.get(anchor, "scrollView"), try f.get(point, "scrollView")) and f.equal(try f.get(anchor, "row"), try f.get(point, "row")) and f.equal(try f.get(anchor, "col"), try f.get(point, "col"));
        const url = if (is_click) try f.field("pressedUrl") else c.pi_js_undefined();
        try f.put("pressedUrl", c.pi_js_undefined());
        if (f.truth(url) and f.truth(try f.field("openUrl"))) {
            try f.put("selectionAnchor", c.pi_js_undefined());
            try f.put("selectionFocus", c.pi_js_undefined());
            _ = f.invoke("openUrl", &.{url}) catch |err| blk: {
                if (err != error.JavaScriptException) return err;
                break :blk c.pi_js_undefined();
            };
            _ = try f.invoke("requestRender", &.{});
            return;
        }
        if (is_click) {
            const extra = try f.record();
            const count = try optional(f, try f.field("lastClick"), "count");
            try f.define(extra, "clickCount", if (f.nullish(count)) f.num(1) else count);
            const click_event = try f.invoke("createMouseEvent", &.{ try f.text("click"), try f.get(event, "button"), try f.get(event, "x"), try f.get(event, "y"), extra });
            const overlay = try f.invoke("dispatchMouseToOverlay", &.{click_event});
            const hit = try f.get(overlay, "result");
            const result = if (!f.nullish(hit)) hit else if (f.truth(try f.get(overlay, "hit"))) c.pi_js_undefined() else try f.invoke("dispatchMouseToLayout", &.{click_event});
            if (f.truth(result)) {
                const render = try f.invoke("applyMouseDispatchResult", &.{ click_event, result });
                _ = try f.invoke("clearTextSelection", &.{});
                if (f.truth(render)) _ = try f.invoke("requestRender", &.{});
                return;
            }
        }
        if (f.truth(try f.field("copyOnSelect"))) _ = try f.invoke("copySelectionToClipboard", &.{});
        _ = try f.invoke("requestRender", &.{});
        return;
    }
    if ((try @import("native_tui_alt_mouse.zig").bits(f, try f.get(event, "button")) & 32) != 0) {
        if (!f.truth(try f.field("selectionPressActive")) or !f.truth(try f.field("selectionAnchor"))) return;
        try f.put("selectionDragged", f.boolean(true));
        try f.put("lastClick", c.pi_js_undefined());
        try f.put("pressedUrl", c.pi_js_undefined());
        _ = try f.invoke("updateSelectionFocus", &.{point});
        _ = try f.invoke("updateSelectionAutoScroll", &.{event});
        _ = try f.invoke("requestRender", &.{});
        return;
    }
    _ = try f.invoke("stopSelectionAutoScroll", &.{});
    try f.put("selectionPressActive", f.boolean(true));
    const target = if (!f.truth(try f.invoke("hasOverlay", &.{})) and f.truth(try f.field("currentLayout"))) try f.at(try f.imported("getScrollViewsAt", &.{ try f.field("currentLayout"), try f.get(event, "x"), try f.get(event, "y") }), 0) else c.pi_js_undefined();
    const anchor = try f.invoke("getSelectionPoint", &.{ event, target });
    const selected_word = try f.invoke("getWordSelection", &.{anchor});
    const count = try f.invoke("getClickCount", &.{ anchor, selected_word });
    const selected = if (f.equal(count, f.num(2))) selected_word else if (f.equal(count, f.num(3))) try f.invoke("getLineSelection", &.{anchor}) else c.pi_js_undefined();
    try f.put("selectionGranularity", try f.text(if (f.truth(selected)) if (f.equal(count, f.num(2))) "word" else "line" else "character"));
    try f.put("selectionInitialRange", selected);
    const first = try optional(f, selected, "start");
    const last = try optional(f, selected, "end");
    try f.put("selectionAnchor", if (f.nullish(first)) anchor else first);
    try f.put("selectionFocus", if (f.nullish(last)) anchor else last);
    try f.put("selectionDragged", f.boolean(false));
    const url = if (f.truth(selected)) c.pi_js_undefined() else try f.imported("getOsc8LinkAtColumn", &.{ try f.emptyLine(try f.field("previousScreen"), try f.math("max", &.{ f.num(0), f.num(try f.math("min", &.{ f.num(try f.n(try f.field("terminal"), "rows") - 1), try f.get(event, "y") })) })), f.num(try f.math("max", &.{ f.num(0), f.num(try f.math("min", &.{ f.num(try f.n(try f.field("terminal"), "columns") - 1), try f.get(event, "x") })) })) });
    try f.put("pressedUrl", url);
    _ = try f.invoke("requestRender", &.{});
}
pub fn invoke(f: *Frame, method: Method, args: []const c.JSValue) anyerror!c.JSValue {
    switch (method) {
        .getScrollSelectionPoint => return scrollPoint(f, v.arg(args, 0), try f.number(v.arg(args, 1)), try f.number(v.arg(args, 2))),
        .getSelectionPoint => return selectionPoint(f, v.arg(args, 0), v.arg(args, 1)),
        .getSelectionSourceLine => return sourceLine(f, v.arg(args, 0)),
        .getWordSelection => return word(f, v.arg(args, 0)),
        .getLineSelection => return range(f, try endpoint(f, v.arg(args, 0), 0, false), try endpoint(f, v.arg(args, 0), try f.width(try f.invoke("getSelectionSourceLine", &.{v.arg(args, 0)})), true)),
        .updateSelectionFocus => try updateFocus(f, v.arg(args, 0)),
        .getClickCount => return click(f, v.arg(args, 0), v.arg(args, 1)),
        .updateSelectionAutoScroll => try updateAuto(f, v.arg(args, 0)),
        .autoScrollSelection => {
            const scroll = try optional(f, try f.field("selectionAnchor"), "scrollView");
            const pointer = try f.field("selectionDragPointer");
            const direction = try f.field("selectionAutoScrollDirection");
            if (!f.truth(scroll) or !f.truth(pointer) or f.equal(direction, f.num(0))) {
                _ = try f.invoke("stopSelectionAutoScroll", &.{});
                return c.pi_js_undefined();
            }
            const remaining = try f.method(scroll, "scrollBy", &.{direction});
            if (f.equal(remaining, direction)) {
                _ = try f.invoke("stopSelectionAutoScroll", &.{});
                return c.pi_js_undefined();
            }
            const point = try f.invoke("getScrollSelectionPoint", &.{ scroll, try f.get(pointer, "x"), try f.get(pointer, "y") });
            if (f.truth(point)) _ = try f.invoke("updateSelectionFocus", &.{point});
            _ = try f.invoke("requestRender", &.{});
        },
        .stopSelectionAutoScroll => {
            if (f.truth(try f.field("selectionAutoScrollTimer"))) {
                _ = try f.call(try f.global("clearInterval"), c.pi_js_undefined(), &.{try f.field("selectionAutoScrollTimer")});
                try f.put("selectionAutoScrollTimer", c.pi_js_undefined());
            }
            try f.put("selectionAutoScrollDirection", f.num(0));
            try f.put("selectionDragPointer", c.pi_js_undefined());
        },
        .handleSelectionMouseEvent => try handleEvent(f, v.arg(args, 0)),
        .getSelectionBounds => return bounds(f),
        .getSelectionColumns => return columns(f, args),
        .getActiveSelectionText => return activeText(f),
        .copyActiveSelectionToClipboard, .copySelectionToClipboard => {
            const text = try f.invoke("getActiveSelectionText", &.{});
            return if (!f.truth(text)) f.boolean(false) else f.invoke("copyTextToClipboard", &.{text});
        },
        .copyTextToClipboard => return copyText(f, v.arg(args, 0)),
        .applySelectionHighlight => return selectionHighlight(f, v.arg(args, 0)),
        .applySelection => return applySelection(f, v.arg(args, 0), v.arg(args, 1)),
    }
    return c.pi_js_undefined();
}
