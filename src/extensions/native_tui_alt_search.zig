//! Source transcript-search overlay, selection retention and ANSI highlighting.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const c = a.c;
const js = a.js;
const v = a.v;
pub const Method = enum(c_int) { toggleSearch, closeSearch, updateSearchQuery, navigateSearch, getSearchNavigationDirectionAt, handleSearchMouseEvent, refreshSearch, applySearchTextHighlight, applySearchHighlights };
fn firstSegment(f: *Frame, match: c.JSValue) !c.JSValue {
    if (f.nullish(match)) return c.pi_js_undefined();
    return f.at(try f.get(match, "segments"), 0);
}
fn firstRow(f: *Frame, match: c.JSValue, fallback: f64) !f64 {
    const first = try firstSegment(f, match);
    if (f.nullish(first)) return fallback;
    const row = try f.get(first, "row");
    return if (f.nullish(row)) fallback else f.number(row);
}
fn matchKey(f: *Frame, match: c.JSValue) !c.JSValue {
    return f.imported("getAltScreenSearchMatchKey", &.{match});
}
fn exactCall(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = data[0], .bindings = data[1] };
    defer f.deinit();
    const key = matchKey(&f, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return a.fail(engine, err);
    const selected = f.get(data[2], "selectedKey") catch |err| return a.fail(engine, err);
    return f.boolean(f.equal(key, selected));
}
fn refresh(f: *Frame, layout: c.JSValue) !c.JSValue {
    const search = try f.field("activeSearch");
    if (!f.truth(search)) return f.boolean(false);
    const primary = try f.get(layout, "primaryScrollView");
    const scroll = if (f.nullish(primary)) try f.field("implicitScrollView") else primary;
    const box = try f.imported("getScrollViewBox", &.{ layout, scroll });
    const lines = if (f.nullish(box)) c.pi_js_undefined() else try f.get(box, "scrollContentLines");
    if (!f.truth(lines) or !f.truth(try f.method(try f.get(search, "query"), "trim", &.{}))) {
        try f.set(search, "matches", try f.array());
        try f.set(search, "selectedIndex", f.num(-1));
        try f.set(search, "selectedKey", c.pi_js_undefined());
        try f.set(search, "selectionMode", try f.text("retain"));
        _ = try f.method(try f.get(search, "component"), "setResult", &.{ f.num(-1), f.num(0) });
        return f.boolean(false);
    }
    const reveal = !try f.is(try f.get(search, "selectionMode"), "retain");
    const result = try f.method(try f.get(search, "index"), "search", &.{ lines, try f.get(search, "query") });
    const matches = try f.get(result, "matches");
    try f.set(search, "matches", matches);
    if (!f.truth(try f.get(result, "changed")) and try f.is(try f.get(search, "selectionMode"), "retain")) return f.boolean(false);
    const exact = blk: {
        if (!f.truth(try f.get(result, "changed"))) break :blk try f.n(search, "selectedIndex");
        if (!f.truth(try f.get(search, "selectedKey"))) break :blk @as(f64, -1);
        var data = [_]c.JSValue{ f.object, f.bindings, search };
        const callback = try f.own(try f.engine.checked(c.JS_NewCFunctionData2(f.engine.context, exactCall, "", 1, 0, 3, &data)));
        break :blk try f.number(try f.method(matches, "findIndex", &.{callback}));
    };
    var selected: f64 = -1;
    const count = try f.n(matches, "length");
    if (count > 0) {
        if (try f.is(try f.get(search, "selectionMode"), "query")) {
            var low: f64 = 0;
            var high = count;
            while (low < high) {
                const middle = low + try f.math("floor", &.{f.num((high - low) / 2)});
                if (try firstRow(f, try f.at(matches, middle), 0) < try f.n(search, "anchorRow")) low = middle + 1 else high = middle;
            }
            selected = if (low < count) low else 0;
        } else if (try f.is(try f.get(search, "selectionMode"), "next")) {
            const base = if (exact >= 0) exact else try f.math("min", &.{ try f.get(search, "selectedIndex"), f.num(count - 1) });
            selected = if (base < 0) 0 else @mod(base + 1, count);
        } else if (try f.is(try f.get(search, "selectionMode"), "previous")) {
            const base = if (exact >= 0) exact else try f.math("min", &.{ try f.get(search, "selectedIndex"), f.num(count - 1) });
            selected = if (base < 0) count - 1 else @mod(base - 1 + count, count);
        } else selected = if (exact >= 0) exact else try f.math("min", &.{ f.num(try f.math("max", &.{ f.num(0), try f.get(search, "selectedIndex") })), f.num(count - 1) });
    }
    try f.set(search, "selectedIndex", f.num(selected));
    try f.set(search, "selectedKey", if (selected >= 0) try matchKey(f, try f.at(matches, selected)) else c.pi_js_undefined());
    try f.set(search, "selectionMode", try f.text("retain"));
    _ = try f.method(try f.get(search, "component"), "setResult", &.{ f.num(selected), try f.get(matches, "length") });
    if (!reveal) return f.boolean(false);
    const selected_match = try f.at(matches, selected);
    const first = try firstSegment(f, selected_match);
    var last: c.JSValue = c.pi_js_undefined();
    if (!f.nullish(selected_match)) {
        const segments = try f.get(selected_match, "segments");
        last = try f.at(segments, try f.n(try f.get(selected_match, "segments"), "length") - 1);
    }
    if (!f.truth(box) or !f.truth(first) or !f.truth(last) or try f.n(scroll, "viewportHeight") <= 0) return f.boolean(false);
    const before = try f.n(scroll, "scrollTop");
    const bottom = before + try f.n(scroll, "viewportHeight") - 1;
    var target = before;
    if (try f.n(first, "row") < before or try f.n(last, "row") > bottom) target = try f.n(first, "row") - try f.math("floor", &.{f.num(try f.n(scroll, "viewportHeight") / 3)});
    const options = try f.record();
    try f.define(options, "disableFollow", f.boolean(true));
    _ = try f.method(scroll, "scrollTo", &.{ f.num(target), options });
    return f.boolean(try f.n(scroll, "scrollTop") != before);
}
fn highlightText(f: *Frame, text: c.JSValue, current: bool) !c.JSValue {
    const style = try f.field(if (current) "searchCurrentMatchStyle" else "searchMatchStyle");
    var result = try f.text("");
    var plain: f64 = 0;
    var index: f64 = 0;
    while (index < try f.n(text, "length")) {
        const ansi = try f.imported("extractAnsiCode", &.{ text, f.num(index) });
        if (!f.truth(ansi)) {
            index += 1;
            continue;
        }
        if (index > plain) result = try f.add(result, try f.call(style, c.pi_js_undefined(), &.{try f.method(text, "slice", &.{ f.num(plain), f.num(index) })}));
        result = try f.add(result, try f.get(ansi, "code"));
        index += try f.n(ansi, "length");
        plain = index;
    }
    if (plain < try f.n(text, "length")) result = try f.add(result, try f.call(style, c.pi_js_undefined(), &.{try f.method(text, "slice", &.{f.num(plain)})}));
    return result;
}
fn sortCall(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const left = v.numberField(engine, v.arg(args, 0), "startCol") catch |err| return a.fail(engine, err);
    const right = v.numberField(engine, v.arg(args, 1), "startCol") catch |err| return a.fail(engine, err);
    return v.numeric(engine, right - left);
}
fn highlights(f: *Frame, screen: c.JSValue, layout: c.JSValue) !c.JSValue {
    const search = try f.field("activeSearch");
    if (!f.truth(search) or try f.n(search, "selectedIndex") < 0 or try f.n(try f.get(search, "matches"), "length") == 0) return screen;
    const primary = try f.get(layout, "primaryScrollView");
    const scroll = if (f.nullish(primary)) try f.field("implicitScrollView") else primary;
    const box = try f.imported("getScrollViewBox", &.{ layout, scroll });
    if (!f.truth(box)) return screen;
    const ranges = try f.construct(try f.global("Map"), &.{});
    const geometry = try f.imported("getScrollbarGeometry", &.{box});
    const column = if (f.nullish(geometry)) c.pi_js_undefined() else try f.get(geometry, "column");
    const area = try f.get(box, "rect");
    const clip = try f.get(box, "clip");
    const min_row = try f.math("max", &.{ f.num(0), try f.get(area, "y"), try f.get(clip, "y") });
    const max_row = try f.math("min", &.{ try f.get(screen, "length"), f.num(try f.n(area, "y") + try f.n(area, "height")), f.num(try f.n(clip, "y") + try f.n(clip, "height")) });
    const min_col = try f.math("max", &.{ f.num(0), try f.get(area, "x"), try f.get(clip, "x") });
    const max_col = try f.math("min", &.{ try f.get(try f.field("terminal"), "columns"), f.num(try f.n(area, "x") + try f.n(area, "width")), f.num(try f.n(clip, "x") + try f.n(clip, "width")), if (f.nullish(column)) try f.get(try f.global("Number"), "POSITIVE_INFINITY") else column });
    const content_min = try f.n(scroll, "scrollTop") + min_row - try f.n(area, "y");
    const content_max = try f.n(scroll, "scrollTop") + max_row - try f.n(area, "y") - 1;
    var low: f64 = 0;
    var high = try f.n(try f.get(search, "matches"), "length");
    while (low < high) {
        const middle = low + try f.math("floor", &.{f.num((high - low) / 2)});
        const match = try f.at(try f.get(search, "matches"), middle);
        const segments = try f.get(match, "segments");
        const last = try f.at(segments, try f.n(try f.get(match, "segments"), "length") - 1);
        const row = if (f.nullish(last)) @as(f64, -1) else try f.n(last, "row");
        if (row < content_min) low = middle + 1 else high = middle;
    }
    var index = low;
    while (index < try f.n(try f.get(search, "matches"), "length")) : (index += 1) {
        const match = try f.at(try f.get(search, "matches"), index);
        if (try firstRow(f, match, 0) > content_max) break;
        const segments = try f.get(match, "segments");
        var iterator = try js.Iterator.init(f.engine, segments, try f.get(f.bindings, "iteratorSymbol"));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |segment| {
            defer f.engine.freeValue(segment);
            const row = try f.n(area, "y") + try f.n(segment, "row") - try f.n(scroll, "scrollTop");
            if (row < min_row or row >= max_row) continue;
            const start = try f.math("max", &.{ f.num(min_col), f.num(try f.n(area, "x") + try f.n(segment, "startCol")) });
            const end = try f.math("min", &.{ f.num(max_col), f.num(try f.n(area, "x") + try f.n(segment, "endCol")) });
            if (end <= start) continue;
            var list = try f.method(ranges, "get", &.{f.num(row)});
            if (f.nullish(list)) list = try f.array();
            const range = try f.record();
            try f.define(range, "startCol", f.num(start));
            try f.define(range, "endCol", f.num(end));
            try f.define(range, "current", f.boolean(f.equal(f.num(index), try f.get(search, "selectedIndex"))));
            try f.push(list, range);
            _ = try f.method(ranges, "set", &.{ f.num(row), list });
        }
    }
    const result = try f.copy(screen);
    var entries = try js.Iterator.init(f.engine, ranges, try f.get(f.bindings, "iteratorSymbol"));
    defer entries.deinit();
    errdefer entries.closePreserving();
    while (try entries.next()) |entry| {
        defer f.engine.freeValue(entry);
        const pair = try f.pair(entry);
        const row = pair[0];
        const list = pair[1];
        var line = try f.emptyLine(result, try f.number(row));
        if (f.truth(try f.imported("isImageLine", &.{line}))) continue;
        const width = try f.width(line);
        const comparator = try f.own(try f.engine.checked(c.JS_NewCFunction(f.engine.context, sortCall, "", 2)));
        const sorted = try f.method(list, "sort", &.{comparator});
        var iterator = try js.Iterator.init(f.engine, sorted, try f.get(f.bindings, "iteratorSymbol"));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |range| {
            defer f.engine.freeValue(range);
            const start = try f.math("min", &.{ try f.get(range, "startCol"), f.num(width) });
            const end = try f.math("min", &.{ try f.get(range, "endCol"), f.num(width) });
            if (end <= start) continue;
            const before = try f.imported("sliceByColumn", &.{ line, f.num(0), f.num(start), f.boolean(true) });
            const middle = try f.imported("sliceByColumn", &.{ line, f.num(start), f.num(end - start), f.boolean(true) });
            const after = try f.imported("sliceByColumn", &.{ line, f.num(end), f.num(try f.math("max", &.{ f.num(0), f.num(width - end) })), f.boolean(true) });
            line = try f.concat(&.{ before, try f.invoke("applySearchTextHighlight", &.{ middle, try f.get(range, "current") }), after });
        }
        try js.setKey(f.engine, result, row, line);
    }
    return result;
}
pub fn invoke(f: *Frame, method: Method, args: []const c.JSValue) anyerror!c.JSValue {
    switch (method) {
        .toggleSearch => {
            if (f.truth(try f.field("activeSearch"))) {
                _ = try f.invoke("closeSearch", &.{});
                return c.pi_js_undefined();
            }
            const component = try f.construct(try f.get(f.bindings, "AltScreenSearchComponent"), &.{ try @import("native_tui_alt_state.zig").queryClosure(f), try f.field("searchNavigationButtonStyle") });
            const search = try f.record();
            try f.define(search, "component", component);
            try f.define(search, "index", try f.construct(try f.get(f.bindings, "AltScreenSearchIndex"), &.{}));
            try f.define(search, "query", try f.text(""));
            try f.define(search, "matches", try f.array());
            try f.define(search, "selectedIndex", f.num(-1));
            try f.define(search, "anchorRow", try f.get(try f.invoke("getPrimaryScrollView", &.{}), "scrollTop"));
            try f.define(search, "selectionMode", try f.text("query"));
            try f.put("activeSearch", search);
            const options = try f.record();
            try f.define(options, "anchor", try f.text("top-right"));
            try f.define(options, "width", try f.text("40%"));
            try f.define(options, "minWidth", f.num(32));
            try f.define(options, "margin", f.num(1));
            try f.set(search, "overlay", try f.invoke("showOverlay", &.{ component, options }));
        },
        .closeSearch => {
            const search = try f.field("activeSearch");
            if (!f.truth(search)) return c.pi_js_undefined();
            try f.put("activeSearch", c.pi_js_undefined());
            const overlay = try f.get(search, "overlay");
            if (!f.nullish(overlay)) _ = try f.method(overlay, "hide", &.{});
            _ = try f.invoke("requestRender", &.{});
        },
        .updateSearchQuery => {
            const search = try f.field("activeSearch");
            if (!f.truth(search) or f.equal(v.arg(args, 0), try f.get(search, "query"))) return c.pi_js_undefined();
            const selected = try f.own(try js.getKey(f.engine, try f.get(search, "matches"), try f.get(search, "selectedIndex")));
            const first = try firstSegment(f, selected);
            const row = if (f.nullish(first)) c.pi_js_undefined() else try f.get(first, "row");
            try f.set(search, "anchorRow", if (f.nullish(row)) try f.get(try f.invoke("getPrimaryScrollView", &.{}), "scrollTop") else row);
            try f.set(search, "query", v.arg(args, 0));
            try f.set(search, "selectionMode", try f.text("query"));
            _ = try f.method(try f.get(search, "component"), "setResult", &.{ f.num(-1), f.num(0) });
            _ = try f.invoke("requestRender", &.{});
        },
        .navigateSearch => {
            const search = try f.field("activeSearch");
            if (f.nullish(search) or !f.truth(try f.get(search, "query"))) return c.pi_js_undefined();
            try f.set(search, "selectionMode", try f.text(if (try f.number(v.arg(args, 0)) < 0) "previous" else "next"));
            _ = try f.invoke("requestRender", &.{});
        },
        .getSearchNavigationDirectionAt => {
            const search = try f.field("activeSearch");
            const overlay = if (f.nullish(search)) c.pi_js_undefined() else try f.get(search, "overlay");
            const bounds = if (f.nullish(overlay)) c.pi_js_undefined() else try f.method(overlay, "getBounds", &.{});
            if (!f.truth(search) or !f.truth(bounds)) return c.pi_js_undefined();
            const x = try f.number(v.arg(args, 0));
            const y = try f.number(v.arg(args, 1));
            if (x < try f.n(bounds, "col") or x >= try f.n(bounds, "col") + try f.n(bounds, "width") or y < try f.n(bounds, "row") or y >= try f.n(bounds, "row") + try f.n(bounds, "height")) return c.pi_js_undefined();
            return f.method(try f.get(search, "component"), "getNavigationDirectionAt", &.{ f.num(y - try f.n(bounds, "row")), f.num(x - try f.n(bounds, "col")) });
        },
        .handleSearchMouseEvent => {
            const search = try f.field("activeSearch");
            if (!f.truth(search)) return f.boolean(false);
            const event = v.arg(args, 0);
            const direction = try f.invoke("getSearchNavigationDirectionAt", &.{ try f.get(event, "x"), try f.get(event, "y") });
            if (f.truth(try f.method(try f.get(search, "component"), "setHoveredNavigationDirection", &.{direction}))) _ = try f.invoke("requestRender", &.{});
            const button = try @import("native_tui_alt_mouse.zig").bits(f, try f.get(event, "button"));
            if (c.JS_IsUndefined(direction) or f.truth(try f.get(event, "release")) or (button & 32) != 0 or (button & 3) != 0) return f.boolean(false);
            _ = try f.invoke("navigateSearch", &.{direction});
            return f.boolean(true);
        },
        .refreshSearch => return refresh(f, v.arg(args, 0)),
        .applySearchTextHighlight => return highlightText(f, v.arg(args, 0), f.truth(v.arg(args, 1))),
        .applySearchHighlights => return highlights(f, v.arg(args, 0), v.arg(args, 1)),
    }
    return c.pi_js_undefined();
}
