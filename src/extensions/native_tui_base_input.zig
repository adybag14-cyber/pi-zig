//! Source keyboard dispatch, including overlay focus recovery and listener edits.
//! Plain callbacks use the emission context; capability values guard themselves.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase input: %s", @as([*:0]const u8, @errorName(err)));
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn fieldEquals(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, expected: []const u8) !bool {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn predicate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const overlay = if (argc > 0) argv[0] else c.pi_js_undefined();
    return predicateBody(engine, data[0], overlay) catch |err| fail(engine, err);
}
fn predicateBody(engine: *js.Engine, screen: c.JSValue, overlay: c.JSValue) !c.JSValue {
    const component = try js.get(engine, overlay, "component");
    defer engine.freeValue(component);
    const focused = try js.get(engine, screen, "focusedComponent");
    defer engine.freeValue(focused);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, component, focused)));
}
fn search(engine: *js.Engine, screen: c.JSValue, method: [*:0]const u8) !c.JSValue {
    const stack = try js.get(engine, screen, "overlayStack");
    defer engine.freeValue(stack);
    const function = try js.get(engine, stack, method);
    defer engine.freeValue(function);
    var data = [_]c.JSValue{screen};
    const matches = try engine.checked(c.JS_NewCFunctionData2(engine.context, predicate, "", 1, 0, 1, &data));
    defer engine.freeValue(matches);
    return js.call(engine, function, stack, &.{matches});
}
fn focusField(engine: *js.Engine, screen: c.JSValue, object: c.JSValue, field: [*:0]const u8) !void {
    const set_focus = try js.get(engine, screen, "setFocus");
    defer engine.freeValue(set_focus);
    const component = try js.get(engine, object, field);
    defer engine.freeValue(component);
    const result = try js.call(engine, set_focus, screen, &.{component});
    engine.freeValue(result);
}
fn focusRestore(engine: *js.Engine, screen: c.JSValue, restore: c.JSValue) !void {
    const set_focus = try js.get(engine, screen, "setFocus");
    defer engine.freeValue(set_focus);
    const overlay = try js.get(engine, restore, "overlay");
    defer engine.freeValue(overlay);
    const component = try js.get(engine, overlay, "component");
    defer engine.freeValue(component);
    const result = try js.call(engine, set_focus, screen, &.{component});
    engine.freeValue(result);
}
fn importedBool(engine: *js.Engine, bindings: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !bool {
    const function = try js.get(engine, bindings, name);
    defer engine.freeValue(function);
    const result = try js.call(engine, function, c.pi_js_undefined(), args);
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
fn consumed(engine: *js.Engine, screen: c.JSValue, method: [*:0]const u8, data: c.JSValue) !bool {
    const result = try js.invoke(engine, screen, method, &.{data});
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
pub fn invoke(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, input: c.JSValue) !c.JSValue {
    if (try consumed(engine, screen, "consumeTerminalColorResponse", input)) return c.pi_js_undefined();
    if (try consumed(engine, screen, "consumeTerminalColorSchemeReport", input)) return c.pi_js_undefined();
    var data = c.JS_DupValue(engine.context, input);
    defer engine.freeValue(data);
    const first_listeners = try js.get(engine, screen, "inputListeners");
    defer engine.freeValue(first_listeners);
    if (try v.numberField(engine, first_listeners, "size") > 0) {
        const listeners = try js.get(engine, screen, "inputListeners");
        defer engine.freeValue(listeners);
        const symbol = try js.get(engine, bindings, "iteratorSymbol");
        defer engine.freeValue(symbol);
        var iterator = try js.Iterator.init(engine, listeners, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |listener| {
            defer engine.freeValue(listener);
            const result = try js.call(engine, listener, c.pi_js_undefined(), &.{data});
            defer engine.freeValue(result);
            if (nullish(result)) continue;
            const consume = try js.get(engine, result, "consume");
            defer engine.freeValue(consume);
            if (v.truthy(engine, consume)) {
                try iterator.close();
                return c.pi_js_undefined();
            }
            const changed = try js.get(engine, result, "data");
            defer engine.freeValue(changed);
            if (!c.JS_IsUndefined(changed)) {
                const next = try js.get(engine, result, "data");
                engine.freeValue(data);
                data = next;
            }
        }
        const length = try js.get(engine, data, "length");
        defer engine.freeValue(length);
        if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
    }
    if (try consumed(engine, screen, "consumeCellSizeResponse", data)) return c.pi_js_undefined();
    const debug_key = try v.text(engine, "shift+ctrl+d");
    defer engine.freeValue(debug_key);
    if (try importedBool(engine, bindings, "matchesKey", &.{ data, debug_key })) {
        const on_debug = try js.get(engine, screen, "onDebug");
        defer engine.freeValue(on_debug);
        if (v.truthy(engine, on_debug)) {
            try v.invokeVoid(engine, screen, "onDebug", &.{});
            return c.pi_js_undefined();
        }
    }
    const focused_overlay = try search(engine, screen, "find");
    defer engine.freeValue(focused_overlay);
    if (v.truthy(engine, focused_overlay) and !try consumed(engine, screen, "isOverlayVisible", focused_overlay)) {
        const top = try js.invoke(engine, screen, "getTopmostVisibleOverlay", &.{});
        defer engine.freeValue(top);
        if (v.truthy(engine, top)) {
            try focusField(engine, screen, top, "component");
        } else {
            const set_focus = try js.get(engine, screen, "setFocusInternal");
            defer engine.freeValue(set_focus);
            const options = try js.object(engine);
            defer engine.freeValue(options);
            try js.define(engine, options, "component", try js.get(engine, focused_overlay, "preFocus"));
            try js.define(engine, options, "overlayFocusRestore", try v.text(engine, "preserve"));
            const result = try js.call(engine, set_focus, screen, &.{options});
            engine.freeValue(result);
        }
    }
    const focus_is_overlay = try search(engine, screen, "some");
    defer engine.freeValue(focus_is_overlay);
    if (!v.truthy(engine, focus_is_overlay)) {
        const restore = try js.invoke(engine, screen, "getVisibleOverlayFocusRestore", &.{});
        defer engine.freeValue(restore);
        if (try fieldEquals(engine, restore, "status", "eligible")) {
            try focusRestore(engine, screen, restore);
        } else if (try fieldEquals(engine, restore, "status", "blocked")) {
            const blocked = try js.get(engine, restore, "blockedBy");
            defer engine.freeValue(blocked);
            const focused = try js.get(engine, screen, "focusedComponent");
            defer engine.freeValue(focused);
            if (!c.JS_IsStrictEqual(engine.context, blocked, focused)) {
                const resume_state = try js.get(engine, restore, "resume");
                defer engine.freeValue(resume_state);
                if (try fieldEquals(engine, resume_state, "status", "restore-overlay")) {
                    try focusRestore(engine, screen, restore);
                } else {
                    try v.invokeVoid(engine, screen, "clearOverlayFocusRestore", &.{});
                    const set_focus = try js.get(engine, screen, "setFocus");
                    defer engine.freeValue(set_focus);
                    const current_resume = try js.get(engine, restore, "resume");
                    defer engine.freeValue(current_resume);
                    const target = try js.get(engine, current_resume, "target");
                    defer engine.freeValue(target);
                    const result = try js.call(engine, set_focus, screen, &.{target});
                    engine.freeValue(result);
                }
            }
        }
    }
    const focused = try js.get(engine, screen, "focusedComponent");
    defer engine.freeValue(focused);
    if (nullish(focused)) return c.pi_js_undefined();
    const handler = try js.get(engine, focused, "handleInput");
    defer engine.freeValue(handler);
    if (!v.truthy(engine, handler)) return c.pi_js_undefined();
    if (try importedBool(engine, bindings, "isKeyRelease", &.{data})) {
        const current = try js.get(engine, screen, "focusedComponent");
        defer engine.freeValue(current);
        const wants = try js.get(engine, current, "wantsKeyRelease");
        defer engine.freeValue(wants);
        if (!v.truthy(engine, wants)) return c.pi_js_undefined();
    }
    const current = try js.get(engine, screen, "focusedComponent");
    defer engine.freeValue(current);
    try v.invokeVoid(engine, current, "handleInput", &.{data});
    try v.invokeVoid(engine, screen, "requestImmediateRender", &.{});
    return c.pi_js_undefined();
}
