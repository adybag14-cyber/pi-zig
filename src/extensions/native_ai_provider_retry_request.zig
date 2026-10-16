//! Source5ab retryProviderRequest, retaining real Error/Headers brands and abort identity.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const asynchronous = @import("native_async_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub fn create(engine: *v.em.Engine) !c.JSValue {
    return asynchronous.createResumable(engine, "retryProviderRequest", 1, retryBody, &.{});
}
fn retryBody(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, slot: *c.JSValue, completion: asynchronous.Completion, value: c.JSValue) !asynchronous.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const owner = try scope.object();
        asynchronous.replaceState(engine, slot, c.JS_DupValue(engine.context, owner));
        try scope.put(owner, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
        try scope.put(owner, "request", if (args.len > 0) args[0] else c.pi_js_undefined());
        const options = if (args.len > 1 and !c.JS_IsUndefined(args[1])) args[1] else try scope.object();
        try scope.put(owner, "options", options);
        const max = try scope.get(options, "maxRetries");
        const maximum = if (v.nullish(max)) c.JS_NewInt32(engine.context, 0) else max;
        try scope.put(owner, "maximum", maximum);
        try scope.put(owner, "remaining", maximum);
        return request(&scope, owner);
    }
    const owner = slot.*;
    if (completion == .rejected) {
        var generation: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &generation, try scope.get(owner, "generation")) < 0) return v.js.capture(engine);
        try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, value, generation);
    }
    if (scope.truthy(try scope.get(owner, "sleeping"))) {
        if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, value) };
        try scope.put(owner, "sleeping", c.JS_NewBool(engine.context, false));
        return request(&scope, owner);
    }
    if (completion == .rejected) return failed(&scope, owner, value);
    return .{ .returned = c.JS_DupValue(engine.context, value) };
}
fn binary(scope: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, operation, left, right));
}
fn abort(scope: *Scope) !c.JSValue {
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("Request aborted")}));
    try scope.set(result, "name", try scope.text("AbortError"));
    return result;
}
fn signal(scope: *Scope, owner: c.JSValue) !c.JSValue {
    return scope.get(try scope.get(owner, "options"), "signal");
}
fn request(scope: *Scope, owner: c.JSValue) !asynchronous.Action {
    const generation = scope.engine.native_allocation_generation;
    const value = scope.call(try scope.get(owner, "request"), c.pi_js_undefined(), &.{}) catch |err| {
        if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        const reason = try scope.own(flow.reason(scope.engine, err));
        if (scope.engine.captured_exception) |captured| {
            scope.engine.captured_exception = null;
            scope.engine.freeValue(captured);
        }
        return failed(scope, owner, reason);
    };
    return .{ .awaited = c.JS_DupValue(scope.engine.context, value) };
}
fn property(scope: *Scope, value: c.JSValue, name: [*:0]const u8) !bool {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(scope.engine);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    const result = c.JS_HasProperty(scope.engine.context, value, atom);
    if (result < 0) return v.js.capture(scope.engine);
    return result == 1;
}
fn providerError(scope: *Scope, value: c.JSValue) !bool {
    const instance = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    if (instance != 1 or !try property(scope, value, "status") or !try property(scope, value, "headers")) return false;
    if (!c.JS_IsUndefined(try scope.get(value, "status")) and !c.JS_IsNumber(try scope.get(value, "status"))) return false;
    if (c.JS_IsUndefined(try scope.get(value, "headers"))) return true;
    const branded = c.JS_IsInstanceOf(scope.engine.context, try scope.get(value, "headers"), try scope.global("Headers"));
    if (branded < 0) return v.js.capture(scope.engine);
    return branded == 1;
}
fn header(scope: *Scope, failure: c.JSValue, key: []const u8) !c.JSValue {
    const headers = try scope.get(failure, "headers");
    return if (v.nullish(headers)) c.pi_js_undefined() else scope.invoke(headers, "get", &.{try scope.text(key)});
}
fn retryable(scope: *Scope, failure: c.JSValue) !bool {
    const hint = try header(scope, failure, "x-should-retry");
    if (try v.eq(scope, hint, "true")) return true;
    if (try v.eq(scope, hint, "false")) return false;
    if (c.JS_IsUndefined(try scope.get(failure, "status"))) return true;
    inline for (.{ 408, 409, 429 }) |status| if (scope.equal(try scope.get(failure, "status"), c.JS_NewInt32(scope.engine.context, status))) return true;
    return c.JS_IsNumber(try scope.get(failure, "status")) and try arithmetic.compare(scope.engine, .greater_equal, try scope.get(failure, "status"), c.JS_NewInt32(scope.engine.context, 500));
}
fn validate(scope: *Scope, delay: c.JSValue, max: c.JSValue, message: c.JSValue) !c.JSValue {
    const limit = if (v.nullish(max)) c.JS_NewInt32(scope.engine.context, 60000) else max;
    if (try arithmetic.compare(scope.engine, .greater, limit, c.JS_NewInt32(scope.engine.context, 0)) and try arithmetic.compare(scope.engine, .greater, delay, limit)) {
        var text = try scope.concat(try scope.text("Server requested "), try scope.stringify(try scope.invoke(try scope.global("Math"), "ceil", &.{try binary(scope, .divide, delay, c.JS_NewInt32(scope.engine.context, 1000))})));
        text = try scope.concat(text, try scope.text("s retry delay (max: "));
        text = try scope.concat(text, try scope.stringify(try scope.invoke(try scope.global("Math"), "ceil", &.{try binary(scope, .divide, limit, c.JS_NewInt32(scope.engine.context, 1000))})));
        return v.errorText(scope, try scope.concat(try scope.concat(text, try scope.text("s). ")), try scope.stringify(message)));
    }
    return delay;
}
fn retryDelay(scope: *Scope, failure: c.JSValue, index: c.JSValue, max: c.JSValue) !c.JSValue {
    const milliseconds = try header(scope, failure, "retry-after-ms");
    if (scope.truthy(milliseconds)) {
        const value = try scope.invoke(try scope.global("Number"), "parseFloat", &.{milliseconds});
        if (scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{value}))) return validate(scope, value, max, try scope.get(failure, "message"));
    }
    const after = try header(scope, failure, "retry-after");
    if (scope.truthy(after)) {
        const seconds = try scope.invoke(try scope.global("Number"), "parseFloat", &.{after});
        const value = if (scope.truthy(try scope.invoke(try scope.global("Number"), "isNaN", &.{seconds}))) try binary(scope, .subtract, try scope.invoke(try scope.global("Date"), "parse", &.{after}), try scope.invoke(try scope.global("Date"), "now", &.{})) else try binary(scope, .multiply, seconds, c.JS_NewInt32(scope.engine.context, 1000));
        if (scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{value}))) return validate(scope, value, max, try scope.get(failure, "message"));
    }
    const exponential = try binary(scope, .multiply, try scope.invoke(try scope.global("Math"), "min", &.{ try binary(scope, .multiply, c.JS_NewFloat64(scope.engine.context, 0.5), try binary(scope, .power, c.JS_NewInt32(scope.engine.context, 2), index)), c.JS_NewInt32(scope.engine.context, 8) }), c.JS_NewInt32(scope.engine.context, 1000));
    return binary(scope, .multiply, exponential, try binary(scope, .subtract, c.JS_NewInt32(scope.engine.context, 1), try binary(scope, .multiply, try scope.invoke(try scope.global("Math"), "random", &.{}), c.JS_NewFloat64(scope.engine.context, 0.25))));
}
fn failed(scope: *Scope, owner: c.JSValue, failure: c.JSValue) !asynchronous.Action {
    const abort_signal = try signal(scope, owner);
    if (scope.truthy(try v.optional(scope, abort_signal, "aborted"))) return .{ .thrown = c.JS_DupValue(scope.engine.context, try abort(scope)) };
    const remaining = try scope.get(owner, "remaining");
    if (try arithmetic.compare(scope.engine, .less_equal, remaining, c.JS_NewInt32(scope.engine.context, 0)) or !try providerError(scope, failure) or !try retryable(scope, failure)) return .{ .thrown = c.JS_DupValue(scope.engine.context, failure) };
    const options = try scope.get(owner, "options");
    if (!c.JS_IsUndefined(try scope.get(failure, "status"))) {
        const statuses = try scope.get(options, "noRetryStatuses");
        if (!v.nullish(statuses) and scope.truthy(try scope.invoke(statuses, "includes", &.{try scope.get(failure, "status")}))) return .{ .thrown = c.JS_DupValue(scope.engine.context, failure) };
    }
    const index = try binary(scope, .subtract, try scope.get(owner, "maximum"), remaining);
    try scope.set(owner, "remaining", try binary(scope, .subtract, remaining, c.JS_NewInt32(scope.engine.context, 1)));
    const pending = try scope.own(try sleep(scope, try retryDelay(scope, failure, index, try scope.get(options, "maxRetryDelayMs")), abort_signal));
    try scope.put(owner, "sleeping", c.JS_NewBool(scope.engine.context, true));
    return .{ .awaited = c.JS_DupValue(scope.engine.context, pending) };
}
fn sleep(scope: *Scope, duration: c.JSValue, abort_signal: c.JSValue) !c.JSValue {
    const pending = try flow.create(scope.engine, abort_signal);
    defer scope.engine.freeValue(pending.owner);
    errdefer scope.engine.freeValue(pending.promise);
    if (scope.truthy(try v.optional(scope, abort_signal, "aborted"))) {
        try flow.settle(scope.engine, pending.owner, true, try abort(scope));
        return pending.promise;
    }
    const Adapter = struct {
        fn timeout(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const signal_value = try row.get(roots[0], "agent");
            if (!v.nullish(signal_value)) _ = try row.invoke(signal_value, "removeEventListener", &.{ try row.text("abort"), try row.get(roots[0], "onAbort") });
            try flow.settle(host, roots[0], false, c.pi_js_undefined());
            return c.pi_js_undefined();
        }
        fn onAbort(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            _ = try row.call(try row.global("clearTimeout"), c.pi_js_undefined(), &.{try row.get(roots[0], "timeout")});
            try flow.settle(host, roots[0], true, try abort(&row));
            return c.pi_js_undefined();
        }
    };
    const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "onAbort", 0, Adapter.onAbort, &.{pending.owner}));
    try scope.put(pending.owner, "onAbort", callback);
    const timer = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 0, Adapter.timeout, &.{pending.owner}));
    const scheduled = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ timer, try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 0), duration }) });
    try scope.put(pending.owner, "timeout", scheduled);
    if (!v.nullish(abort_signal)) {
        const once = try scope.object();
        try scope.put(once, "once", c.pi_js_bool(scope.engine.context, 1));
        _ = try scope.invoke(abort_signal, "addEventListener", &.{ try scope.text("abort"), callback, once });
    }
    return pending.promise;
}
