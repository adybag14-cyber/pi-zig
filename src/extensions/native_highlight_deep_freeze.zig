//! Actual Source highlight.js10.7.3 deepFreeze helper and common-mode pass.
//! Source-only; cyclic-user-graph behavior follows Source, native interrupts bound work.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const legacy = @import("native_legacy_function.zig");
const c = em.c;
fn sourceError(engine: *em.Engine, message: []const u8) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var args = [_]c.JSValue{try s.text(message)};
    const reason = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, try s.global("Error"), args.len, &args)));
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    return js.capture(engine);
}
fn readonly(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    return sourceError(engine, if (c.JS_ToBool(engine.context, roots[0]) == 1) "map is read-only" else "set is read-only");
}
fn child(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const prop = try s.own(try js.getKey(engine, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined()));
    if ((c.JS_IsObject(prop) and !c.JS_IsFunction(engine.context, prop)) or c.JS_IsNull(prop)) {
        if (!s.truthy(try s.invoke(try s.global("Object"), "isFrozen", &.{prop}))) {
            const result = try freeze(engine, prop);
            engine.freeValue(result);
        }
    }
    return c.pi_js_undefined();
}
pub fn freeze(engine: *em.Engine, obj: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    engine.interrupts +|= 1;
    if (engine.cancelled.load(.acquire) or engine.interrupts > engine.options.interrupt_budget) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
    const map = c.JS_IsInstanceOf(engine.context, obj, try s.global("Map"));
    if (map < 0) return js.capture(engine);
    if (map == 1) {
        const fn_value = try s.own(try legacy.create(engine, "", 0, readonly, &.{c.pi_js_bool(engine.context, 1)}));
        try s.set(obj, "set", fn_value);
        try s.set(obj, "delete", fn_value);
        try s.set(obj, "clear", fn_value);
    } else {
        const set = c.JS_IsInstanceOf(engine.context, obj, try s.global("Set"));
        if (set < 0) return js.capture(engine);
        if (set == 1) {
            const fn_value = try s.own(try legacy.create(engine, "", 0, readonly, &.{c.pi_js_bool(engine.context, 0)}));
            try s.set(obj, "delete", fn_value);
            try s.set(obj, "clear", fn_value);
            try s.set(obj, "add", fn_value);
        }
    }
    _ = try s.invoke(try s.global("Object"), "freeze", &.{obj});
    const names = try s.invoke(try s.global("Object"), "getOwnPropertyNames", &.{obj});
    const callback = try s.own(try legacy.create(engine, "", 1, child, &.{obj}));
    _ = try s.invoke(names, "forEach", &.{callback});
    return c.JS_DupValue(engine.context, obj);
}
pub fn freezeModeValues(engine: *em.Engine, modes: c.JSValue) !void {
    var iterator = try @import("native_source_for_in.zig").Iterator.init(engine, modes);
    defer iterator.deinit();
    while (try iterator.next()) |name| {
        defer engine.freeValue(name);
        const value = try js.getKey(engine, modes, name);
        defer engine.freeValue(value);
        if ((c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value)) or c.JS_IsNull(value)) {
            const frozen = try freeze(engine, value);
            engine.freeValue(frozen);
        }
    }
}
