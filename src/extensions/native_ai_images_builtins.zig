//! Actual native counterpart of providers/images/register-builtins.ts exports.
//! The C-backed provider module is materialized lazily once per owned facade;
//! its real module promise and loader state stay visible to the VM collector.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const shared = @import("native_ai_classifier_values.zig");
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "modulePromise", c.pi_js_undefined());
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            host.native_exception_diagnostics_suppressed += 1;
            defer host.native_exception_diagnostics_suppressed -= 1;
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const pending = try flow.create(host, roots[0]);
            defer host.freeValue(pending.owner);
            errdefer host.freeValue(pending.promise);
            try shared.generation(&row, pending.owner);
            inline for (.{ "model", "context", "options" }, 0..) |name, index| try row.put(pending.owner, name, if (args.len > index) args[index] else c.pi_js_undefined());
            load(&row, pending.owner) catch |err| try failedError(&row, pending.owner, err);
            return pending.promise;
        }
    };
    const function = try scope.own(try @import("native_node_function.zig").createArrow(engine, "generateImagesOpenRouter", 3, Adapter.call, &.{owner}));
    const prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return v.js.capture(engine);
    const result = try scope.object();
    try scope.put(result, "generateImagesOpenRouter", function);
    return c.JS_DupValue(engine.context, result);
}
fn load(scope: *Scope, pending: c.JSValue) !void {
    const owner = try scope.get(pending, "agent");
    var promise = try scope.get(owner, "modulePromise");
    if (c.JS_IsUndefined(promise)) {
        // This loads the native implementation, not repository JavaScript.
        const module = try scope.own(try @import("native_ai_images_factory.zig").create(scope.engine));
        promise = try scope.own(try scope.engine.checked(c.JS_PiPromiseResolve(scope.engine.context, module)));
        try scope.put(owner, "modulePromise", promise);
    }
    try flow.wait(continued, scope.engine, pending, promise, 0);
}
fn failedError(scope: *Scope, pending: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    try failed(scope, pending, reason);
}
fn failed(scope: *Scope, pending: c.JSValue, reason: c.JSValue) !void {
    if (try shared.ownedAllocation(scope, pending, reason)) return flow.settle(scope.engine, pending, true, reason);
    const model = try scope.get(pending, "model");
    const output = try scope.object();
    inline for (.{ "api", "provider" }) |name| try scope.put(output, name, try scope.get(model, name));
    try scope.put(output, "model", try scope.get(model, "id"));
    try scope.put(output, "output", try scope.array());
    try scope.put(output, "stopReason", try scope.text("error"));
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    try scope.put(output, "errorMessage", if (instance == 1) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason}));
    try scope.put(output, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try flow.settle(scope.engine, pending, false, output);
}
fn continued(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        failed(&scope, pending, value) catch |err| try flow.rejectError(engine, pending, err);
        return;
    }
    if (stage == 1) return flow.settle(engine, pending, false, value);
    invoke(&scope, pending, value) catch |err| try failedError(&scope, pending, err);
}
fn invoke(scope: *Scope, pending: c.JSValue, module: c.JSValue) !void {
    const result = try scope.invoke(module, "generateImages", &.{ try scope.get(pending, "model"), try scope.get(pending, "context"), try scope.get(pending, "options") });
    try flow.wait(continued, scope.engine, pending, result, 1);
}
