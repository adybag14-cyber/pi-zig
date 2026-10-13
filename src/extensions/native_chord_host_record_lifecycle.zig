//! Actual Record resource dependency opens, sequential independent cleanup and disposal.
const h = @import("native_chord_host_values.zig");
const record_api = @import("native_chord_host_record.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
pub fn open(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, resources: c.JSValue, holds: c.JSValue, signal: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try record_api.workFor(&s, record, bindings);
    try h.field(&s, work, "resources", resources);
    try h.field(&s, work, "signal", signal);
    try h.field(&s, work, "opening", try h.map(&s));
    const pending = try s.list();
    for (0..try h.length(&s, resources)) |index| try js.push(engine, pending, try s.keep(try openOne(engine, work, try s.at(resources, index))));
    for (0..try h.length(&s, holds)) |index| try js.push(engine, pending, try s.get(try s.at(holds, index), "ready"));
    const settled = try h.invoke(&s, try s.keep(try js.global(engine, "Promise")), "allSettled", &.{pending});
    return h.wait(openComplete, engine, work, settled, 0);
}
fn openOne(engine: *h.Engine, work: c.JSValue, resource: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const opening = try s.get(work, "opening");
    const existing = try h.invoke(&s, opening, "get", &.{resource});
    if (!c.JS_IsUndefined(existing)) return s.result(existing);
    const args = try s.record();
    try js.spreadInto(engine, args, work);
    try h.field(&s, args, "resource", resource);
    const promise = try s.keep(try h.wait(openDependencies, engine, args, c.pi_js_undefined(), 0));
    _ = try h.invoke(&s, opening, "set", &.{ resource, promise });
    return s.result(promise);
}
fn openDependencies(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    const resource = try s.get(work, "resource");
    const record = try s.get(work, "record");
    if (stage == 1) return js.invoke(engine, resource, "open", &.{ try s.get(work, "signal"), try s.get(record, "openOrder") });
    const dependencies = try s.get(resource, "deps");
    const promises = try s.list();
    const bindings = try s.get(work, "bindings");
    const resources = try s.get(work, "resources");
    for (0..try h.length(&s, dependencies)) |index| {
        const dep = try s.at(dependencies, index);
        const instance = c.JS_IsInstanceOf(engine.context, dep, try s.get(bindings, "ResourceImpl"));
        if (instance < 0) return js.capture(engine);
        const promise = if (instance == 0) try s.get(dep, "ready") else if (c.JS_ToBool(engine.context, try h.invoke(&s, resources, "includes", &.{dep})) != 0) try s.keep(try openOne(engine, work, dep)) else c.pi_js_undefined();
        try js.push(engine, promises, promise);
    }
    return h.wait(openDependencies, engine, work, try h.invoke(&s, try s.keep(try js.global(engine, "Promise")), "all", &.{promises}), 1);
}
fn openComplete(engine: *h.Engine, _: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    for (0..try h.length(&s, value)) |index| {
        const item = try s.at(value, index);
        if (try s.equal(try s.get(item, "status"), "rejected")) return h.throwValue(&s, try s.get(item, "reason"));
    }
    return c.pi_js_undefined();
}
fn sorting(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return sorted(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn sorted(engine: *h.Engine, order: c.JSValue, left: c.JSValue, right: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var a: f64 = undefined;
    var b: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &a, try h.invoke(&s, order, "indexOf", &.{left})) < 0 or c.JS_ToFloat64(engine.context, &b, try h.invoke(&s, order, "indexOf", &.{right})) < 0) return js.capture(engine);
    return c.JS_NewFloat64(engine.context, b - a);
}
pub fn unwind(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, run: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const created = try s.get(run, "created");
    const derives = try s.get(created, "derives");
    for (0..try h.length(&s, derives)) |index| _ = try h.invoke(&s, try s.at(derives, index), "detach", &.{});
    const resources = try h.snapshot(&s, try s.get(created, "resources"));
    var captures = [_]c.JSValue{try s.get(record, "openOrder")};
    const comparator = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, sorting, "", 2, 0, 1, &captures)));
    _ = try h.invoke(&s, resources, "sort", &.{comparator});
    return cleanup(engine, record, bindings, resources, try s.get(created, "holds"), try s.text("cleanup failed"), false);
}
pub fn cleanup(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, resources: c.JSValue, holds: c.JSValue, label: c.JSValue, disposed: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try record_api.workFor(&s, record, bindings);
    try h.field(&s, work, "resources", resources);
    try h.field(&s, work, "holds", holds);
    try h.field(&s, work, "errors", try s.list());
    try h.field(&s, work, "position", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, work, "label", label);
    try h.field(&s, work, "disposed", c.pi_js_bool(engine.context, @intFromBool(disposed)));
    return cleanupNext(engine, work, c.pi_js_undefined(), false, -1);
}
fn cleanupNext(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const errors = try s.get(work, "errors");
    if (rejected) try js.push(engine, errors, value);
    const resources = try s.get(work, "resources");
    const holds = try s.get(work, "holds");
    const record = try s.get(work, "record");
    const resource_count = try h.length(&s, resources);
    const total = resource_count + try h.length(&s, holds);
    var position: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &position, try s.get(work, "position")) < 0) return js.capture(engine);
    while (position < total) {
        try h.field(&s, work, "position", c.JS_NewUint32(engine.context, position + 1));
        const result = if (position < resource_count) js.invoke(engine, try s.at(resources, position), "close", &.{try s.get(record, "openOrder")}) else js.invoke(engine, try s.at(holds, position - resource_count), "release", &.{});
        const promise = result catch |err| {
            if (err != error.JavaScriptException) return err;
            try js.push(engine, errors, engine.captured_exception orelse return err);
            position += 1;
            continue;
        };
        defer engine.freeValue(promise);
        return h.wait(cleanupNext, engine, work, promise, 0);
    }
    if (try h.flag(&s, work, "disposed")) try h.field(&s, record, "status", try s.text("disposed"));
    const count = try h.length(&s, errors);
    if (count == 0) return c.pi_js_undefined();
    if (count == 1) return h.throwValue(&s, try s.at(errors, 0));
    const message = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ try s.get(record, "address"), try s.text(": "), try s.get(work, "label") }));
    return h.throwValue(&s, try s.keep(try js.builtin(engine, "AggregateError", &.{ errors, message })));
}
pub fn dispose(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue, forced: bool, reason: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = try record_api.state(&s, record, bindings);
    const existing = try s.get(data, "disposal");
    if (!c.JS_IsUndefined(existing)) return s.result(existing);
    // Reserve the promise before executing synchronous notifications, preserving idempotence under reentrancy.
    var resolving: [2]c.JSValue = undefined;
    const promise = try s.keep(try engine.checked(c.JS_NewPromiseCapability(engine.context, &resolving)));
    const resolve = try s.keep(resolving[0]);
    const reject = try s.keep(resolving[1]);
    try h.field(&s, data, "disposal", promise);
    const work = try record_api.workFor(&s, record, bindings);
    try h.field(&s, work, "resolve", resolve);
    try h.field(&s, work, "reject", reject);
    const started = beginDispose(&s, work, forced, reason) catch |err| {
        if (err != error.JavaScriptException) return err;
        _ = try s.keep(try js.call(engine, reject, c.pi_js_undefined(), &.{engine.captured_exception orelse return err}));
        return s.result(promise);
    };
    defer engine.freeValue(started);
    _ = try s.keep(try h.wait(disposeSettled, engine, work, started, 0));
    return s.result(promise);
}
fn beginDispose(s: *Scope, work: c.JSValue, forced: bool, reason: c.JSValue) anyerror!c.JSValue {
    const record = try s.get(work, "record");
    const bindings = try s.get(work, "bindings");
    const was_activating = try s.equal(try s.get(record, "status"), "activating");
    try h.field(s, record, "status", try s.text("disposing"));
    _ = try h.invoke(s, try s.get(record, "host"), "forget", &.{record});
    try record_api.cancelLinger(s, try record_api.state(s, record, bindings));
    const failure = if (h.nullish(reason)) try h.errorValue(s, bindings, "gone", &.{ try s.get(record, "address"), try s.text(" was disposed") }, c.pi_js_undefined()) else reason;
    try h.field(s, work, "reason", failure);
    if (forced) {
        try handlesGone(s, record, failure);
        _ = try h.invoke(s, try s.get(record, "callAbort"), "abort", &.{failure});
    }
    _ = try h.invoke(s, try s.get(record, "activationAbort"), "abort", &.{failure});
    return h.wait(disposeStep, s.engine, work, if (was_activating) try s.get(record, "ready") else c.pi_js_undefined(), 0);
}
fn handlesGone(s: *Scope, record: c.JSValue, failure: c.JSValue) !void {
    const holds = try h.snapshot(s, try s.get(record, "holds"));
    for (0..try h.length(s, holds)) |index| _ = try h.invoke(s, try s.at(holds, index), "gone", &.{failure});
}
fn disposeStep(engine: *h.Engine, work: c.JSValue, _: c.JSValue, _: bool, stage: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const record = try s.get(work, "record");
    const bindings = try s.get(work, "bindings");
    const data = try record_api.state(&s, record, bindings);
    if (stage == 0) {
        try handlesGone(&s, record, try s.get(work, "reason"));
        const decls = try h.snapshot(&s, try h.invoke(&s, record, "allDecls", &.{}));
        try h.field(&s, work, "decls", decls);
        _ = try h.invoke(&s, record, "stopTasks", &.{});
        _ = try h.invoke(&s, record, "stopListeners", &.{});
        return h.wait(disposeStep, engine, work, try h.invoke(&s, try s.keep(try js.global(engine, "Promise")), "allSettled", &.{try h.snapshot(&s, try s.get(data, "invocations"))}), 1);
    }
    if (stage == 1) {
        const decls = try s.get(work, "decls");
        var registered = false;
        const holds = try h.set(&s);
        for (0..try h.length(&s, decls)) |index| {
            const set = try s.at(decls, index);
            registered = registered or try record_api.nonempty(&s, try s.get(set, "registrations"));
            const derives = try h.values(&s, try s.get(set, "derives"));
            for (0..try h.length(&s, derives)) |slot| _ = try h.invoke(&s, try s.at(derives, slot), "detach", &.{});
            const held = try h.values(&s, try s.get(set, "holds"));
            for (0..try h.length(&s, held)) |slot| _ = try h.invoke(&s, holds, "add", &.{try s.at(held, slot)});
        }
        _ = try h.invoke(&s, try s.get(record, "behaviors"), "clear", &.{});
        try h.field(&s, record, "decls", try h.construct(&s, bindings, "Decls", &.{}));
        if (registered and !try h.flag(&s, record, "deferredRuntime")) _ = try h.invoke(&s, try s.get(record, "host"), "registriesChanged", &.{});
        try h.field(&s, work, "holds", try h.snapshot(&s, holds));
        const stopped = try h.invoke(&s, try s.get(data, "stopped"), "splice", &.{c.JS_NewInt32(engine.context, 0)});
        return h.wait(disposeStep, engine, work, try h.invoke(&s, try s.keep(try js.global(engine, "Promise")), "allSettled", &.{stopped}), 2);
    }
    const resources = try h.snapshot(&s, try s.get(record, "openOrder"));
    _ = try h.invoke(&s, resources, "reverse", &.{});
    return cleanup(engine, record, bindings, resources, try s.get(work, "holds"), try s.text("disposal failed"), true);
}
fn disposeSettled(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !c.JSValue {
    // Settling the already-owned capability must remain possible after a
    // continuation fails to allocate its temporary Zig roots.
    const function = try js.get(engine, work, if (rejected) "reject" else "resolve");
    defer engine.freeValue(function);
    const result = try js.call(engine, function, c.pi_js_undefined(), &.{value});
    defer engine.freeValue(result);
    return c.pi_js_undefined();
}
