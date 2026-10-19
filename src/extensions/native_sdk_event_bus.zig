//! Actual c268 createEventBus over the genuine Node EventEmitter import.
//! The public factory and internal session factory share one implementation;
//! safeHandler uses a real intrinsic Await and ordinary catch completion.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const af = v.af;
const frames = @import("native_public_lexical_frame.zig");
const cache_key = "\x00sdk-event-bus-module-c268";
const HandlerFrame = frames.Frame(enum { caught });

pub fn exports(engine: *h.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, exportsBody, .{});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn exportsBody(s: *h.Scope) !c.JSValue {
    if (!s.engine.native_module_values.contains("node:events"))
        try @import("node_events.zig").install(s.engine);
    const module = s.engine.native_module_values.get("node:events") orelse return error.NativeEventEmitterMissing;
    const constructor = try v.get(s, module, "EventEmitter");
    const result = try v.object(s);
    try v.put(s, result, "createEventBus", try v.ordinary(s, "createEventBus", 0, createCall, &.{constructor}));
    return v.duplicate(s, result);
}
/// Existing native session callers use this same actual ordinary factory.
pub fn create(engine: *h.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    return h.expression(engine, createEntry, .{});
}
fn createEntry(s: *h.Scope) !c.JSValue {
    const module = try v.own(s, try exports(s.engine));
    const function = try v.get(s, module, "createEventBus");
    return v.duplicate(s, try v.call(s, function, c.pi_js_undefined(), &.{}));
}
fn createCall(engine: *h.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, createBody, .{roots[0]});
}
fn createBody(s: *h.Scope, constructor: c.JSValue) !c.JSValue {
    const emitter = try v.construct(s, constructor, &.{});
    const result = try v.object(s);
    try v.put(s, result, "emit", try v.arrow(s, "emit", 2, emitCall, &.{emitter}));
    try v.put(s, result, "on", try v.arrow(s, "on", 2, onCall, &.{emitter}));
    try v.put(s, result, "clear", try v.arrow(s, "clear", 0, clearCall, &.{emitter}));
    return v.duplicate(s, result);
}
fn discardMethod(s: *h.Scope, emitter: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    _ = try v.invoke(s, emitter, name, args);
}
fn emitCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.statement(engine, discardMethod, .{
        roots[0], @as([*:0]const u8, "emit"), @as([]const c.JSValue, &.{v.arg(args, 0), v.arg(args, 1)}),
    });
    return c.pi_js_undefined();
}
fn clearCall(engine: *h.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try h.statement(engine, discardMethod, .{roots[0], @as([*:0]const u8, "removeAllListeners"), @as([]const c.JSValue, &.{})});
    return c.pi_js_undefined();
}
fn onCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, onBody, .{roots[0], v.arg(args, 0), v.arg(args, 1)});
}
fn onBody(s: *h.Scope, emitter: c.JSValue, channel: c.JSValue, handler: c.JSValue) !c.JSValue {
    const captures = [_]c.JSValue{channel, handler};
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const safe_handler = try boundary.finishValue(s,
        af.createResumableArrow(s.engine, "safeHandler", 1, safeHandler, &captures, c.pi_js_undefined()));
    try h.statement(s.engine, discardMethod, .{
        emitter, @as([*:0]const u8, "on"), @as([]const c.JSValue, &.{channel, safe_handler}),
    });
    return v.duplicate(s, try v.arrow(s, "", 0, unsubscribeCall, &.{emitter, channel, safe_handler}));
}
fn unsubscribeCall(engine: *h.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.invokeOwned(engine, roots[0], "off", &.{roots[1], roots[2]});
}
fn attempt(engine: *h.Engine, handler: c.JSValue, data: c.JSValue) !af.Action {
    var s: h.Scope = .{ .engine = engine };
    const result: anyerror!af.Action = if (v.call(&s, handler, c.pi_js_undefined(), &.{data})) |value|
        .{ .returned = v.duplicate(&s, value) } else |err| err;
    return v.owned.finishAction(&s, result);
}
fn errorText(s: *h.Scope, channel: c.JSValue) !c.JSValue {
    const prefix = try v.text(s, "Event handler error (");
    const rendered = try v.stringify(s, channel);
    const joined = try h.binary(s, .add, prefix, rendered);
    return v.duplicate(s, try h.binary(s, .add, joined, try v.text(s, "):")));
}
fn report(s: *h.Scope, channel: c.JSValue, reason: c.JSValue) !void {
    const console = try v.global(s, "console");
    const error_method = try v.get(s, console, "error");
    const message = try v.own(s, try h.expression(s.engine, errorText, .{channel}));
    _ = try v.call(s, error_method, console, &.{message, reason});
}
fn safeHandler(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) try @import("native_async_body.zig").enterRejectedContinuation(engine);
    var s: h.Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, safeHandlerBody(&s, args, roots, state, completion, input));
}
fn safeHandlerBody(s: *h.Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const frame = if (completion == .start) first: {
        const value = try HandlerFrame.create(s);
        af.replaceState(s.engine, state, v.duplicate(s, value.owner));
        break :first value;
    } else HandlerFrame.from(state.*);
    switch (completion) {
        .start => switch (try attempt(s.engine, roots[1], v.arg(args, 0))) {
            .returned => |value| return .{ .awaited = value },
            .thrown => |reason| try frame.take(.caught, reason),
            .awaited => unreachable,
        },
        .fulfilled => return .{ .returned = c.pi_js_undefined() },
        .rejected => try frame.copy(.caught, input),
    }
    try h.statement(s.engine, report, .{roots[0], frame.get(.caught)});
    return .{ .returned = c.pi_js_undefined() };
}
