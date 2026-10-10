//! Source mouse parsing, component gestures, wheel routing and scrollbar dragging.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
const v = a.v;
pub const Method = enum(c_int) { decodeMouseButton, createMouseEvent, dispatchMouseToLayout, applyMouseDispatchResult, dispatchMouseToTarget, getComponentClickCount, handleMouseEvent, parseWheelEvent, routeWheel, parseSgrMouseEvent, handleRightClickPaste, handleScrollToEndIndicatorMouseEvent, getScrollbarTargetAt, setScrollbarHover, updateScrollbarHover, stopScrollbarHover, scrollScrollbarToPointer, handleScrollbarMouseEvent, stopScrollbarDrag, isMouseSequence };
pub fn bits(f: *Frame, value: c.JSValue) !i32 {
    var result: i32 = 0;
    if (c.JS_ToInt32(f.engine.context, &result, value) < 0) return js.capture(f.engine);
    return result;
}
fn parseInt(f: *Frame, value: c.JSValue) !f64 {
    return f.number(try f.method(try f.global("Number"), "parseInt", &.{ value, f.num(10) }));
}
fn regex(f: *Frame, pattern: []const u8) !c.JSValue {
    return f.own(try @import("native_tui_base_utilities.zig").regexp(f.engine, pattern, ""));
}
fn point(f: *Frame, x: c.JSValue, y: c.JSValue) !c.JSValue {
    const result = try f.record();
    try f.define(result, "x", x);
    try f.define(result, "y", y);
    return result;
}
fn parsed(f: *Frame, button: c.JSValue, x: f64, y: f64, wheel: bool, release: bool) !c.JSValue {
    const result = try f.record();
    if (wheel) try f.define(result, "direction", f.num(if ((try bits(f, button) & 3) == 0) -1 else 1));
    try f.define(result, if (wheel) "x" else "button", if (wheel) f.num(x) else button);
    try f.define(result, if (wheel) "y" else "x", f.num(if (wheel) y else x));
    if (wheel) try f.define(result, "button", button) else {
        try f.define(result, "y", f.num(y));
        try f.define(result, "release", f.boolean(release));
    }
    return result;
}
fn parseWheel(f: *Frame, data: c.JSValue) !c.JSValue {
    const sgr = try f.method(try regex(f, "^\x1b\\[<(\\d+);(\\d+);(\\d+)[Mm]$"), "exec", &.{data});
    if (f.truth(sgr)) {
        const button = try parseInt(f, try f.at(sgr, 1));
        const code = try bits(f, f.num(button));
        if ((code & 64) == 0) return c.pi_js_undefined();
        const direction = code & 3;
        if (direction != 0 and direction != 1) return c.pi_js_undefined();
        return parsed(f, f.num(button), try parseInt(f, try f.at(sgr, 2)) - 1, try parseInt(f, try f.at(sgr, 3)) - 1, true, false);
    }
    if (f.equal(try f.get(data, "length"), f.num(6)) and f.truth(try f.method(data, "startsWith", &.{try f.text("\x1b[M")}))) {
        const button = try f.number(try f.method(data, "charCodeAt", &.{f.num(3)})) - 32;
        const code = try bits(f, f.num(button));
        if ((code & 64) == 0) return c.pi_js_undefined();
        const direction = code & 3;
        if (direction != 0 and direction != 1) return c.pi_js_undefined();
        return parsed(f, f.num(button), try f.number(try f.method(data, "charCodeAt", &.{f.num(4)})) - 33, try f.number(try f.method(data, "charCodeAt", &.{f.num(5)})) - 33, true, false);
    }
    return c.pi_js_undefined();
}
fn parseMouse(f: *Frame, data: c.JSValue) !c.JSValue {
    const match = try f.method(try regex(f, "^\x1b\\[<(\\d+);(\\d+);(\\d+)([Mm])$"), "exec", &.{data});
    if (!f.truth(match)) return c.pi_js_undefined();
    return parsed(f, f.num(try parseInt(f, try f.at(match, 1))), try parseInt(f, try f.at(match, 2)) - 1, try parseInt(f, try f.at(match, 3)) - 1, false, try f.is(try f.at(match, 4), "m"));
}
fn createEvent(f: *Frame, args: []const c.JSValue) !c.JSValue {
    const kind = v.arg(args, 0);
    const button = v.arg(args, 1);
    const x = v.arg(args, 2);
    const y = v.arg(args, 3);
    const extra = if (c.JS_IsUndefined(v.arg(args, 4))) try f.record() else v.arg(args, 4);
    const event = try f.record();
    try f.define(event, "type", kind);
    try f.define(event, "button", if (try f.is(kind, "wheel")) try f.text("none") else try f.invoke("decodeMouseButton", &.{button}));
    try f.define(event, "x", x);
    try f.define(event, "y", y);
    try f.define(event, "screenX", x);
    try f.define(event, "screenY", y);
    try f.define(event, "width", f.num(try f.math("max", &.{ f.num(1), try f.get(try f.field("terminal"), "columns") })));
    try f.define(event, "height", f.num(try f.math("max", &.{ f.num(1), try f.get(try f.field("terminal"), "rows") })));
    try f.define(event, "shift", f.boolean((try bits(f, button) & 4) != 0));
    try f.define(event, "alt", f.boolean((try bits(f, button) & 8) != 0));
    try f.define(event, "ctrl", f.boolean((try bits(f, button) & 16) != 0));
    inline for (.{ "wheelDelta", "clickCount" }) |name| if (!c.JS_IsUndefined(try f.get(extra, name))) try f.define(event, name, try f.get(extra, name));
    return event;
}
fn dispatchLayout(f: *Frame, event: c.JSValue) !c.JSValue {
    if (!f.truth(try f.field("currentLayout"))) return c.pi_js_undefined();
    const visited = try f.construct(try f.global("Set"), &.{});
    const boxes = try f.imported("getLayoutBoxesAt", &.{ try f.field("currentLayout"), try f.get(event, "screenX"), try f.get(event, "screenY") });
    var iterator = try js.Iterator.init(f.engine, boxes, try f.get(f.bindings, "iteratorSymbol"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |box| {
        defer f.engine.freeValue(box);
        if (f.truth(try f.method(visited, "has", &.{try f.get(box, "component")}))) continue;
        if (f.truth(try f.imported("getLayoutNode", &.{try f.get(box, "component")})) and f.equal(try f.get(try f.get(box, "component"), "handleMouse"), try f.get(try f.get(try f.get(f.bindings, "Container"), "prototype"), "handleMouse"))) continue;
        _ = try f.method(visited, "add", &.{try f.get(box, "component")});
        const local = try f.spread(event);
        try f.define(local, "x", f.num(try f.n(event, "screenX") - try f.n(try f.get(box, "rect"), "x")));
        try f.define(local, "y", f.num(try f.n(event, "screenY") - try f.n(try f.get(box, "rect"), "y")));
        try f.define(local, "width", try f.get(try f.get(box, "rect"), "width"));
        try f.define(local, "height", try f.get(try f.get(box, "rect"), "height"));
        const result = try f.imported("dispatchMouseEvent", &.{ try f.get(box, "component"), local });
        if (f.truth(result)) {
            try iterator.close();
            return result;
        }
    }
    return c.pi_js_undefined();
}
fn applyResult(f: *Frame, event: c.JSValue, result: c.JSValue) !c.JSValue {
    const explicit = try f.get(result, "focusTarget");
    const focus = try f.invoke("resolveMouseFocusTarget", &.{if (f.nullish(explicit)) try f.get(try f.get(result, "target"), "component") else explicit});
    const changed = f.equal(try f.get(result, "focus"), f.boolean(true)) and !f.equal(try f.invoke("getFocusedComponent", &.{}), focus);
    if (f.truth(try f.get(result, "focus"))) _ = try f.invoke("setFocus", &.{focus});
    if (f.truth(try f.get(result, "capture"))) try f.put("mouseCapture", try f.get(result, "target"));
    const rendered = try f.get(result, "render");
    if (!f.nullish(rendered)) return rendered;
    if (changed) return f.boolean(true);
    inline for (.{ "press", "click", "drag", "wheel" }) |kind| if (try f.is(try f.get(event, "type"), kind)) return f.boolean(true);
    return f.boolean(false);
}
fn clickCount(f: *Frame, target: c.JSValue, x: c.JSValue, y: c.JSValue) !c.JSValue {
    const now = try f.method(try f.global("Date"), "now", &.{});
    const previous = try f.field("lastComponentClick");
    var count: f64 = 1;
    if (f.truth(previous) and try f.number(now) - try f.n(previous, "timestamp") <= 500 and f.equal(try f.get(previous, "component"), try f.get(target, "component")) and f.equal(try f.get(previous, "x"), x) and f.equal(try f.get(previous, "y"), y)) count = @mod(try f.n(previous, "count"), 3) + 1;
    const record = try f.record();
    try f.define(record, "timestamp", now);
    try f.define(record, "count", f.num(count));
    try f.define(record, "component", try f.get(target, "component"));
    try f.define(record, "x", x);
    try f.define(record, "y", y);
    try f.put("lastComponentClick", record);
    return f.num(count);
}
fn dispatchChoice(f: *Frame, event: c.JSValue, overlay: c.JSValue) !c.JSValue {
    const result = try f.get(overlay, "result");
    return if (!f.nullish(result)) result else if (f.truth(try f.get(overlay, "hit"))) c.pi_js_undefined() else f.invoke("dispatchMouseToLayout", &.{event});
}
fn handle(f: *Frame, raw: c.JSValue) !void {
    const motion = (try bits(f, try f.get(raw, "button")) & 32) != 0;
    const release = f.truth(try f.get(raw, "release"));
    const kind = if (release) "release" else if (motion) if (try f.is(try f.invoke("decodeMouseButton", &.{try f.get(raw, "button")}), "none")) "move" else "drag" else "press";
    const event = try f.invoke("createMouseEvent", &.{ try f.text(kind), try f.get(raw, "button"), try f.get(raw, "x"), try f.get(raw, "y") });
    if (f.truth(try f.field("mouseCapture")) or f.truth(try f.field("mousePressTarget"))) {
        const captured = try f.field("mouseCapture");
        const target = if (f.nullish(captured)) try f.field("mousePressTarget") else captured;
        const point_value = try f.field("mousePressPoint");
        if (f.truth(point_value) and (!f.equal(try f.get(raw, "x"), try f.get(point_value, "x")) or !f.equal(try f.get(raw, "y"), try f.get(point_value, "y")))) {
            try f.put("mousePressMoved", f.boolean(true));
            try f.put("lastComponentClick", c.pi_js_undefined());
        }
        var render = false;
        const result = try f.invoke("dispatchMouseToTarget", &.{ event, target });
        if (f.truth(result)) render = f.truth(try f.invoke("applyMouseDispatchResult", &.{ event, result }));
        if (f.truth(try f.get(raw, "release"))) {
            const press = try f.field("mousePressPoint");
            if (!f.truth(try f.field("mousePressMoved")) and !f.nullish(press) and f.equal(try f.get(press, "x"), try f.get(raw, "x")) and f.equal(try f.get(try f.field("mousePressPoint"), "y"), try f.get(raw, "y"))) {
                const extra = try f.record();
                try f.define(extra, "clickCount", try f.invoke("getComponentClickCount", &.{ target, try f.get(raw, "x"), try f.get(raw, "y") }));
                const click = try f.invoke("createMouseEvent", &.{ try f.text("click"), try f.get(raw, "button"), try f.get(raw, "x"), try f.get(raw, "y"), extra });
                const clicked = try f.invoke("dispatchMouseToTarget", &.{ click, target });
                if (f.truth(clicked)) render = f.truth(try f.invoke("applyMouseDispatchResult", &.{ click, clicked })) or render;
            }
            _ = try f.invoke("clearComponentMouseGesture", &.{});
        }
        if (render) _ = try f.invoke("requestRender", &.{});
        return;
    }
    if (f.truth(try f.invoke("handleSearchMouseEvent", &.{raw}))) return;
    const overlay = try f.invoke("dispatchMouseToOverlay", &.{event});
    if (!f.truth(try f.get(overlay, "hit"))) {
        if (f.truth(try f.invoke("handleScrollToEndIndicatorMouseEvent", &.{raw}))) return;
        const handled = try f.invoke("handleScrollbarMouseEvent", &.{raw});
        if (!f.truth(try f.field("scrollbarDrag"))) _ = try f.invoke("updateScrollbarHover", &.{ try f.get(raw, "x"), try f.get(raw, "y") });
        if (f.truth(handled)) return;
    } else _ = try f.invoke("stopScrollbarHover", &.{});
    const result = try dispatchChoice(f, event, overlay);
    if (f.truth(result)) {
        const render = try f.invoke("applyMouseDispatchResult", &.{ event, result });
        if (stdEqual(kind, "press")) {
            _ = try f.invoke("clearTextSelection", &.{});
            try f.put("mousePressTarget", try f.get(result, "target"));
            try f.put("mousePressPoint", try point(f, try f.get(raw, "x"), try f.get(raw, "y")));
            try f.put("mousePressMoved", f.boolean(false));
        }
        if (f.truth(render)) _ = try f.invoke("requestRender", &.{});
        return;
    }
    if (f.truth(try f.invoke("handleRightClickPaste", &.{raw}))) return;
    _ = try f.invoke("handleSelectionMouseEvent", &.{raw});
}
fn stdEqual(left: []const u8, right: []const u8) bool {
    return @import("std").mem.eql(u8, left, right);
}
fn scrollbarTarget(f: *Frame, x: c.JSValue, y: c.JSValue, hidden: bool) !c.JSValue {
    if (f.truth(try f.invoke("hasOverlay", &.{})) or !f.truth(try f.field("currentLayout"))) return c.pi_js_undefined();
    const views = try f.imported("getScrollViewsAt", &.{ try f.field("currentLayout"), x, y });
    var iterator = try js.Iterator.init(f.engine, views, try f.get(f.bindings, "iteratorSymbol"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |scroll| {
        defer f.engine.freeValue(scroll);
        const box = try f.imported("getScrollViewBox", &.{ try f.field("currentLayout"), scroll });
        const geometry = if (f.truth(box)) try f.imported("getScrollbarGeometry", &.{ box, f.boolean(hidden) }) else c.pi_js_undefined();
        if (f.truth(geometry) and f.equal(x, try f.get(geometry, "column")) and try f.number(y) >= try f.n(geometry, "trackTop") and try f.number(y) < try f.n(geometry, "trackTop") + try f.n(geometry, "trackHeight")) {
            const result = try f.record();
            try f.define(result, "scrollView", scroll);
            try f.define(result, "geometry", geometry);
            try iterator.close();
            return result;
        }
    }
    return c.pi_js_undefined();
}
fn hover(f: *Frame, scroll: c.JSValue) !void {
    if (f.equal(scroll, try f.field("scrollbarHover"))) return;
    const previous = try f.field("scrollbarHover");
    if (!f.nullish(previous)) _ = try f.method(previous, "setScrollbarActive", &.{f.boolean(false)});
    try f.put("scrollbarHover", scroll);
    const current = try f.field("scrollbarHover");
    if (!f.nullish(current)) _ = try f.method(current, "setScrollbarActive", &.{f.boolean(true)});
}
fn scrollPointer(f: *Frame, args: []const c.JSValue) !void {
    const scroll = v.arg(args, 0);
    const geometry = v.arg(args, 1);
    const maximum = try f.n(geometry, "trackHeight") - try f.n(geometry, "thumbHeight");
    const offset = try f.math("max", &.{ f.num(0), f.num(try f.math("min", &.{ f.num(maximum), f.num(try f.number(v.arg(args, 2)) - try f.n(geometry, "trackTop") - try f.number(v.arg(args, 3))) })) });
    const top = if (maximum == 0) 0 else try f.math("round", &.{f.num(offset / maximum * try f.n(geometry, "maxScrollTop"))});
    _ = try f.method(scroll, "scrollTo", &.{f.num(top)});
}
fn scrollbarEvent(f: *Frame, event: c.JSValue) !c.JSValue {
    if (f.truth(try f.field("scrollbarDrag"))) {
        if (f.truth(try f.get(event, "release"))) {
            _ = try f.invoke("stopScrollbarDrag", &.{});
            return f.boolean(true);
        }
        const box = if (f.truth(try f.field("currentLayout"))) try f.imported("getScrollViewBox", &.{ try f.field("currentLayout"), try f.get(try f.field("scrollbarDrag"), "scrollView") }) else c.pi_js_undefined();
        const geometry = if (f.truth(box)) try f.imported("getScrollbarGeometry", &.{box}) else c.pi_js_undefined();
        if (f.truth(geometry)) _ = try f.invoke("scrollScrollbarToPointer", &.{ try f.get(try f.field("scrollbarDrag"), "scrollView"), geometry, try f.get(event, "y"), try f.get(try f.field("scrollbarDrag"), "grabOffset") });
        return f.boolean(true);
    }
    if (f.truth(try f.get(event, "release")) or (try bits(f, try f.get(event, "button")) & 32) != 0 or (try bits(f, try f.get(event, "button")) & 3) != 0) return f.boolean(false);
    const target = try f.invoke("getScrollbarTargetAt", &.{ try f.get(event, "x"), try f.get(event, "y") });
    if (!f.truth(target)) return f.boolean(false);
    _ = try f.invoke("stopSelectionAutoScroll", &.{});
    try f.put("selectionPressActive", f.boolean(false));
    inline for (.{ "selectionAnchor", "selectionFocus" }) |name| try f.put(name, c.pi_js_undefined());
    try f.put("selectionGranularity", try f.text("character"));
    inline for (.{ "selectionInitialRange", "lastClick", "pressedUrl" }) |name| try f.put(name, c.pi_js_undefined());
    try f.put("selectionDragged", f.boolean(false));
    _ = try f.invoke("setScrollbarHover", &.{try f.get(target, "scrollView")});
    const geometry = try f.get(target, "geometry");
    const on_thumb = try f.n(event, "y") >= try f.n(geometry, "thumbTop") and try f.n(event, "y") < try f.n(geometry, "thumbTop") + try f.n(geometry, "thumbHeight");
    const grab = if (on_thumb) try f.n(event, "y") - try f.n(geometry, "thumbTop") else try f.math("floor", &.{f.num(try f.n(geometry, "thumbHeight") / 2)});
    if (!on_thumb) _ = try f.invoke("scrollScrollbarToPointer", &.{ try f.get(target, "scrollView"), try f.get(target, "geometry"), try f.get(event, "y"), f.num(grab) });
    const drag = try f.record();
    try f.define(drag, "scrollView", try f.get(target, "scrollView"));
    try f.define(drag, "grabOffset", f.num(grab));
    try f.put("scrollbarDrag", drag);
    return f.boolean(true);
}
pub fn invoke(f: *Frame, method: Method, args: []const c.JSValue) anyerror!c.JSValue {
    switch (method) {
        .decodeMouseButton => return f.text(switch (try bits(f, v.arg(args, 0)) & 3) {
            0 => "left",
            1 => "middle",
            2 => "right",
            else => "none",
        }),
        .createMouseEvent => return createEvent(f, args),
        .dispatchMouseToLayout => return dispatchLayout(f, v.arg(args, 0)),
        .applyMouseDispatchResult => return applyResult(f, v.arg(args, 0), v.arg(args, 1)),
        .dispatchMouseToTarget => return f.imported("dispatchMouseEvent", &.{ try f.get(v.arg(args, 1), "component"), try f.imported("retargetMouseEvent", &.{ v.arg(args, 0), v.arg(args, 1) }) }),
        .getComponentClickCount => return clickCount(f, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2)),
        .handleMouseEvent => try handle(f, v.arg(args, 0)),
        .parseWheelEvent => return parseWheel(f, v.arg(args, 0)),
        .parseSgrMouseEvent => return parseMouse(f, v.arg(args, 0)),
        .routeWheel => {
            const event = v.arg(args, 0);
            var remaining = v.arg(args, 1);
            const seen = try f.construct(try f.global("Set"), &.{});
            const views = if (f.truth(try f.field("currentLayout"))) try f.imported("getScrollViewsAt", &.{ try f.field("currentLayout"), try f.get(event, "x"), try f.get(event, "y") }) else try f.array();
            var iterator = try js.Iterator.init(f.engine, views, try f.get(f.bindings, "iteratorSymbol"));
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |scroll| {
                defer f.engine.freeValue(scroll);
                _ = try f.method(seen, "add", &.{scroll});
                remaining = try f.method(scroll, "scrollBy", &.{remaining});
                if (f.equal(remaining, f.num(0)) or try f.is(try f.get(scroll, "overscroll"), "contain")) {
                    try iterator.close();
                    break;
                }
            }
            const primary = try f.invoke("getPrimaryScrollView", &.{});
            if (!f.equal(remaining, f.num(0)) and !f.truth(try f.method(seen, "has", &.{primary}))) _ = try f.method(primary, "scrollBy", &.{remaining});
            _ = try f.invoke("updateScrollbarHover", &.{ try f.get(event, "x"), try f.get(event, "y") });
            _ = try f.invoke("requestRender", &.{});
        },
        .handleRightClickPaste => {
            const event = v.arg(args, 0);
            if (!f.truth(try f.field("onRightClickPaste")) or !try f.is(try f.get(try f.global("process"), "platform"), "win32")) return f.boolean(false);
            const program = try f.get(try f.get(try f.global("process"), "env"), "TERM_PROGRAM");
            if ((!f.nullish(program) and try f.is(try f.method(program, "toLowerCase", &.{}), "vscode")) or f.truth(try f.get(event, "release")) or !f.equal(try f.get(event, "button"), f.num(2))) return f.boolean(false);
            _ = f.invoke("onRightClickPaste", &.{}) catch |err| blk: {
                if (err != error.JavaScriptException) return err;
                break :blk c.pi_js_undefined();
            };
            return f.boolean(true);
        },
        .handleScrollToEndIndicatorMouseEvent => {
            const event = v.arg(args, 0);
            const area = try f.field("scrollToEndIndicatorRect");
            if (!f.truth(area) or f.truth(try f.get(event, "release")) or (try bits(f, try f.get(event, "button")) & 32) != 0 or (try bits(f, try f.get(event, "button")) & 3) != 0) return f.boolean(false);
            if (!f.equal(try f.get(event, "y"), try f.get(area, "row")) or try f.n(event, "x") < try f.n(area, "column") or try f.n(event, "x") >= try f.n(area, "column") + try f.n(area, "width")) return f.boolean(false);
            _ = try f.invoke("scrollToBottom", &.{});
            return f.boolean(true);
        },
        .getScrollbarTargetAt => return scrollbarTarget(f, v.arg(args, 0), v.arg(args, 1), f.truth(v.arg(args, 2))),
        .setScrollbarHover => try hover(f, v.arg(args, 0)),
        .updateScrollbarHover => {
            const target = try f.invoke("getScrollbarTargetAt", &.{ v.arg(args, 0), v.arg(args, 1), f.boolean(true) });
            _ = try f.invoke("setScrollbarHover", &.{if (f.nullish(target)) c.pi_js_undefined() else try f.get(target, "scrollView")});
        },
        .stopScrollbarHover => {
            _ = try f.invoke("setScrollbarHover", &.{c.pi_js_undefined()});
        },
        .scrollScrollbarToPointer => try scrollPointer(f, args),
        .handleScrollbarMouseEvent => return scrollbarEvent(f, v.arg(args, 0)),
        .stopScrollbarDrag => try f.put("scrollbarDrag", c.pi_js_undefined()),
        .isMouseSequence => {
            const data = v.arg(args, 0);
            return f.boolean(f.truth(try f.method(try regex(f, "^\x1b\\[<\\d+;\\d+;\\d+[Mm]$"), "test", &.{data})) or (f.equal(try f.get(data, "length"), f.num(6)) and f.truth(try f.method(data, "startsWith", &.{try f.text("\x1b[M")}))));
        },
    }
    return c.pi_js_undefined();
}
