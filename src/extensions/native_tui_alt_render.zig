//! Source fullscreen rendering, Kitty LRU budgets and overlay/flash composition.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
const v = a.v;
const sequence = @import("native_tui_alt_state.zig").sequence;
const callbacks = @import("native_tui_alt_callbacks.zig");
pub const Method = enum(c_int) { prepareKittyScreen, compositeScrollToEndIndicator, compositeFlashes, doRender };
pub fn kittyLine(f: *Frame, line: c.JSValue, visible: c.JSValue) anyerror!c.JSValue {
    const placement = try f.imported("getKittyImagePlacement", &.{line});
    if (!f.truth(placement)) return line;
    _ = try f.method(visible, "add", &.{try f.get(placement, "imageId")});
    const cached = try f.method(try f.field("uploadedKittyImages"), "get", &.{try f.get(placement, "imageId")});
    const next = try f.record();
    inline for (.{ "transmissionGeneration", "transmissionBytes", "estimatedDecodedBytes" }) |name| try f.define(next, name, try f.get(placement, name));
    if (f.truth(cached)) _ = try f.method(try f.field("uploadedKittyImages"), "delete", &.{try f.get(placement, "imageId")});
    _ = try f.method(try f.field("uploadedKittyImages"), "set", &.{ try f.get(placement, "imageId"), next });
    const generation = if (f.nullish(cached)) c.pi_js_undefined() else try f.get(cached, "transmissionGeneration");
    return if (f.equal(generation, try f.get(placement, "transmissionGeneration"))) f.get(placement, "replacementLine") else line;
}
fn prepare(f: *Frame, screen: c.JSValue) !c.JSValue {
    const visible = try f.construct(try f.global("Set"), &.{});
    const capture = try f.record();
    try f.define(capture, "visibleImageIds", visible);
    const lines = try callbacks.map(f, screen, .kittyLine, capture);
    var count: f64 = 0;
    var transmission: c.JSValue = f.num(0);
    var decoded: c.JSValue = f.num(0);
    var iterator = try js.Iterator.init(f.engine, try f.field("uploadedKittyImages"), try f.get(f.bindings, "iteratorSymbol"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer f.engine.freeValue(entry);
        const pair = try f.pair(entry);
        const id = pair[0];
        const cache = pair[1];
        if (f.truth(try f.method(visible, "has", &.{id}))) continue;
        count += 1;
        transmission = try f.add(transmission, try f.get(cache, "transmissionBytes"));
        decoded = try f.add(decoded, try f.get(cache, "estimatedDecodedBytes"));
    }
    var deletion = try f.text("");
    var evictions = try js.Iterator.init(f.engine, try f.field("uploadedKittyImages"), try f.get(f.bindings, "iteratorSymbol"));
    defer evictions.deinit();
    errdefer evictions.closePreserving();
    while (try evictions.next()) |entry| {
        defer f.engine.freeValue(entry);
        const pair = try f.pair(entry);
        const id = pair[0];
        const cache = pair[1];
        if (count <= 16 and try f.number(transmission) <= 32 * 1024 * 1024 and try f.number(decoded) <= 64 * 1024 * 1024) {
            try evictions.close();
            break;
        }
        if (f.truth(try f.method(visible, "has", &.{id}))) continue;
        deletion = try f.add(deletion, try f.imported("deleteKittyImage", &.{id}));
        _ = try f.method(try f.field("uploadedKittyImages"), "delete", &.{id});
        count -= 1;
        transmission = f.num(try f.number(transmission) - try f.n(cache, "transmissionBytes"));
        decoded = f.num(try f.number(decoded) - try f.n(cache, "estimatedDecodedBytes"));
    }
    const output = try f.record();
    try f.define(output, "lines", lines);
    try f.define(output, "evictedImageDeletion", deletion);
    return output;
}
fn indicator(f: *Frame, screen: c.JSValue, layout: c.JSValue, width: c.JSValue) !c.JSValue {
    try f.put("scrollToEndIndicatorRect", c.pi_js_undefined());
    const primary = try f.get(layout, "primaryScrollView");
    const scroll = if (f.nullish(primary)) try f.field("implicitScrollView") else primary;
    if (!f.truth(try f.field("scrollToEndIndicator")) or !f.truth(try f.get(scroll, "followEnd")) or f.truth(try f.get(scroll, "isFollowingEnd"))) return screen;
    const box = try f.imported("getScrollViewBox", &.{ layout, scroll });
    const clip = if (f.nullish(box)) c.pi_js_undefined() else try f.get(box, "clip");
    if (!f.truth(clip) or try f.n(clip, "width") <= 0 or try f.n(clip, "height") <= 0) return screen;
    const row = try f.n(clip, "y") + try f.n(clip, "height") - 1;
    if (row >= try f.n(screen, "length") or f.truth(try f.imported("isImageLine", &.{try f.emptyLine(screen, row)}))) return screen;
    const geometry = if (f.truth(box)) try f.imported("getScrollbarGeometry", &.{box}) else c.pi_js_undefined();
    const scrollbar = if (f.nullish(geometry)) c.pi_js_undefined() else try f.get(geometry, "column");
    const label = try f.imported("truncateToWidth", &.{ try f.invoke("scrollToEndIndicator", &.{}), try f.get(clip, "width"), try f.text("") });
    const label_width = try f.width(label);
    const column = try f.n(clip, "x") + try f.math("floor", &.{f.num((try f.n(clip, "width") - label_width) / 2)});
    const edge = if (f.nullish(scrollbar)) try f.n(clip, "x") + try f.n(clip, "width") else try f.number(scrollbar);
    const available = try f.math("max", &.{ f.num(0), f.num(edge - column) });
    const text = try f.imported("truncateToWidth", &.{ label, f.num(available), try f.text("") });
    const text_width = try f.width(text);
    if (text_width == 0) return screen;
    const result = try f.copy(screen);
    try js.setKey(f.engine, result, f.num(row), try f.imported("compositeTuiLine", &.{ try f.emptyLine(result, row), text, f.num(column), f.num(text_width), width }));
    const area = try f.record();
    try f.define(area, "row", f.num(row));
    try f.define(area, "column", f.num(column));
    try f.define(area, "width", f.num(text_width));
    try f.put("scrollToEndIndicatorRect", area);
    return result;
}
fn flashes(f: *Frame, screen: c.JSValue, width: c.JSValue, height: c.JSValue) !c.JSValue {
    const lines = try f.method(try f.method(try f.field("flashes"), "render", &.{width}), "slice", &.{f.num(-try f.number(height))});
    if (f.equal(try f.get(lines, "length"), f.num(0))) return screen;
    const result = try f.copy(screen);
    while (try f.n(result, "length") < try f.number(height)) try f.push(result, try f.text(""));
    var row: f64 = 0;
    while (row < try f.n(lines, "length")) : (row += 1) {
        const line = try f.at(lines, row);
        const flash_width = try f.width(line);
        if (flash_width == 0) continue;
        try js.setKey(f.engine, result, f.num(row), try f.imported("compositeTuiLine", &.{ try f.emptyLine(result, row), line, f.num(try f.number(width) - flash_width), f.num(flash_width), width }));
    }
    return result;
}
fn rowPrefix(f: *Frame, row: f64, erase: bool) !c.JSValue {
    return f.concat(&.{ try f.text("\x1b["), f.num(row + 1), try f.text(if (erase) ";1H\x1b[2K" else ";1H") });
}
fn render(f: *Frame) !void {
    if (f.truth(try f.field("stopped")) or !f.truth(try f.field("altScreenActive"))) return;
    const width = try f.math("max", &.{ f.num(1), try f.get(try f.field("terminal"), "columns") });
    const height = try f.math("max", &.{ f.num(1), try f.get(try f.field("terminal"), "rows") });
    const supplied = try f.field("layoutRoot");
    const root = if (f.nullish(supplied)) try f.field("implicitScrollView") else supplied;
    var layout = try f.imported("renderLayoutFrame", &.{ root, f.num(width), f.num(height), try @import("native_tui_alt_state.zig").requestRenderClosure(f) });
    if (f.truth(try f.invoke("refreshSearch", &.{layout}))) layout = try f.imported("renderLayoutFrame", &.{ root, f.num(width), f.num(height), try @import("native_tui_alt_state.zig").requestRenderClosure(f) });
    const layout_lines = try f.get(layout, "lines");
    const stripped = try callbacks.map(f, layout_lines, .stripZones, c.pi_js_undefined());
    var screen = try f.invoke("resolveFakeCursors", &.{stripped});
    screen = try f.invoke("applySearchHighlights", &.{ screen, layout });
    screen = try f.invoke("compositeScrollToEndIndicator", &.{ screen, layout, f.num(width) });
    screen = try f.invoke("compositeOverlays", &.{ screen, f.num(width), f.num(height) });
    if (try f.n(screen, "length") > height) screen = try f.method(screen, "slice", &.{f.num(try f.n(screen, "length") - height)});
    screen = try f.invoke("applySelection", &.{ screen, layout });
    screen = try f.invoke("compositeFlashes", &.{ screen, f.num(width), f.num(height) });
    const cursor = try f.invoke("extractCursorPosition", &.{ screen, f.num(height) });
    const resets = try f.invoke("applyLineResets", &.{screen});
    const capture = try f.record();
    try f.define(capture, "width", f.num(width));
    screen = try callbacks.map(f, resets, .clampLine, capture);
    const full = f.equal(try f.get(try f.field("previousScreen"), "length"), f.num(0)) or !f.equal(try f.field("previousScreenWidth"), f.num(width)) or !f.equal(try f.field("previousScreenHeight"), f.num(height));
    const changed = try callbacks.map(f, screen, .changedRow, c.pi_js_undefined());
    try f.define(capture, "changedRows", changed);
    const anchors = f.truth(try callbacks.some(f, screen, .imageAnchor, capture));
    const pane = try f.get(try f.get(try f.global("process"), "env"), "WEZTERM_PANE");
    var wezterm = f.truth(pane);
    if (!wezterm) {
        const program = try f.get(try f.get(try f.global("process"), "env"), "TERM_PROGRAM");
        wezterm = !f.nullish(program) and try f.is(try f.method(program, "toLowerCase", &.{}), "wezterm");
    }
    var cells = false;
    if (!anchors and wezterm and try f.is(try f.field("imageProtocol"), "kitty")) {
        if (f.truth(try f.method(changed, "some", &.{try f.global("Boolean")}))) cells = f.truth(try callbacks.some(f, screen, .imageCells, capture));
    }
    const images = anchors or cells;
    const redraw = full or images;
    const had_images = try f.n(try f.field("uploadedKittyImages"), "size") > 0;
    var prepared: c.JSValue = undefined;
    if (redraw and try f.is(try f.field("imageProtocol"), "kitty")) prepared = try f.invoke("prepareKittyScreen", &.{screen}) else {
        prepared = try f.record();
        try f.define(prepared, "lines", screen);
        try f.define(prepared, "evictedImageDeletion", try f.text(""));
    }
    var buffer = try f.text(sequence.begin);
    if (full) {
        try f.put("fullRedrawCount", try f.add(try f.field("fullRedrawCount"), f.num(1)));
        const clear = if (try f.is(try f.field("imageProtocol"), "kitty") and had_images) try f.imported("deleteAllKittyPlacements", &.{}) else try f.invoke("deleteKittyImages", &.{});
        buffer = try f.concat(&.{ buffer, clear, try f.text("\x1b[2J") });
    } else if (images) {
        if (try f.is(try f.field("imageProtocol"), "iterm2")) buffer = try f.add(buffer, try f.text("\x1b[2J")) else if (try f.is(try f.field("imageProtocol"), "kitty")) buffer = try f.add(buffer, try f.imported("deleteAllKittyPlacements", &.{}));
    }
    buffer = try f.add(buffer, try f.get(prepared, "evictedImageDeletion"));
    const last = redraw and try f.is(try f.field("imageProtocol"), "kitty") and f.truth(try f.method(screen, "some", &.{try f.get(f.bindings, "isImageLine")})) and wezterm;
    var row: f64 = 0;
    if (last) {
        row = 0;
        while (row < height) : (row += 1) {
            if (!full and !images and f.equal(try f.at(screen, row), try f.at(try f.field("previousScreen"), row))) continue;
            buffer = try f.add(buffer, try rowPrefix(f, row, true));
        }
        inline for (.{ false, true }) |want_image| {
            row = 0;
            while (row < height) : (row += 1) {
                if (!full and !images and f.equal(try f.at(screen, row), try f.at(try f.field("previousScreen"), row))) continue;
                const line = try f.emptyLine(try f.get(prepared, "lines"), row);
                if (f.truth(try f.imported("isImageLine", &.{line})) != want_image) continue;
                buffer = try f.concat(&.{ buffer, try rowPrefix(f, row, false), line });
            }
        }
    } else {
        row = 0;
        while (row < height) : (row += 1) {
            if (!full and !images and f.equal(try f.at(screen, row), try f.at(try f.field("previousScreen"), row))) continue;
            buffer = try f.concat(&.{ buffer, try rowPrefix(f, row, true), try f.emptyLine(try f.get(prepared, "lines"), row) });
        }
    }
    if (f.truth(cursor)) {
        buffer = try f.concat(&.{ buffer, try f.text("\x1b["), try f.add(try f.get(cursor, "row"), f.num(1)), try f.text(";"), f.num(try f.math("min", &.{ f.num(width), try f.get(cursor, "col") }) + 1), try f.text("H"), try f.text(if (f.truth(try f.invoke("getShowHardwareCursor", &.{}))) "\x1b[?25h" else "\x1b[?25l") });
    } else buffer = try f.add(buffer, try f.text("\x1b[?25l"));
    buffer = try f.add(buffer, try f.text(sequence.end));
    try f.write(buffer);
    try f.put("previousScreen", screen);
    try f.put("previousScreenWidth", f.num(width));
    try f.put("previousScreenHeight", f.num(height));
    try f.put("currentLayout", layout);
}
pub fn invoke(f: *Frame, method: Method, args: []const c.JSValue) anyerror!c.JSValue {
    switch (method) {
        .prepareKittyScreen => return prepare(f, v.arg(args, 0)),
        .compositeScrollToEndIndicator => return indicator(f, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)),
        .compositeFlashes => return flashes(f, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)),
        .doRender => try render(f),
    }
    return c.pi_js_undefined();
}
