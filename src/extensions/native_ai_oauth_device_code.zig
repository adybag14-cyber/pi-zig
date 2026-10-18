//! c268154c auth/oauth/device-code.ts: an ordinary Promise constructor producer
//! and a genuine async polling declaration with its exact Source Await edges.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const functions = @import("native_node_function.zig");
const cancel_message = "Login cancelled";
const timeout_message = "Device flow timed out";
const slow_timeout_message = "Device flow timed out after one or more slow_down responses. This is often caused by clock drift in WSL or VM environments. Please sync or restart the VM clock and try again.";

fn expression(engine: *x.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, @call(.auto, body, .{&o} ++ args));
}
fn statement(engine: *x.em.Engine, comptime body: anytype, args: anytype) !void {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishVoid(&scope, @call(.auto, body, .{&o} ++ args));
}
fn invocation(engine: *x.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    try engine.checkNativeEntry();
    var frame: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&frame);
    return x.finishInvocation(engine, &frame, expression(engine, body, args));
}
fn boolean(o: *x.Ops, value: bool) c.JSValue { return c.pi_js_bool(o.s.engine.context, @intFromBool(value)); }
fn integer(o: *x.Ops, value: i32) c.JSValue { return c.JS_NewInt32(o.s.engine.context, value); }

pub fn create(engine: *x.em.Engine) !c.JSValue { return invocation(engine, createBody, .{}); }
fn createBody(o: *x.Ops) !c.JSValue {
    const exports = try o.object();
    try o.put(exports, "abortableSleep", try o.own(try functions.create(o.s.engine, "abortableSleep", 3, sleepCall, &.{})));
    try o.put(exports, "pollOAuthDeviceCodeFlow", try o.own(try af.createResumable(o.s.engine, "pollOAuthDeviceCodeFlow", 1, pollBody, &.{})));
    return c.JS_DupValue(o.s.engine.context, exports);
}
fn sleepCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, sleepExpression, .{ x.arg(args, 0), x.arg(args, 1), x.arg(args, 2) });
}
pub fn sleep(engine: *x.em.Engine, milliseconds: c.JSValue, signal: c.JSValue, message: c.JSValue) !c.JSValue {
    return invocation(engine, sleepExpression, .{ milliseconds, signal, message });
}
fn sleepExpression(o: *x.Ops, milliseconds: c.JSValue, signal: c.JSValue, message: c.JSValue) !c.JSValue {
    // The Source producer reads the mutable global Promise before constructing
    // its ordinary arrow executor. It is not an AsyncFunction.
    const constructor = try o.global("Promise");
    const executor = try o.own(try functions.createArrow(o.s.engine, "", 2, sleepExecutor, &.{ milliseconds, signal, message }));
    return c.JS_DupValue(o.s.engine.context, try x.guest.construct(o.s, constructor, &.{executor}));
}
fn sleepExecutor(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, executorBody, .{ roots[0], roots[1], roots[2], x.arg(args, 0), x.arg(args, 1) });
    return c.pi_js_undefined();
}
fn executorBody(o: *x.Ops, milliseconds: c.JSValue, signal: c.JSValue, message: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !void {
    if (o.truthy(try o.own(try expression(o.s.engine, propertyTruth, .{ signal, "aborted" })))) {
        return statement(o.s.engine, rejectError, .{ reject, message });
    }
    // Only the timeout binding is shared by onAbort; unrelated lexical inputs
    // are not retained by a broad native owner object.
    const timeout = try o.cell();
    try o.put(timeout, "initialized", boolean(o, false));
    const on_abort = try o.own(try functions.createArrow(o.s.engine, "onAbort", 0, abortCall, &.{ timeout, reject, message }));
    const handle = try o.own(try expression(o.s.engine, startTimer, .{ milliseconds, signal, on_abort, resolve }));
    try o.put(timeout, "value", handle);
    try o.put(timeout, "initialized", boolean(o, true));
    try statement(o.s.engine, addAbortListener, .{ signal, on_abort });
}
fn abortCall(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, clearTimer, .{roots[0]});
    try statement(engine, rejectError, .{ roots[1], roots[2] });
    return c.pi_js_undefined();
}
fn elapsedCall(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, removeAbortListener, .{ roots[0], roots[1] });
    try statement(engine, callEmpty, .{roots[2]});
    return c.pi_js_undefined();
}
fn startTimer(o: *x.Ops, milliseconds: c.JSValue, signal: c.JSValue, on_abort: c.JSValue, resolve: c.JSValue) !c.JSValue {
    const timer = try o.global("setTimeout");
    const elapsed = try o.own(try functions.createArrow(o.s.engine, "", 0, elapsedCall, &.{ signal, on_abort, resolve }));
    return c.JS_DupValue(o.s.engine.context, try o.call(timer, c.pi_js_undefined(), &.{ elapsed, milliseconds }));
}
fn clearTimer(o: *x.Ops, timeout: c.JSValue) !void {
    const clear = try o.global("clearTimeout");
    if (!o.truthy(try o.get(timeout, "initialized"))) {
        // A guest setTimeout can synchronously invoke the elapsed callback,
        // whose removeEventListener may reenter onAbort before const timeout.
        const generation = try o.beforeAllocation();
        _ = try o.allocation(c.JS_ThrowReferenceError(o.s.engine.context, "timeout is not initialized"), generation);
        unreachable;
    }
    _ = try o.call(clear, c.pi_js_undefined(), &.{try o.get(timeout, "value")});
}
fn rejectError(o: *x.Ops, reject: c.JSValue, message: c.JSValue) !void {
    const reason = try o.own(try expression(o.s.engine, constructError, .{message}));
    _ = try o.call(reject, c.pi_js_undefined(), &.{reason});
}
fn constructError(o: *x.Ops, message: c.JSValue) !c.JSValue {
    return c.JS_DupValue(o.s.engine.context, try x.guest.construct(o.s, try o.global("Error"), &.{message}));
}
fn addAbortListener(o: *x.Ops, signal: c.JSValue, on_abort: c.JSValue) !void {
    const add = try o.get(signal, "addEventListener");
    const name = try o.text("abort");
    const options = try o.object();
    try o.put(options, "once", boolean(o, true));
    _ = try o.call(add, signal, &.{ name, on_abort, options });
}
fn removeAbortListener(o: *x.Ops, signal: c.JSValue, on_abort: c.JSValue) !void {
    const remove = try o.get(signal, "removeEventListener");
    _ = try o.call(remove, signal, &.{ try o.text("abort"), on_abort });
}
fn callEmpty(o: *x.Ops, callable: c.JSValue) !void { _ = try o.call(callable, c.pi_js_undefined(), &.{}); }

