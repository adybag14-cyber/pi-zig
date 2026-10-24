// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete original debuglog time/timeEnd/timeLog/timeLogImpl bodies.
//! The process and trace callable are original private inputs. No clock,
//! category buffer, event registry or disabled fallback is manufactured here.
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const sync = @import("native_sync_arguments.zig");
const c = a.c;
const Scope = a.Scope;
const LogFrame = a.frames.Frame(enum { time, duration, milliseconds, formatted });
const Kind = enum { start, end, log };
pub const Inputs = struct {
    process: c.JSValue,
    trace: c.JSValue,
    format_time: c.JSValue,
};
pub fn create(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, createBody, .{inputs});
}
fn createBody(s: *Scope, inputs: Inputs) anyerror!c.JSValue {
    const owner = try s.objectProto(c.pi_js_null());
    try s.define(owner, "process", inputs.process, 0);
    try s.define(owner, "trace", inputs.trace, 0);
    try s.define(owner, "formatTime", inputs.format_time, 0);
    const implementation = try s.own(try functions.createWithArguments(s.engine, "timeLogImpl", 5, true,
        .{ .formal_count = 5, .callback = logImplementationCallback, .hooks = sync.frameHooks(LogFrame) }, &.{owner}));
    try s.define(owner, "timeLogImpl", implementation, 0);
    const start = try s.own(try functions.createWithArguments(s.engine, "time", 4, true,
        .{ .formal_count = 6, .callback = operationCallback(.start) }, &.{owner}));
    const end = try s.own(try functions.createWithArguments(s.engine, "timeEnd", 5, true,
        .{ .formal_count = 7, .callback = operationCallback(.end) }, &.{owner}));
    const log = try s.own(try functions.createWithArguments(s.engine, "timeLog", 5, true,
        .{ .formal_count = 8, .callback = operationCallback(.log) }, &.{owner}));
    const result = try s.objectProto(c.pi_js_null());
    try s.define(result, "time", start, 0);
    try s.define(result, "timeEnd", end, 0);
    try s.define(result, "timeLog", log, 0);
    return a.duplicate(s.engine, result);
}
fn stringValue(s: *Scope, value: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.toString(value));
}
fn escapedBackslash(s: *Scope, label: c.JSValue) !c.JSValue {
    const method = try s.get(label, "replaceAll");
    return a.duplicate(s.engine, try s.call(method, label, &.{try s.text("\\"), try s.text("\\\\")}));
}
fn safeTraceLabel(s: *Scope, label: c.JSValue) !c.JSValue {
    const first = try s.own(try a.expression(s.engine, escapedBackslash, .{label}));
    const method = try s.get(first, "replaceAll");
    return a.duplicate(s.engine, try s.call(method, first, &.{try s.text("\""), try s.text("\\\"")}));
}
fn flagClear(s: *Scope, flags: c.JSValue, mask: i32) !c.JSValue {
    const value = try s.binary(10, flags, c.JS_NewInt32(s.engine.context, mask));
    return a.boolean(s, s.equal(value, c.JS_NewInt32(s.engine.context, 0)));
}
fn hasLabel(s: *Scope, store: c.JSValue, label: c.JSValue) !c.JSValue {
    const method = try s.get(store, "has");
    return a.boolean(s, s.truthy(try s.call(method, store, &.{label})));
}
fn warning(s: *Scope, owner: c.JSValue, label: c.JSValue,
    implementation: c.JSValue, duplicate: bool) !c.JSValue
{
    const process = try s.get(owner, "process");
    const method = try s.get(process, "emitWarning");
    const start = try a.add(s, try s.text(if (duplicate) "Label '" else "No such label '"), try s.toString(label));
    const middle = try a.add(s, start, try s.text(if (duplicate) "' already exists for " else "' for "));
    const message = try a.add(s, middle, try s.toString(implementation));
    _ = try s.call(method, process, &.{message});
    return c.pi_js_undefined();
}
fn traceCall(s: *Scope, owner: c.JSValue, phase: i32,
    category: c.JSValue, label: c.JSValue) !c.JSValue
{
    const function = try s.get(owner, "trace");
    _ = try s.call(function, c.pi_js_undefined(),
        &.{c.JS_NewInt32(s.engine.context, phase), category, label, c.JS_NewInt32(s.engine.context, 0)});
    return c.pi_js_undefined();
}
fn storeCurrentTime(s: *Scope, owner: c.JSValue, store: c.JSValue, label: c.JSValue) !c.JSValue {
    // Preserve set's reference before evaluating the later live hrtime lookup.
    const method = try s.get(store, "set");
    const process = try s.get(owner, "process");
    const hrtime = try s.get(process, "hrtime");
    const value = try s.call(hrtime, process, &.{});
    _ = try s.call(method, store, &.{label, value});
    return c.pi_js_undefined();
}
fn deleteLabel(s: *Scope, store: c.JSValue, label: c.JSValue) !c.JSValue {
    const method = try s.get(store, "delete");
    _ = try s.call(method, store, &.{label});
    return c.pi_js_undefined();
}
fn logTime(s: *Scope, owner: c.JSValue, store: c.JSValue, implementation: c.JSValue,
    logger: c.JSValue, label: c.JSValue, extra: ?c.JSValue) !c.JSValue
{
    const function = try s.get(owner, "timeLogImpl");
    if (extra) |value| {
        _ = try s.call(function, c.pi_js_undefined(), &.{store, implementation, logger, label, value});
    } else {
        _ = try s.call(function, c.pi_js_undefined(), &.{store, implementation, logger, label});
    }
    return c.pi_js_undefined();
}
fn operationCallback(comptime kind: Kind) sync.Callback {
    return struct {
        fn callback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
            roots: []const c.JSValue) anyerror!c.JSValue
        {
            return a.expression(engine, operationBody, .{args, roots[0], kind});
        }
    }.callback;
}
fn operationBody(s: *Scope, args: *sync.Arguments, owner: c.JSValue,
    comptime kind: Kind) anyerror!c.JSValue
{
    const label_index = if (kind == .start) 4 else 5;
    const trace_index = label_index + 1;
    if (c.JS_IsUndefined(args.get(label_index)))
        try args.take(label_index, a.expression(s.engine, defaultLabel, .{}));
    try args.take(label_index, a.expression(s.engine, stringValue, .{args.get(label_index)}));
    if (!c.JS_IsUndefined(args.get(trace_index))) {
        try args.take(trace_index, a.expression(s.engine, stringValue, .{args.get(trace_index)}));
    } else {
        try args.copy(trace_index, args.get(label_index));
    }
    if (kind == .start) {
        if (try a.condition(s.engine, hasLabel, .{args.get(0), args.get(label_index)})) {
            _ = try a.expression(s.engine, warning, .{owner, args.get(label_index), args.get(2), true});
            return c.pi_js_undefined();
        }
    } else if (try a.condition(s.engine, flagClear, .{args.get(3), @as(i32, 2)})) {
        _ = try a.expression(s.engine, logTime,
            .{owner, args.get(0), args.get(2), args.get(4), args.get(label_index),
              if (kind == .log) @as(?c.JSValue, args.get(7)) else @as(?c.JSValue, null)});
    }
    if (try a.condition(s.engine, flagClear, .{args.get(3), @as(i32, 4)})) {
        try args.take(trace_index, a.expression(s.engine, safeTraceLabel, .{args.get(trace_index)}));
        _ = try a.expression(s.engine, traceCall,
            .{owner, @as(i32, switch (kind) { .start => 'b', .end => 'e', .log => 'n' }),
              args.get(1), args.get(trace_index)});
    }
    if (kind == .start) {
        _ = try a.expression(s.engine, storeCurrentTime, .{owner, args.get(0), args.get(label_index)});
    } else if (kind == .end) {
        _ = try a.expression(s.engine, deleteLabel, .{args.get(0), args.get(label_index)});
    }
    return c.pi_js_undefined();
}
fn defaultLabel(s: *Scope) !c.JSValue { return a.duplicate(s.engine, try s.text("default")); }
fn readTime(s: *Scope, store: c.JSValue, label: c.JSValue) !c.JSValue {
    const method = try s.get(store, "get");
    return a.duplicate(s.engine, try s.call(method, store, &.{label}));
}
fn elapsed(s: *Scope, owner: c.JSValue, time: c.JSValue) !c.JSValue {
    const process = try s.get(owner, "process");
    const method = try s.get(process, "hrtime");
    return a.duplicate(s.engine, try s.call(method, process, &.{time}));
}
fn milliseconds(s: *Scope, duration: c.JSValue) !c.JSValue {
    const seconds = try s.getKey(duration, c.JS_NewInt32(s.engine.context, 0));
    const first = try s.binary(2, seconds, c.JS_NewInt32(s.engine.context, 1000));
    const nanos = try s.getKey(duration, c.JS_NewInt32(s.engine.context, 1));
    const second = try s.binary(3, nanos, c.JS_NewInt32(s.engine.context, 1000000));
    return a.duplicate(s.engine, try a.add(s, first, second));
}
fn formatElapsed(s: *Scope, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(owner, "formatTime"), c.pi_js_undefined(), &.{value}));
}
fn emitLog(s: *Scope, args: *sync.Arguments, formatted: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(args.get(4))) {
        _ = try s.call(args.get(2), c.pi_js_undefined(), &.{args.get(3), formatted});
    } else {
        _ = try s.call(args.get(2), c.pi_js_undefined(), &.{args.get(3), formatted, args.get(4)});
    }
    return c.pi_js_undefined();
}
fn logImplementationCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, logImplementationBody, .{args, roots[0]});
}
fn logImplementationBody(s: *Scope, args: *sync.Arguments, owner: c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, LogFrame);
    try frame.take(.time, a.expression(s.engine, readTime, .{args.get(0), args.get(3)}));
    if (c.JS_IsUndefined(frame.get(.time))) {
        _ = try a.expression(s.engine, warning, .{owner, args.get(3), args.get(1), false});
        return c.pi_js_undefined();
    }
    try frame.take(.duration, a.expression(s.engine, elapsed, .{owner, frame.get(.time)}));
    try frame.take(.milliseconds, a.expression(s.engine, milliseconds, .{frame.get(.duration)}));
    try frame.take(.formatted, a.expression(s.engine, formatElapsed, .{owner, frame.get(.milliseconds)}));
    _ = try a.expression(s.engine, emitLog, .{args, frame.get(.formatted)});
    return c.pi_js_undefined();
}
