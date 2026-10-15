//! Actual 4954 management fetchWithRetry: live global fetch, immediate retries,
//! per-attempt/overall/caller signals and original awaited cancellation policy.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const Stage = enum(c_int) { fetched, cancelled };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const statuses = try scope.array();
    inline for (.{ 408, 425, 429, 500, 502, 503, 504 }, 0..) |status, index| try scope.index(statuses, @intCast(index), c.JS_NewInt32(engine.context, status));
    const retry_statuses = try scope.own(try v.js.builtin(engine, "Set", &.{statuses}));
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const pending = try flow.create(host, roots[0]);
            defer host.freeValue(pending.owner);
            errdefer host.freeValue(pending.promise);
            try row.put(pending.owner, "generation", try row.own(try host.checked(c.JS_NewBigUint64(host.context, host.native_allocation_generation))));
            try row.put(pending.owner, "input", if (args.len > 0) args[0] else c.pi_js_undefined());
            try row.put(pending.owner, "init", if (args.len > 1) args[1] else c.pi_js_undefined());
            try row.put(pending.owner, "options", if (args.len < 3 or c.JS_IsUndefined(args[2])) try row.object() else args[2]);
            setup(&row, pending.owner) catch |err| try rejectError(&row, pending.owner, err);
            return pending.promise;
        }
    };
    // The original is an async function declaration, not a constructible function.
    const function = try scope.own(try @import("native_node_function.zig").createMethod(engine, "fetchWithRetry", 1, Adapter.call, &.{retry_statuses}));
    const prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return v.js.capture(engine);
    const result = try scope.object();
    try scope.put(result, "fetchWithRetry", function);
    try scope.put(result, "getPiUserAgent", try scope.own(try @import("native_pi_user_agent.zig").create(engine)));
    return c.JS_DupValue(engine.context, result);
}
fn ownedAllocation(scope: *Scope, owner: c.JSValue, exception: c.JSValue) !bool {
    const tag = c.pi_js_native_allocation_error_generation(exception);
    if (tag == 0) return false;
    var initial: u64 = 0;
    if (c.JS_ToBigUint64(scope.engine.context, &initial, try scope.get(owner, "generation")) < 0) return v.js.capture(scope.engine);
    const distance = tag -% initial;
    return distance != 0 and distance <= scope.engine.native_allocation_generation -% initial;
}
fn reason(scope: *Scope, err: anyerror) !c.JSValue {
    const captured = try scope.own(flow.reason(scope.engine, err));
    if (scope.engine.captured_exception) |old| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(old);
    }
    return captured;
}
fn rejectError(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    try flow.settle(scope.engine, owner, true, try reason(scope, err));
}
fn setup(scope: *Scope, owner: c.JSValue) !void {
    const options = try scope.get(owner, "options");
    var maximum = c.JS_NewInt32(scope.engine.context, 2);
    if (!c.JS_IsUndefined(try scope.get(options, "maxRetries"))) {
        const number = try scope.global("Number");
        const finite = try scope.get(number, "isFinite");
        if (scope.truthy(try scope.call(finite, number, &.{try scope.get(options, "maxRetries")}))) {
            const max_math = try scope.global("Math");
            const max_function = try scope.get(max_math, "max");
            const floor_math = try scope.global("Math");
            const floor_function = try scope.get(floor_math, "floor");
            const floored = try scope.call(floor_function, floor_math, &.{try scope.get(options, "maxRetries")});
            maximum = try scope.call(max_function, max_math, &.{ c.JS_NewInt32(scope.engine.context, 0), floored });
        }
    }
    try scope.put(owner, "maximum", maximum);
    const retry_on_status = try scope.get(options, "retryOnStatus");
    try scope.put(owner, "retryOnStatus", if (v.nullish(retry_on_status)) c.pi_js_bool(scope.engine.context, 1) else retry_on_status);
    const parent = try v.optional(scope, try scope.get(owner, "init"), "signal");
    try scope.put(owner, "parent", if (v.nullish(parent)) c.pi_js_undefined() else parent);
    var overall = c.pi_js_undefined();
    if (!c.JS_IsUndefined(try scope.get(options, "timeoutMs")) and try arithmetic.compare(scope.engine, .greater, try scope.get(options, "timeoutMs"), c.JS_NewInt32(scope.engine.context, 0))) {
        const abort_signal = try scope.global("AbortSignal");
        const timeout = try scope.get(abort_signal, "timeout");
        overall = try scope.call(timeout, abort_signal, &.{try scope.get(options, "timeoutMs")});
    }
    try scope.put(owner, "overall", overall);
    var attempt_timeout = c.pi_js_undefined();
    if (!c.JS_IsUndefined(try scope.get(options, "attemptTimeoutMs")) and try arithmetic.compare(scope.engine, .greater, try scope.get(options, "attemptTimeoutMs"), c.JS_NewInt32(scope.engine.context, 0))) attempt_timeout = try scope.get(options, "attemptTimeoutMs");
    try scope.put(owner, "attemptTimeoutMs", attempt_timeout);
    try scope.put(owner, "attempt", c.JS_NewInt32(scope.engine.context, 0));
    try attempt(scope.engine, owner);
}
fn increment(scope: *Scope, owner: c.JSValue) !void {
    try scope.put(owner, "attempt", try scope.own(try arithmetic.binary(scope.engine, .add, try scope.get(owner, "attempt"), c.JS_NewInt32(scope.engine.context, 1))));
}
fn attempt(engine: *v.em.Engine, owner: c.JSValue) !void {
    // Synchronous fetch failures can retry without an await. Use an actual loop
    // rather than recurse and grow the native stack for a large retry budget.
    while (true) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const parent = try scope.get(owner, "parent");
        const overall = try scope.get(owner, "overall");
        if (!v.nullish(parent)) _ = try scope.invoke(parent, "throwIfAborted", &.{});
        if (!v.nullish(overall)) _ = try scope.invoke(overall, "throwIfAborted", &.{});
        const duration = try scope.get(owner, "attemptTimeoutMs");
        var attempt_signal = c.pi_js_undefined();
        if (scope.truthy(duration)) attempt_signal = try scope.invoke(try scope.global("AbortSignal"), "timeout", &.{duration});
        try scope.put(owner, "attemptSignal", attempt_signal);
        const signals = try scope.array();
        try scope.index(signals, 0, parent);
        try scope.index(signals, 1, overall);
        try scope.index(signals, 2, attempt_signal);
        const filter_method = try scope.get(signals, "filter");
        const Filter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                return c.pi_js_bool(host.context, @intFromBool(args.len > 0 and !c.JS_IsUndefined(args[0])));
            }
        };
        const filter = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, Filter.call, &.{}));
        const selected = try scope.call(filter_method, signals, &.{filter});
        const signal = if (try arithmetic.compare(engine, .greater, try scope.get(selected, "length"), c.JS_NewInt32(engine.context, 1))) try scope.invoke(try scope.global("AbortSignal"), "any", &.{selected}) else try v.at(&scope, selected, 0);
        try scope.put(owner, "signal", signal);
        const fetched = fetch(&scope, owner, signal) catch |err| {
            if (try caught(&scope, owner, try reason(&scope, err))) {
                try increment(&scope, owner);
                continue;
            }
            return;
        };
        try flow.wait(continued, engine, owner, fetched, @intFromEnum(Stage.fetched));
        return;
    }
}
fn fetch(scope: *Scope, owner: c.JSValue, signal: c.JSValue) !c.JSValue {
    const global = try scope.own(c.JS_GetGlobalObject(scope.engine.context));
    if (!try v.js.hasKey(scope.engine, global, try scope.text("fetch"))) {
        _ = c.JS_ThrowReferenceError(scope.engine.context, "fetch is not defined");
        return v.js.capture(scope.engine);
    }
    const function = try scope.get(global, "fetch");
    var init = try scope.get(owner, "init");
    if (scope.truthy(signal)) {
        init = try v.spread(scope, init);
        try scope.put(init, "signal", signal);
    }
    return scope.call(function, c.pi_js_undefined(), &.{ try scope.get(owner, "input"), init });
}
fn aborted(scope: *Scope, owner: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return v.optional(scope, try scope.get(owner, key), "aborted");
}
fn caught(scope: *Scope, owner: c.JSValue, failure: c.JSValue) !bool {
    if (try ownedAllocation(scope, owner, failure)) {
        try flow.settle(scope.engine, owner, true, failure);
        return false;
    }
    const attempt_timed_out = scope.equal(try aborted(scope, owner, "attemptSignal"), c.pi_js_bool(scope.engine.context, 1)) and !scope.truthy(try aborted(scope, owner, "parent")) and !scope.truthy(try aborted(scope, owner, "overall"));
    var terminal = scope.truthy(try aborted(scope, owner, "parent")) or scope.truthy(try aborted(scope, owner, "overall"));
    if (!terminal) {
        const instance = c.JS_IsInstanceOf(scope.engine.context, failure, try scope.global("Error"));
        if (instance < 0) return v.js.capture(scope.engine);
        terminal = instance == 1 and try v.eq(scope, try scope.get(failure, "name"), "AbortError") and !attempt_timed_out and c.JS_IsUndefined(try scope.get(owner, "overall"));
    }
    if (!terminal) terminal = try arithmetic.compare(scope.engine, .greater_equal, try scope.get(owner, "attempt"), try scope.get(owner, "maximum"));
    if (terminal) {
        try flow.settle(scope.engine, owner, true, failure);
        return false;
    }
    return true;
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (stage == .cancelled) {
        if (rejected and try ownedAllocation(&scope, owner, value)) return flow.settle(engine, owner, true, value);
        try increment(&scope, owner);
        return attempt(engine, owner);
    }
    if (rejected) {
        if (try caught(&scope, owner, value)) {
            try increment(&scope, owner);
            try attempt(engine, owner);
        }
        return;
    }
    const retry_after_cancel = response(&scope, owner, value) catch |err| {
        if (try caught(&scope, owner, try reason(&scope, err))) {
            try increment(&scope, owner);
            try attempt(engine, owner);
        }
        return;
    };
    if (retry_after_cancel) {
        try increment(&scope, owner);
        try attempt(engine, owner);
    }
}
fn response(scope: *Scope, owner: c.JSValue, value: c.JSValue) !bool {
    var should_retry = false;
    if (scope.truthy(try scope.get(owner, "retryOnStatus"))) {
        const statuses = try scope.get(owner, "agent");
        const has = try scope.get(statuses, "has");
        should_retry = scope.truthy(try scope.call(has, statuses, &.{try scope.get(value, "status")})) and try arithmetic.compare(scope.engine, .less, try scope.get(owner, "attempt"), try scope.get(owner, "maximum"));
    }
    if (!should_retry) {
        try flow.settle(scope.engine, owner, false, value);
        return false;
    }
    const cancelled = cancel(scope, value) catch |err| {
        const failure = try reason(scope, err);
        if (try ownedAllocation(scope, owner, failure)) {
            try flow.settle(scope.engine, owner, true, failure);
            return false;
        }
        return true;
    };
    try flow.wait(continued, scope.engine, owner, cancelled, @intFromEnum(Stage.cancelled));
    return false;
}
fn cancel(scope: *Scope, value: c.JSValue) !c.JSValue {
    const body = try scope.get(value, "body");
    return if (v.nullish(body)) c.pi_js_undefined() else scope.invoke(body, "cancel", &.{});
}
