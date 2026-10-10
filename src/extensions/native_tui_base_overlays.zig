//! Source overlay visibility, focus targeting and mouse dispatch.
//! The ordinary entry/layout objects are shared with the screen renderer.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Method = enum { hideOverlay, hasOverlay, isOverlayFocused, resolveMouseFocusTarget, dispatchMouseToOverlay, isOverlayVisible, getTopmostVisibleOverlay };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase overlays: %s", @as([*:0]const u8, @errorName(err)));
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn boolean(engine: *js.Engine, value: bool) c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(value));
}
fn visible(engine: *js.Engine, screen: c.JSValue, entry: c.JSValue) !bool {
    const value = try js.invoke(engine, screen, "isOverlayVisible", &.{entry});
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn predicate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return predicateBody(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), magic != 0) catch |err| fail(engine, err);
}
fn predicateBody(engine: *js.Engine, screen: c.JSValue, entry: c.JSValue, focused_only: bool) !c.JSValue {
    if (focused_only) {
        const component = try js.get(engine, entry, "component");
        defer engine.freeValue(component);
        const focused = try js.get(engine, screen, "focusedComponent");
        defer engine.freeValue(focused);
        if (!c.JS_IsStrictEqual(engine.context, component, focused)) return boolean(engine, false);
    }
    return js.invoke(engine, screen, "isOverlayVisible", &.{entry});
}
fn hit(engine: *js.Engine, value: bool) !c.JSValue {
    const object = try js.object(engine);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "hit", boolean(engine, value));
    return object;
}
pub fn invoke(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .isOverlayVisible => {
            const entry = v.arg(args, 0);
            const hidden = try js.get(engine, entry, "hidden");
            defer engine.freeValue(hidden);
            if (v.truthy(engine, hidden)) return boolean(engine, false);
            const options = try js.get(engine, entry, "options");
            defer engine.freeValue(options);
            if (!nullish(options)) {
                const callback = try js.get(engine, options, "visible");
                defer engine.freeValue(callback);
                if (v.truthy(engine, callback)) {
                    const current_options = try js.get(engine, entry, "options");
                    defer engine.freeValue(current_options);
                    const current_callback = try js.get(engine, current_options, "visible");
                    defer engine.freeValue(current_callback);
                    const first_terminal = try js.get(engine, screen, "terminal");
                    defer engine.freeValue(first_terminal);
                    const columns = try js.get(engine, first_terminal, "columns");
                    defer engine.freeValue(columns);
                    const second_terminal = try js.get(engine, screen, "terminal");
                    defer engine.freeValue(second_terminal);
                    const rows = try js.get(engine, second_terminal, "rows");
                    defer engine.freeValue(rows);
                    return js.call(engine, current_callback, current_options, &.{ columns, rows });
                }
            }
            return boolean(engine, true);
        },
        .getTopmostVisibleOverlay => {
            const stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(stack);
            const symbol = try js.get(engine, bindings, "iteratorSymbol");
            defer engine.freeValue(symbol);
            var iterator = try js.Iterator.init(engine, stack, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            var topmost = c.pi_js_undefined();
            errdefer engine.freeValue(topmost);
            while (try iterator.next()) |entry| {
                defer engine.freeValue(entry);
                const options = try js.get(engine, entry, "options");
                defer engine.freeValue(options);
                if (!nullish(options)) {
                    const non_capturing = try js.get(engine, options, "nonCapturing");
                    defer engine.freeValue(non_capturing);
                    if (v.truthy(engine, non_capturing)) continue;
                }
                if (!try visible(engine, screen, entry)) continue;
                if (!v.truthy(engine, topmost) or try v.numberField(engine, entry, "focusOrder") > try v.numberField(engine, topmost, "focusOrder")) {
                    engine.freeValue(topmost);
                    topmost = c.JS_DupValue(engine.context, entry);
                }
            }
            return topmost;
        },
        .hasOverlay, .isOverlayFocused => {
            const stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(stack);
            const some = try js.get(engine, stack, "some");
            defer engine.freeValue(some);
            var data = [_]c.JSValue{screen};
            const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, predicate, "", 1, @intFromBool(method == .isOverlayFocused), 1, &data));
            defer engine.freeValue(callback);
            return js.call(engine, some, stack, &.{callback});
        },
        .hideOverlay => {
            const stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(stack);
            const length_stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(length_stack);
            const index = v.numeric(engine, try v.numberField(engine, length_stack, "length") - 1);
            const entry = try js.getKey(engine, stack, index);
            defer engine.freeValue(entry);
            if (!v.truthy(engine, entry)) return c.pi_js_undefined();
            try v.invokeVoid(engine, screen, "clearOverlayFocusRestoreFor", &.{entry});
            try v.invokeVoid(engine, screen, "retargetOverlayPreFocus", &.{entry});
            const current_stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(current_stack);
            try v.invokeVoid(engine, current_stack, "pop", &.{});
            const focused = try js.get(engine, screen, "focusedComponent");
            defer engine.freeValue(focused);
            const component = try js.get(engine, entry, "component");
            defer engine.freeValue(component);
            if (c.JS_IsStrictEqual(engine.context, focused, component)) {
                const top = try js.invoke(engine, screen, "getTopmostVisibleOverlay", &.{});
                defer engine.freeValue(top);
                const set_focus = try js.get(engine, screen, "setFocus");
                defer engine.freeValue(set_focus);
                var next = if (nullish(top)) c.pi_js_undefined() else try js.get(engine, top, "component");
                defer engine.freeValue(next);
                if (nullish(next)) {
                    const fallback = try js.get(engine, entry, "preFocus");
                    engine.freeValue(next);
                    next = fallback;
                }
                const result = try js.call(engine, set_focus, screen, &.{next});
                engine.freeValue(result);
            }
            const final_stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(final_stack);
            const length = try js.get(engine, final_stack, "length");
            defer engine.freeValue(length);
            if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) try v.invokeVoid(engine, screen, "hideTerminalCursor", &.{});
            try v.invokeVoid(engine, screen, "requestRender", &.{});
            return c.pi_js_undefined();
        },
        .resolveMouseFocusTarget => {
            const component = v.arg(args, 0);
            const first_stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(first_stack);
            var index = try v.numberField(engine, first_stack, "length") - 1;
            while (index >= 0) : (index -= 1) {
                const stack = try js.get(engine, screen, "overlayStack");
                defer engine.freeValue(stack);
                const entry = try js.getKey(engine, stack, v.numeric(engine, index));
                defer engine.freeValue(entry);
                if (!try visible(engine, screen, entry)) continue;
                const contains = try js.get(engine, screen, "containsComponent");
                defer engine.freeValue(contains);
                const root = try js.get(engine, entry, "component");
                defer engine.freeValue(root);
                const matched = try js.call(engine, contains, screen, &.{ root, component });
                defer engine.freeValue(matched);
                if (v.truthy(engine, matched)) return js.get(engine, entry, "component");
            }
            return c.JS_DupValue(engine.context, component);
        },
        .dispatchMouseToOverlay => return dispatchMouse(engine, screen, bindings, v.arg(args, 0)),
    }
}
fn dispatchMouse(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, event: c.JSValue) !c.JSValue {
    const first_layouts = try js.get(engine, screen, "renderedOverlayLayouts");
    defer engine.freeValue(first_layouts);
    var index = try v.numberField(engine, first_layouts, "length") - 1;
    while (index >= 0) : (index -= 1) {
        const layouts = try js.get(engine, screen, "renderedOverlayLayouts");
        defer engine.freeValue(layouts);
        const layout = try js.getKey(engine, layouts, v.numeric(engine, index));
        defer engine.freeValue(layout);
        if (try v.numberField(engine, event, "screenX") < try v.numberField(engine, layout, "col")) continue;
        if (try v.numberField(engine, event, "screenX") >= try edge(engine, bindings, layout, "col", "width")) continue;
        if (try v.numberField(engine, event, "screenY") < try v.numberField(engine, layout, "row")) continue;
        if (try v.numberField(engine, event, "screenY") >= try edge(engine, bindings, layout, "row", "height")) continue;
        const dispatch = try js.get(engine, bindings, "dispatchMouseEvent");
        defer engine.freeValue(dispatch);
        const entry = try js.get(engine, layout, "entry");
        defer engine.freeValue(entry);
        const component = try js.get(engine, entry, "component");
        defer engine.freeValue(component);
        const local = try js.object(engine);
        defer engine.freeValue(local);
        try js.spreadInto(engine, local, event);
        try js.define(engine, local, "x", v.numeric(engine, try v.numberField(engine, event, "screenX") - try v.numberField(engine, layout, "col")));
        try js.define(engine, local, "y", v.numeric(engine, try v.numberField(engine, event, "screenY") - try v.numberField(engine, layout, "row")));
        try js.define(engine, local, "width", try js.get(engine, layout, "width"));
        try js.define(engine, local, "height", try js.get(engine, layout, "height"));
        const dispatched = try js.call(engine, dispatch, c.pi_js_undefined(), &.{ component, local });
        defer engine.freeValue(dispatched);
        const result = try hit(engine, true);
        errdefer engine.freeValue(result);
        if (!v.truthy(engine, dispatched)) return result;
        const focus = try js.get(engine, dispatched, "focus");
        defer engine.freeValue(focus);
        if (!v.truthy(engine, focus)) {
            try js.define(engine, result, "result", c.JS_DupValue(engine.context, dispatched));
        } else {
            const with_focus = blk: {
                const object = try js.object(engine);
                errdefer engine.freeValue(object);
                try js.spreadInto(engine, object, dispatched);
                const current_entry = try js.get(engine, layout, "entry");
                defer engine.freeValue(current_entry);
                try js.define(engine, object, "focusTarget", try js.get(engine, current_entry, "component"));
                break :blk object;
            };
            try js.define(engine, result, "result", with_focus);
        }
        return result;
    }
    return hit(engine, false);
}
fn edge(engine: *js.Engine, bindings: c.JSValue, layout: c.JSValue, first: [*:0]const u8, second: [*:0]const u8) !f64 {
    const a = try js.get(engine, layout, first);
    defer engine.freeValue(a);
    const b = try js.get(engine, layout, second);
    defer engine.freeValue(b);
    const symbol = try js.get(engine, bindings, "primitiveSymbol");
    defer engine.freeValue(symbol);
    const value = try @import("native_tui_value_arithmetic.zig").add(engine, a, b, symbol);
    defer engine.freeValue(value);
    return v.number(engine, value);
}
