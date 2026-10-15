//! A retained ordinary for-of iterator across actual native async continuations.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn retain(scope: *Scope, owner: c.JSValue, iterable: c.JSValue) !void {
    const symbol = try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context)));
    var iterator = try js.Iterator.init(scope.engine, iterable, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    try scope.put(owner, "iterator", iterator.iterator);
    try scope.put(owner, "next", iterator.next_function);
    try scope.put(owner, "iteratorClosed", c.pi_js_bool(scope.engine.context, 0));
    try scope.put(owner, "iteratorSteps", c.JS_NewInt32(scope.engine.context, 0));
}
fn restore(engine: *em.Engine, owner: c.JSValue) !js.Iterator {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var count: i64 = 0;
    if (c.JS_ToInt64(engine.context, &count, try scope.get(owner, "iteratorSteps")) < 0) return js.capture(engine);
    const iterator = try sdk.get(engine, owner, "iterator");
    errdefer engine.freeValue(iterator);
    const next_function = try sdk.get(engine, owner, "next");
    errdefer engine.freeValue(next_function);
    return .{ .engine = engine, .iterator = iterator, .next_function = next_function, .closed = scope.truthy(try scope.get(owner, "iteratorClosed")), .native_steps = @intCast(@max(count, 0)) };
}
pub fn next(scope: *Scope, owner: c.JSValue) !?c.JSValue {
    var iterator = try restore(scope.engine, owner);
    defer iterator.deinit();
    const value = iterator.next() catch |err| {
        try scope.put(owner, "iteratorClosed", c.pi_js_bool(scope.engine.context, 1));
        return err;
    };
    errdefer if (value) |item| scope.engine.freeValue(item);
    try scope.put(owner, "iteratorClosed", c.pi_js_bool(scope.engine.context, @intFromBool(iterator.closed)));
    try scope.put(owner, "iteratorSteps", c.JS_NewFloat64(scope.engine.context, @floatFromInt(@min(iterator.native_steps, std.math.maxInt(i64)))));
    return value;
}
pub fn closePreserving(engine: *em.Engine, owner: c.JSValue) void {
    const value = sdk.get(engine, owner, "iterator") catch return;
    defer engine.freeValue(value);
    if (c.JS_IsUndefined(value)) return;
    var iterator = restore(engine, owner) catch return;
    defer iterator.deinit();
    iterator.closePreserving();
    sdk.put(engine, owner, "iteratorClosed", c.pi_js_bool(engine.context, 1)) catch {};
}
