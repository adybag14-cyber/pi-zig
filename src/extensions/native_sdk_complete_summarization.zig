//! Actual c268 completeSummarization and its nested async produce closure.
//! The application supplies the genuine module-bound uuidv7, completeSimple
//! and retryAssistantCall owners. QuickJS owns both async Promise capabilities.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const af = v.af;
const Engine = h.Engine;
const Scope = h.Scope;
const copy = @import("native_sdk_catalog_copy.zig");
const x = @import("native_sdk_catalog_values.zig");

pub fn create(engine: *Engine, uuid: c.JSValue, complete_simple: c.JSValue, retry_assistant: c.JSValue) !c.JSValue {
    return h.expression(engine, createBody, .{ uuid, complete_simple, retry_assistant });
}
fn createBody(s: *Scope, uuid: c.JSValue, complete_simple: c.JSValue, retry_assistant: c.JSValue) !c.JSValue {
    const captures = [_]c.JSValue{ uuid, complete_simple, retry_assistant };
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return v.duplicate(s, try boundary.finishValue(s, af.createResumable(s.engine, "completeSummarization", 6, completeBody, &captures)));
}
fn initialize(s: *Scope, state: *c.JSValue) !c.JSValue {
    const owner = try v.stateObject(s);
    // These are actual Source locals in declaration order. They remain in the
    // genuine AF state through the intrinsic return-adoption operation.
    try v.put(s, owner, "requestOptions", c.pi_js_undefined());
    try v.put(s, owner, "produce", c.pi_js_undefined());
    af.replaceState(s.engine, state, v.duplicate(s, owner));
    return owner;
}
fn requestOptions(s: *Scope, input: c.JSValue, uuid: c.JSValue) !c.JSValue {
    var operations: x.Ops = .{ .s = s };
    const result = try copy.object(&operations, input);
    try v.put(s, result, "cacheRetention", try v.text(s, "none"));
    const session_id = try v.get(s, input, "sessionId");
    const selected = if (v.nullish(session_id)) try v.call(s, uuid, c.pi_js_undefined(), &.{}) else session_id;
    try v.put(s, result, "sessionId", selected);
    return v.duplicate(s, result);
}
fn makeProducer(s: *Scope, model: c.JSValue, context: c.JSValue, options: c.JSValue, stream: c.JSValue, complete_simple: c.JSValue) !c.JSValue {
    // The four captured Source bindings are never reassigned. This closed
    // capture graph does not retain options, retry or callbacks parameters.
    const captures = [_]c.JSValue{ model, context, options, stream, complete_simple };
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return v.duplicate(s, try boundary.finishValue(s, af.createResumableArrow(s.engine, "produce", 0, produceBody, &captures, c.pi_js_undefined())));
}
fn requestRetry(s: *Scope, retry_assistant: c.JSValue, producer: c.JSValue, retry: c.JSValue, options: c.JSValue, callbacks: c.JSValue) !c.JSValue {
    const signal = try v.get(s, options, "signal");
    return v.duplicate(s, try v.call(s, retry_assistant, c.pi_js_undefined(), &.{ producer, retry, signal, callbacks }));
}
fn completeBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(engine);
        return .{ .thrown = h.duplicate(engine, input) };
    }
    if (completion != .start) return error.UnexpectedSummarizationContinuation;
    var scope: Scope = .{ .engine = engine };
    return v.owned.finishAction(&scope, completeStart(&scope, args, roots, state));
}
fn completeStart(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue) !af.Action {
    const owner = try initialize(s, state);
    const options = try v.own(s, try h.expression(s.engine, requestOptions, .{ v.arg(args, 2), roots[0] }));
    try v.put(s, owner, "requestOptions", options);
    const producer = try v.own(s, try h.expression(s.engine, makeProducer, .{
        v.arg(args, 0), v.arg(args, 1), options, v.arg(args, 3), roots[1],
    }));
    try v.put(s, owner, "produce", producer);
    // Source returns this value directly. Await would add a suspension and
    // bypass the observable public then lookup of return adoption.
    return .{ .returned = try h.expression(s.engine, requestRetry, .{
        roots[2], producer, v.arg(args, 4), options, v.arg(args, 5),
    }) };
}
fn produceRequest(s: *Scope, function: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, function, c.pi_js_undefined(), &.{ roots[0], roots[1], roots[2] }));
}
fn streamResult(s: *Scope, input: c.JSValue) !c.JSValue {
    const stream = try v.own(s, h.duplicate(s.engine, input));
    const method = try v.get(s, stream, "result");
    return v.duplicate(s, try v.call(s, method, stream, &.{}));
}
fn produceBody(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(engine);
        return .{ .thrown = h.duplicate(engine, input) };
    }
    if (completion == .start) {
        const result = try h.expression(engine, produceRequest, .{
            if (h.truthy(engine, roots[3])) roots[3] else roots[4], roots,
        });
        return if (h.truthy(engine, roots[3])) .{ .awaited = result } else .{ .returned = result };
    }
    return .{ .returned = try h.expression(engine, streamResult, .{input}) };
}
