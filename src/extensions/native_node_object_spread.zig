//! Object spread used by actual internal/fs/utils getOptions.
//! Own keys, descriptors and getter values stay in Source order; each field's
//! temporary roots retire before the next descriptor or getter operation.
const a = @import("native_node_argument_values.zig");
const c = a.c;
fn enumerable(s: *a.Scope, source: c.JSValue, atom: c.JSAtom) !bool {
    try s.pending();
    var descriptor: c.JSPropertyDescriptor = undefined;
    const status = c.JS_GetOwnProperty(s.engine.context, &descriptor, source, atom);
    const outcome: anyerror!c.JSValue = checked: {
        s.pending() catch |err| break :checked err;
        if (status < 0) break :checked error.MissingActualNodeSpreadDescriptorReason;
        break :checked a.boolean(s, status != 0 and descriptor.flags & c.JS_PROP_ENUMERABLE != 0);
    };
    var completion = a.owned.Completion.initValue(s.engine, outcome);
    if (status > 0) {
        completion.release(descriptor.value);
        completion.release(descriptor.getter);
        completion.release(descriptor.setter);
    }
    return s.truthy(try completion.finishValue());
}
fn property(s: *a.Scope, target: c.JSValue, source: c.JSValue, atom: c.JSAtom) !c.JSValue {
    try s.pending();
    const value = try s.checked(c.JS_GetProperty(s.engine.context, source, atom));
    try s.pending();
    const status = c.JS_DefinePropertyValue(s.engine.context, target, atom, a.duplicate(s.engine, value), c.JS_PROP_C_W_E);
    try s.pending();
    if (status < 0) return error.MissingActualNodeSpreadDefinitionReason;
    return c.pi_js_undefined();
}
fn body(s: *a.Scope, source: c.JSValue) !c.JSValue {
    const target = try s.object();
    if (a.v.nullish(source)) return a.duplicate(s.engine, target);
    try s.pending();
    const boxed = try s.checked(c.JS_ToObject(s.engine.context, source));
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    try s.pending();
    const status = c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
    defer if (names != null) c.JS_FreePropertyEnum(s.engine.context, names, count);
    try s.pending();
    if (status < 0) return error.MissingActualNodeSpreadOwnKeysReason;
    for (names[0..count]) |entry| {
        if (!try enumerable(s, boxed, entry.atom)) continue;
        _ = try a.expression(s.engine, property, .{target, boxed, entry.atom});
    }
    return a.duplicate(s.engine, target);
}
pub fn copy(engine: *a.v.em.Engine, source: c.JSValue) !c.JSValue {
    return a.expression(engine, body, .{source});
}
