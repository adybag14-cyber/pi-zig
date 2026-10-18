//! Genuine c268 public model resolver entries, retaining real imported owners.
const r = @import("native_sdk_model_reference_live.zig");
const h = @import("native_sdk_session_locals.zig");
const cli_body = @import("native_sdk_public_model_cli.zig");
const scope_body = @import("native_sdk_public_model_scope.zig");
const v = r.v;
const c = v.c;
const cache_key = "\x00sdk-public-model-resolver";
/// The actual application graph supplies its retained CLI module binding.
pub const Inputs = struct { thinking: c.JSValue };
pub fn create(engine: *r.Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{inputs});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var completed = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        completed.release(candidate);
        return completed.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn createBody(s: *v.Scope, inputs: Inputs) !c.JSValue {
    const defaults = try v.own(s, try @import("native_sdk_factory_model.zig").defaultModelPerProvider(s.engine));
    const models = try v.own(s, try @import("native_ai_model_values.zig").bindings(s.engine));
    const matcher = try v.own(s, try @import("native_minimatch_namespace.zig").create(s.engine));
    const equal = try v.get(s, models, "modelsAreEqual");
    const minimatch = try v.get(s, matcher, "minimatch");
    const exports = try v.object(s);
    const roots = [_]c.JSValue{inputs.thinking, defaults, minimatch, equal};
    try v.put(s, exports, "resolveCliModel", try v.ordinary(s, "resolveCliModel", 1, cli, &roots));
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const scope = try boundary.finishValue(s, v.af.createResumable(s.engine, "resolveModelScopeWithDiagnostics", 3, scoped, &roots));
    try v.put(s, exports, "resolveModelScopeWithDiagnostics", scope);
    return v.duplicate(s, exports);
}
fn cli(engine: *r.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return cli_body.resolve(engine, .{ .thinking = roots[0], .defaults = roots[1] }, v.arg(args, 0));
}
fn scoped(engine: *r.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: v.af.Completion, input: c.JSValue) !v.af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine)
    else try engine.checkNativeEntry();
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, scopedBody(&s, args, roots, completion, input));
}
fn scopedBody(s: *v.Scope, args: []const c.JSValue, roots: []const c.JSValue, completion: v.af.Completion, input: c.JSValue) !v.af.Action {
    return switch (completion) {
        .start => .{ .awaited = try v.invokeOwned(s.engine, v.arg(args, 1), "getAvailable", &.{c.pi_js_undefined(), v.arg(args, 2)}) },
        .fulfilled => .{ .returned = try scope_body.resolve(s.engine, .{
            .reference = .{ .thinking = roots[0], .defaults = roots[1] },
            .minimatch = roots[2], .equal = roots[3],
        }, v.arg(args, 0), input) },
        .rejected => .{ .thrown = v.duplicate(s, input) },
    };
}
