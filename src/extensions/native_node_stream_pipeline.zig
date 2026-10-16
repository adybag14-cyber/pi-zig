//! Node-stage branch of Node24 pipeline. Function/iterable/Web stages are a
//! separate capability gate; this branch never substitutes them with aliases.
const core = @import("native_node_stream.zig");
const life = @import("native_node_stream_lifecycle.zig");
const abort = @import("abort_signal.zig");
const fnc = @import("native_node_function.zig");
const em = core.em; const c = core.c; const js = core.js; const Scope = core.Scope;
const Op = enum(c_int) { destroy_close, destroy_eos, on_error, pipe_close, pipe_end, source_done, destination_done, finish, callback_tick, aborted };
fn object(scope: *Scope) !c.JSValue { return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null()))); }
fn flag(scope: *Scope, record: c.JSValue, key: [*:0]const u8) !bool { return scope.truthy(try scope.get(record, key)); }
fn setFlag(scope: *Scope, record: c.JSValue, key: [*:0]const u8, value: bool) !void { try scope.put(record, key, c.pi_js_bool(scope.engine.context, @intFromBool(value))); }
fn handler(scope: *Scope, record: c.JSValue, op: Op) !c.JSValue { return scope.own(try fnc.createArrow(scope.engine, "", 1, event, &.{ record, c.JS_NewInt32(scope.engine.context, @intFromEnum(op)) })); }
fn arrayLength(scope: *Scope, array: c.JSValue) !usize { var n: u64 = 0; if (c.JS_ToIndex(scope.engine.context, &n, try scope.get(array, "length")) < 0) return js.capture(scope.engine); return @intCast(n); }
fn at(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue { return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index)))); }
fn append(scope: *Scope, array: c.JSValue, value: c.JSValue) !void { try scope.index(array, @intCast(try arrayLength(scope, array)), value); }
fn isCode(scope: *Scope, reason: c.JSValue, value: []const u8) !bool { return !core.nullish(reason) and scope.equal(try scope.get(reason, "code"), try scope.text(value)); }
fn finish(scope: *Scope, record: c.JSValue, reason: c.JSValue, decrement: bool) !void {
    var pending: i64 = 0; if (c.JS_ToInt64(scope.engine.context, &pending, try scope.get(record, "pending")) < 0) return js.capture(scope.engine);
    if (decrement) { pending -= 1; try scope.put(record, "pending", c.JS_NewInt64(scope.engine.context, pending)); }
    const final = decrement and pending == 0;
    const previous = try scope.get(record, "error");
    if (scope.truthy(reason) and (!scope.truthy(previous) or try isCode(scope, previous, "ERR_STREAM_PREMATURE_CLOSE"))) try scope.put(record, "error", reason);
    const failure = try scope.get(record, "error"); if (!scope.truthy(failure) and !final) return;
    const destroys = try scope.get(record, "destroys");
    const length = try arrayLength(scope, destroys);
    for (0..length) |i| {
        const item = try at(scope, destroys, i);
        if (!try flag(scope, item, "finished")) {
            try setFlag(scope, item, "finished", true);
            const err = if (scope.truthy(failure)) failure else try scope.own(try core.errorValue(scope, "Error", "ERR_STREAM_DESTROYED", "Cannot call pipe after a stream was destroyed"));
            _ = try scope.invoke(try scope.get(item, "stream"), "destroy", &.{err});
        }
    }
    if (!try flag(scope, record, "signalRemoved")) {
        try setFlag(scope, record, "signalRemoved", true); const signal = try scope.get(record, "signal");
        if (!core.nullish(signal)) { var id: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &id, try scope.get(record, "signalId")) < 0) return js.capture(scope.engine); try abort.removeNativeListener(scope.engine, signal, id); }
    }
    if (final and !try flag(scope, record, "callbackQueued")) {
        try setFlag(scope, record, "callbackQueued", true);
        if (!scope.truthy(failure)) { const cleanups = try scope.get(record, "lastCleanups"); for (0..try arrayLength(scope, cleanups)) |i| _ = try scope.call(try at(scope, cleanups, i), c.pi_js_undefined(), &.{}); }
        try core.tick(scope, try handler(scope, record, .callback_tick), &.{});
    }
}
fn optionsFor(scope: *Scope, readable: bool, writable: bool) !c.JSValue { const options = try object(scope); try scope.put(options, "readable", c.pi_js_bool(scope.engine.context, @intFromBool(readable))); try scope.put(options, "writable", c.pi_js_bool(scope.engine.context, @intFromBool(writable))); return options; }
fn setup(scope: *Scope, args: []const c.JSValue, record: c.JSValue, promise_mode: bool) !c.JSValue {
    var count = args.len; var cb = c.pi_js_undefined(); var signal = c.pi_js_undefined(); var end_option = c.pi_js_undefined();
    if (!promise_mode) {
        if (count == 0 or !c.JS_IsFunction(scope.engine.context, args[count - 1])) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The last argument must be of type function");
        count -= 1; cb = args[count];
    } else if (count > 0 and c.JS_IsObject(args[count - 1]) and !c.JS_IsArray(args[count - 1])) {
        const last = args[count - 1];
        if (try core.state(scope, last, .readable) == null and try core.state(scope, last, .writable) == null) {
            // The original Promise executor observes signal before end.
            signal = try scope.get(last, "signal"); end_option = try scope.get(last, "end"); count -= 1;
        }
    }
    const streams = try scope.array();
    if (count == 1 and c.JS_IsArray(args[0])) { count = try arrayLength(scope, args[0]); for (0..count) |i| try scope.index(streams, @intCast(i), try at(scope, args[0], i)); }
    else for (args[0..count], 0..) |stream, i| try scope.index(streams, @intCast(i), stream);
    if (count < 2) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_MISSING_ARGS", "The \"streams\" argument must be specified");
    try scope.put(record, "streams", streams); try scope.put(record, "callback", cb); try scope.put(record, "error", c.pi_js_undefined()); try scope.put(record, "pending", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(record, "destroys", try scope.array()); try scope.put(record, "lastCleanups", try scope.array()); try setFlag(scope, record, "callbackQueued", false); try setFlag(scope, record, "promise", promise_mode); try setFlag(scope, record, "signalRemoved", false); try scope.put(record, "signal", signal);
    if (!core.nullish(signal)) {
        if (c.JS_GetOpaque(signal, scope.engine.abort_signal_class) == null) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"options.signal\" property must be an instance of AbortSignal");
        const id = try abort.addNativeListener(scope.engine, signal, try handler(scope, record, .aborted)); try scope.put(record, "signalId", c.JS_NewUint32(scope.engine.context, id));
    }
    for (0..count) |i| {
        const stream = try at(scope, streams, i); const reading = i + 1 < count; const writing = i > 0; const end = reading or !scope.equal(end_option, c.pi_js_bool(scope.engine.context, 0));
        const r = try core.state(scope, stream, .readable); const w = try core.state(scope, stream, .writable);
        if ((reading and r == null) or (writing and w == null)) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "This native pipeline requires genuine Node readable and writable stages");
        if (reading) { const next = try at(scope, streams, i + 1); if (scope.truthy(try scope.get(next, "closed")) or scope.truthy(try scope.get(next, "destroyed"))) return @import("node_events.zig").codedError(scope.engine, "Error", "ERR_STREAM_UNABLE_TO_PIPE", "Cannot pipe to a closed or destroyed stream"); }
        if (end) {
            const item = try object(scope); try scope.put(item, "stream", stream); try setFlag(scope, item, "finished", false);
            _ = try scope.invoke(stream, "on", &.{ try scope.text("close"), try handler(scope, item, .destroy_close) });
            const cleanup = try scope.own(try life.eos(scope.engine, stream, try optionsFor(scope, reading, writing), try handler(scope, item, .destroy_eos)));
            try append(scope, try scope.get(record, "destroys"), item);
            if (r != null and r.?.enabled and !reading) try append(scope, try scope.get(record, "lastCleanups"), cleanup);
        }
        _ = try scope.invoke(stream, "on", &.{ try scope.text("error"), try handler(scope, record, .on_error) });
        if (i == 0) continue;
        const src = try at(scope, streams, i - 1); const pair = try object(scope); try scope.put(pair, "pipeline", record); try scope.put(pair, "source", src); try scope.put(pair, "destination", stream); try setFlag(scope, pair, "ended", false);
        var pending: i64 = 0; if (c.JS_ToInt64(scope.engine.context, &pending, try scope.get(record, "pending")) < 0) return js.capture(scope.engine); try scope.put(record, "pending", c.JS_NewInt64(scope.engine.context, pending + 2));
        _ = try scope.invoke(stream, "on", &.{ try scope.text("close"), try handler(scope, pair, .pipe_close) });
        const pipe_options = try object(scope); try scope.put(pipe_options, "end", c.pi_js_bool(scope.engine.context, 0)); _ = try scope.invoke(src, "pipe", &.{ stream, pipe_options });
        if (end) {
            const source_state = (try core.state(scope, src, .readable)).?; const end_fn = try handler(scope, pair, .pipe_end);
            if (source_state.end_emitted) try core.tick(scope, end_fn, &.{}) else _ = try scope.invoke(src, "once", &.{ try scope.text("end"), end_fn });
        } else try finish(scope, record, c.pi_js_undefined(), true);
        _ = try scope.own(try life.eos(scope.engine, src, try optionsFor(scope, true, false), try handler(scope, pair, .source_done)));
        const cleanup = try scope.own(try life.eos(scope.engine, stream, try optionsFor(scope, false, true), try handler(scope, record, .destination_done)));
        if (r != null and r.?.enabled and !reading) try append(scope, try scope.get(record, "lastCleanups"), cleanup);
    }
    if (!core.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) try core.tick(scope, try handler(scope, record, .aborted), &.{});
    return c.JS_DupValue(scope.engine.context, try at(scope, streams, count - 1));
}
pub fn pipeline(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const record = try object(&scope); const promise_mode = scope.truthy(roots[0]);
    if (!promise_mode) return setup(&scope, args, record, false);
    var functions: [2]c.JSValue = undefined; const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions))); defer for (functions) |value| engine.freeValue(value);
    try scope.put(record, "resolve", functions[0]); try scope.put(record, "reject", functions[1]);
    const returned = setup(&scope, args, record, true) catch |err| {
        if (err != error.JavaScriptException) return err;
        _ = try scope.call(functions[1], c.pi_js_undefined(), &.{engine.captured_exception.?}); return c.JS_DupValue(engine.context, promise);
    }; engine.freeValue(returned); return c.JS_DupValue(engine.context, promise);
}
fn event(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const record = roots[0]; var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine); const op: Op = @enumFromInt(raw); const reason = core.arg(args, 0);
    switch (op) {
        .destroy_close => try setFlag(&scope, record, "finished", true),
        .destroy_eos => try setFlag(&scope, record, "finished", !scope.truthy(reason)),
        .on_error => if (scope.truthy(reason) and !scope.equal(try scope.get(reason, "name"), try scope.text("AbortError")) and !try isCode(&scope, reason, "ERR_STREAM_PREMATURE_CLOSE")) { try finish(&scope, record, reason, false); },
        .pipe_close => if (!try flag(&scope, record, "ended")) { const failure = try scope.own(try core.errorValue(&scope, "Error", "ERR_STREAM_PREMATURE_CLOSE", "Premature close")); try finish(&scope, try scope.get(record, "pipeline"), failure, false); },
        .pipe_end => { try setFlag(&scope, record, "ended", true); _ = try scope.invoke(try scope.get(record, "destination"), "end", &.{}); },
        .source_done => {
            const src = try scope.get(record, "source"); const r = try core.state(&scope, src, .readable); const pipeline_record = try scope.get(record, "pipeline");
            if (try isCode(&scope, reason, "ERR_STREAM_PREMATURE_CLOSE") and r != null and r.?.ended and core.nullish(r.?.error_value) and !r.?.error_emitted) {
                const cb = try handler(&scope, pipeline_record, .finish); _ = try scope.invoke(src, "once", &.{ try scope.text("end"), cb }); _ = try scope.invoke(src, "once", &.{ try scope.text("error"), cb });
            } else try finish(&scope, pipeline_record, reason, true);
        },
        .destination_done, .finish => try finish(&scope, record, reason, true),
        .callback_tick => { const failure = try scope.get(record, "error"); if (try flag(&scope, record, "promise")) _ = try scope.call(try scope.get(record, if (scope.truthy(failure)) "reject" else "resolve"), c.pi_js_undefined(), if (scope.truthy(failure)) &.{failure} else &.{c.pi_js_undefined()}) else _ = try scope.call(try scope.get(record, "callback"), c.pi_js_undefined(), &.{ failure, c.pi_js_undefined() }); },
        .aborted => { const failure = try scope.own(try core.errorValue(&scope, "Error", "ABORT_ERR", "The operation was aborted")); try scope.put(failure, "name", try scope.text("AbortError")); try scope.put(failure, "cause", try scope.get(try scope.get(record, "signal"), "reason")); try finish(&scope, record, failure, false); },
    }
    return c.pi_js_undefined();
}
