//! Source TuiBase focus state over ordinary fields and virtual instance methods.
//! The complete screen class installation is authored separately.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub const Method = enum {
    getFocusedComponent,
    setFocus,
    setFocusInternal,
    clearOverlayFocusRestore,
    clearOverlayFocusRestoreFor,
    resolveBlockedOverlayFocusResume,
    getVisibleOverlayFocusRestore,
    isOverlayFocusAncestor,
    retargetOverlayPreFocus,
    getMountedRoots,
    isComponentMounted,
    containsComponent,
};
const Callback = enum(c_int) { visibleComponent, matchingComponent, containsChild };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase focus: %s", @as([*:0]const u8, @errorName(err)));
}
fn equal(engine: *js.Engine, left: c.JSValue, right: c.JSValue) bool {
    return c.JS_IsStrictEqual(engine.context, left, right);
}
fn status(engine: *js.Engine, object: c.JSValue, expected: []const u8) !bool {
    const value = try js.get(engine, object, "status");
    defer engine.freeValue(value);
    const text = try v.text(engine, expected);
    defer engine.freeValue(text);
    return equal(engine, value, text);
}
fn returnedBool(engine: *js.Engine, value: bool) c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(value));
}
fn callback(engine: *js.Engine, kind: Callback, screen: c.JSValue, target: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{ screen, target };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callbackCall, "", 1, @intFromEnum(kind), 2, &data));
}
fn callbackCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return callbackBody(engine, @enumFromInt(magic), data[0], data[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn callbackBody(engine: *js.Engine, kind: Callback, screen: c.JSValue, target: c.JSValue, item: c.JSValue) !c.JSValue {
    if (kind == .containsChild) return js.invoke(engine, screen, "containsComponent", &.{ item, target });
    const component = try js.get(engine, item, "component");
    defer engine.freeValue(component);
    if (!equal(engine, component, target)) return returnedBool(engine, false);
    return if (kind == .visibleComponent) js.invoke(engine, screen, "isOverlayVisible", &.{item}) else returnedBool(engine, true);
}
fn search(engine: *js.Engine, screen: c.JSValue, method: [*:0]const u8, kind: Callback, target: c.JSValue) !c.JSValue {
    const stack = try js.get(engine, screen, "overlayStack");
    defer engine.freeValue(stack);
    const predicate = try callback(engine, kind, screen, target);
    defer engine.freeValue(predicate);
    return js.invoke(engine, stack, method, &.{predicate});
}
fn invokeField(engine: *js.Engine, receiver: c.JSValue, method: [*:0]const u8, object: c.JSValue, field: [*:0]const u8) !c.JSValue {
    const function = try js.get(engine, receiver, method);
    defer engine.freeValue(function);
    const argument = try js.get(engine, object, field);
    defer engine.freeValue(argument);
    return js.call(engine, function, receiver, &.{argument});
}
fn setFocusOption(engine: *js.Engine, screen: c.JSValue, component: c.JSValue) !c.JSValue {
    const function = try js.get(engine, screen, "setFocusInternal");
    defer engine.freeValue(function);
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "component", c.JS_DupValue(engine.context, component));
    try js.define(engine, options, "overlayFocusRestore", try v.text(engine, "clear"));
    return js.call(engine, function, screen, &.{options});
}
fn focusable(engine: *js.Engine, bindings: c.JSValue, value: c.JSValue) !bool {
    const function = try js.get(engine, bindings, "isFocusable");
    defer engine.freeValue(function);
    const result = try js.call(engine, function, c.pi_js_undefined(), &.{value});
    defer engine.freeValue(result);
    return v.truthy(engine, result);
}
fn replaceBlocked(engine: *js.Engine, screen: c.JSValue, overlay: c.JSValue, next: c.JSValue) !void {
    const value = try js.object(engine);
    defer engine.freeValue(value);
    try js.define(engine, value, "status", try v.text(engine, "blocked"));
    try js.define(engine, value, "overlay", c.JS_DupValue(engine.context, overlay));
    try js.define(engine, value, "blockedBy", c.JS_DupValue(engine.context, next));
    const resume_state = blk: {
        const result = try js.object(engine);
        errdefer engine.freeValue(result);
        try js.define(engine, result, "status", try v.text(engine, "restore-overlay"));
        break :blk result;
    };
    try js.define(engine, value, "resume", resume_state);
    try v.set(engine, screen, "overlayFocusRestore", c.JS_DupValue(engine.context, value));
}
pub fn invoke(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .getFocusedComponent => return js.get(engine, screen, "focusedComponent"),
        .getMountedRoots => return js.get(engine, screen, "children"),
        .setFocus => return setFocusOption(engine, screen, v.arg(args, 0)),
        .clearOverlayFocusRestore => {
            try v.set(engine, screen, "overlayFocusRestore", try @import("native_tui_base_fields.zig").inactiveRestore(engine));
            return c.pi_js_undefined();
        },
        .clearOverlayFocusRestoreFor => {
            const tested = try js.get(engine, screen, "overlayFocusRestore");
            defer engine.freeValue(tested);
            if (!try status(engine, tested, "inactive")) {
                const restore = try js.get(engine, screen, "overlayFocusRestore");
                defer engine.freeValue(restore);
                const overlay = try js.get(engine, restore, "overlay");
                defer engine.freeValue(overlay);
                if (equal(engine, overlay, v.arg(args, 0))) try v.invokeVoid(engine, screen, "clearOverlayFocusRestore", &.{});
            }
            return c.pi_js_undefined();
        },
        .resolveBlockedOverlayFocusResume => {
            const restore = v.arg(args, 0);
            const resume_state = try js.get(engine, restore, "resume");
            defer engine.freeValue(resume_state);
            if (try status(engine, resume_state, "restore-overlay")) {
                const overlay = try js.get(engine, restore, "overlay");
                defer engine.freeValue(overlay);
                return js.get(engine, overlay, "component");
            }
            try v.invokeVoid(engine, screen, "clearOverlayFocusRestore", &.{});
            const latest_resume = try js.get(engine, restore, "resume");
            defer engine.freeValue(latest_resume);
            return js.get(engine, latest_resume, "target");
        },
        .getVisibleOverlayFocusRestore => {
            const restore = try js.get(engine, screen, "overlayFocusRestore");
            defer engine.freeValue(restore);
            if (try status(engine, restore, "inactive")) return c.JS_DupValue(engine.context, restore);
            const stack = try js.get(engine, screen, "overlayStack");
            defer engine.freeValue(stack);
            const included = try invokeField(engine, stack, "includes", restore, "overlay");
            defer engine.freeValue(included);
            const visible = if (v.truthy(engine, included)) try invokeField(engine, screen, "isOverlayVisible", restore, "overlay") else c.pi_js_bool(engine.context, 0);
            defer engine.freeValue(visible);
            if (!v.truthy(engine, included) or !v.truthy(engine, visible)) {
                return @import("native_tui_base_fields.zig").inactiveRestore(engine);
            }
            return c.JS_DupValue(engine.context, restore);
        },
        .isComponentMounted => {
            const roots = try js.invoke(engine, screen, "getMountedRoots", &.{});
            defer engine.freeValue(roots);
            const predicate = try callback(engine, .containsChild, screen, v.arg(args, 0));
            defer engine.freeValue(predicate);
            return js.invoke(engine, roots, "some", &.{predicate});
        },
        .containsComponent => {
            const root = v.arg(args, 0);
            const target = v.arg(args, 1);
            if (equal(engine, root, target)) return returnedBool(engine, true);
            const container = try js.get(engine, bindings, "Container");
            defer engine.freeValue(container);
            const is_instance = c.JS_IsInstanceOf(engine.context, root, container);
            if (is_instance < 0) return js.capture(engine);
            if (is_instance == 0) return returnedBool(engine, false);
            const children = try js.get(engine, root, "children");
            defer engine.freeValue(children);
            const predicate = try callback(engine, .containsChild, screen, target);
            defer engine.freeValue(predicate);
            return js.invoke(engine, children, "some", &.{predicate});
        },
        .isOverlayFocusAncestor => return ancestor(engine, screen, v.arg(args, 0), v.arg(args, 1)),
        .retargetOverlayPreFocus => return retarget(engine, screen, bindings, v.arg(args, 0)),
        .setFocusInternal => return setFocusInternal(engine, screen, bindings, v.arg(args, 0)),
    }
}
fn ancestor(engine: *js.Engine, screen: c.JSValue, entry: c.JSValue, component: c.JSValue) !c.JSValue {
    const visited = try js.builtin(engine, "Set", &.{});
    defer engine.freeValue(visited);
    var current = try js.get(engine, entry, "preFocus");
    defer engine.freeValue(current);
    while (v.truthy(engine, current)) {
        const included = try js.invoke(engine, visited, "has", &.{current});
        defer engine.freeValue(included);
        if (v.truthy(engine, included)) break;
        try v.invokeVoid(engine, visited, "add", &.{current});
        if (equal(engine, current, component)) return returnedBool(engine, true);
        const found = try search(engine, screen, "find", .matchingComponent, current);
        defer engine.freeValue(found);
        const next = if (c.JS_IsNull(found) or c.JS_IsUndefined(found)) c.pi_js_undefined() else try js.get(engine, found, "preFocus");
        engine.freeValue(current);
        current = if (c.JS_IsNull(next) or c.JS_IsUndefined(next)) blk: {
            engine.freeValue(next);
            break :blk c.pi_js_null();
        } else next;
    }
    return returnedBool(engine, false);
}
fn retarget(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, removed: c.JSValue) !c.JSValue {
    const stack = try js.get(engine, screen, "overlayStack");
    defer engine.freeValue(stack);
    const symbol = try js.get(engine, bindings, "iteratorSymbol");
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, stack, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |overlay| {
        defer engine.freeValue(overlay);
        if (equal(engine, overlay, removed)) continue;
        const pre_focus = try js.get(engine, overlay, "preFocus");
        defer engine.freeValue(pre_focus);
        const component = try js.get(engine, removed, "component");
        defer engine.freeValue(component);
        if (equal(engine, pre_focus, component)) try v.set(engine, overlay, "preFocus", try js.get(engine, removed, "preFocus"));
    }
    return c.pi_js_undefined();
}
fn setFocusInternal(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue, options: c.JSValue) !c.JSValue {
    const component = try js.get(engine, options, "component");
    defer engine.freeValue(component);
    const policy = try js.get(engine, options, "overlayFocusRestore");
    defer engine.freeValue(policy);
    const previous = try js.get(engine, screen, "focusedComponent");
    defer engine.freeValue(previous);
    var next = c.JS_DupValue(engine.context, component);
    defer engine.freeValue(next);
    const previous_overlay = if (v.truthy(engine, previous)) try search(engine, screen, "find", .visibleComponent, previous) else c.pi_js_undefined();
    defer engine.freeValue(previous_overlay);
    const next_overlay = if (v.truthy(engine, next)) try search(engine, screen, "some", .matchingComponent, next) else c.pi_js_bool(engine.context, 0);
    defer engine.freeValue(next_overlay);
    const restore = try js.invoke(engine, screen, "getVisibleOverlayFocusRestore", &.{});
    defer engine.freeValue(restore);
    if (v.truthy(engine, next) and !v.truthy(engine, next_overlay)) {
        const blocked = try status(engine, restore, "blocked");
        const blocked_by = if (blocked) try js.get(engine, restore, "blockedBy") else c.pi_js_undefined();
        defer engine.freeValue(blocked_by);
        if (blocked and equal(engine, blocked_by, previous)) {
            const resume_state = try js.get(engine, restore, "resume");
            defer engine.freeValue(resume_state);
            const focus_target = try status(engine, resume_state, "focus-target");
            const mounted = if (!focus_target) try invokeField(engine, screen, "isComponentMounted", restore, "blockedBy") else c.pi_js_bool(engine.context, 0);
            defer engine.freeValue(mounted);
            if (focus_target or !v.truthy(engine, mounted)) {
                const resolved = try js.invoke(engine, screen, "resolveBlockedOverlayFocusResume", &.{restore});
                engine.freeValue(next);
                next = resolved;
            } else {
                const value = try js.object(engine);
                defer engine.freeValue(value);
                try js.define(engine, value, "status", try v.text(engine, "blocked"));
                try js.define(engine, value, "overlay", try js.get(engine, restore, "overlay"));
                try js.define(engine, value, "blockedBy", c.JS_DupValue(engine.context, next));
                try js.define(engine, value, "resume", try js.get(engine, restore, "resume"));
                try v.set(engine, screen, "overlayFocusRestore", c.JS_DupValue(engine.context, value));
            }
        } else if (v.truthy(engine, previous_overlay) and !try status(engine, restore, "inactive")) {
            const restored_overlay = try js.get(engine, restore, "overlay");
            defer engine.freeValue(restored_overlay);
            if (equal(engine, restored_overlay, previous_overlay)) {
                const is_ancestor = try js.invoke(engine, screen, "isOverlayFocusAncestor", &.{ previous_overlay, next });
                defer engine.freeValue(is_ancestor);
                if (!v.truthy(engine, is_ancestor)) try replaceBlocked(engine, screen, previous_overlay, next);
            }
        }
    } else if (c.JS_IsNull(next)) {
        const blocked = try status(engine, restore, "blocked");
        const blocked_by = if (blocked) try js.get(engine, restore, "blockedBy") else c.pi_js_undefined();
        defer engine.freeValue(blocked_by);
        if (blocked and equal(engine, blocked_by, previous)) {
            const resolved = try js.invoke(engine, screen, "resolveBlockedOverlayFocusResume", &.{restore});
            engine.freeValue(next);
            next = resolved;
        } else {
            const clear = try v.text(engine, "clear");
            defer engine.freeValue(clear);
            if (equal(engine, policy, clear)) try v.invokeVoid(engine, screen, "clearOverlayFocusRestore", &.{});
        }
    }
    const tested_focus = try js.get(engine, screen, "focusedComponent");
    defer engine.freeValue(tested_focus);
    if (try focusable(engine, bindings, tested_focus)) {
        const old_focus = try js.get(engine, screen, "focusedComponent");
        defer engine.freeValue(old_focus);
        try v.set(engine, old_focus, "focused", c.pi_js_bool(engine.context, 0));
    }
    try v.set(engine, screen, "focusedComponent", c.JS_DupValue(engine.context, next));
    if (try focusable(engine, bindings, next)) try v.set(engine, next, "focused", c.pi_js_bool(engine.context, 1));
    const overlay = if (v.truthy(engine, next)) try search(engine, screen, "find", .visibleComponent, next) else c.pi_js_undefined();
    defer engine.freeValue(overlay);
    if (v.truthy(engine, overlay)) {
        const eligible = try js.object(engine);
        defer engine.freeValue(eligible);
        try js.define(engine, eligible, "status", try v.text(engine, "eligible"));
        try js.define(engine, eligible, "overlay", c.JS_DupValue(engine.context, overlay));
        try v.set(engine, screen, "overlayFocusRestore", c.JS_DupValue(engine.context, eligible));
    }
    return c.pi_js_undefined();
}
