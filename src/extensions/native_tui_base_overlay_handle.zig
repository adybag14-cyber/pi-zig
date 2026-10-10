//! Source showOverlay and its seven plain closure methods over the live entry.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const Method = enum(c_int) { hide, setHidden, isHidden, focus, unfocus, isFocused, getBounds };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase overlay handle: %s", @as([*:0]const u8, @errorName(err)));
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn nonCapturing(engine: *js.Engine, options: c.JSValue) !bool {
    if (nullish(options)) return false;
    const value = try js.get(engine, options, "nonCapturing");
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn visible(engine: *js.Engine, screen: c.JSValue, entry: c.JSValue) !bool {
    const result = try js.invoke(engine, screen, "isOverlayVisible", &.{entry});
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
fn includes(engine: *js.Engine, screen: c.JSValue, entry: c.JSValue) !bool {
    const stack = try js.get(engine, screen, "overlayStack");
    defer engine.freeValue(stack);
    const value = try js.invoke(engine, stack, "includes", &.{entry});
    defer engine.freeValue(value);
    return v.truthy(engine, value);
}
fn focused(engine: *js.Engine, screen: c.JSValue, component: c.JSValue) !bool {
    const value = try js.get(engine, screen, "focusedComponent");
    defer engine.freeValue(value);
    return c.JS_IsStrictEqual(engine.context, value, component);
}
fn sameField(engine: *js.Engine, object: c.JSValue, name: [*:0]const u8, expected: c.JSValue) !bool {
    const value = try js.get(engine, object, name);
    defer engine.freeValue(value);
    return c.JS_IsStrictEqual(engine.context, value, expected);
}
fn status(engine: *js.Engine, object: c.JSValue, expected: []const u8) !bool {
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return sameField(engine, object, "status", text);
}
fn restoreFocus(engine: *js.Engine, screen: c.JSValue, entry: c.JSValue) !void {
    const top = try js.invoke(engine, screen, "getTopmostVisibleOverlay", &.{});
    defer engine.freeValue(top);
    const set_focus = try js.get(engine, screen, "setFocus");
    defer engine.freeValue(set_focus);
    var component = if (nullish(top)) c.pi_js_undefined() else try js.get(engine, top, "component");
    defer engine.freeValue(component);
    if (nullish(component)) {
        const fallback = try js.get(engine, entry, "preFocus");
        engine.freeValue(component);
        component = fallback;
    }
    const result = try js.call(engine, set_focus, screen, &.{component});
    engine.freeValue(result);
}
fn counter(engine: *js.Engine, screen: c.JSValue, entry: c.JSValue, bindings: c.JSValue) !void {
    try v.set(engine, entry, "focusOrder", try @import("native_tui_base_counter.zig").increment(engine, screen, bindings));
}
pub fn show(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const component = v.arg(args, 0);
    const options = v.arg(args, 1);
    const entry = try js.object(engine);
    defer engine.freeValue(entry);
    try js.define(engine, entry, "component", c.JS_DupValue(engine.context, component));
    if (!c.JS_IsUndefined(options)) try js.define(engine, entry, "options", c.JS_DupValue(engine.context, options));
    try js.define(engine, entry, "preFocus", try js.get(engine, screen, "focusedComponent"));
    try js.define(engine, entry, "hidden", c.pi_js_bool(engine.context, 0));
    try js.define(engine, entry, "focusOrder", try @import("native_tui_base_counter.zig").increment(engine, screen, bindings));
    const stack = try js.get(engine, screen, "overlayStack");
    defer engine.freeValue(stack);
    try v.invokeVoid(engine, stack, "push", &.{entry});
    if (!try nonCapturing(engine, options) and try visible(engine, screen, entry)) try v.invokeVoid(engine, screen, "setFocus", &.{component});
    try v.invokeVoid(engine, screen, "hideTerminalCursor", &.{});
    try v.invokeVoid(engine, screen, "requestRender", &.{});
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        var data = [_]c.JSValue{ screen, entry, component, options, bindings };
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, callbackCall, field.name, if (field.value == @intFromEnum(Method.setHidden) or field.value == @intFromEnum(Method.unfocus)) 1 else 0, field.value, 5, &data));
        try js.define(engine, result, field.name, callback);
    }
    return result;
}
fn callbackCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, @enumFromInt(magic), data, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn invoke(engine: *js.Engine, method: Method, data: [*c]c.JSValue, argument: c.JSValue) !c.JSValue {
    const screen = data[0];
    const entry = data[1];
    const component = data[2];
    const options = data[3];
    const bindings = data[4];
    switch (method) {
        .isHidden => return js.get(engine, entry, "hidden"),
        .isFocused => return c.pi_js_bool(engine.context, @intFromBool(try focused(engine, screen, component))),
        .hide => {
            const stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(stack);
            const index = try js.invoke(engine, stack, "indexOf", &.{entry});
            defer engine.freeValue(index);
            if (c.JS_IsStrictEqual(engine.context, index, c.JS_NewInt32(engine.context, -1))) return c.pi_js_undefined();
            try v.invokeVoid(engine, screen, "clearOverlayFocusRestoreFor", &.{entry});
            try v.invokeVoid(engine, screen, "retargetOverlayPreFocus", &.{entry});
            const current_stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(current_stack);
            try v.invokeVoid(engine, current_stack, "splice", &.{ index, c.JS_NewInt32(engine.context, 1) });
            if (try focused(engine, screen, component)) try restoreFocus(engine, screen, entry);
            const final_stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(final_stack);
            const length = try js.get(engine, final_stack, "length");
            defer engine.freeValue(length);
            if (c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 0))) try v.invokeVoid(engine, screen, "hideTerminalCursor", &.{});
            try v.invokeVoid(engine, screen, "requestRender", &.{});
        },
        .setHidden => {
            if (try sameField(engine, entry, "hidden", argument)) return c.pi_js_undefined();
            try v.set(engine, entry, "hidden", c.JS_DupValue(engine.context, argument));
            if (v.truthy(engine, argument)) {
                try v.invokeVoid(engine, screen, "clearOverlayFocusRestoreFor", &.{entry});
                if (try focused(engine, screen, component)) try restoreFocus(engine, screen, entry);
            } else if (!try nonCapturing(engine, options) and try visible(engine, screen, entry)) {
                try counter(engine, screen, entry, bindings);
                try v.invokeVoid(engine, screen, "setFocus", &.{component});
            }
            try v.invokeVoid(engine, screen, "requestRender", &.{});
        },
        .focus => {
            if (!try includes(engine, screen, entry) or !try visible(engine, screen, entry)) return c.pi_js_undefined();
            try counter(engine, screen, entry, bindings);
            try v.invokeVoid(engine, screen, "setFocus", &.{component});
            try v.invokeVoid(engine, screen, "requestRender", &.{});
        },
        .getBounds => {
            if (!try includes(engine, screen, entry) or !try visible(engine, screen, entry)) return c.pi_js_undefined();
            const bounds = try js.get(engine, entry, "bounds");
            defer engine.freeValue(bounds);
            if (!v.truthy(engine, bounds)) return c.pi_js_undefined();
            const result = try js.object(engine);
            errdefer engine.freeValue(result);
            const current = try js.get(engine, entry, "bounds");
            defer engine.freeValue(current);
            try js.spreadInto(engine, result, current);
            return result;
        },
        .unfocus => try unfocus(engine, screen, entry, component, argument),
    }
    return c.pi_js_undefined();
}
fn unfocus(engine: *js.Engine, screen: c.JSValue, entry: c.JSValue, component: c.JSValue, options: c.JSValue) !void {
    const is_focused = try focused(engine, screen, component);
    const restore = try js.get(engine, screen, "overlayFocusRestore");
    defer engine.freeValue(restore);
    const has_pending = !try status(engine, restore, "inactive") and try sameField(engine, restore, "overlay", entry);
    if (!is_focused and !has_pending) return;
    if (try status(engine, restore, "blocked") and try sameField(engine, restore, "overlay", entry)) {
        const current_focus = try js.get(engine, screen, "focusedComponent");
        defer engine.freeValue(current_focus);
        if (try sameField(engine, restore, "blockedBy", current_focus)) {
            if (v.truthy(engine, options)) {
                const changed = try js.object(engine);
                defer engine.freeValue(changed);
                try js.define(engine, changed, "status", try v.text(engine, "blocked"));
                try js.define(engine, changed, "overlay", c.JS_DupValue(engine.context, entry));
                try js.define(engine, changed, "blockedBy", try js.get(engine, restore, "blockedBy"));
                const resume_state = blk: {
                    const value = try js.object(engine);
                    errdefer engine.freeValue(value);
                    try js.define(engine, value, "status", try v.text(engine, "focus-target"));
                    try js.define(engine, value, "target", try js.get(engine, options, "target"));
                    break :blk value;
                };
                try js.define(engine, changed, "resume", resume_state);
                try v.set(engine, screen, "overlayFocusRestore", c.JS_DupValue(engine.context, changed));
            } else {
                try v.invokeVoid(engine, screen, "clearOverlayFocusRestore", &.{});
            }
            try v.invokeVoid(engine, screen, "requestRender", &.{});
            return;
        }
    }
    try v.invokeVoid(engine, screen, "clearOverlayFocusRestoreFor", &.{entry});
    if (is_focused or v.truthy(engine, options)) {
        const top = try js.invoke(engine, screen, "getTopmostVisibleOverlay", &.{});
        defer engine.freeValue(top);
        const fallback = if (v.truthy(engine, top) and !c.JS_IsStrictEqual(engine.context, top, entry)) try js.get(engine, top, "component") else try js.get(engine, entry, "preFocus");
        defer engine.freeValue(fallback);
        const set_focus = try js.get(engine, screen, "setFocus");
        defer engine.freeValue(set_focus);
        const target = if (v.truthy(engine, options)) try js.get(engine, options, "target") else c.JS_DupValue(engine.context, fallback);
        defer engine.freeValue(target);
        const result = try js.call(engine, set_focus, screen, &.{target});
        engine.freeValue(result);
    }
    try v.invokeVoid(engine, screen, "requestRender", &.{});
}
