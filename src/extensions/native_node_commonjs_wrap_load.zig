// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Original loader.js timer cells, lazy module.require channel and wrapModuleLoad.
//! The canonical assembler supplies the actual debugWithTimer and tracingChannel
//! declarations. This owner neither publishes a partial node:module nor invents
//! tracing channels, clocks, enabled flags, errors or process bindings.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const modules = @import("native_node_module_constructor.zig");
const sync = @import("native_sync_arguments.zig");
const guest = @import("native_sdk_guest_operation.zig");
const ModuleFrame = a.frames.Frame(enum { start_timer, end_timer, channel_value, channel_initialized });
const CallFrame = a.frames.Frame(enum { log_label, trace_label, channel });
pub const Inputs = struct {
    module_constructor: c.JSValue,
    debug_with_timer: c.JSValue,
    tracing_channel: c.JSValue,
};
/// Returns the ordinary original wrapModuleLoad declaration. Inputs are
/// retained through its complete lifetime; its timer callback shares mutable
/// lexical cells, including updates made during startTimer itself.
pub fn create(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, createBody, .{inputs});
}
fn createBody(s: *Scope, inputs: Inputs) anyerror!c.JSValue {
    const actual = try s.own(try modules.actualConstructor(s.engine));
    if (!s.equal(actual, inputs.module_constructor)) return error.ActualCanonicalModuleRequired;
    if (!c.JS_IsFunction(s.engine.context, inputs.debug_with_timer) or
        !c.JS_IsFunction(s.engine.context, inputs.tracing_channel))
        return error.ActualModuleLoadTracingDeclarationsRequired;
    const frame = try ModuleFrame.create(&s.values);
    const callback = try s.own(try functions.createWithArguments(s.engine, "", 2, false,
        .{ .formal_count = 2, .callback = updateTimers }, &.{frame.owner}));
    // The actual initializer precedes both destructuring reads. A synchronous
    // updater call observes the original TDZ rather than fabricating timers.
    _ = try a.expression(s.engine, installTimers, .{inputs.debug_with_timer, callback, frame});
    try frame.clear(.channel_value);
    try frame.copy(.channel_initialized, a.boolean(s, false));
    return functions.createWithArguments(s.engine, "wrapModuleLoad", 4, true,
        .{ .formal_count = 4, .callback = invoke, .hooks = sync.frameHooks(CallFrame) },
        &.{actual, inputs.tracing_channel, frame.owner});
}
fn initializeTimers(s: *Scope, factory: c.JSValue, callback: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(factory, c.pi_js_undefined(),
        &.{try s.text("module_timer"), callback}));
}
fn installTimers(s: *Scope, factory: c.JSValue, callback: c.JSValue, frame: *ModuleFrame) !c.JSValue {
    const result = try s.own(try a.expression(s.engine, initializeTimers, .{factory, callback}));
    const receiver = try guest.toObject(&s.values, result);
    try frame.take(.start_timer, a.field(s.engine, receiver, "startTimer"));
    try frame.take(.end_timer, a.field(s.engine, receiver, "endTimer"));
    return c.pi_js_undefined();
}
fn updateTimers(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    const frame = ModuleFrame.from(roots[0]);
    // Assignment checks initialization without retaining the displaced value.
    // Its retirement occurs at the exact assignment boundary in frame.copy.
    return a.expression(engine, updateBody, .{frame, args});
}
fn updateBody(s: *Scope, frame: *ModuleFrame, args: *sync.Arguments) !c.JSValue {
    if (!frame.ready[0]) {
        const generation = try s.beforeAllocation();
        _ = try s.checkedAllocation(c.JS_ThrowReferenceError(s.engine.context, "Cannot access 'startTimer' before initialization"), generation);
        unreachable;
    }
    try frame.copy(.start_timer, args.get(0));
    if (!frame.ready[1]) {
        const generation = try s.beforeAllocation();
        _ = try s.checkedAllocation(c.JS_ThrowReferenceError(s.engine.context, "Cannot access 'endTimer' before initialization"), generation);
        unreachable;
    }
    try frame.copy(.end_timer, args.get(1));
    return c.pi_js_undefined();
}
fn optional(s: *Scope, input: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (a.v.nullish(input)) c.pi_js_undefined() else s.get(input, name);
}
fn parentText(s: *Scope, parent: c.JSValue) !c.JSValue {
    const id = try optional(s, parent, "id");
    return a.duplicate(s.engine, if (s.truthy(id)) try s.toString(id) else try s.text(""));
}
fn requestText(s: *Scope, request: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.toString(request));
}
fn logLabel(s: *Scope, args: *sync.Arguments) !c.JSValue {
    // Independent template substitutions retire their original object before
    // the next substitution; only the resulting strings remain here.
    const parent = try s.own(try a.expression(s.engine, parentText, .{args.get(1)}));
    const prefix = try a.add(s, try a.add(s, try s.text("["), parent), try s.text("] ["));
    const request = try s.own(try a.expression(s.engine, requestText, .{args.get(0)}));
    return a.duplicate(s.engine, try a.add(s, try a.add(s, prefix, request), try s.text("]")));
}
fn traceLabel(s: *Scope, args: *sync.Arguments) !c.JSValue {
    const request = try s.own(try a.expression(s.engine, requestText, .{args.get(0)}));
    return a.duplicate(s.engine, try a.add(s,
        try a.add(s, try s.text("require('"), request), try s.text("')")));
}
fn channel(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const frame = ModuleFrame.from(roots[2]);
    if (!s.truthy(frame.get(.channel_initialized))) {
        const produced = try a.call(s.engine, roots[1], c.pi_js_undefined(), &.{try s.text("module.require")});
        try frame.take(.channel_value, produced);
        try frame.copy(.channel_initialized, a.boolean(s, true));
    }
    return a.duplicate(s.engine, frame.get(.channel_value));
}
fn timer(s: *Scope, roots: []const c.JSValue, frame: *CallFrame, comptime ending: bool) !c.JSValue {
    const owner = ModuleFrame.from(roots[2]);
    const callable = try s.own(a.duplicate(s.engine, if (ending) owner.get(.end_timer) else owner.get(.start_timer)));
    // Resolve the live lexical callable before arguments. A first startTimer
    // may update endTimer through the original lazy callback.
    _ = try s.call(callable, c.pi_js_undefined(), &.{frame.get(.log_label), frame.get(.trace_label)});
    return c.pi_js_undefined();
}
fn subscribers(s: *Scope, frame: *CallFrame) !c.JSValue {
    return a.boolean(s, s.truthy(try s.get(frame.get(.channel), "hasSubscribers")));
}
fn load(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue, traced: bool) !c.JSValue {
    if (traced) {
        const current_channel = try s.own(try a.expression(s.engine, channel, .{roots}));
        const trace = try s.get(current_channel, "traceSync");
        const loader = try s.get(roots[0], "_load");
        const context = try s.objectProto(c.pi_js_null());
        try s.define(context, "parentFilename", try optional(s, args.get(1), "filename"), c.JS_PROP_C_W_E);
        try s.define(context, "id", args.get(0), c.JS_PROP_C_W_E);
        return a.duplicate(s.engine, try s.call(trace, current_channel,
            &.{loader, context, roots[0], args.get(0), args.get(1), args.get(2), args.get(3)}));
    }
    const loader = try s.get(roots[0], "_load");
    return a.duplicate(s.engine, try s.call(loader, roots[0],
        &.{args.get(0), args.get(1), args.get(2), args.get(3)}));
}
fn tryBody(engine: *a.v.em.Engine, args: *sync.Arguments, roots: []const c.JSValue,
    frame: *CallFrame) !c.JSValue
{
    const traced = try a.condition(engine, subscribers, .{frame});
    return a.expression(engine, load, .{args, roots, traced});
}
fn finishFinally(engine: *a.v.em.Engine, pending: anytype, roots: []const c.JSValue,
    frame: *CallFrame) !c.JSValue
{
    // A completed ordinary throw is data while Source finally executes.
    // Actual fatal events still unwind without executing additional guest code.
    var cleanup = a.owned.Completion.initValue(engine, a.expression(engine, timer, .{roots, frame, true}));
    const result = cleanup.finishAction() catch |err| {
        var fatal = a.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        switch (pending) { .returned, .thrown => |value| fatal.release(value), .awaited => unreachable }
        return fatal.finishValue();
    };
    var selected = a.owned.Completion.initAction(engine, if (result == .thrown) result else pending);
    if (result == .thrown) {
        switch (pending) { .returned, .thrown => |value| selected.release(value), .awaited => unreachable }
    } else selected.release(result.returned);
    return selected.finishValue();
}
fn invoke(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, body, .{args, roots});
}
fn body(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, CallFrame);
    try frame.take(.log_label, a.expression(s.engine, logLabel, .{args}));
    try frame.take(.trace_label, a.expression(s.engine, traceLabel, .{args}));
    try frame.take(.channel, a.expression(s.engine, channel, .{roots}));
    _ = try a.expression(s.engine, timer, .{roots, frame, false});
    // startTimer is outside Source try/finally. Get hasSubscribers, traceSync,
    // _load and all calls inside it are covered by the single endTimer call.
    var operation = a.owned.Completion.initValue(s.engine, tryBody(s.engine, args, roots, frame));
    const pending = try operation.finishAction();
    return finishFinally(s.engine, pending, roots, frame);
}
