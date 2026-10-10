//! Source focus, wheel, mouse and keyboard viewport-input routing.
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const js = a.js;
const c = a.c;
fn consume(f: *Frame) !c.JSValue {
    const result = try f.record();
    try f.define(result, "consume", f.boolean(true));
    return result;
}
fn matches(f: *Frame, bindings: c.JSValue, data: c.JSValue, action: []const u8) !bool {
    return f.truth(try f.method(bindings, "matches", &.{ data, try f.text(action) }));
}
pub fn invoke(f: *Frame, data: c.JSValue) anyerror!c.JSValue {
    if (try f.is(data, "\x1b[O")) {
        const active = try f.field("selectionPressActive");
        const nonempty = f.truth(active) and !c.JS_IsUndefined(try f.invoke("getSelectionBounds", &.{}));
        try f.put("selectionPressActive", f.boolean(false));
        _ = try f.invoke("stopSelectionAutoScroll", &.{});
        _ = try f.invoke("stopScrollbarHover", &.{});
        const search = try f.field("activeSearch");
        if (!f.nullish(search) and f.truth(try f.method(try f.get(search, "component"), "setHoveredNavigationDirection", &.{c.pi_js_undefined()}))) _ = try f.invoke("requestRender", &.{});
        _ = try f.invoke("stopScrollbarDrag", &.{});
        try f.put("pressedUrl", c.pi_js_undefined());
        try f.put("selectionDragged", f.boolean(false));
        _ = try f.invoke("clearComponentMouseGesture", &.{});
        try f.put("lastComponentClick", c.pi_js_undefined());
        if (f.truth(active)) {
            try f.put("selectionAnchor", c.pi_js_undefined());
            try f.put("selectionFocus", c.pi_js_undefined());
            try f.put("selectionGranularity", try f.text("character"));
            try f.put("selectionInitialRange", c.pi_js_undefined());
            if (nonempty) _ = try f.invoke("requestRender", &.{});
        }
        try f.put("lastClick", c.pi_js_undefined());
        return consume(f);
    }
    if (try f.is(data, "\x1b[I")) return consume(f);
    const wheel = try f.invoke("parseWheelEvent", &.{data});
    if (f.truth(wheel)) {
        const clock = try f.global("performance");
        const lines = try f.method(try f.field("wheelScroll"), "next", &.{ try f.get(wheel, "direction"), try f.method(clock, "now", &.{}) });
        const delta = try f.n(wheel, "direction") * ((if ((try @import("native_tui_alt_mouse.zig").bits(f, try f.get(wheel, "button")) & 8) != 0) try f.number(lines) * 5 else try f.number(lines)));
        const extra = try f.record();
        try f.define(extra, "wheelDelta", f.num(delta));
        const event = try f.invoke("createMouseEvent", &.{ try f.text("wheel"), try f.get(wheel, "button"), try f.get(wheel, "x"), try f.get(wheel, "y"), extra });
        const overlay = try f.invoke("dispatchMouseToOverlay", &.{event});
        const overlay_result = try f.get(overlay, "result");
        const result = if (!f.nullish(overlay_result)) overlay_result else if (f.truth(try f.get(overlay, "hit"))) c.pi_js_undefined() else try f.invoke("dispatchMouseToLayout", &.{event});
        if (f.truth(result)) {
            if (f.truth(try f.invoke("applyMouseDispatchResult", &.{ event, result }))) _ = try f.invoke("requestRender", &.{});
            return consume(f);
        }
        if (f.truth(try f.invoke("shouldDeferViewportInputToOverlay", &.{}))) return c.pi_js_undefined();
        _ = try f.invoke("routeWheel", &.{ wheel, f.num(delta) });
        return consume(f);
    }
    const mouse = try f.invoke("parseSgrMouseEvent", &.{data});
    if (f.truth(mouse)) {
        _ = try f.invoke("handleMouseEvent", &.{mouse});
        return consume(f);
    }
    if (f.truth(try f.invoke("isMouseSequence", &.{data}))) return consume(f);
    const keys = try f.imported("getKeybindings", &.{});
    const release = f.truth(try f.imported("isKeyRelease", &.{data}));
    if (try matches(f, keys, data, "tui.altScreen.search")) {
        if (!release) _ = try f.invoke("toggleSearch", &.{});
        return consume(f);
    }
    const search = try f.field("activeSearch");
    const overlay = if (f.nullish(search)) c.pi_js_undefined() else try f.get(search, "overlay");
    if (!f.nullish(overlay) and f.truth(try f.method(overlay, "isFocused", &.{}))) {
        if (try matches(f, keys, data, "tui.altScreen.searchNext")) {
            if (!release) _ = try f.invoke("navigateSearch", &.{f.num(1)});
            return consume(f);
        }
        if (try matches(f, keys, data, "tui.altScreen.searchPrevious")) {
            if (!release) _ = try f.invoke("navigateSearch", &.{f.num(-1)});
            return consume(f);
        }
        if (try matches(f, keys, data, "tui.altScreen.searchClose")) {
            if (!release) _ = try f.invoke("closeSearch", &.{});
            return consume(f);
        }
    }
    if (f.truth(try f.invoke("shouldDeferViewportInputToOverlay", &.{}))) return c.pi_js_undefined();
    inline for (.{ .{ "pageUp", @as(f64, -1), false }, .{ "pageDown", @as(f64, 1), false }, .{ "halfPageUp", @as(f64, -1), true }, .{ "halfPageDown", @as(f64, 1), true } }) |action| {
        if (try matches(f, keys, data, "tui.altScreen." ++ action[0])) {
            if (!release) {
                const height = try f.n(try f.invoke("getPrimaryScrollView", &.{}), "viewportHeight");
                const size = if (action[2]) try f.math("floor", &.{f.num(height / 2)}) else height - 4;
                _ = try f.invoke("scrollBy", &.{f.num(action[1] * try f.math("max", &.{ f.num(1), f.num(size) }))});
            }
            return consume(f);
        }
    }
    inline for (.{ .{ "lineUp", "scrollBy", @as(f64, -1) }, .{ "lineDown", "scrollBy", @as(f64, 1) }, .{ "previousPrompt", "scrollToPrompt", @as(f64, -1) }, .{ "nextPrompt", "scrollToPrompt", @as(f64, 1) } }) |action| {
        if (try matches(f, keys, data, "tui.altScreen." ++ action[0])) {
            if (!release) _ = try f.invoke(action[1], &.{f.num(action[2])});
            return consume(f);
        }
    }
    if (try matches(f, keys, data, "tui.altScreen.top")) {
        if (!release) _ = try f.invoke("scrollToTop", &.{});
        return consume(f);
    }
    if (try matches(f, keys, data, "tui.altScreen.bottom")) {
        if (!release) _ = try f.invoke("scrollToBottom", &.{});
        return consume(f);
    }
    return c.pi_js_undefined();
}
