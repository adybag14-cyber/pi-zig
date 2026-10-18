//! Private ignore7.0.8 VM operations, exact SDK retirement dependency.
pub const em = @import("engine.zig");
pub const c = em.c;
pub const Scope = @import("native_sdk_chalk_scope.zig").Scope;
pub const owned = @import("native_sdk_owned_completion.zig");
pub const f = @import("native_node_function.zig");
pub const Body = *const fn (*Scope, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
pub fn adapt(comptime body: Body) f.Callback {
    return struct { fn invoke(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
        var s: Scope = .{ .engine = engine };
        return owned.finishValue(&s, body(&s, receiver, args, roots));
    } }.invoke;
}
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
pub fn dup(s: *Scope, value: c.JSValue) c.JSValue { return c.JS_DupValue(s.engine.context, value); }
pub fn num(s: *Scope, value: usize) c.JSValue { return c.JS_NewFloat64(s.engine.context, @floatFromInt(value)); }
pub fn at(s: *Scope, value: c.JSValue, index: usize) anyerror!c.JSValue { return s.getKey(value, num(s, index)); }
pub fn eq(s: *Scope, value: c.JSValue, text: []const u8) anyerror!bool { return s.equal(value, try s.text(text)); }
pub fn len(s: *Scope, value: c.JSValue) anyerror!c.JSValue { return s.get(value, "length"); }
pub fn string(s: *Scope, value: c.JSValue) anyerror!c.JSValue { return s.stringify(value); }
pub fn increment(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    const numeric=try s.toNumeric(value);
    const one=if(c.JS_IsBigInt(numeric)) big: {const born=s.engine.native_allocation_generation;break :big try s.own(try s.rawAllocation(c.JS_NewBigInt64(s.engine.context,1),born));} else num(s,1);
    return s.binary(.add,numeric,one);
}
pub fn literal(s: *Scope, source: []const u8, flags: []const u8) anyerror!c.JSValue { return s.construct(s.engine.intrinsic_regexp_constructor, &.{try s.text(source), try s.text(flags)}); }
pub fn testRegex(s: *Scope, regexp: c.JSValue, value: c.JSValue) anyerror!bool { return s.truthy(try s.invoke(regexp, "test", &.{value})); }
pub fn regex(s: *Scope, context: c.JSValue, name: [*:0]const u8, value: c.JSValue) anyerror!bool { return testRegex(s, try s.get(context, name), value); }
pub fn nullObject(s: *Scope) anyerror!c.JSValue { return s.invoke(try s.global("Object"), "create", &.{c.pi_js_null()}); }
pub fn define(s: *Scope, target: c.JSValue, key: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    const descriptor = try s.object(); try s.put(descriptor, "value", value);
    _ = try s.invoke(try s.global("Object"), "defineProperty", &.{target,key,descriptor}); return value;
}
pub fn namedDefine(s: *Scope, target: c.JSValue, name: []const u8, value: c.JSValue) anyerror!c.JSValue { return define(s, target, try s.text(name), value); }
pub fn method(s: *Scope, prototype: c.JSValue, comptime name: [*:0]const u8, length: c_int, comptime body: Body, roots: []const c.JSValue) anyerror!void {
    const value = try s.own(try f.createMethod(s.engine, name, length, adapt(body), roots));
    try s.define(prototype, name, value, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
}
pub fn getter(s: *Scope, prototype: c.JSValue, name: [*:0]const u8, function_name: [*:0]const u8, comptime body: Body, roots: []const c.JSValue) anyerror!void {
    const function = try s.own(try f.createMethod(s.engine, function_name, 0, adapt(body), roots));
    try s.defineGetter(prototype, name, function, c.JS_PROP_CONFIGURABLE);
}
pub fn objectFromTarget(s: *Scope, target: c.JSValue) anyerror!c.JSValue {
    const prototype = try s.get(target, "prototype"); const generation = s.engine.native_allocation_generation;
    return s.own(try s.rawAllocation(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(s.engine.context, prototype) else c.JS_NewObject(s.engine.context), generation));
}
pub fn throwType(s: *Scope, name: [*:0]const u8, message: c.JSValue) anyerror!noreturn { return s.raise(try s.construct(try s.global(name), &.{message})); }
/// Actual three-element BindingPattern iteration, including normal early
/// IteratorClose. Abrupt IteratorStepValue is terminal, as in the linked VM.
pub fn three(s: *Scope, entry: c.JSValue) anyerror![3]c.JSValue {
    const generation = s.engine.native_allocation_generation;
    const symbol = try s.own(try s.raw(c.JS_GetIteratorSymbol(s.engine.context), generation));
    const iterator = try s.call(try s.getKey(entry, symbol), entry, &.{});
    if (!c.JS_IsObject(iterator)) return throwType(s, "TypeError", try s.text("Iterator is not an object"));
    const next = try s.get(iterator, "next");
    var result = [_]c.JSValue{c.pi_js_undefined(),c.pi_js_undefined(),c.pi_js_undefined()};
    var done = false;
    for (&result) |*value| {
        if (done) continue;
        const step = try s.call(next, iterator, &.{});
        if (!c.JS_IsObject(step)) return throwType(s, "TypeError", try s.text("Iterator result is not an object"));
        done = s.truthy(try s.get(step, "done"));
        if (!done) value.* = try s.get(step, "value");
    }
    if (!done) {
        const finish = try s.get(iterator, "return");
        if (!c.JS_IsUndefined(finish) and !c.JS_IsNull(finish)) {
            const closed = try s.call(finish, iterator, &.{});
            if (!c.JS_IsObject(closed)) return throwType(s, "TypeError", try s.text("Iterator return result is not an object"));
        }
    }
    return result;
}
