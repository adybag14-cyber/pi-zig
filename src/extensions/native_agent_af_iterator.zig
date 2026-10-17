//! Sync for-of record retained over native AF Awaits; step and body phases.
const p = @import("native_agent_af_values.zig");
const c = p.c;
const js = @import("native_js_values.zig");
pub fn init(s: *p.Scope, owner: c.JSValue, iterable: c.JSValue) !void {
    try s.put(owner, "iteratorBody", c.pi_js_bool(s.engine.context, 0));
    const symbol = try s.own(try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)));
    const generation = s.engine.native_allocation_generation;
    const method = try s.own(try p.guard(s.engine, generation, js.getKey(s.engine, iterable, symbol)));
    const iterator = try p.call(s, method, iterable, &.{});
    if (!c.JS_IsObject(iterator)) return js.typeError(s.engine, "Iterator is not an object");
    try s.put(owner, "iterator", iterator);
    try s.put(owner, "iteratorNext", try p.get(s, iterator, "next"));
    try s.put(owner, "iteratorSteps", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, 0))));
}
pub fn next(s: *p.Scope, owner: c.JSValue) !?c.JSValue {
    try s.put(owner, "iteratorBody", c.pi_js_bool(s.engine.context, 0));
    var steps: u64 = 0;
    if (c.JS_ToBigUint64(s.engine.context, &steps, try s.get(owner, "iteratorSteps")) < 0) return js.capture(s.engine);
    steps +|= 1;
    if (s.engine.cancelled.load(.acquire) or (steps % 256 == 0 and blk: { s.engine.interrupts +|= 1; break :blk s.engine.interrupts > s.engine.options.interrupt_budget; })) {
        _ = c.JS_ThrowInternalError(s.engine.context, "interrupted");
        const reason = c.JS_GetException(s.engine.context);
        c.JS_SetUncatchableError(s.engine.context, reason);
        _ = try s.engine.checked(c.JS_Throw(s.engine.context, reason)); unreachable;
    }
    try s.put(owner, "iteratorSteps", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, steps))));
    const result = try p.call(s, try s.get(owner, "iteratorNext"), try s.get(owner, "iterator"), &.{});
    if (!c.JS_IsObject(result)) return js.typeError(s.engine, "Iterator result is not an object");
    if (s.truthy(try p.get(s, result, "done"))) return null;
    const value = try p.get(s, result, "value");
    try s.put(owner, "iteratorBody", c.pi_js_bool(s.engine.context, 1));
    try s.put(owner, "iteratorValue", value);
    return value;
}
pub fn close(s: *p.Scope, owner: c.JSValue) !void {
    return closeResult(s, owner, true);
}
fn closeResult(s: *p.Scope, owner: c.JSValue, check_result: bool) !void {
    try s.put(owner, "iteratorBody", c.pi_js_bool(s.engine.context, 0));
    const iterator = try s.get(owner, "iterator");
    const method = try p.get(s, iterator, "return");
    if (c.JS_IsNull(method) or c.JS_IsUndefined(method)) return;
    const result = try p.call(s, method, iterator, &.{});
    if (check_result and !c.JS_IsObject(result)) return js.typeError(s.engine, "Iterator return result is not an object");
}
pub fn throwCompletion(s: *p.Scope, owner: c.JSValue, reason: c.JSValue) !p.af.Action {
    if (s.truthy(try s.get(owner, "iteratorBody"))) closeResult(s, owner, false) catch |err| { const discarded = try p.caught(s.engine, err); s.engine.freeValue(discarded); };
    return .{ .thrown = c.JS_DupValue(s.engine.context, reason) };
}
