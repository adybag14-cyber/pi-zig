//! Source async refresh, retaining its receiver/run across both real awaits.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const values = @import("native_cache_warming_values.zig");
const c = em.c;

pub fn begin(engine: *em.Engine, receiver: c.JSValue, run: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, run) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn clearGuestFailure(engine: *em.Engine) void {
    if (engine.captured_exception) |exception| engine.freeValue(exception);
    engine.captured_exception = null;
}
fn storeGeneration(scope: *Scope, owner: c.JSValue) !void {
    try scope.put(owner, "generation", try scope.own(try scope.engine.checked(c.JS_NewBigUint64(scope.engine.context, scope.engine.native_allocation_generation))));
}
fn nativeReason(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !bool {
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(scope.engine.context, &generation, try scope.get(owner, "generation")) < 0) return js.capture(scope.engine);
    const tagged = c.pi_js_native_allocation_error_generation(reason);
    const distance = tagged -% generation;
    return tagged != 0 and distance != 0 and distance <= scope.engine.native_allocation_generation -% generation;
}
fn caught(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    if (err == error.OutOfMemory) return err;
    if (err != error.JavaScriptException) return err;
    if (scope.engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return err;
        if (try nativeReason(scope, owner, reason)) {
            var generation: u64 = 0;
            if (c.JS_ToBigUint64(scope.engine.context, &generation, try scope.get(owner, "generation")) < 0) return js.capture(scope.engine);
            try @import("native_async_body.zig").rethrowRecognizedAllocation(scope.engine, reason, generation);
        }
    }
    clearGuestFailure(scope.engine);
}
fn valid(scope: *Scope, receiver: c.JSValue, run: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(receiver, "validateRun", &.{run}));
}
fn start(engine: *em.Engine, owner: c.JSValue, run: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    try scope.put(owner, "run", run);
    try scope.set(run, "timer", c.pi_js_undefined());
    if (!try valid(&scope, receiver, run) or scope.truthy(try scope.invoke(receiver, "refreshDeadlineMissed", &.{run}))) return flow.settle(engine, owner, false, c.pi_js_undefined());
    const decision = try scope.invoke(receiver, "evaluate", &.{run});
    try scope.put(owner, "decision", decision);
    const warm = try scope.get(decision, "warmCost");
    const miss = try scope.get(decision, "missCost");
    const probability = try scope.get(decision, "continuationProbability");
    const action = try scope.get(decision, "action");
    try scope.put(owner, "action", action);
    try storeGeneration(&scope, owner);
    const result = decide(&scope, receiver, warm, miss, probability, action) catch |err| {
        try caught(&scope, owner, err);
        return afterDecision(engine, owner, action);
    };
    try flow.wait(continuation, engine, owner, result, 0);
}
fn decide(scope: *Scope, receiver: c.JSValue, warm: c.JSValue, miss: c.JSValue, probability: c.JSValue, action: c.JSValue) !c.JSValue {
    const function = try scope.get(receiver, "decide");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("cache_warming_decision"));
    try scope.put(event, "warmCost", warm);
    try scope.put(event, "missCost", miss);
    try scope.put(event, "continuationProbability", probability);
    try scope.put(event, "action", action);
    return scope.call(function, receiver, &.{event});
}
fn continuation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    if (stage == 0) return afterDecision(engine, owner, if (rejected) try scope.get(owner, "action") else value);
    if (!rejected) {
        const keep_going = record(&scope, owner, value) catch |err| fallback: {
            try caught(&scope, owner, err);
            break :fallback true;
        };
        if (!keep_going) return flow.settle(engine, owner, false, c.pi_js_undefined());
    }
    try reschedule(&scope, owner);
}
fn afterDecision(engine: *em.Engine, owner: c.JSValue, action: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const run = try scope.get(owner, "run");
    if (!try valid(&scope, receiver, run) or scope.truthy(try scope.invoke(receiver, "refreshDeadlineMissed", &.{run}))) return flow.settle(engine, owner, false, c.pi_js_undefined());
    const decision = try scope.get(owner, "decision");
    const overridden = !scope.equal(action, try scope.get(decision, "action"));
    const override_value = c.pi_js_bool(engine.context, @intFromBool(overridden));
    try scope.put(owner, "extensionOverride", override_value);
    if (try values.is(&scope, action, "stop")) {
        const reason = if (overridden) "stopped by extension" else if (scope.truthy(try scope.get(decision, "economicsAvailable"))) "expected savings below threshold" else "cache economics unavailable";
        const stopped = try scope.object();
        try scope.put(stopped, "decision", decision);
        try scope.put(stopped, "extensionOverride", override_value);
        _ = try scope.invoke(receiver, "stop", &.{ try scope.text(reason), stopped });
        return flow.settle(engine, owner, false, c.pi_js_undefined());
    }
    try scope.set(run, "extensionOverride", override_value);
    try storeGeneration(&scope, owner);
    const response = request(&scope, receiver, run) catch |err| {
        try caught(&scope, owner, err);
        return reschedule(&scope, owner);
    };
    try flow.wait(continuation, engine, owner, response, 1);
}
fn request(scope: *Scope, receiver: c.JSValue, run: c.JSValue) !c.JSValue {
    const models = try scope.get(receiver, "models");
    const stream = try scope.get(models, "streamSimple");
    const model = try scope.get(run, "model");
    const context = try scope.get(run, "context");
    const options = try scope.own(try js.spread(scope.engine, try scope.get(run, "options")));
    try scope.put(options, "maxTokens", c.JS_NewInt32(scope.engine.context, 1));
    try scope.put(options, "maxRetries", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(options, "signal", try scope.get(try scope.get(run, "controller"), "signal"));
    const events = try scope.call(stream, models, &.{ model, context, options });
    return scope.invoke(events, "result", &.{});
}
fn record(scope: *Scope, owner: c.JSValue, message: c.JSValue) !bool {
    const receiver = try scope.get(owner, "agent");
    const run = try scope.get(owner, "run");
    if (!try valid(scope, receiver, run)) return false;
    if (!try values.is(scope, try scope.get(message, "stopReason"), "error") and !try values.is(scope, try scope.get(message, "stopReason"), "aborted")) {
        const manager = try scope.get(receiver, "sessionManager");
        const append = try scope.get(manager, "appendUsage");
        const kind = try scope.text("cache_warm");
        const provider = try scope.get(message, "provider");
        const response_model = try scope.get(message, "responseModel");
        const model = if (temp.nullish(response_model)) try scope.get(message, "model") else response_model;
        const usage = try scope.get(message, "usage");
        const note = if (scope.truthy(try scope.get(owner, "extensionOverride"))) try scope.text("extension override") else c.pi_js_undefined();
        const entry = try scope.call(append, manager, &.{ kind, provider, model, usage, note });
        const warmed = try scope.get(receiver, "onWarmed");
        if (!temp.nullish(warmed)) _ = try scope.call(warmed, receiver, &.{entry});
    }
    return true;
}
fn reschedule(scope: *Scope, owner: c.JSValue) !void {
    const receiver = try scope.get(owner, "agent");
    const run = try scope.get(owner, "run");
    if (scope.equal(try scope.get(receiver, "run"), run)) _ = try scope.invoke(receiver, "schedule", &.{run});
    try flow.settle(scope.engine, owner, false, c.pi_js_undefined());
}
