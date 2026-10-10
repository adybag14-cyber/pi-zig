//! Source layout painting, scroll clipping and grapheme-safe scrollbar cells.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const c = a.c;
const js = a.js;
fn setRow(f: *Frame, screen: c.JSValue, row: f64, line: c.JSValue) !void {
    return js.setKey(f.engine, screen, f.num(row), line);
}
fn slice(f: *Frame, line: c.JSValue, start: f64, length: f64) !c.JSValue {
    return f.imported("sliceByColumn", &.{ line, f.num(start), f.num(length), f.boolean(true) });
}
fn spaces(f: *Frame, count: f64) !c.JSValue {
    return f.method(try f.text(" "), "repeat", &.{f.num(try f.math("max", &.{ f.num(0), f.num(count) }))});
}
fn replaceCell(f: *Frame, line: c.JSValue, column: f64, total: f64, replacement: c.JSValue, preserve: bool) !c.JSValue {
    if (f.truth(try f.imported("isImageLine", &.{line}))) return line;
    const range = try f.imported("getGraphemeCellRange", &.{ line, f.num(column) });
    const start = if (f.nullish(range)) column else try f.n(range, "start");
    const end = if (f.nullish(range)) column + 1 else try f.n(range, "end");
    const before = try slice(f, line, 0, start);
    const target = try slice(f, line, start, end - start);
    const after = try slice(f, line, end, try f.math("max", &.{ f.num(0), f.num(total - end) }));
    var prefix = try f.text("");
    var index: f64 = 0;
    while (index < try f.n(target, "length")) {
        const ansi = try f.imported("extractAnsiCode", &.{ target, f.num(index) });
        if (!f.truth(ansi)) break;
        prefix = try f.concat(&.{ prefix, try f.get(ansi, "code") });
        index += try f.n(ansi, "length");
    }
    const style = try f.concat(&.{ try f.text("\x1b[0m\x1b]8;;\x07"), if (preserve) try f.imported("getActiveBackgroundAnsi", &.{prefix}) else try f.text("") });
    return f.concat(&.{ before, try spaces(f, start - try f.width(before)), style, try spaces(f, column - start), replacement, try spaces(f, end - column - 1), after });
}
fn scrollbar(f: *Frame, box: c.JSValue, screen: c.JSValue, total: f64) !void {
    const geometry = try @import("native_tui_layout.zig").geometry(f, box, false);
    const scroll = try f.get(box, "scrollView");
    if (!f.truth(geometry) or !f.truth(scroll)) return;
    var offset: f64 = 0;
    while (offset < try f.n(geometry, "trackHeight")) : (offset += 1) {
        const row = try f.n(geometry, "trackTop") + offset;
        const clip = try f.get(box, "clip");
        if (row < try f.n(clip, "y") or row >= try f.n(clip, "y") + try f.n(clip, "height") or row < 0 or row >= try f.n(screen, "length")) continue;
        const thumb = row >= try f.n(geometry, "thumbTop") and row < try f.n(geometry, "thumbTop") + try f.n(geometry, "thumbHeight");
        const replacement = if (thumb) try f.method(try f.get(box, "scrollView"), "scrollbarThumbStyle", &.{try f.text(if (f.truth(try f.get(try f.get(box, "scrollView"), "isScrollbarActive"))) "█" else "┃")}) else try f.method(try f.get(box, "scrollView"), "scrollbarTrackStyle", &.{try f.text("│")});
        try setRow(f, screen, row, try replaceCell(f, try f.emptyLine(screen, row), try f.n(geometry, "column"), total, replacement, !try f.is(try f.get(try f.get(box, "scrollView"), "scrollbar"), "always")));
    }
}
pub fn paint(f: *Frame, box: c.JSValue, screen: c.JSValue, total: f64) anyerror!void {
    const lines = try f.get(box, "lines");
    if (f.truth(lines)) {
        const raw_offset = try f.get(box, "lineOffset");
        const offset = if (f.nullish(raw_offset)) 0 else try f.number(raw_offset);
        const area = try f.get(box, "rect");
        const clip = try f.get(box, "clip");
        const first = try f.math("max", &.{ try f.get(area, "y"), try f.get(clip, "y"), f.num(0) });
        const last = try f.math("min", &.{ f.num(try f.n(area, "y") + try f.n(area, "height")), f.num(try f.n(clip, "y") + try f.n(clip, "height")), try f.get(screen, "length") });
        var row = first;
        while (row < last) : (row += 1) {
            const source = try f.at(lines, offset + row - try f.n(area, "y"));
            if (c.JS_IsUndefined(source)) continue;
            var line = try f.method(source, "replace", &.{ try f.get(f.bindings, "osc133ZonePrefix"), try f.text("") });
            const metadata = try f.imported("getKittyImageMetadata", &.{line});
            if (f.truth(metadata)) {
                const bottom = try f.math("min", &.{ try f.get(screen, "length"), f.num(try f.n(clip, "y") + try f.n(clip, "height")) });
                const rows = try f.math("min", &.{ try f.get(metadata, "rows"), f.num(bottom - row) });
                if (rows < try f.n(metadata, "rows")) line = try f.imported("cropKittyImageLine", &.{ line, f.num(0), f.num(rows) });
            }
            if (try f.n(area, "x") == 0 and try f.n(area, "width") >= total and (f.truth(try f.imported("isImageLine", &.{line})) or !f.truth(try f.at(screen, row)))) try setRow(f, screen, row, line) else try setRow(f, screen, row, try f.imported("compositeTuiLine", &.{ try f.emptyLine(screen, row), line, try f.get(area, "x"), try f.get(area, "width"), f.num(total) }));
        }
    }
    const children = try f.get(box, "children");
    var iterator = try js.Iterator.init(f.engine, children, try f.get(f.bindings, "iteratorSymbol"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer f.engine.freeValue(child);
        try paint(f, child, screen, total);
    }
    const scroll = try f.get(box, "scrollView");
    const content = try f.get(box, "scrollContentLines");
    const area = try f.get(box, "rect");
    if (f.truth(scroll) and f.truth(content) and try f.n(scroll, "scrollTop") > 0 and try f.n(area, "height") > 0) {
        var row = try f.n(scroll, "scrollTop") - 1;
        while (row >= 0) : (row -= 1) {
            const image = try f.emptyLine(content, row);
            const metadata = try f.imported("getKittyImageMetadata", &.{image});
            if (f.truth(metadata)) {
                const hidden = try f.n(scroll, "scrollTop") - row;
                if (hidden < try f.n(metadata, "rows")) {
                    const visible = try f.math("min", &.{ try f.get(area, "height"), f.num(try f.n(metadata, "rows") - hidden) });
                    const cropped = try f.imported("cropKittyImageLine", &.{ image, f.num(hidden), f.num(visible) });
                    if (try f.n(area, "x") == 0 and try f.n(area, "width") >= total) try setRow(f, screen, try f.n(area, "y"), cropped);
                }
                break;
            }
            if (!try f.is(image, "")) break;
        }
    }
    try scrollbar(f, box, screen, total);
}
