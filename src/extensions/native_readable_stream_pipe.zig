//! Actual native reader/writer pipe state. No transport worker or stream substitute.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const readable = @import("native_readable_byte_stream.zig");
const writable = @import("native_writable_stream.zig");
const signal_mod = @import("abort_signal.zig");
const c = js.c;
const Stage = enum(c_int) { ready, read, sourceClosed, destinationClosed, currentWrite, action, abortDestination, abortSource };
const Action = enum(i32) { none, close, abortDestination, cancelSource, abortBoth };
fn flag(scope: *Scope, data: c.JSValue, key: [*:0]const u8) !bool {
    return scope.truthy(try scope.get(data, key));
}
fn setFlag(scope: *Scope, data: c.JSValue, key: [*:0]const u8, value: bool) !void {
    try scope.put(data, key, c.pi_js_bool(scope.engine.context, @intFromBool(value)));
}
fn wait(scope: *Scope, data: c.JSValue, value: c.JSValue, stage: Stage) !void {
    const pending = try flow.create(scope.engine, data);
    defer scope.engine.freeValue(pending.owner);
    defer scope.engine.freeValue(pending.promise);
    c.JS_PromiseMarkAsHandled(scope.engine.context, pending.promise);
    if (stage == .currentWrite) try scope.put(pending.owner, "observedWrite", value);
    try flow.wait(continued, scope.engine, pending.owner, value, @intFromEnum(stage));
}
fn removeListener(engine: *js.Engine, data: c.JSValue) !void {
    const signal = try js.get(engine, data, "signal");
    defer engine.freeValue(signal);
    const id_value = try js.get(engine, data, "listenerId");
    defer engine.freeValue(id_value);
    if (c.JS_IsUndefined(signal) or c.JS_IsUndefined(id_value)) return;
    var id: u32 = 0;
    if (c.JS_ToUint32(engine.context, &id, id_value) < 0) return js.capture(engine);
    try signal_mod.removeNativeListener(engine, signal, id);
    try js.define(engine, data, "listenerId", c.pi_js_undefined());
}
fn finish(scope: *Scope, data: c.JSValue, rejected: bool, reason: c.JSValue) !void {
    if (try flag(scope, data, "finished")) return;
    try removeListener(scope.engine, data);
    const writer = try scope.get(data, "writer");
    if (!c.JS_IsUndefined(writer)) try writable.releaseWriterNative(scope.engine, writer);
    const reader = try scope.get(data, "reader");
    if (!c.JS_IsUndefined(reader)) try readable.releaseReaderNative(scope, try scope.get(data, "bindings"), reader);
    try setFlag(scope, data, "finished", true);
    try flow.settle(scope.engine, try scope.get(data, "owner"), rejected, if (rejected) reason else c.pi_js_undefined());
}
fn ready(scope: *Scope, data: c.JSValue) !void {
    if (try flag(scope, data, "shutting")) return;
    const promise = try scope.own(try writable.writerReadyNative(scope.engine, try scope.get(data, "writer")));
    try wait(scope, data, promise, .ready);
}
fn sourceFailure(scope: *Scope, data: c.JSValue, reason: c.JSValue) !void {
    try shutdown(scope, data, if (try flag(scope, data, "preventAbort")) .none else .abortDestination, true, reason);
}
fn destinationFailure(scope: *Scope, data: c.JSValue, reason: c.JSValue) !void {
    try shutdown(scope, data, if (try flag(scope, data, "preventCancel")) .none else .cancelSource, true, reason);
}
fn sourceClosed(scope: *Scope, data: c.JSValue) !void {
    try setFlag(scope, data, "sourceClosed", true);
    // readNative exposes a real read Promise, while Node's private Pipe read
    // request writes synchronously from kChunk. Defer EOF until that pending
    // result has recorded its write, so close never overtakes the final chunk.
    if (try flag(scope, data, "readPending")) return;
    try shutdown(scope, data, if (try flag(scope, data, "preventClose")) .none else .close, false, c.pi_js_undefined());
}
fn shutdown(scope: *Scope, data: c.JSValue, action: Action, rejected: bool, reason: c.JSValue) !void {
    if (try flag(scope, data, "shutting")) return;
    try setFlag(scope, data, "shutting", true);
    try setFlag(scope, data, "rejected", rejected);
    try scope.put(data, "reason", reason);
    try scope.put(data, "action", c.JS_NewInt32(scope.engine.context, @intFromEnum(action)));
    const destination = try scope.get(data, "destination");
    if (try writable.isWritableNative(scope.engine, destination) and !try writable.closeQueuedOrInFlightNative(scope.engine, destination)) {
        try wait(scope, data, try scope.get(data, "currentWrite"), .currentWrite);
    } else try runAction(scope, data);
}
fn runAction(scope: *Scope, data: c.JSValue) !void {
    var raw: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &raw, try scope.get(data, "action")) < 0) return js.capture(scope.engine);
    const action: Action = @enumFromInt(raw);
    const writer = try scope.get(data, "writer");
    const reason = try scope.get(data, "reason");
    const bindings = try scope.get(data, "bindings");
    const source = try scope.get(data, "source");
    if (action == .none) return finish(scope, data, try flag(scope, data, "rejected"), reason);
    if (action == .abortBoth) {
        // Invoke both actual actions before waiting for either. The first
        // rejection wins, matching Promise.all; both continuations stay rooted.
        try scope.put(data, "abortRemaining", c.JS_NewInt32(scope.engine.context, 2));
        const destination = try scope.get(data, "destination");
        const abort_dest = if (!try flag(scope, data, "preventAbort") and try writable.isWritableNative(scope.engine, destination)) try scope.own(try writable.writerAbortNative(scope.engine, writer, reason)) else c.pi_js_undefined();
        const abort_source = if (!try flag(scope, data, "preventCancel") and try readable.isReadableStateNative(scope, bindings, source)) try readable.cancelNative(scope, bindings, source, reason) else c.pi_js_undefined();
        try wait(scope, data, abort_dest, .abortDestination);
        try wait(scope, data, abort_source, .abortSource);
        return;
    }
    const promise = switch (action) {
        .close => try scope.own(try writable.closeWithErrorPropagationNative(scope.engine, writer)),
        .abortDestination => try scope.own(try writable.writerAbortNative(scope.engine, writer, reason)),
        .cancelSource => try readable.cancelNative(scope, bindings, source, reason),
        else => unreachable,
    };
    try wait(scope, data, promise, .action);
}
fn step(scope: *Scope, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !void {
    const data = try scope.get(owner, "agent");
    if (try flag(scope, data, "finished")) return;
    switch (stage) {
        .sourceClosed => {
            if (rejected) try sourceFailure(scope, data, value) else try sourceClosed(scope, data);
        },
        .destinationClosed => if (rejected) try destinationFailure(scope, data, value),
        .ready => {
            if (try flag(scope, data, "shutting")) return;
            // Source/destination close observers own shutdown; run() itself
            // does not replace their original rejection with a ready error.
            if (rejected) return;
            try setFlag(scope, data, "readPending", true);
            const promise = try readable.readNative(scope, try scope.get(data, "bindings"), try scope.get(data, "reader"), &.{});
            try wait(scope, data, promise, .read);
        },
        .read => {
            try setFlag(scope, data, "readPending", false);
            if (try flag(scope, data, "shutting")) return;
            if (rejected) return sourceFailure(scope, data, value);
            if (scope.truthy(try scope.get(value, "done"))) return sourceClosed(scope, data);
            const chunk = try scope.get(value, "value");
            const written = try scope.own(try writable.writerWriteNative(scope.engine, try scope.get(data, "writer"), chunk));
            c.JS_PromiseMarkAsHandled(scope.engine.context, written);
            try scope.put(data, "currentWrite", written);
            if (try flag(scope, data, "sourceClosed")) try sourceClosed(scope, data) else try ready(scope, data);
        },
        .currentWrite => {
            if (rejected) return finish(scope, data, true, value);
            const current = try scope.get(data, "currentWrite");
            if (!scope.equal(current, try scope.get(owner, "observedWrite"))) return wait(scope, data, current, .currentWrite);
            try runAction(scope, data);
        },
        .action => try finish(scope, data, rejected or try flag(scope, data, "rejected"), if (rejected) value else try scope.get(data, "reason")),
        .abortDestination, .abortSource => {
            if (rejected) return finish(scope, data, true, value);
            var remaining: i32 = 0;
            if (c.JS_ToInt32(scope.engine.context, &remaining, try scope.get(data, "abortRemaining")) < 0) return js.capture(scope.engine);
            remaining -= 1;
            try scope.put(data, "abortRemaining", c.JS_NewInt32(scope.engine.context, remaining));
            if (remaining == 0) try finish(scope, data, true, try scope.get(data, "reason"));
        },
    }
}
fn fatal(engine: *js.Engine, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    try fatalReason(engine, owner, reason);
}
fn fatalReason(engine: *js.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    const data = try js.get(engine, owner, "agent");
    defer engine.freeValue(data);
    const bindings = try js.get(engine, data, "bindings");
    defer engine.freeValue(bindings);
    const source = try js.get(engine, data, "source");
    defer engine.freeValue(source);
    try readable.errorStreamAfterHostFailure(engine, bindings, source, reason);
    const reader = try js.get(engine, data, "reader");
    defer engine.freeValue(reader);
    if (!c.JS_IsUndefined(reader)) try readable.releaseReaderAfterHostFailure(engine, bindings, reader);
    const writer = try js.get(engine, data, "writer");
    defer engine.freeValue(writer);
    const destination = try js.get(engine, data, "destination");
    defer engine.freeValue(destination);
    try writable.retireAfterHostFailureNative(engine, destination, reason);
    if (!c.JS_IsUndefined(writer)) writable.releaseWriterNative(engine, writer) catch {};
    try removeListener(engine, data);
    try js.define(engine, data, "finished", c.pi_js_bool(engine.context, 1));
    const external = try js.get(engine, data, "owner");
    defer engine.freeValue(external);
    try flow.settle(engine, external, true, reason);
}
fn continued(engine: *js.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    step(&scope, owner, value, rejected, @enumFromInt(raw)) catch |err| {
        if (err == error.OutOfMemory) {
            try fatal(engine, owner, err);
        } else {
            const reason = flow.reason(engine, err);
            defer engine.freeValue(reason);
            const data = try js.get(engine, owner, "agent");
            defer engine.freeValue(data);
            // Ordinary action failures keep the real stream cancellation/
            // abort state. Only host-failure cleanup forces capability retirement.
            finish(&scope, data, true, reason) catch try fatalReason(engine, owner, reason);
        }
    };
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn abortCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const data = roots[0];
    abortAlgorithm(&scope, data) catch |err| {
        const owner = js.get(engine, data, "owner") catch |failure| return @import("native_sdk.zig").fail(engine, failure);
        defer engine.freeValue(owner);
        fatal(engine, owner, err) catch |failure| return @import("native_sdk.zig").fail(engine, failure);
    };
    return c.pi_js_undefined();
}
fn abortAlgorithm(scope: *Scope, data: c.JSValue) !void {
    const signal = try scope.get(data, "signal");
    try shutdown(scope, data, .abortBoth, true, try scope.get(signal, "reason"));
}
pub const Options = struct { prevent_abort: bool = false, prevent_cancel: bool = false, prevent_close: bool = false, signal: c.JSValue };
pub fn start(scope: *Scope, bindings: c.JSValue, source: c.JSValue, destination: c.JSValue, options: Options) !c.JSValue {
    const data = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
    try scope.put(data, "bindings", bindings);
    try scope.put(data, "source", source);
    try scope.put(data, "destination", destination);
    try scope.put(data, "signal", options.signal);
    try setFlag(scope, data, "preventAbort", options.prevent_abort);
    try setFlag(scope, data, "preventCancel", options.prevent_cancel);
    try setFlag(scope, data, "preventClose", options.prevent_close);
    const external = try flow.create(scope.engine, data);
    defer scope.engine.freeValue(external.owner);
    // Root the returned capability before acquiring either real lock. A later
    // host root-growth failure must reach the same returned pipe capability.
    const promise = try scope.own(external.promise);
    try scope.put(data, "owner", external.owner);
    startOwned(scope, data, bindings, source, destination, options) catch |err| {
        if (err == error.OutOfMemory) {
            try fatal(scope.engine, external.owner, err);
        } else {
            const reason = flow.reason(scope.engine, err);
            defer scope.engine.freeValue(reason);
            finish(scope, data, true, reason) catch try fatalReason(scope.engine, external.owner, reason);
        }
    };
    return promise;
}
fn startOwned(scope: *Scope, data: c.JSValue, bindings: c.JSValue, source: c.JSValue, destination: c.JSValue, options: Options) !void {
    const reader = try readable.getReaderNative(scope, bindings, source, c.pi_js_undefined());
    try scope.put(data, "reader", reader);
    const writer = try writable.acquireWriterNative(scope.engine, destination);
    defer scope.engine.freeValue(writer);
    try scope.put(data, "writer", writer);
    try readable.markDisturbedNative(scope, bindings, source);
    if (!c.JS_IsUndefined(options.signal)) {
        if (scope.truthy(try scope.get(options.signal, "aborted"))) {
            try shutdown(scope, data, .abortBoth, true, try scope.get(options.signal, "reason"));
            return;
        }
        var roots = [_]c.JSValue{data};
        const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, abortCallback, "abortAlgorithm", 0, 0, roots.len, &roots)));
        const id = try signal_mod.addNativeListener(scope.engine, options.signal, callback);
        try scope.put(data, "listenerId", c.JS_NewUint32(scope.engine.context, id));
    }
    try ready(scope, data);
    const source_closed = try readable.closedNative(scope, bindings, reader);
    try wait(scope, data, source_closed, .sourceClosed);
    const destination_closed = try scope.own(try writable.writerClosedNative(scope.engine, writer));
    try wait(scope, data, destination_closed, .destinationClosed);
    if (try writable.closeQueuedOrInFlightNative(scope.engine, destination) or try writable.isClosedNative(scope.engine, destination)) {
        const err = @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_STATE", "Invalid state: Destination WritableStream is closed");
        const reason = flow.reason(scope.engine, err);
        defer scope.engine.freeValue(reason);
        try destinationFailure(scope, data, reason);
    }
}
