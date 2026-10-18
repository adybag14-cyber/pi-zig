//! Public child completion frontier over the SAME reviewed local owner used by
//! canonical Socket. No Engine/shared Scope rewrite or historical flag guard.
const js = @import("native_js_values.zig");
pub const c = js.c;
const local = @import("native_node_socket_scope.zig");
pub const Scope = local.Scope;
pub fn pending(engine: *js.Engine) !void { return engine.checkNativeEntry(); }
pub fn failure(engine: *js.Engine, err: anyerror) anyerror { pending(engine) catch |actual| return actual; return err; }
pub fn owned(engine: *js.Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    return c.JS_DupValue(engine.context, try scope.own(value));
}
/// Object spread keeps its actual VM key/get/descriptor order. A descriptor's
/// THREE returned owners are adopted together BEFORE a pending check or free.
pub fn spreadInto(scope: *Scope, target: c.JSValue, source: c.JSValue) !void {
    if (c.JS_IsNull(source) or c.JS_IsUndefined(source)) return;
    const engine = scope.engine;
    try pending(engine);
    const generation = engine.native_allocation_generation;
    const boxed = try scope.ownSince(c.JS_ToObject(engine.context, source), generation);
    var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    const status = c.JS_GetOwnPropertyNames(engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
    if (status < 0) return @as(anyerror!void, js.capture(engine));
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    try pending(engine);
    for (names[0..count]) |entry| {
        var row: Scope = .{ .engine = engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return @as(anyerror!void, js.capture(engine));
        if (present == 0) { try pending(engine); continue; }
        row.inline_values[0] = descriptor.value; row.inline_values[1] = descriptor.getter; row.inline_values[2] = descriptor.setter; row.inline_count = 3;
        try pending(engine);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const before_get = engine.native_allocation_generation;
        const value = try row.ownSince(c.JS_GetProperty(engine.context, boxed, entry.atom), before_get);
        const defined = c.JS_DefinePropertyValue(engine.context, target, entry.atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E);
        try pending(engine); if (defined < 0) return @as(anyerror!void, js.capture(engine));
    }
}
pub fn getKey(scope: *Scope, object: c.JSValue, key: c.JSValue) !c.JSValue {
    try pending(scope.engine);
    const atom = c.JS_ValueToAtom(scope.engine.context, key);
    if (atom == c.JS_ATOM_NULL) return @as(anyerror!c.JSValue, js.capture(scope.engine));
    defer c.JS_FreeAtom(scope.engine.context, atom);
    try pending(scope.engine);
    const generation = scope.engine.native_allocation_generation;
    return scope.ownSince(c.JS_GetProperty(scope.engine.context, object, atom), generation);
}
pub fn binary(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    try pending(scope.engine); const generation = scope.engine.native_allocation_generation;
    return scope.ownSince(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right), generation);
}
pub fn increment(scope: *Scope, value: c.JSValue) !c.JSValue {
    try pending(scope.engine); const generation = scope.engine.native_allocation_generation;
    return scope.ownSince(c.JS_PiIncrement(scope.engine.context, value), generation);
}
pub fn prototype(scope: *Scope, value: c.JSValue) !c.JSValue {
    try pending(scope.engine); const generation = scope.engine.native_allocation_generation;
    return scope.ownSince(c.JS_GetPrototype(scope.engine.context, value), generation);
}
pub fn toObject(scope: *Scope, value: c.JSValue) !c.JSValue {
    try pending(scope.engine); const generation = scope.engine.native_allocation_generation;
    return scope.ownSince(c.JS_ToObject(scope.engine.context, value), generation);
}