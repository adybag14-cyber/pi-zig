//! Actual method/schema call boundary and tracked invocation ownership.
const h = @import("native_chord_host_values.zig");
const r = @import("native_chord_object.zig");
const schema = @import("native_chord_object_schema.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
pub fn call(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, handle: c.JSValue, name: c.JSValue, input: c.JSValue, ctx: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, ctx, "check", &.{try s.get(record, "host")});
    const status = try s.get(handle, "status");
    if (try s.equal(status, "released") or try s.equal(status, "gone")) return h.throwValue(&s, try h.invoke(&s, handle, "terminalError", &.{}));
    const work = try r.workFor(&s, record, bindings);
    try h.field(&s, work, "handle", handle);
    try h.field(&s, work, "name", name);
    try h.field(&s, work, "input", input);
    try h.field(&s, work, "ctx", ctx);
    if (try s.equal(status, "loading")) return h.wait(invokeCall, engine, work, try s.keep(try raceSignal(engine, bindings, try s.get(handle, "ready"), try s.get(ctx, "signal"))), 0);
    return invokeCall(engine, work, c.pi_js_undefined(), false, 0);
}
fn invokeCall(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    const record = try s.get(work, "object");
    const bindings = try s.get(work, "bindings");
    const handle = try s.get(work, "handle");
    const name = try s.get(work, "name");
    const ctx = try s.get(work, "ctx");
    const status = try s.get(handle, "status");
    if (!try s.equal(status, "live") or !try s.equal(try s.get(record, "status"), "live")) return h.throwValue(&s, if (try s.equal(status, "live")) try h.errorValue(&s, bindings, "gone", &.{ try s.get(record, "address"), try s.text(" is "), try s.get(record, "status") }, c.pi_js_undefined()) else try h.invoke(&s, handle, "terminalError", &.{}));
    _ = try h.invoke(&s, record, "admit", &.{ctx});
    const epoch = try s.get(ctx, "codeVersion");
    const installed = try h.invoke(&s, try s.get(record, "implementations"), "get", &.{epoch});
    if (c.JS_IsUndefined(installed)) return h.throwValue(&s, try h.errorValue(&s, bindings, "superseded", &.{ try s.get(record, "address"), try s.text(" has no implementation for code version "), epoch }, c.pi_js_undefined()));
    const view = try h.invoke(&s, handle, "viewOf", &.{installed});
    const raw_kind = try s.get(view, "variant");
    const kind = if (c.JS_IsString(raw_kind)) raw_kind else c.pi_js_undefined();
    const remote = try s.equal(try s.get(try s.get(handle, "contract"), "scope"), "remote");
    const wanted = try h.invoke(&s, handle, "describe", &.{ if (remote) kind else try s.text(""), name });
    const function = try s.key(view, name);
    if (!c.JS_IsFunction(engine.context, function) or (remote and (h.nullish(wanted) or !try s.equal(try s.get(wanted, "kind"), "method")))) return h.throwValue(&s, try h.errorValue(&s, bindings, "not_in_variant", &.{ try s.get(record, "address"), try s.text(": "), name, try s.text(" is not a method of variant "), if (h.nullish(kind)) try s.text("(local)") else kind }, c.pi_js_undefined()));
    const direct = c.JS_IsStrictEqual(engine.context, view, try s.get(installed, "implementation"));
    const variants = try s.get(try s.get(try s.get(try s.get(installed, "service"), "contract"), "description"), "variants");
    const members = if (direct) try s.key(variants, if (h.nullish(kind)) try s.text("") else kind) else c.pi_js_undefined();
    const description = if (!direct) wanted else if (h.nullish(members)) c.pi_js_undefined() else try s.key(members, name);
    const method = if (!h.nullish(description) and try s.equal(try s.get(description, "kind"), "method")) description else c.pi_js_undefined();
    const takes_args = c.JS_IsUndefined(method) or !c.JS_IsUndefined(try s.get(method, "args"));
    const returns = c.JS_IsUndefined(method) or !c.JS_IsUndefined(try s.get(method, "result"));
    const validated = remote and !c.JS_IsUndefined(method);
    var cleaned = c.pi_js_undefined();
    const args_schema = if (validated) try s.get(method, "args") else c.pi_js_undefined();
    if (takes_args) {
        const own = if (remote and !h.nullish(wanted) and try s.equal(try s.get(wanted, "kind"), "method")) try s.get(wanted, "args") else c.pi_js_undefined();
        const input = try s.get(work, "input");
        const sent = if (c.JS_IsUndefined(own)) input else try schema.clean(&s, own, input);
        cleaned = if (c.JS_ToBool(engine.context, args_schema) != 0) try schema.clean(&s, args_schema, sent) else sent;
    }
    const label = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ try s.get(record, "address"), try s.text("."), name }));
    if (takes_args and c.JS_ToBool(engine.context, args_schema) != 0) try schema.assertValid(&s, bindings, "args", try s.keep(try @import("native_utf16.zig").concat(engine, &.{ label, try s.text(" args") })), args_schema, cleaned);
    _ = try h.invoke(&s, record, "lease", &.{ctx});
    const child = try h.invoke(&s, ctx, "child", &.{record});
    try h.field(&s, work, "child", child);
    try h.field(&s, work, "validated", c.pi_js_bool(engine.context, @intFromBool(validated)));
    try h.field(&s, work, "returns", c.pi_js_bool(engine.context, @intFromBool(returns)));
    try h.field(&s, work, "description", method);
    try h.field(&s, work, "label", label);
    const returned = js.call(engine, function, c.pi_js_undefined(), if (takes_args) &.{ cleaned, child } else &.{child}) catch |err| {
        if (err != error.JavaScriptException) return err;
        const failed = try s.keep(try h.rejected(engine, engine.captured_exception orelse return err));
        const invocation = try s.keep(try track(engine, record, bindings, failed));
        return h.wait(callComplete, engine, work, invocation, 0);
    };
    const result = try s.keep(returned);
    const invocation = try s.keep(try track(engine, record, bindings, result));
    return h.wait(callComplete, engine, work, invocation, 0);
}
fn callComplete(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, try s.get(work, "child"), "close", &.{});
    if (rejected) return h.throwValue(&s, value);
    if (!try h.flag(&s, work, "returns")) return c.pi_js_undefined();
    if (try h.flag(&s, work, "validated") and c.JS_ToBool(engine.context, try s.get(try s.get(work, "description"), "result")) != 0) {
        const label = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ try s.get(work, "label"), try s.text(" result") }));
        try schema.assertValid(&s, try s.get(work, "bindings"), "result", label, try s.get(try s.get(work, "description"), "result"), value);
    }
    return s.result(value);
}
pub fn track(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, returned: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const invocation = try s.keep(try h.resolved(engine, returned));
    const work = try r.workFor(&s, record, bindings);
    try h.field(&s, work, "invocation", invocation);
    const state = try r.state(&s, record, bindings);
    _ = try h.invoke(&s, try s.get(state, "invocations"), "add", &.{invocation});
    const tracked = try s.keep(try h.wait(invocationDone, engine, work, invocation, 0));
    h.ignore(engine, tracked);
    return s.result(invocation);
}
fn invocationDone(engine: *h.Engine, work: c.JSValue, _: c.JSValue, _: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const record = try s.get(work, "object");
    const bindings = try s.get(work, "bindings");
    const state = try r.state(&s, record, bindings);
    const jobs = try s.get(state, "invocations");
    _ = try h.invoke(&s, jobs, "delete", &.{try s.get(work, "invocation")});
    if (!try r.nonempty(&s, jobs)) try r.maybeIdle(engine, record, bindings);
    return c.pi_js_undefined();
}
pub fn raceSignal(engine: *h.Engine, bindings: c.JSValue, promise: c.JSValue, signal: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try h.flag(&s, signal, "aborted")) return h.throwValue(&s, try abortError(&s, bindings, signal));
    var resolving: [2]c.JSValue = undefined;
    const aborted = try s.keep(try engine.checked(c.JS_NewPromiseCapability(engine.context, &resolving)));
    _ = try s.keep(resolving[0]);
    _ = try s.keep(resolving[1]);
    var data = [_]c.JSValue{ bindings, signal, resolving[1] };
    const listener = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, abortListener, "", 0, 0, 3, &data)));
    const options = try s.record();
    try h.field(&s, options, "once", c.pi_js_bool(engine.context, 1));
    _ = try h.invoke(&s, signal, "addEventListener", &.{ try s.text("abort"), listener, options });
    const promises = try s.list();
    try js.push(engine, promises, promise);
    try js.push(engine, promises, aborted);
    const race = try h.invoke(&s, try s.keep(try js.global(engine, "Promise")), "race", &.{promises});
    const work = try s.record();
    try h.field(&s, work, "signal", signal);
    try h.field(&s, work, "listener", listener);
    return h.wait(raceDone, engine, work, race, 0);
}
fn abortError(s: *Scope, bindings: c.JSValue, signal: c.JSValue) !c.JSValue {
    const options = try s.record();
    try h.field(s, options, "cause", try s.get(signal, "reason"));
    return h.errorValue(s, bindings, "aborted", &.{try s.text("call aborted")}, options);
}
fn abortListener(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const failure = abortError(&s, data[0], data[1]) catch |err| return @import("native_durable.zig").reject(engine, err);
    return js.call(engine, data[2], c.pi_js_undefined(), &.{failure}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn raceDone(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, try s.get(work, "signal"), "removeEventListener", &.{ try s.text("abort"), try s.get(work, "listener") });
    return if (rejected) h.throwValue(&s, value) else s.result(value);
}
