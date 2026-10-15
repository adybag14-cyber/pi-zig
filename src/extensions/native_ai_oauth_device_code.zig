//! Native bodies for auth/oauth/device-code.ts; no network or host bridge.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const functions = @import("native_node_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.object();
    const Adapter = struct {
        fn sleepCall(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return sleep(host, arg(args, 0), arg(args, 1), arg(args, 2));
        }
        fn pollCall(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return poll(host, arg(args, 0));
        }
    };
    try scope.put(exports, "abortableSleep", try scope.own(try functions.create(engine, "abortableSleep", 3, Adapter.sleepCall, &.{})));
    try scope.put(exports, "pollOAuthDeviceCodeFlow", try scope.own(try @import("native_ai_auth_helpers.zig").asyncArrow(engine, "pollOAuthDeviceCodeFlow", 1, Adapter.pollCall, &.{})));
    return c.JS_DupValue(engine.context, exports);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn failure(scope: *Scope, owner: c.JSValue, message: c.JSValue) !void {
    return flow.settle(scope.engine, owner, true, try scope.own(try v.js.builtin(scope.engine, "Error", &.{message})));
}
pub fn sleep(engine: *v.em.Engine, milliseconds: c.JSValue, signal: c.JSValue, cancel_message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startSleep(&scope, pending.owner, milliseconds, signal, cancel_message) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startSleep(scope: *Scope, owner: c.JSValue, milliseconds: c.JSValue, signal: c.JSValue, cancel_message: c.JSValue) !void {
    if (scope.truthy(try scope.get(signal, "aborted"))) return failure(scope, owner, cancel_message);
    try scope.put(owner, "signal", signal);
    try scope.put(owner, "cancelMessage", cancel_message);
    const Adapter = struct {
        fn aborted(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            _ = try local.call(try local.global("clearTimeout"), c.pi_js_undefined(), &.{try local.get(roots[0], "timeout")});
            try failure(&local, roots[0], try local.get(roots[0], "cancelMessage"));
            return c.pi_js_undefined();
        }
        fn elapsed(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            _ = try local.invoke(try local.get(roots[0], "signal"), "removeEventListener", &.{ try local.text("abort"), try local.get(roots[0], "onAbort") });
            try flow.settle(engine, roots[0], false, c.pi_js_undefined());
            return c.pi_js_undefined();
        }
    };
    const on_abort = try scope.own(try functions.createArrow(scope.engine, "onAbort", 0, Adapter.aborted, &.{owner}));
    try scope.put(owner, "onAbort", on_abort);
    const elapsed = try scope.own(try functions.createArrow(scope.engine, "", 0, Adapter.elapsed, &.{owner}));
    try scope.put(owner, "timeout", try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ elapsed, milliseconds }));
    const options = try scope.object();
    try scope.put(options, "once", c.pi_js_bool(scope.engine.context, 1));
    _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), on_abort, options });
}
fn binary(scope: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, operation, left, right));
}
fn now(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("Date"), "now", &.{});
}
pub fn poll(engine: *v.em.Engine, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, options);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startPoll(&scope, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startPoll(scope: *Scope, owner: c.JSValue) !void {
    const options = try scope.get(owner, "agent");
    const deadline = if (c.JS_IsNumber(try scope.get(options, "expiresInSeconds"))) try binary(scope, .add, try now(scope), try binary(scope, .multiply, try scope.get(options, "expiresInSeconds"), c.JS_NewInt32(scope.engine.context, 1000))) else try scope.get(try scope.global("Number"), "POSITIVE_INFINITY");
    try scope.put(owner, "deadline", deadline);
    const outer_math = try scope.global("Math");
    const maximum = try scope.get(outer_math, "max");
    const inner_math = try scope.global("Math");
    const floor = try scope.get(inner_math, "floor");
    const interval = try scope.get(options, "intervalSeconds");
    const initial = try scope.call(floor, inner_math, &.{try binary(scope, .multiply, if (v.nullish(interval)) c.JS_NewInt32(scope.engine.context, 5) else interval, c.JS_NewInt32(scope.engine.context, 1000))});
    try scope.put(owner, "interval", try scope.call(maximum, outer_math, &.{ c.JS_NewInt32(scope.engine.context, 1000), initial }));
    try scope.put(owner, "slowDownResponses", c.JS_NewInt32(scope.engine.context, 0));
    if (scope.truthy(try scope.get(options, "waitBeforeFirstPoll"))) {
        const remaining = try binary(scope, .subtract, deadline, try now(scope));
        if (try arithmetic.compare(scope.engine, .greater, remaining, c.JS_NewInt32(scope.engine.context, 0))) return waitSleep(scope, owner, remaining);
    }
    return nextPoll(scope, owner);
}
fn nextPoll(scope: *Scope, owner: c.JSValue) !void {
    if (!try arithmetic.compare(scope.engine, .less, try now(scope), try scope.get(owner, "deadline"))) return timedOut(scope, owner);
    const options = try scope.get(owner, "agent");
    if (scope.truthy(try scope.get(try scope.get(options, "signal"), "aborted"))) return failure(scope, owner, try scope.text("Login cancelled"));
    return flow.wait(continued, scope.engine, owner, try scope.invoke(options, "poll", &.{}), 0);
}
fn waitSleep(scope: *Scope, owner: c.JSValue, remaining: c.JSValue) !void {
    const duration = try scope.invoke(try scope.global("Math"), "min", &.{ try scope.get(owner, "interval"), remaining });
    const promise = try scope.own(try sleep(scope.engine, duration, try scope.get(try scope.get(owner, "agent"), "signal"), try scope.text("Login cancelled")));
    return flow.wait(continued, scope.engine, owner, promise, 1);
}
fn timedOut(scope: *Scope, owner: c.JSValue) !void {
    const slow = try arithmetic.compare(scope.engine, .greater, try scope.get(owner, "slowDownResponses"), c.JS_NewInt32(scope.engine.context, 0));
    return failure(scope, owner, try scope.text(if (slow) "Device flow timed out after one or more slow_down responses. This is often caused by clock drift in WSL or VM environments. Please sync or restart the VM clock and try again." else "Device flow timed out"));
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) nextPoll(&scope, owner) catch |err| try flow.rejectError(engine, owner, err) else afterPoll(&scope, owner, value) catch |err| try flow.rejectError(engine, owner, err);
}
fn afterPoll(scope: *Scope, owner: c.JSValue, result: c.JSValue) !void {
    if (try v.eq(scope, try scope.get(result, "status"), "complete")) return flow.settle(scope.engine, owner, false, try scope.get(result, "value"));
    if (try v.eq(scope, try scope.get(result, "status"), "failed")) return failure(scope, owner, try scope.get(result, "message"));
    if (try v.eq(scope, try scope.get(result, "status"), "slow_down")) {
        try scope.put(owner, "slowDownResponses", try binary(scope, .add, try scope.get(owner, "slowDownResponses"), c.JS_NewInt32(scope.engine.context, 1)));
        const server_interval = c.JS_IsNumber(try scope.get(result, "intervalSeconds")) and scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{try scope.get(result, "intervalSeconds")})) and try arithmetic.compare(scope.engine, .greater, try scope.get(result, "intervalSeconds"), c.JS_NewInt32(scope.engine.context, 0));
        const outer_math = try scope.global("Math");
        const maximum = try scope.get(outer_math, "max");
        const minimum = if (server_interval) blk: {
            const inner_math = try scope.global("Math");
            const floor = try scope.get(inner_math, "floor");
            break :blk try scope.call(floor, inner_math, &.{try binary(scope, .multiply, try scope.get(result, "intervalSeconds"), c.JS_NewInt32(scope.engine.context, 1000))});
        } else try binary(scope, .add, try scope.get(owner, "interval"), c.JS_NewInt32(scope.engine.context, 5000));
        try scope.put(owner, "interval", try scope.call(maximum, outer_math, &.{ c.JS_NewInt32(scope.engine.context, 1000), minimum }));
    }
    const remaining = try binary(scope, .subtract, try scope.get(owner, "deadline"), try now(scope));
    if (try arithmetic.compare(scope.engine, .less_equal, remaining, c.JS_NewInt32(scope.engine.context, 0))) return timedOut(scope, owner);
    return waitSleep(scope, owner, remaining);
}
