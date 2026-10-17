//! Exact ordinary SerialOperationQueue methods; guest Promise jobs own order.
const em = @import("engine.zig");
const v = @import("native_chord_sqlite_node_values.zig");
const c = v.c;
const functions = @import("native_node_function.zig");
pub fn prototype(engine: *em.Engine, ignore: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    const result = try s.object();
    inline for (.{ "run", "runAsync", "enqueue", "release" }) |name| {
        const Adapter = struct { fn call(host: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return method(host, name, receiver, v.at(args, 0), roots[0]); } };
        const method_value = try s.own(try functions.createMethod(engine, name, 1, v.callback(Adapter.call), &.{ignore}));
        if (c.JS_DefinePropertyValueStr(engine.context, result, name, c.JS_DupValue(engine.context, method_value), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return @import("native_js_values.zig").capture(engine);
    }
    return c.JS_DupValue(engine.context, result);
}
pub fn create(s: *v.Scope, result: c.JSValue) !c.JSValue {
    try s.put(result, "tail", try v.invoke(s, try v.global(s, "Promise"), "resolve", &.{}));
    try s.put(result, "pending", c.JS_NewInt32(s.engine.context, 0));
    return result;
}
fn adjust(s: *v.Scope, queue: c.JSValue, comptime increment: bool) !void {
    const old = try v.get(s, queue, "pending"); const generation = s.engine.native_allocation_generation;
    const next = try s.own(try v.guard(s.engine, generation, v.checked(s.engine, if (increment) c.JS_PiIncrement(s.engine.context, old) else c.JS_PiDecrement(s.engine.context, old))));
    try v.set(s, queue, "pending", next);
}
fn method(engine: *em.Engine, comptime name: []const u8, queue: c.JSValue, operation: c.JSValue, ignore: c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err);
    if (comptime @import("std").mem.eql(u8, name, "run") or @import("std").mem.eql(u8, name, "runAsync")) {
        if (try s.positive(try v.get(&s, queue, "pending"))) return c.JS_DupValue(engine.context, try v.invoke(&s, queue, "enqueue", &.{operation}));
        if (comptime @import("std").mem.eql(u8, name, "run")) {
            const returned = synchronous(&s, operation) catch |err| {
                const reason = try s.own(try v.caught(engine, err));
                return c.JS_DupValue(engine.context, try v.invoke(&s, try v.global(&s, "Promise"), "reject", &.{reason}));
            };
            return c.JS_DupValue(engine.context, returned);
        } else {
            try adjust(&s, queue, true);
            const pair = try v.invoke(&s, try v.global(&s, "Promise"), "withResolvers", &.{});
            const barrier = try v.get(&s, pair, "promise"); const release = try v.get(&s, pair, "resolve");
            try v.set(&s, queue, "tail", barrier);
            const started = v.call(&s, operation, c.pi_js_undefined(), &.{}) catch |err| blk: {
                const reason = try s.own(try v.caught(engine, err));
                break :blk try v.invoke(&s, try v.global(&s, "Promise"), "reject", &.{reason});
            };
            const finally = try v.get(&s, started, "finally");
            const callback = try s.own(try functions.createArrow(engine, "", 0, v.callback(releaseBarrier), &.{ queue, release }));
            return c.JS_DupValue(engine.context, try v.call(&s, finally, started, &.{callback}));
        }
    } else if (comptime @import("std").mem.eql(u8, name, "enqueue")) {
        try adjust(&s, queue, true);
        const release = try v.get(&s, queue, "release");
        const pending = try v.invoke(&s, try v.get(&s, queue, "tail"), "then", &.{operation});
        return c.JS_DupValue(engine.context, try v.call(&s, release, queue, &.{pending}));
    } else {
        const finally = try v.get(&s, operation, "finally");
        const callback = try s.own(try functions.createArrow(engine, "", 0, v.callback(decrement), &.{queue}));
        const settled = try v.call(&s, finally, operation, &.{callback});
        try v.set(&s, queue, "tail", try v.invoke(&s, settled, "then", &.{ ignore, ignore }));
        return c.JS_DupValue(engine.context, settled);
    }
}
fn synchronous(s: *v.Scope, operation: c.JSValue) !c.JSValue {
    // Promise.resolve is selected before evaluating operation(), as in Source.
    const promise = try v.global(s, "Promise"); const resolve = try v.get(s, promise, "resolve");
    return v.call(s, resolve, promise, &.{try v.call(s, operation, c.pi_js_undefined(), &.{})});
}
fn decrement(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); try adjust(&s, roots[0], false); return c.pi_js_undefined(); }
fn releaseBarrier(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { var s: v.Scope = .{ .engine = engine }; defer s.deinit(); errdefer |err| s.captureUnwind(err); try adjust(&s, roots[0], false); _ = try v.call(&s, roots[1], c.pi_js_undefined(), &.{}); return c.pi_js_undefined(); }
