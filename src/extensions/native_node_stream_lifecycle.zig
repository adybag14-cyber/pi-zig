//! Classic Node pipe/EOS/pipeline lifecycle over the actual Node stream state.
//! Transport retirement remains in the producer's _destroy hook. No child
//! process exit is converted into a stream EOF, and no timer pads settlement.
const core = @import("native_node_stream.zig");
const std = core.std; const em = core.em; const js = core.js; const Scope = core.Scope; const c = core.c;
const fnc = @import("native_node_function.zig");
const abort = @import("abort_signal.zig");
const Event = enum(c_int) { pipe_data, pipe_drain, pipe_end, pipe_close, pipe_error, pipe_unpipe, eos_end, eos_finish, eos_close, eos_error, eos_initial, eos_cleanup, promise_done, aborted, abort_cleanup };
fn private(scope: *Scope) !c.JSValue { return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null()))); }
fn handler(scope: *Scope, record: c.JSValue, op: Event, name: [*:0]const u8) !c.JSValue { return scope.own(try fnc.create(scope.engine, name, 1, event, &.{ record, c.JS_NewInt32(scope.engine.context, @intFromEnum(op)) })); }
fn flag(scope: *Scope, record: c.JSValue, key: [*:0]const u8) !bool { return scope.truthy(try scope.get(record, key)); }
fn setFlag(scope: *Scope, record: c.JSValue, key: [*:0]const u8, value: bool) !void { try scope.set(record, key, c.pi_js_bool(scope.engine.context, @intFromBool(value))); }
fn remove(scope: *Scope, stream: c.JSValue, name: []const u8, callback: c.JSValue) !void { _ = try scope.invoke(stream, "removeListener", &.{ try scope.text(name), callback }); }
fn pipeCleanup(scope: *Scope, record: c.JSValue) !void {
    if (try flag(scope, record, "cleaned")) return;
    try setFlag(scope, record, "cleaned", true);
    const src = try scope.get(record, "source"); const dest = try scope.get(record, "destination");
    inline for (.{ "data", "end", "close" }, .{ "ondata", "onend", "onsourceclose" }) |name, key| try remove(scope, src, name, try scope.get(record, key));
    inline for (.{ "drain", "close", "finish", "error", "unpipe" }, .{ "ondrain", "onclose", "onfinish", "onerror", "onunpipe" }) |name, key| try remove(scope, dest, name, try scope.get(record, key));
    if (try core.state(scope, src, .readable)) |s| {
        for (s.pipes.items, 0..) |item, i| if (scope.equal(item, record)) { scope.engine.freeValue(s.pipes.orderedRemove(i)); break; };
        if (try flag(scope, record, "waiting")) { try setFlag(scope, record, "waiting", false); if (s.await_drain_writers > 0) s.await_drain_writers -= 1; }
    }
}
fn unpipeOne(scope: *Scope, record: c.JSValue) !void {
    if (try flag(scope, record, "cleaned")) return;
    const src = try scope.get(record, "source"); const dest = try scope.get(record, "destination");
    const info = try scope.object(); try scope.put(info, "hasUnpiped", c.pi_js_bool(scope.engine.context, 0));
    try core.emit(scope, dest, "unpipe", &.{ src, info });
    if (!try flag(scope, record, "cleaned")) try pipeCleanup(scope, record);
}
fn pipe(engine: *em.Engine, source: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const dest = core.arg(args, 0); const options = core.arg(args, 1);
    const record = try private(&scope); try scope.put(record, "source", source); try scope.put(record, "destination", dest); try setFlag(&scope, record, "cleaned", false); try setFlag(&scope, record, "waiting", false);
    const process = try scope.get(try core.owner(engine), "process");
    const do_end = !scope.equal(try core.optional(&scope, options, "end"), c.pi_js_bool(engine.context, 0)) and !scope.equal(dest, try scope.get(process, "stdout")) and !scope.equal(dest, try scope.get(process, "stderr"));
    try setFlag(&scope, record, "endDestination", do_end);
    inline for (.{ "ondata", "ondrain", "onend", "onsourceclose", "onclose", "onfinish", "onerror", "onunpipe" }, .{ Event.pipe_data, Event.pipe_drain, Event.pipe_end, Event.pipe_close, Event.pipe_close, Event.pipe_close, Event.pipe_error, Event.pipe_unpipe }) |name, op| try scope.put(record, name, try handler(&scope, record, op, name));
    if (try core.state(&scope, source, .readable)) |s| try s.pipes.append(engine.gpa, c.JS_DupValue(engine.context, record));
    _ = try scope.invoke(dest, "on", &.{ try scope.text("unpipe"), try scope.get(record, "onunpipe") });
    _ = try scope.invoke(dest, "on", &.{ try scope.text("drain"), try scope.get(record, "ondrain") });
    _ = try scope.invoke(dest, "prependListener", &.{ try scope.text("error"), try scope.get(record, "onerror") });
    _ = try scope.invoke(dest, "once", &.{ try scope.text("close"), try scope.get(record, "onclose") });
    _ = try scope.invoke(dest, "once", &.{ try scope.text("finish"), try scope.get(record, "onfinish") });
    _ = try scope.invoke(source, "once", &.{ try scope.text("close"), try scope.get(record, "onsourceclose") });
    const r = try core.state(&scope, source, .readable);
    if (r != null and r.?.end_emitted) try core.tick(&scope, try scope.get(record, "onend"), &.{}) else _ = try scope.invoke(source, "once", &.{ try scope.text("end"), try scope.get(record, "onend") });
    _ = try scope.invoke(source, "on", &.{ try scope.text("data"), try scope.get(record, "ondata") });
    try core.emit(&scope, dest, "pipe", &.{source});
    if (r != null and r.?.flowing != true) _ = try scope.invoke(source, "resume", &.{});
    return c.JS_DupValue(engine.context, dest);
}
fn unpipe(engine: *em.Engine, source: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const s = (try core.state(&scope, source, .readable)) orelse return c.JS_DupValue(engine.context, source);
    const dest = core.arg(args, 0);
    var records: std.ArrayList(c.JSValue) = .empty; defer { for (records.items) |value| engine.freeValue(value); records.deinit(engine.gpa); }
    for (s.pipes.items) |record| if (!scope.truthy(dest) or scope.equal(try scope.get(record, "destination"), dest)) try records.append(engine.gpa, c.JS_DupValue(engine.context, record));
    if (records.items.len > 0 and (records.items.len == s.pipes.items.len)) _ = try scope.invoke(source, "pause", &.{});
    for (records.items) |record| try unpipeOne(&scope, record);
    return c.JS_DupValue(engine.context, source);
}
fn eosComplete(scope: *Scope, record: c.JSValue, reason: c.JSValue) !void {
    if (try flag(scope, record, "done")) return;
    try setFlag(scope, record, "done", true);
    const stream = try scope.get(record, "stream");
    _ = try scope.call(try scope.get(record, "callback"), stream, if (scope.truthy(reason)) &.{reason} else &.{});
}
fn eosCleanup(scope: *Scope, record: c.JSValue) !void {
    const stream = try scope.get(record, "stream");
    inline for (.{ "end", "finish", "close", "error" }, .{ "onend", "onfinish", "onclose", "onerror" }) |name, key| try remove(scope, stream, name, try scope.get(record, key));
}
pub fn eos(engine: *em.Engine, stream: c.JSValue, options: c.JSValue, cb: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (!c.JS_IsFunction(engine.context, cb)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"callback\" argument must be of type function");
    const r = try core.state(&scope, stream, .readable); const w = try core.state(&scope, stream, .writable);
    const record = try private(&scope); try scope.put(record, "stream", stream); try scope.put(record, "callback", cb); try setFlag(&scope, record, "done", false);
    const read_option = try core.optional(&scope, options, "readable"); const write_option = try core.optional(&scope, options, "writable");
    try setFlag(&scope, record, "readable", if (!core.nullish(read_option)) scope.truthy(read_option) else r != null and r.?.enabled);
    try setFlag(&scope, record, "writable", if (!core.nullish(write_option)) scope.truthy(write_option) else w != null and w.?.enabled);
    try setFlag(&scope, record, "readDone", r == null or r.?.end_emitted);
    try setFlag(&scope, record, "writeDone", w == null or w.?.finished);
    try setFlag(&scope, record, "waitClose", (r != null or w != null) and (r == null or (r.?.auto_destroy and r.?.emit_close)) and (w == null or (w.?.auto_destroy and w.?.emit_close)));
    inline for (.{ "onend", "onfinish", "onclose", "onerror" }, .{ Event.eos_end, Event.eos_finish, Event.eos_close, Event.eos_error }) |name, op| try scope.put(record, name, try handler(&scope, record, op, name));
    inline for (.{ "end", "finish", "close" }, .{ "onend", "onfinish", "onclose" }) |name, key| _ = try scope.invoke(stream, "on", &.{ try scope.text(name), try scope.get(record, key) });
    if (!scope.equal(try core.optional(&scope, options, "error"), c.pi_js_bool(engine.context, 0))) _ = try scope.invoke(stream, "on", &.{ try scope.text("error"), try scope.get(record, "onerror") });
    const cleanup = try handler(&scope, record, .eos_cleanup, "cleanup");
    if ((r != null and r.?.closed) or (w != null and w.?.closed) or ((!try flag(&scope, record, "readable") or try flag(&scope, record, "readDone")) and (!try flag(&scope, record, "writable") or try flag(&scope, record, "writeDone")))) try core.tick(&scope, try handler(&scope, record, .eos_initial, "onclosed"), &.{});
    return c.JS_DupValue(engine.context, cleanup);
}
fn makePromise(scope: *Scope, record: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try scope.own(try scope.engine.checked(c.JS_NewPromiseCapability(scope.engine.context, &functions)));
    defer for (functions) |value| scope.engine.freeValue(value);
    try scope.put(record, "resolve", functions[0]); try scope.put(record, "reject", functions[1]);
    return promise;
}
fn finished(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (!scope.truthy(roots[0])) {
        const opts = if (c.JS_IsFunction(engine.context, core.arg(args, 1))) c.pi_js_undefined() else core.arg(args, 1);
        return eos(engine, core.arg(args, 0), opts, if (c.JS_IsFunction(engine.context, core.arg(args, 1))) core.arg(args, 1) else core.arg(args, 2));
    }
    const cleanup_option = try core.optional(&scope, core.arg(args, 1), "cleanup");
    if (!c.JS_IsUndefined(cleanup_option) and !c.JS_IsBool(cleanup_option)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"cleanup\" argument must be of type boolean");
    const record = try private(&scope); try setFlag(&scope, record, "settled", false); try setFlag(&scope, record, "cleanupAfter", scope.truthy(cleanup_option));
    const promise = try makePromise(&scope, record);
    const cb = try handler(&scope, record, .promise_done, "");
    const cleanup = eos(engine, core.arg(args, 0), core.arg(args, 1), cb) catch |err| {
        if (err != error.JavaScriptException) return err; _ = try scope.call(try scope.get(record, "reject"), c.pi_js_undefined(), &.{engine.captured_exception.?}); return c.JS_DupValue(engine.context, promise);
    };
    defer engine.freeValue(cleanup); try scope.put(record, "cleanup", cleanup);
    return c.JS_DupValue(engine.context, promise);
}
fn pipeline(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return @import("native_node_stream_pipeline.zig").pipeline(engine, receiver, args, roots);
}
pub fn addAbortSignal(engine: *em.Engine, signal: c.JSValue, stream: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (c.JS_GetOpaque(signal, engine.abort_signal_class) == null) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"signal\" argument must be an instance of AbortSignal");
    const record = try private(&scope); try scope.put(record, "stream", stream); try scope.put(record, "signal", signal); try setFlag(&scope, record, "removed", false);
    const callback = try handler(&scope, record, .aborted, "onAbort");
    if (scope.truthy(try scope.get(signal, "aborted"))) _ = try scope.call(callback, c.pi_js_undefined(), &.{})
    else { const id = try abort.addNativeListener(engine, signal, callback); try scope.put(record, "listenerId", c.JS_NewUint32(engine.context, id)); _ = try scope.invoke(stream, "once", &.{ try scope.text("close"), try handler(&scope, record, .abort_cleanup, "dispose") }); }
    return c.JS_DupValue(engine.context, stream);
}
fn event(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const record = roots[0]; var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return js.capture(engine); const op: Event = @enumFromInt(raw);
    switch (op) {
        .pipe_data => {
            if (try flag(&scope, record, "cleaned")) return c.pi_js_undefined(); const dest = try scope.get(record, "destination"); const src = try scope.get(record, "source");
            const ret = scope.invoke(dest, "write", &.{core.arg(args, 0)}) catch |err| { if (err != error.JavaScriptException) return err; _ = try scope.invoke(dest, "destroy", &.{engine.captured_exception.?}); return c.pi_js_undefined(); };
            if (scope.equal(ret, c.pi_js_bool(engine.context, 0))) { if (!try flag(&scope, record, "waiting") and !try flag(&scope, record, "cleaned")) { try setFlag(&scope, record, "waiting", true); if (try core.state(&scope, src, .readable)) |s| s.await_drain_writers += 1; } _ = try scope.invoke(src, "pause", &.{}); }
        },
        .pipe_drain => {
            const src = try scope.get(record, "source"); if (try core.state(&scope, src, .readable)) |s| { if (try flag(&scope, record, "waiting")) { try setFlag(&scope, record, "waiting", false); if (s.await_drain_writers > 0) s.await_drain_writers -= 1; } if (s.await_drain_writers == 0 and scope.truthy(try scope.invoke(src, "listenerCount", &.{try scope.text("data")}))) _ = try scope.invoke(src, "resume", &.{}); }
        },
        .pipe_end => { if (!try flag(&scope, record, "cleaned") and try flag(&scope, record, "endDestination")) _ = try scope.invoke(try scope.get(record, "destination"), "end", &.{}); },
        .pipe_close => try unpipeOne(&scope, record),
        .pipe_error => { const dest = try scope.get(record, "destination"); try unpipeOne(&scope, record); if (!scope.truthy(try scope.invoke(dest, "listenerCount", &.{try scope.text("error")}))) try core.emit(&scope, dest, "error", &.{core.arg(args, 0)}); },
        .pipe_unpipe => { if (scope.equal(core.arg(args, 0), try scope.get(record, "source"))) { const info = core.arg(args, 1); if (core.nullish(info) or !scope.truthy(try scope.get(info, "hasUnpiped"))) { if (!core.nullish(info)) try setFlag(&scope, info, "hasUnpiped", true); try pipeCleanup(&scope, record); } } },
        .eos_cleanup => try eosCleanup(&scope, record),
        .eos_end, .eos_finish, .eos_close, .eos_error, .eos_initial => {
            const stream = try scope.get(record, "stream"); const r = try core.state(&scope, stream, .readable); const w = try core.state(&scope, stream, .writable);
            if (op == .eos_error) { try eosComplete(&scope, record, core.arg(args, 0)); return c.pi_js_undefined(); }
            if (op == .eos_end) try setFlag(&scope, record, "readDone", true); if (op == .eos_finish) try setFlag(&scope, record, "writeDone", true);
            const closed = op == .eos_close or (r != null and r.?.closed) or (w != null and w.?.closed);
            if (closed) {
                const reason = if (w != null and !core.nullish(w.?.error_value)) w.?.error_value else if (r != null and !core.nullish(r.?.error_value)) r.?.error_value else c.pi_js_null();
                if (!core.nullish(reason)) try eosComplete(&scope, record, reason)
                else if ((try flag(&scope, record, "readable") and !try flag(&scope, record, "readDone") and r != null and !(r.?.ended and r.?.length == 0)) or (try flag(&scope, record, "writable") and !try flag(&scope, record, "writeDone") and w != null and !(w.?.ended and w.?.length == 0))) { const err = try scope.own(try core.errorValue(&scope, "Error", "ERR_STREAM_PREMATURE_CLOSE", "Premature close")); try eosComplete(&scope, record, err); }
                else try eosComplete(&scope, record, c.pi_js_null());
            } else {
                if (scope.truthy(try scope.get(stream, "destroyed"))) try setFlag(&scope, record, "waitClose", false);
                const read_done = !try flag(&scope, record, "readable") or try flag(&scope, record, "readDone"); const write_done = !try flag(&scope, record, "writable") or try flag(&scope, record, "writeDone");
                const waiting = try flag(&scope, record, "waitClose") and ((op == .eos_end and (!scope.truthy(try scope.get(stream, "writable")) or try flag(&scope, record, "writable"))) or (op == .eos_finish and (!scope.truthy(try scope.get(stream, "readable")) or try flag(&scope, record, "readable"))));
                if (read_done and write_done and !waiting) try eosComplete(&scope, record, c.pi_js_null());
            }
        },
        .promise_done => { if (!try flag(&scope, record, "settled")) { try setFlag(&scope, record, "settled", true); if (try flag(&scope, record, "cleanupAfter")) _ = try scope.call(try scope.get(record, "cleanup"), c.pi_js_undefined(), &.{}); const reason = core.arg(args, 0); _ = try scope.call(try scope.get(record, if (scope.truthy(reason)) "reject" else "resolve"), c.pi_js_undefined(), if (scope.truthy(reason)) &.{reason} else &.{}); } },
        .aborted => { const err = try scope.own(try core.errorValue(&scope, "Error", "ABORT_ERR", "The operation was aborted")); try scope.put(err, "name", try scope.text("AbortError")); try scope.put(err, "cause", try scope.get(try scope.get(record, "signal"), "reason")); _ = try scope.invoke(try scope.get(record, "stream"), "destroy", &.{err}); },
        .abort_cleanup => { if (!try flag(&scope, record, "removed")) { try setFlag(&scope, record, "removed", true); var id: u32 = 0; if (c.JS_ToUint32(engine.context, &id, try scope.get(record, "listenerId")) < 0) return js.capture(engine); try abort.removeNativeListener(engine, try scope.get(record, "signal"), id); } },
    }
    return c.pi_js_undefined();
}
fn predicate(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const name = try engine.toString(roots[0]); defer engine.gpa.free(name); const stream = core.arg(args, 0);
    if (!c.JS_IsObject(stream)) return c.pi_js_bool(engine.context, 0);
    const r = try core.state(&scope, stream, .readable); const w = try core.state(&scope, stream, .writable);
    const value = if (std.mem.eql(u8, name, "isDestroyed")) (r != null and r.?.destroyed) or (w != null and w.?.destroyed)
        else if (std.mem.eql(u8, name, "isErrored")) (r != null and !core.nullish(r.?.error_value)) or (w != null and !core.nullish(w.?.error_value))
        else if (std.mem.eql(u8, name, "isReadable")) r != null and r.?.enabled and !r.?.destroyed and !r.?.ended
        else if (std.mem.eql(u8, name, "isWritable")) w != null and w.?.enabled and !w.?.destroyed and !w.?.ending
        else r != null and (r.?.data_emitted or r.?.destroyed);
    return c.pi_js_bool(engine.context, @intFromBool(value));
}
fn hwm(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const key: [*:0]const u8 = if (scope.truthy(core.arg(args, 0))) "objectHwm" else "byteHwm";
    if (scope.truthy(roots[0])) {
        const value = core.arg(args, 1); var number: f64 = 0;
        if (!c.JS_IsNumber(value)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"value\" argument must be of type number");
        if (c.JS_ToFloat64(engine.context, &number, value) < 0) return js.capture(engine);
        if (!std.math.isFinite(number) or number < 0 or number != @floor(number) or number > 9007199254740991) return @import("node_events.zig").codedError(engine, "RangeError", "ERR_OUT_OF_RANGE", "The value of \"value\" is out of range");
        try scope.put(try core.owner(engine), key, value); return c.pi_js_undefined();
    }
    return js.get(engine, try core.owner(engine), key);
}
fn abortFunction(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return addAbortSignal(engine, core.arg(args, 0), core.arg(args, 1)); }
/// Classic native branch of internal destroyer, used by iterator finally.
/// Early return aborts an unfinished stream; natural EOF does not manufacture
/// another error. Stream destruction remains separate from process signaling.
pub fn destroyer(engine: *em.Engine, stream: c.JSValue, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    if (!scope.truthy(stream) or scope.truthy(try scope.get(stream, "destroyed"))) return;
    var selected = reason;
    if (!scope.truthy(selected) and (scope.truthy(try scope.get(stream, "readable")) or scope.truthy(try scope.get(stream, "writable")))) {
        selected = try scope.own(try core.errorValue(&scope, "Error", "ABORT_ERR", "The operation was aborted")); try scope.set(selected, "name", try scope.text("AbortError"));
    }
    _ = try scope.invoke(stream, "destroy", &.{selected});
}
pub fn install(engine: *em.Engine, module: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const readable = try scope.get(try scope.get(module, "Readable"), "prototype"); const base = try scope.get(module, "StreamPrototype");
    const pipe_fn = try scope.own(try fnc.create(engine, "pipe", 2, pipe, &.{})); try scope.put(readable, "pipe", pipe_fn); try @import("native_node_stream_legacy_pipe.zig").install(engine, base); try scope.put(readable, "unpipe", try scope.own(try fnc.create(engine, "unpipe", 1, unpipe, &.{})));
    try scope.put(module, "pipeline", try scope.own(try fnc.create(engine, "pipeline", 0, pipeline, &.{c.pi_js_bool(engine.context, 0)}))); try scope.put(module, "finished", try scope.own(try fnc.create(engine, "eos", 3, finished, &.{c.pi_js_bool(engine.context, 0)})));
    try scope.put(module, "addAbortSignal", try scope.own(try fnc.create(engine, "addAbortSignal", 2, abortFunction, &.{})));
    inline for (.{ "isDestroyed", "isErrored", "isReadable", "isWritable", "isDisturbed" }) |name| try scope.put(module, name, try scope.own(try fnc.create(engine, name, 1, predicate, &.{try scope.text(name)})));
    try scope.put(module, "getDefaultHighWaterMark", try scope.own(try fnc.create(engine, "getDefaultHighWaterMark", 1, hwm, &.{c.pi_js_bool(engine.context, 0)}))); try scope.put(module, "setDefaultHighWaterMark", try scope.own(try fnc.create(engine, "setDefaultHighWaterMark", 2, hwm, &.{c.pi_js_bool(engine.context, 1)})));
    const promises = try scope.object(); try scope.put(promises, "finished", try scope.own(try fnc.create(engine, "finished", 2, finished, &.{c.pi_js_bool(engine.context, 1)}))); try scope.put(promises, "pipeline", try scope.own(try fnc.create(engine, "pipeline", 0, pipeline, &.{c.pi_js_bool(engine.context, 1)}))); try scope.put(module, "promises", promises);
    try engine.registerDefaultModule("node:stream/promises", promises); try engine.registerDefaultModule("stream/promises", promises);
}
