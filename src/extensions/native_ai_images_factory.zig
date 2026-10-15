//! Actual OpenRouter one-shot image generation over the shared HTTP body core.
const v = @import("native_ai_provider_values.zig");
const shared = @import("native_ai_classifier_values.zig");
const codec = @import("native_ai_openrouter_images_codec.zig");
const flow = @import("native_agent_async.zig");
const Scope = v.Scope;
const c = v.c;
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const retry = try scope.own(try @import("native_ai_provider_retry_request.zig").create(engine));
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
            for (args[0..@min(args.len, values.len)], 0..) |value, i| values[i] = value;
            return generate(host, roots[0], &values);
        }
    };
    const function = try scope.own(try @import("native_node_function.zig").createArrow(engine, "generateImages", 3, Adapter.call, &.{retry}));
    const prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return v.js.capture(engine);
    const result = try scope.object();
    try scope.put(result, "generateImages", function);
    return c.JS_DupValue(engine.context, result);
}
fn generate(engine: *v.em.Engine, retry: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, retry);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const owner = pending.owner;
    try shared.generation(&scope, owner);
    inline for (.{ "model", "context", "options" }, 0..) |key, i| try scope.put(owner, key, args[i]);
    const output = shared.result(&scope, args[0], true) catch |err| {
        try flow.rejectError(engine, owner, err);
        return pending.promise;
    };
    try scope.put(owner, "output", output);
    setup(&scope, owner) catch |err| try failError(&scope, owner, err);
    return pending.promise;
}
fn setup(scope: *Scope, owner: c.JSValue) !void {
    const model = try scope.get(owner, "model");
    const options = try scope.get(owner, "options");
    const key = try v.optional(scope, options, "apiKey");
    if (!scope.truthy(key)) return v.errorText(scope, try scope.concat(try scope.text("No API key for provider: "), try scope.stringify(try scope.get(model, "provider"))));
    const headers = try @import("native_ai_openai_headers.zig").build(scope, model, options, key);
    const body = try codec.build(scope, model, try scope.get(owner, "context"));
    const base = try scope.get(model, "baseUrl");
    const url = try scope.own(try v.js.builtin(scope.engine, "URL", &.{try scope.concat(if (scope.truthy(try scope.invoke(base, "endsWith", &.{try scope.text("/")}))) try scope.invoke(base, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, -1) }) else base, try scope.text("/chat/completions"))}));
    const promise = try scope.own(try @import("native_ai_classifier_request.zig").post(scope.engine, try scope.get(owner, "agent"), &.{ try scope.text("OpenAI"), try scope.invoke(url, "toString", &.{}), model, body, options, c.pi_js_undefined() }, .{ .require_key = false, .prepared_headers = headers, .sdk_errors = true, .default_retries = 0 }));
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
    try shared.failure(scope, output, try scope.get(owner, "options"), reason, c.pi_js_undefined(), false);
    try flow.settle(scope.engine, owner, false, output);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, response: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return fail(&scope, owner, response);
    const output = try scope.get(owner, "output");
    codec.decode(&scope, output, response, try scope.get(owner, "model")) catch |err| return failError(&scope, owner, err);
    try flow.settle(engine, owner, false, output);
}
