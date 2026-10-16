//! Exact per-model policy resolution from upstream 0fbdbd3 compactionPolicy.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;

pub fn resolve(engine: *em.Engine, settings: c.JSValue, model: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const source = try scope.get(settings, "compaction");
    const overrides = try scope.get(source, "modelOverrides");
    // Object rest reads enumerable own fields, including symbols, exactly once
    // after the explicit modelOverrides getter and before selecting its entry.
    const policy = try scope.object();
    const excluded = c.JS_NewAtom(engine.context, "modelOverrides");
    if (excluded == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, excluded);
    const boxed = try scope.own(try engine.checked(c.JS_ToObject(engine.context, source)));
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        if (entry.atom == excluded) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return js.capture(engine);
        if (present == 0) continue;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, boxed, entry.atom));
        if (c.JS_DefinePropertyValue(engine.context, policy, entry.atom, value, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    var selected = c.pi_js_undefined();
    if (!c.JS_IsNull(overrides) and !c.JS_IsUndefined(overrides)) {
        // Template substitutions coerce provider before reading modelId.
        const provider = try scope.stringify(try scope.get(model, "provider"));
        const model_id = try scope.stringify(try scope.get(model, "modelId"));
        const key = try scope.own(try @import("native_utf16.zig").concat(engine, &.{ provider, try scope.text("/"), model_id }));
        selected = try scope.own(try js.getKey(engine, overrides, key));
    }
    const result = try scope.object();
    inline for (.{ "enabled", "reserveTokens", "keepRecentTokens", "backgroundTokens" }) |key| {
        const field = if (c.JS_IsUndefined(selected) or c.JS_IsNull(selected)) c.pi_js_undefined() else try scope.get(selected, key);
        try scope.put(result, key, if (c.JS_IsUndefined(field) or c.JS_IsNull(field)) try scope.get(policy, key) else field);
    }
    return c.JS_DupValue(engine.context, result);
}