pub fn poll(engine: *x.em.Engine, options: c.JSValue) !c.JSValue { return invocation(engine, pollCall, .{options}); }
fn pollCall(o: *x.Ops, options: c.JSValue) !c.JSValue {
    const function = try o.own(try af.createResumable(o.s.engine, "pollOAuthDeviceCodeFlow", 1, pollBody, &.{}));
    return c.JS_DupValue(o.s.engine.context, try o.call(function, c.pi_js_undefined(), &.{options}));
}
fn pollBody(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishAction(&scope, advance(&o, args, state, completion, input));
}
fn advance(o: *x.Ops, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(o.s.engine);
        return .{ .thrown = c.JS_DupValue(o.s.engine.context, input) };
    }
    if (completion == .start) {
        const owner = try o.cell();
        af.replaceState(o.s.engine, state, c.JS_DupValue(o.s.engine.context, owner));
        const options = x.arg(args, 0);
        try o.put(owner, "options", options);
        try o.put(owner, "deadline", try o.own(try expression(o.s.engine, deadlineValue, .{options})));
        try o.put(owner, "interval", try o.own(try expression(o.s.engine, boundedFloorProperty, .{ options, "intervalSeconds", true })));
        try o.put(owner, "slow", integer(o, 0));
        try o.put(owner, "awaitPoll", boolean(o, false));
        if (o.truthy(try o.own(try expression(o.s.engine, propertyTruth, .{ options, "waitBeforeFirstPoll" })))) {
            const remaining = try o.own(try expression(o.s.engine, remainingValue, .{try o.get(owner, "deadline")}));
            try o.put(owner, "firstRemaining", remaining);
            if (o.truthy(try o.binary(6, remaining, integer(o, 0)))) return awaitSleep(o, owner, "firstRemaining");
        }
        return nextPoll(o, owner);
    }
    if (o.truthy(try o.get(state.*, "awaitPoll"))) return afterPoll(o, state.*, input);
    // BCDF keeps uncaptured lexical slots across leave_scope. A while
    // condition runs before the next enter_scope resets the prior body slots.
    return nextPoll(o, state.*);
}
fn nextPoll(o: *x.Ops, owner: c.JSValue) !af.Action {
    if (!o.truthy(try o.own(try expression(o.s.engine, withinDeadline, .{try o.get(owner, "deadline")})))) return timedOut(o, owner);
    // Actual enter_scope resets body lexicals in reverse declaration order.
    // A false condition retains them through the final Error construction.
    try o.put(owner, "remaining", c.pi_js_undefined());
    try o.put(owner, "result", c.pi_js_undefined());
    const options = try o.get(owner, "options");
    if (o.truthy(try o.own(try expression(o.s.engine, abortedOption, .{options})))) {
        return .{ .thrown = try expression(o.s.engine, errorText, .{cancel_message}) };
    }
    try o.put(owner, "awaitPoll", boolean(o, true));
    return .{ .awaited = try expression(o.s.engine, callPoll, .{options}) };
}
fn callPoll(o: *x.Ops, options: c.JSValue) !c.JSValue {
    return c.JS_DupValue(o.s.engine.context, try o.invoke(options, "poll", &.{}));
}
fn afterPoll(o: *x.Ops, owner: c.JSValue, result: c.JSValue) !af.Action {
    try o.put(owner, "result", result);
    if (o.truthy(try o.own(try expression(o.s.engine, statusIs, .{ result, "complete" })))) {
        return .{ .returned = c.JS_DupValue(o.s.engine.context, try o.get(result, "value")) };
    }
    if (o.truthy(try o.own(try expression(o.s.engine, statusIs, .{ result, "failed" })))) {
        return .{ .thrown = try expression(o.s.engine, failedError, .{result}) };
    }
    if (o.truthy(try o.own(try expression(o.s.engine, statusIs, .{ result, "slow_down" })))) {
        try o.put(owner, "slow", try o.binary(0, try o.get(owner, "slow"), integer(o, 1)));
        const valid = o.truthy(try o.own(try expression(o.s.engine, validServerInterval, .{result})));
        const interval = if (valid)
            try expression(o.s.engine, boundedFloorProperty, .{ result, "intervalSeconds", false })
        else
            try expression(o.s.engine, incrementedInterval, .{owner});
        try o.put(owner, "interval", try o.own(interval));
    }
    const remaining = try o.own(try expression(o.s.engine, remainingValue, .{try o.get(owner, "deadline")}));
    try o.put(owner, "remaining", remaining);
    if (o.truthy(try o.binary(5, remaining, integer(o, 0)))) return timedOut(o, owner);
    return awaitSleep(o, owner, "remaining");
}
fn awaitSleep(o: *x.Ops, owner: c.JSValue, remaining_name: [*:0]const u8) !af.Action {
    try o.put(owner, "awaitPoll", boolean(o, false));
    return .{ .awaited = try expression(o.s.engine, sleepAwaitValue, .{ owner, remaining_name }) };
}
fn sleepAwaitValue(o: *x.Ops, owner: c.JSValue, remaining_name: [*:0]const u8) !c.JSValue {
    // Math.min and its receiver retire before options.signal is read.
    const duration = try o.own(try expression(o.s.engine, minimumDuration, .{ owner, remaining_name }));
    const signal = try o.get(try o.get(owner, "options"), "signal");
    return sleep(o.s.engine, duration, signal, try o.text(cancel_message));
}
fn minimumDuration(o: *x.Ops, owner: c.JSValue, remaining_name: [*:0]const u8) !c.JSValue {
    const math = try o.global("Math");
    const minimum = try o.get(math, "min");
    return c.JS_DupValue(o.s.engine.context, try o.call(minimum, math, &.{ try o.get(owner, "interval"), try o.get(owner, remaining_name) }));
}
fn timedOut(o: *x.Ops, owner: c.JSValue) !af.Action {
    return .{ .thrown = try expression(o.s.engine, timeoutError, .{try o.get(owner, "slow")}) };
}
fn timeoutError(o: *x.Ops, slow: c.JSValue) !c.JSValue {
    const constructor = try o.global("Error");
    const message = if (o.truthy(try o.binary(6, slow, integer(o, 0)))) slow_timeout_message else timeout_message;
    return c.JS_DupValue(o.s.engine.context, try x.guest.construct(o.s, constructor, &.{try o.text(message)}));
}
fn errorText(o: *x.Ops, message: []const u8) !c.JSValue {
    const constructor = try o.global("Error");
    return c.JS_DupValue(o.s.engine.context, try x.guest.construct(o.s, constructor, &.{try o.text(message)}));
}
fn failedError(o: *x.Ops, result: c.JSValue) !c.JSValue {
    const constructor = try o.global("Error");
    return c.JS_DupValue(o.s.engine.context, try x.guest.construct(o.s, constructor, &.{try o.get(result, "message")}));
}
fn propertyTruth(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, o.truthy(try o.get(receiver, name))); }
fn propertyIsNumber(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue { return boolean(o, c.JS_IsNumber(try o.get(receiver, name))); }
fn statusIs(o: *x.Ops, result: c.JSValue, status: []const u8) !c.JSValue {
    const actual = try o.get(result, "status");
    return boolean(o, o.s.equal(actual, try o.text(status)));
}
fn dateNow(o: *x.Ops) !c.JSValue {
    return c.JS_DupValue(o.s.engine.context, try o.invoke(try o.global("Date"), "now", &.{}));
}
fn multiplyProperty(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8, default_interval: bool) !c.JSValue {
    const value = try o.get(receiver, name);
    return c.JS_DupValue(o.s.engine.context, try o.binary(2, if (default_interval and x.nullish(value)) integer(o, 5) else value, integer(o, 1000)));
}
fn deadlineValue(o: *x.Ops, options: c.JSValue) !c.JSValue {
    if (!o.truthy(try o.own(try expression(o.s.engine, propertyIsNumber, .{ options, "expiresInSeconds" }))))
        return c.JS_DupValue(o.s.engine.context, try o.get(try o.global("Number"), "POSITIVE_INFINITY"));
    const current = try o.own(try expression(o.s.engine, dateNow, .{}));
    const duration = try o.own(try expression(o.s.engine, multiplyProperty, .{ options, "expiresInSeconds", false }));
    return c.JS_DupValue(o.s.engine.context, try o.binary(0, current, duration));
}
fn flooredProperty(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8, default_interval: bool) !c.JSValue {
    const math = try o.global("Math");
    const floor = try o.get(math, "floor");
    const milliseconds = try o.own(try expression(o.s.engine, multiplyProperty, .{ receiver, name, default_interval }));
    return c.JS_DupValue(o.s.engine.context, try o.call(floor, math, &.{milliseconds}));
}
fn boundedFloorProperty(o: *x.Ops, receiver: c.JSValue, name: [*:0]const u8, default_interval: bool) !c.JSValue {
    const math = try o.global("Math");
    const maximum = try o.get(math, "max");
    const floored = try o.own(try expression(o.s.engine, flooredProperty, .{ receiver, name, default_interval }));
    return c.JS_DupValue(o.s.engine.context, try o.call(maximum, math, &.{ integer(o, 1000), floored }));
}
fn remainingValue(o: *x.Ops, deadline: c.JSValue) !c.JSValue {
    const now = try o.own(try expression(o.s.engine, dateNow, .{}));
    return c.JS_DupValue(o.s.engine.context, try o.binary(1, deadline, now));
}
fn withinDeadline(o: *x.Ops, deadline: c.JSValue) !c.JSValue {
    const now = try o.own(try expression(o.s.engine, dateNow, .{}));
    return c.JS_DupValue(o.s.engine.context, try o.binary(4, now, deadline));
}
fn abortedOption(o: *x.Ops, options: c.JSValue) !c.JSValue {
    return boolean(o, o.truthy(try o.get(try o.get(options, "signal"), "aborted")));
}
fn finiteProperty(o: *x.Ops, result: c.JSValue) !c.JSValue {
    const number = try o.global("Number");
    const finite = try o.get(number, "isFinite");
    return boolean(o, o.truthy(try o.call(finite, number, &.{try o.get(result, "intervalSeconds")})));
}
fn positiveProperty(o: *x.Ops, result: c.JSValue) !c.JSValue {
    return c.JS_DupValue(o.s.engine.context, try o.binary(6, try o.get(result, "intervalSeconds"), integer(o, 0)));
}
fn validServerInterval(o: *x.Ops, result: c.JSValue) !c.JSValue {
    if (!o.truthy(try o.own(try expression(o.s.engine, propertyIsNumber, .{ result, "intervalSeconds" })))) return boolean(o, false);
    if (!o.truthy(try o.own(try expression(o.s.engine, finiteProperty, .{result})))) return boolean(o, false);
    return positiveProperty(o, result);
}
fn incrementedInterval(o: *x.Ops, owner: c.JSValue) !c.JSValue {
    const math = try o.global("Math");
    const maximum = try o.get(math, "max");
    const next = try o.binary(0, try o.get(owner, "interval"), integer(o, 5000));
    return c.JS_DupValue(o.s.engine.context, try o.call(maximum, math, &.{ integer(o, 1000), next }));
}
