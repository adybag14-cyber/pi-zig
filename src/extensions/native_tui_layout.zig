//! Genuine layout.ts tree, clipping, scroll geometry and hit paths.
const std = @import("std");
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
const v = a.v;
const callbacks = @import("native_tui_alt_callbacks.zig");
pub const Method = enum(c_int) { renderLayoutFrame, getLayoutNode, getLayoutBoxesAt, getScrollViewBox, getScrollViewsAt, getScrollbarGeometry };
fn rect(f: *Frame, x: f64, y: f64, width: f64, height: f64) !c.JSValue {
    const object = try f.record();
    try f.define(object, "x", f.num(x));
    try f.define(object, "y", f.num(y));
    try f.define(object, "width", f.num(width));
    try f.define(object, "height", f.num(height));
    return object;
}
fn intersection(f: *Frame, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const x = try f.math("max", &.{ try f.get(left, "x"), try f.get(right, "x") });
    const y = try f.math("max", &.{ try f.get(left, "y"), try f.get(right, "y") });
    const edge = try f.math("min", &.{ f.num(try f.n(left, "x") + try f.n(left, "width")), f.num(try f.n(right, "x") + try f.n(right, "width")) });
    const bottom = try f.math("min", &.{ f.num(try f.n(left, "y") + try f.n(left, "height")), f.num(try f.n(right, "y") + try f.n(right, "height")) });
    return rect(f, x, y, try f.math("max", &.{ f.num(0), f.num(edge - x) }), try f.math("max", &.{ f.num(0), f.num(bottom - y) }));
}
fn node(f: *Frame, component: c.JSValue) !c.JSValue {
    const key = try f.get(f.bindings, "layoutSymbol");
    const candidate = try f.own(try js.getKey(f.engine, component, key));
    if (!c.JS_IsFunction(f.engine.context, candidate)) return c.pi_js_undefined();
    // Source reads the candidate again for the actual member call.
    return f.call(try f.own(try js.getKey(f.engine, component, key)), component, &.{});
}
fn renderCached(f: *Frame, context: c.JSValue, component: c.JSValue, width: f64) !c.JSValue {
    const safe = try f.math("max", &.{ f.num(1), f.num(try f.math("floor", &.{f.num(width)})) });
    const cache = try f.get(context, "renderCache");
    var widths = try f.method(cache, "get", &.{component});
    if (!f.truth(widths)) {
        widths = try f.construct(try f.global("Map"), &.{});
        _ = try f.method(cache, "set", &.{ component, widths });
    }
    var lines = try f.method(widths, "get", &.{f.num(safe)});
    if (!f.truth(lines)) {
        lines = try f.method(component, "render", &.{f.num(safe)});
        _ = try f.method(widths, "set", &.{ f.num(safe), lines });
    }
    return lines;
}
pub fn measureValue(f: *Frame, context: c.JSValue, component: c.JSValue, width: f64, horizontal: bool) anyerror!c.JSValue {
    const lines = try renderCached(f, context, component, width);
    if (!horizontal) return f.get(lines, "length");
    return callbacks.reduce(f, lines, .maxWidth, c.pi_js_undefined());
}
fn translate(f: *Frame, box: c.JSValue, delta: f64) anyerror!void {
    const area = try f.get(box, "rect");
    try f.set(area, "y", try f.add(try f.get(area, "y"), f.num(delta)));
    const children = try f.get(box, "children");
    var iterator = try js.Iterator.init(f.engine, children, try f.get(f.bindings, "iteratorSymbol"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer f.engine.freeValue(child);
        try translate(f, child, delta);
    }
}
fn clips(f: *Frame, box: c.JSValue, parent: c.JSValue) anyerror!void {
    try f.set(box, "clip", try intersection(f, parent, try f.get(box, "rect")));
    const children = try f.get(box, "children");
    var iterator = try js.Iterator.init(f.engine, children, try f.get(f.bindings, "iteratorSymbol"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer f.engine.freeValue(child);
        try clips(f, child, try f.get(box, "clip"));
    }
}
fn boxObject(f: *Frame, component: c.JSValue, area: c.JSValue, clip: c.JSValue) !c.JSValue {
    const object = try f.record();
    try f.define(object, "component", component);
    try f.define(object, "rect", area);
    try f.define(object, "clip", clip);
    try f.define(object, "children", try f.array());
    return object;
}
threadlocal var layout_depth: usize = 0;
fn layout(f: *Frame, context: c.JSValue, component: c.JSValue, x: f64, y: f64, width: f64, height: c.JSValue, clip: c.JSValue) anyerror!c.JSValue {
    layout_depth += 1;
    defer layout_depth -= 1;
    if (layout_depth > 512) return js.typeError(f.engine, "Maximum layout depth exceeded");
    const safe = try f.math("max", &.{ f.num(1), f.num(try f.math("floor", &.{f.num(width)})) });
    const layout_node = try node(f, component);
    if (!f.truth(layout_node)) {
        const lines = try renderCached(f, context, component, safe);
        const allocated = if (c.JS_IsUndefined(height)) try f.n(lines, "length") else try f.math("max", &.{ f.num(0), f.num(try f.math("floor", &.{height})) });
        var offset: f64 = 0;
        if (try f.n(lines, "length") > allocated and allocated > 0) {
            const find = try f.get(lines, "findIndex");
            const cursor_line = try f.number(try f.call(find, lines, &.{try callbacks.create(f, .hasCursor, c.pi_js_undefined())}));
            if (cursor_line >= allocated) offset = cursor_line - allocated + 1;
        }
        const area = try rect(f, x, y, safe, allocated);
        const box = try boxObject(f, component, area, try intersection(f, clip, area));
        try f.define(box, "lines", lines);
        try f.define(box, "lineOffset", f.num(offset));
        try f.define(box, "layer", f.num(0));
        return box;
    }
    if (try f.is(try f.get(layout_node, "type"), "scroll")) {
        const state = try f.get(layout_node, "state");
        const before = try f.n(state, "scrollTop");
        const content_width = try f.number(try f.method(state, "getContentWidth", &.{f.num(safe)}));
        const child = try layout(f, context, try f.get(layout_node, "component"), x, y - before, content_width, c.pi_js_undefined(), clip);
        const content_height = try f.n(try f.get(child, "rect"), "height");
        const viewport_height = if (c.JS_IsUndefined(height)) content_height else try f.math("max", &.{ f.num(0), f.num(try f.math("floor", &.{height})) });
        _ = try f.method(try f.get(layout_node, "state"), "updateLayout", &.{ f.num(content_height), f.num(viewport_height), try f.get(context, "requestRender") });
        try translate(f, child, before - try f.n(try f.get(layout_node, "state"), "scrollTop"));
        const scroll = try f.get(layout_node, "state");
        if (f.truth(try f.get(try f.get(layout_node, "state"), "primary")) or !f.truth(try f.get(context, "primaryScrollView"))) try f.set(context, "primaryScrollView", scroll);
        const area = try rect(f, x, y, safe, viewport_height);
        const child_clip = try intersection(f, clip, area);
        const box = try boxObject(f, component, area, child_clip);
        try f.define(box, "children", try f.literal(&.{child}));
        try f.define(box, "scrollView", scroll);
        try f.define(box, "scrollContentLines", try renderCached(f, context, try f.get(layout_node, "component"), content_width));
        try f.define(box, "layer", f.num(0));
        try f.set(child, "parent", box);
        try clips(f, child, child_clip);
        return box;
    }
    const entries = try f.own(try @import("native_stack_components.zig").visibleLayoutEntries(f.engine, try f.get(layout_node, "entries"), try f.get(context, "viewport")));
    const gap_total = try f.math("max", &.{ f.num(0), f.num(try f.n(entries, "length") - 1) }) * try f.n(layout_node, "gap");
    const vertical = try f.is(try f.get(layout_node, "type"), "vstack");
    const capture = try f.record();
    try f.define(capture, "context", context);
    try f.define(capture, "width", f.num(safe));
    try f.define(capture, "horizontal", f.boolean(!vertical));
    const intrinsic = try callbacks.map(f, entries, .intrinsic, capture);
    const sizes = try f.own(try @import("native_stack_components.zig").allocateLayoutSizes(f.engine, entries, intrinsic, if (vertical) height else f.num(safe), try f.get(layout_node, "gap"), try f.get(f.bindings, "iteratorSymbol"), try f.get(f.bindings, "primitiveSymbol")));
    var allocated: f64 = 0;
    var heights: c.JSValue = c.pi_js_undefined();
    if (vertical) {
        allocated = try f.number(try callbacks.reduce(f, sizes, .sum, c.pi_js_undefined()));
        allocated += gap_total;
        if (!c.JS_IsUndefined(height)) allocated = try f.math("max", &.{ f.num(0), f.num(try f.math("floor", &.{height})) });
    } else {
        try f.define(capture, "sizes", sizes);
        heights = try callbacks.map(f, entries, .childHeight, capture);
        allocated = if (c.JS_IsUndefined(height)) try f.number(try callbacks.reduce(f, heights, .max, c.pi_js_undefined())) else try f.math("max", &.{ f.num(0), height });
    }
    const area = try rect(f, x, y, safe, allocated);
    const box = try boxObject(f, component, area, try intersection(f, clip, area));
    try f.define(box, "layer", f.num(0));
    var child_x = x;
    var child_y = y;
    var index: f64 = 0;
    while (index < try f.n(entries, "length")) : (index += 1) {
        const child_width = if (vertical) safe else try f.number(try f.at(sizes, index));
        var child_height = if (vertical) try f.number(try f.at(sizes, index)) else allocated;
        if (!vertical) {
            const alignment = try f.get(layout_node, "align");
            if (!try f.is(alignment, "stretch")) child_height = try f.math("min", &.{ f.num(allocated), try f.at(heights, index) });
            child_y = y;
            if (try f.is(try f.get(layout_node, "align"), "center")) child_y += try f.math("floor", &.{f.num((allocated - child_height) / 2)}) else if (try f.is(try f.get(layout_node, "align"), "end")) child_y += allocated - child_height;
        }
        const child_component = try f.get(try f.at(entries, index), "component");
        const child = if (!vertical and child_width == 0) try boxObject(f, child_component, try rect(f, child_x, child_y, 0, child_height), try rect(f, child_x, child_y, 0, 0)) else try layout(f, context, child_component, child_x, child_y, child_width, f.num(child_height), try f.get(box, "clip"));
        try f.set(child, "parent", box);
        if (!vertical and child_width == 0) try f.define(child, "layer", f.num(0));
        try f.push(try f.get(box, "children"), child);
        if (vertical) child_y += try f.number(try f.at(sizes, index)) + try f.n(layout_node, "gap") else child_x += child_width + try f.n(layout_node, "gap");
    }
    return box;
}
pub fn geometry(f: *Frame, box: c.JSValue, include_hidden: bool) !c.JSValue {
    const scroll = try f.get(box, "scrollView");
    const area = try f.get(box, "rect");
    if (!f.truth(scroll) or try f.n(area, "width") <= 0 or try f.n(area, "height") <= 0) return c.pi_js_undefined();
    const first = try f.at(try f.get(box, "children"), 0);
    var content: f64 = 0;
    if (!f.nullish(first)) content = try f.n(try f.get(first, "rect"), "height") else {
        const lines = try f.get(box, "scrollContentLines");
        if (!f.nullish(lines)) content = try f.n(lines, "length");
    }
    const track = try f.n(area, "height");
    const can_reveal = include_hidden and try f.is(try f.get(scroll, "scrollbar"), "auto") and content > track;
    if (!f.truth(try f.get(try f.get(box, "scrollView"), "isScrollbarVisible")) and !can_reveal) return c.pi_js_undefined();
    const thumb = try f.math("max", &.{ f.num(try f.math("min", &.{ f.num(2), f.num(track) })), f.num(try f.math("min", &.{ f.num(track), f.num(try f.math("round", &.{f.num(track * track / content)})) })) });
    const maximum = try f.math("max", &.{ f.num(0), f.num(content - track) });
    const offset = if (maximum == 0) 0 else try f.math("round", &.{f.num(try f.n(try f.get(box, "scrollView"), "scrollTop") / maximum * (track - thumb))});
    const column = try f.n(area, "x") + try f.n(area, "width") - 1;
    const clip = try f.get(box, "clip");
    if (column < try f.n(clip, "x") or column >= try f.n(clip, "x") + try f.n(clip, "width")) return c.pi_js_undefined();
    const output = try f.record();
    try f.define(output, "column", f.num(column));
    try f.define(output, "trackTop", try f.get(area, "y"));
    try f.define(output, "trackHeight", f.num(track));
    try f.define(output, "thumbTop", f.num(try f.n(area, "y") + offset));
    try f.define(output, "thumbHeight", f.num(thumb));
    try f.define(output, "maxScrollTop", f.num(maximum));
    return output;
}
fn contains(f: *Frame, area: c.JSValue, x: f64, y: f64) !bool {
    return x >= try f.n(area, "x") and x < try f.n(area, "x") + try f.n(area, "width") and y >= try f.n(area, "y") and y < try f.n(area, "y") + try f.n(area, "height");
}
fn findScroll(f: *Frame, box: c.JSValue, scroll: c.JSValue) anyerror!c.JSValue {
    if (f.equal(try f.get(box, "scrollView"), scroll)) return box;
    const children = try f.get(box, "children");
    var iterator = try js.Iterator.init(f.engine, children, try f.get(f.bindings, "iteratorSymbol"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer f.engine.freeValue(child);
        const found = try findScroll(f, child, scroll);
        if (f.truth(found)) {
            try iterator.close();
            return found;
        }
    }
    return c.pi_js_undefined();
}
fn hits(f: *Frame, box: c.JSValue, x: f64, y: f64, depth: f64, scroll_only: bool, result: c.JSValue) anyerror!void {
    if (!try contains(f, try f.get(box, "clip"), x, y)) return;
    const scroll = try f.get(box, "scrollView");
    if (!scroll_only or (f.truth(scroll) and try contains(f, try f.get(box, "rect"), x, y))) {
        const entry = try f.record();
        try f.define(entry, if (scroll_only) "scrollView" else "box", if (scroll_only) scroll else box);
        try f.define(entry, "depth", f.num(depth));
        try f.push(result, entry);
    }
    const children = try f.get(box, "children");
    var iterator = try js.Iterator.init(f.engine, children, try f.get(f.bindings, "iteratorSymbol"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |child| {
        defer f.engine.freeValue(child);
        try hits(f, child, x, y, depth + 1, scroll_only, result);
    }
}
fn sortCall(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = c.pi_js_undefined(), .bindings = c.pi_js_undefined() };
    defer f.deinit();
    return sort(&f, v.arg(if (argc > 0) argv[0..@intCast(argc)] else &.{}, 0), v.arg(if (argc > 0) argv[0..@intCast(argc)] else &.{}, 1), f.truth(data[0])) catch |err| a.fail(engine, err);
}
fn sort(f: *Frame, left: c.JSValue, right: c.JSValue, scroll_only: bool) !c.JSValue {
    if (scroll_only) return f.num(try f.n(right, "depth") - try f.n(left, "depth"));
    const layer = try f.n(try f.get(right, "box"), "layer") - try f.n(try f.get(left, "box"), "layer");
    return f.num(if (layer != 0 and !std.math.isNan(layer)) layer else try f.n(right, "depth") - try f.n(left, "depth"));
}
pub fn invoke(f: *Frame, method: Method, args: []const c.JSValue) anyerror!c.JSValue {
    switch (method) {
        .getLayoutNode => return node(f, v.arg(args, 0)),
        .getScrollViewBox => return findScroll(f, try f.get(v.arg(args, 0), "root"), v.arg(args, 1)),
        .getScrollbarGeometry => return geometry(f, v.arg(args, 0), f.truth(v.arg(args, 1))),
        .getLayoutBoxesAt, .getScrollViewsAt => {
            const result = try f.array();
            try hits(f, try f.get(v.arg(args, 0), "root"), try f.number(v.arg(args, 1)), try f.number(v.arg(args, 2)), 0, method == .getScrollViewsAt, result);
            var data = [_]c.JSValue{f.boolean(method == .getScrollViewsAt)};
            const sort_function = try f.get(result, "sort");
            const comparator = try f.own(try f.engine.checked(c.JS_NewCFunctionData2(f.engine.context, sortCall, "", 2, 0, 1, &data)));
            _ = try f.call(sort_function, result, &.{comparator});
            return callbacks.map(f, result, .unwrap, try f.text(if (method == .getScrollViewsAt) "scrollView" else "box"));
        },
        .renderLayoutFrame => return render(f, args),
    }
}
fn render(f: *Frame, args: []const c.JSValue) anyerror!c.JSValue {
    const width = try f.math("max", &.{ f.num(1), f.num(try f.math("floor", &.{v.arg(args, 1)})) });
    const height = try f.math("max", &.{ f.num(1), f.num(try f.math("floor", &.{v.arg(args, 2)})) });
    const context = try f.record();
    const viewport = try f.record();
    try f.define(viewport, "width", f.num(width));
    try f.define(viewport, "height", f.num(height));
    try f.define(context, "viewport", viewport);
    try f.define(context, "renderCache", try f.construct(try f.global("Map"), &.{}));
    try f.define(context, "requestRender", v.arg(args, 3));
    try f.define(context, "primaryScrollView", c.pi_js_undefined());
    const root = try layout(f, context, v.arg(args, 0), 0, 0, width, f.num(height), try rect(f, 0, 0, width, height));
    const length = try f.record();
    try f.define(length, "length", f.num(height));
    const array = try f.global("Array");
    const from = try f.get(array, "from");
    const lines = try f.call(from, array, &.{ length, try callbacks.create(f, .empty, c.pi_js_undefined()) });
    try @import("native_tui_layout_paint.zig").paint(f, root, lines, width);
    const output = try f.record();
    try f.define(output, "root", root);
    try f.define(output, "width", f.num(width));
    try f.define(output, "height", f.num(height));
    try f.define(output, "lines", lines);
    const primary = try f.get(context, "primaryScrollView");
    if (!c.JS_IsUndefined(primary)) try f.define(output, "primaryScrollView", primary);
    return output;
}
fn call(ctx: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = this, .bindings = data[0] };
    defer f.deinit();
    const result = invoke(&f, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| return a.fail(engine, err);
    return f.result(result);
}
pub fn install(engine: *js.Engine, bindings: c.JSValue) !void {
    var data = [_]c.JSValue{bindings};
    inline for (std.meta.fields(Method)) |field| {
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .renderLayoutFrame => 4,
            .getLayoutBoxesAt, .getScrollViewsAt => 3,
            .getScrollViewBox => 2,
            else => 1,
        };
        try js.define(engine, bindings, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, call, field.name, length, field.value, 1, &data)));
    }
}
