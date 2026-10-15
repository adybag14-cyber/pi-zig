//! Source5ab retryProviderRequest, retaining real Error/Headers brands and abort identity.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub fn create(engine: *v.em.Engine) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var scope: Scope = .{ .engine = host };
            defer scope.deinit();
            const pending = try flow.create(host, c.pi_js_undefined());
            defer host.freeValue(pending.owner);
            errdefer host.freeValue(pending.promise);
            try scope.put(pending.owner, "request", if (args.len > 0) args[0] else c.pi_js_undefined());
            const options = if (args.len > 1 and !c.JS_IsUndefined(args[1])) args[1] else try scope.object();
            try scope.put(pending.owner, "options", options);
            const max = try scope.get(options, "maxRetries");
            const maximum = if (v.nullish(max)) c.JS_NewInt32(host.context, 0) else max;
            try scope.put(pending.owner, "maximum", maximum);
            try scope.put(pending.owner, "remaining", maximum);
            request(&scope, pending.owner) catch |err| try failed(&scope, pending.owner, flow.reason(host, err), true);
            return pending.promise;
        }
    };
    const result = try @import("native_node_function.zig").create(engine, "retryProviderRequest", 1, Adapter.call, &.{});
    errdefer engine.freeValue(result);
    const prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(prototype);
    if (c.JS_SetPrototype(engine.context, result, prototype) < 0) return v.js.capture(engine);
    return result;
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
fn request(scope: *Scope, owner: c.JSValue) !void {
    const value = scope.call(try scope.get(owner, "request"), c.pi_js_undefined(), &.{}) catch |err| {
        const reason = flow.reason(scope.engine, err);
        defer scope.engine.freeValue(reason);
        return failed(scope, owner, reason, false);
    };
    try flow.wait(continued, scope.engine, owner, value, 0);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        if (stage == 0) failed(&scope, owner, value, false) catch |err| try flow.rejectError(engine, owner, err) else try flow.settle(engine, owner, true, value);
    } else if (stage == 0) try flow.settle(engine, owner, false, value) else request(&scope, owner) catch |err| try flow.rejectError(engine, owner, err);
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
fn delay(scope: *Scope, failure: c.JSValue, index: c.JSValue, max: c.JSValue) !c.JSValue {
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
fn failed(scope: *Scope, owner: c.JSValue, failure: c.JSValue, owned: bool) !void {
    defer if (owned) scope.engine.freeValue(failure);
    const abort_signal = try signal(scope, owner);
    if (scope.truthy(try v.optional(scope, abort_signal, "aborted"))) return flow.settle(scope.engine, owner, true, try abort(scope));
    const remaining = try scope.get(owner, "remaining");
    if (try arithmetic.compare(scope.engine, .less_equal, remaining, c.JS_NewInt32(scope.engine.context, 0)) or !try providerError(scope, failure) or !try retryable(scope, failure)) return flow.settle(scope.engine, owner, true, failure);
    const options = try scope.get(owner, "options");
    if (!c.JS_IsUndefined(try scope.get(failure, "status"))) {
        const statuses = try scope.get(options, "noRetryStatuses");
        if (!v.nullish(statuses) and scope.truthy(try scope.invoke(statuses, "includes", &.{try scope.get(failure, "status")}))) return flow.settle(scope.engine, owner, true, failure);
    }
    const index = try binary(scope, .subtract, try scope.get(owner, "maximum"), remaining);
    try scope.set(owner, "remaining", try binary(scope, .subtract, remaining, c.JS_NewInt32(scope.engine.context, 1)));
    try flow.wait(continued, scope.engine, owner, try sleep(scope, try delay(scope, failure, index, try scope.get(options, "maxRetryDelayMs")), abort_signal), 1);
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
    const callback = try scope.own(try @import("native_node_function.zig").create(scope.engine, "onAbort", 0, Adapter.onAbort, &.{pending.owner}));
    try scope.put(pending.owner, "onAbort", callback);
    const timer = try scope.own(try @import("native_node_function.zig").create(scope.engine, "", 0, Adapter.timeout, &.{pending.owner}));
    const scheduled = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ timer, try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 0), duration }) });
    try scope.put(pending.owner, "timeout", scheduled);
    if (!v.nullish(abort_signal)) {
        const once = try scope.object();
        try scope.put(once, "once", c.pi_js_bool(scope.engine.context, 1));
        _ = try scope.invoke(abort_signal, "addEventListener", &.{ try scope.text("abort"), callback, once });
    }
    return pending.promise;
}
