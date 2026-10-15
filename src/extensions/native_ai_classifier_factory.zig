//! Actual TypeSafe, Cloudflare System One and OpenAI Decisions facades.
const v = @import("native_ai_provider_values.zig");
const shared = @import("native_ai_classifier_values.zig");
const codec = @import("native_ai_system_one_codec.zig");
const request = @import("native_ai_classifier_request.zig");
const flow = @import("native_agent_async.zig");
const Scope = v.Scope;
const c = v.c;
pub const Kind = enum { typesafe, cloudflare, decisions };
pub fn create(engine: *v.em.Engine, kind: Kind) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.object();
    try scope.put(dependencies, "retry", try scope.own(try @import("native_ai_provider_retry_request.zig").create(engine)));
    try scope.put(dependencies, "kind", c.JS_NewInt32(engine.context, @intFromEnum(kind)));
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
            for (args[0..@min(args.len, values.len)], 0..) |value, i| values[i] = value;
            return classify(host, roots[0], &values);
        }
    };
    const result = try scope.object();
    const function = try scope.own(try @import("native_node_function.zig").createArrow(engine, "classify", 3, Adapter.call, &.{dependencies}));
    if (kind == .decisions) {
        const prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
        if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return v.js.capture(engine);
    }
    try scope.put(result, "classify", function);
    return c.JS_DupValue(engine.context, result);
}
fn classify(engine: *v.em.Engine, dependencies: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, dependencies);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const owner = pending.owner;
    try shared.generation(&scope, owner);
    try scope.put(owner, "model", args[0]);
    try scope.put(owner, "context", args[1]);
    try scope.put(owner, "options", args[2]);
    const kind = try kindOf(&scope, dependencies);
    const label = try scope.text(switch (kind) {
        .cloudflare => "Cloudflare Workers AI",
        .typesafe => "System One API",
        .decisions => "OpenAI Decisions",
    });
    try scope.put(owner, "label", label);
    const output = shared.result(&scope, args[0], false) catch |err| {
        try flow.rejectError(engine, owner, err);
        return pending.promise;
    };
    try scope.put(owner, "output", output);
    setup(&scope, owner, kind) catch |err| try failError(&scope, owner, err);
    return pending.promise;
}
fn kindOf(scope: *Scope, dependencies: c.JSValue) !Kind {
    var value: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &value, try scope.get(dependencies, "kind")) < 0) return v.js.capture(scope.engine);
    return @enumFromInt(value);
}
fn setup(scope: *Scope, owner: c.JSValue, kind: Kind) !void {
    const model = try scope.get(owner, "model");
    const context = try scope.get(owner, "context");
    if (!try v.eq(scope, try scope.get(model, "api"), switch (kind) {
        .cloudflare => "cloudflare-workers-ai-system-one",
        .typesafe => "typesafe-system-one",
        .decisions => "openai-decisions",
    })) return v.errorText(scope, try scope.concat(try scope.text("Unsupported classifier API: "), try scope.stringify(try scope.get(model, "api"))));
    if (kind != .decisions and scope.truthy(try v.optional(scope, try scope.get(context, "images"), "length"))) return v.errorText(scope, try scope.concat(try scope.get(owner, "label"), try scope.text(" does not support image input")));
    const trailing = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text("/+$"), try scope.text("u") }));
    const base = try scope.concat(try scope.invoke(try scope.get(model, "baseUrl"), "replace", &.{ trailing, try scope.text("") }), try scope.text("/"));
    const url = try scope.own(try v.js.builtin(scope.engine, "URL", &.{ try scope.text(switch (kind) {
        .cloudflare => "run",
        .typesafe => "systemone",
        .decisions => "decisions",
    }), base }));
    const payload = if (kind == .decisions) try @import("native_ai_openai_decisions_codec.zig").build(scope, model, context) else try codec.payload(scope, model, context, kind == .cloudflare);
    const excluded = if (kind == .decisions) try scope.array() else c.pi_js_undefined();
    if (kind == .decisions) try scope.index(excluded, 0, c.JS_NewInt32(scope.engine.context, 504));
    const dependencies = try scope.get(owner, "agent");
    const promise = try scope.own(try request.post(scope.engine, try scope.get(dependencies, "retry"), &.{ try scope.get(owner, "label"), url, model, payload, try scope.get(owner, "options"), excluded }, .{}));
    try flow.wait(continued, scope.engine, owner, promise, 0);
}
fn failError(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    if (err == error.OutOfMemory) return flow.rejectError(scope.engine, owner, err);
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    try fail(scope, owner, reason);
}
fn fail(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    if (try shared.ownedAllocation(scope, owner, reason)) return flow.settle(scope.engine, owner, true, reason);
    const output = try scope.get(owner, "output");
    if (try kindOf(scope, try scope.get(owner, "agent")) == .decisions and scope.equal(try scope.get(reason, "status"), c.JS_NewInt32(scope.engine.context, 504))) {
        const signal = try v.optional(scope, try scope.get(owner, "options"), "signal");
        try scope.set(output, "answers", try scope.object());
        try scope.set(output, "stopReason", try scope.text(if (scope.truthy(try v.optional(scope, signal, "aborted"))) "aborted" else "error"));
        try scope.set(output, "errorMessage", try scope.text("OpenAI Decisions error (504): the request timed out at the gateway. Very large inputs (above roughly 600K tokens) currently exceed its time limit."));
        return flow.settle(scope.engine, owner, false, output);
    }
    try shared.failure(scope, output, try scope.get(owner, "options"), reason, try scope.concat(try scope.get(owner, "label"), try scope.text(" error")), false);
    try flow.settle(scope.engine, owner, false, output);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return fail(&scope, owner, value);
    finish(&scope, owner, value) catch |err| try failError(&scope, owner, err);
}
fn finish(scope: *Scope, owner: c.JSValue, body: c.JSValue) !void {
    const kind = try kindOf(scope, try scope.get(owner, "agent"));
    const result = try codec.unwrap(scope, body, try scope.get(owner, "label"), kind == .cloudflare);
    const output = try scope.get(owner, "output");
    const usage = try shared.usage(scope, try scope.get(result, "usage"), try scope.get(owner, "model"));
    if (scope.truthy(usage)) try scope.set(output, "usage", usage);
    const answers = if (kind == .decisions) try @import("native_ai_openai_decisions_codec.zig").answers(scope, try scope.get(result, "answers"), try scope.get(owner, "context")) else try codec.answers(scope, try scope.get(owner, "label"), try scope.get(result, "answers"), try scope.get(owner, "context"));
    try scope.set(output, "answers", answers);
    try flow.settle(scope.engine, owner, false, output);
}
