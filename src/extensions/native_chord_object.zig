//! Source-bound RecordImpl factory transaction, invocation admission and lifetime.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { start, run, open, unwind, currentInstalled, refreshSchemas, allDecls, stageListeners, startRuntime, startTasks, stopListeners, startTask, stopTasks, openGate, admit, lease, call, rootEnded, addRef, release, dispose, guard };
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(operation);
    const result = invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, method, data[0]) catch |err| {
        return if (method == .open or method == .unwind or method == .call) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
    };
    if (method == .open or method == .unwind or method == .call) {
        defer engine.freeValue(result);
        return h.resolved(engine, result) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
    }
    return result;
}
pub fn state(s: *Scope, record: c.JSValue, bindings: c.JSValue) !c.JSValue {
    return (try h.actor(s, record, bindings, .ObjectImpl)).data;
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = try state(&s, receiver, bindings);
    const host = try s.get(receiver, "host");
    switch (method) {
        .start => {
            const work = try workFor(&s, receiver, bindings);
            const started = try s.keep(try h.wait(activate, engine, work, h.arg(args, 0), 0));
            const ready = try s.keep(try h.wait(startedResult, engine, work, started, 0));
            try h.field(&s, receiver, "ready", ready);
            h.ignore(engine, ready);
            return c.pi_js_undefined();
        },
        .run => return run(&s, receiver, h.arg(args, 0), h.arg(args, 1), bindings),
        .open => return @import("native_chord_object_lifecycle.zig").open(engine, receiver, bindings, h.arg(args, 0), h.arg(args, 1), h.arg(args, 2)),
        .unwind => return @import("native_chord_object_lifecycle.zig").unwind(engine, receiver, bindings, h.arg(args, 0)),
        .currentInstalled => {
            const behaviors = try s.get(receiver, "implementations");
            const current = try h.invoke(&s, behaviors, "get", &.{try h.invoke(&s, host, "currentCodeVersion", &.{})});
            if (!h.nullish(current)) return s.result(current);
            return js.invoke(engine, try h.values(&s, behaviors), "at", &.{c.JS_NewInt32(engine.context, -1)});
        },
        .allDecls => {
            const result = try h.set(&s);
            _ = try h.invoke(&s, result, "add", &.{try s.get(receiver, "decls")});
            const pending = try h.snapshot(&s, try s.get(receiver, "pending"));
            for (0..try h.length(&s, pending)) |index| _ = try h.invoke(&s, result, "add", &.{try s.at(pending, index)});
            const installed = try h.values(&s, try s.get(receiver, "implementations"));
            for (0..try h.length(&s, installed)) |index| _ = try h.invoke(&s, result, "add", &.{try s.get(try s.at(installed, index), "decls")});
            return s.result(result);
        },
        .refreshSchemas => return @import("native_chord_object_schema.zig").refresh(engine, receiver, bindings),
        .stageListeners, .startRuntime, .startTasks, .stopListeners, .startTask, .stopTasks, .openGate => return @import("native_chord_object_runtime.zig").invoke(engine, receiver, bindings, @tagName(method), args),
        .admit => {
            const ctx = h.arg(args, 0);
            if (!c.JS_IsUndefined(try s.get(host, "failed"))) {
                const options = try s.record();
                try h.field(&s, options, "reason", try s.text("host_failed"));
                return h.throwValue(&s, try h.errorValue(&s, bindings, "unavailable", &.{ try s.get(host, "name"), try s.text(" failed and admits no work") }, options));
            }
            const epoch = try s.get(ctx, "codeVersion");
            if (c.JS_ToBool(engine.context, try h.invoke(&s, host, "hasCodeVersion", &.{epoch})) == 0) return h.throwValue(&s, try h.errorValue(&s, bindings, "superseded", &.{ try s.text("code version "), epoch, try s.text(" is retired") }, c.pi_js_undefined()));
            var value: f64 = undefined;
            var minimum: f64 = undefined;
            if (c.JS_ToFloat64(engine.context, &value, epoch) < 0 or c.JS_ToFloat64(engine.context, &minimum, try s.get(receiver, "minCodeVersion")) < 0) return js.capture(engine);
            if (value < minimum) return h.throwValue(&s, try h.errorValue(&s, bindings, "upgrade_conflict", &.{ try s.get(receiver, "address"), try s.text(" was upgraded in code version "), try s.get(receiver, "minCodeVersion") }, c.pi_js_undefined()));
            const gate = try s.get(receiver, "gate");
            if (!h.nullish(gate) and c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(gate, "grandfathered"), "has", &.{try s.get(ctx, "rootId")})) == 0) return h.throwValue(&s, try h.errorValue(&s, bindings, "upgrade_conflict", &.{ try s.get(receiver, "address"), try s.text(" is being upgraded") }, c.pi_js_undefined()));
            return c.pi_js_undefined();
        },
        .lease => {
            const ctx = h.arg(args, 0);
            const leases = try s.get(receiver, "leases");
            const root_id = try s.get(ctx, "rootId");
            if (c.JS_ToBool(engine.context, try h.invoke(&s, leases, "has", &.{root_id})) != 0) return c.pi_js_undefined();
            _ = try h.invoke(&s, leases, "set", &.{ root_id, try s.get(ctx, "codeVersion") });
            _ = try h.invoke(&s, host, "touch", &.{ root_id, receiver });
            return c.pi_js_undefined();
        },
        .rootEnded => {
            _ = try h.invoke(&s, try s.get(receiver, "leases"), "delete", &.{h.arg(args, 0)});
            const gate = try s.get(receiver, "gate");
            if (!h.nullish(gate) and c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(gate, "grandfathered"), "delete", &.{h.arg(args, 0)})) != 0 and c.JS_IsStrictEqual(engine.context, try s.get(try s.get(gate, "grandfathered"), "size"), c.JS_NewInt32(engine.context, 0))) _ = try s.keep(try js.call(engine, try s.get(gate, "drained"), gate, &.{}));
            return c.pi_js_undefined();
        },
        .call => return @import("native_chord_object_call.zig").call(engine, receiver, bindings, h.arg(args, 0), h.arg(args, 1), h.arg(args, 2), h.arg(args, 3)),
        .addRef => {
            _ = try h.invoke(&s, try s.get(receiver, "refs"), "add", &.{h.arg(args, 0)});
            try cancelLinger(&s, owned);
            return c.pi_js_undefined();
        },
        .release => {
            if (c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(receiver, "refs"), "delete", &.{h.arg(args, 0)})) != 0) try maybeIdle(engine, receiver, bindings);
            return c.pi_js_undefined();
        },
        .dispose => return @import("native_chord_object_lifecycle.zig").dispose(engine, receiver, bindings, c.JS_ToBool(engine.context, h.arg(args, 0)) != 0, h.arg(args, 1)),
        .guard => {
            const ctx = h.arg(args, 0);
            var in_factory: f64 = undefined;
            if (c.JS_ToFloat64(engine.context, &in_factory, try s.get(host, "inFactory")) < 0) return js.capture(engine);
            if (in_factory > 0) return h.invalid(&s, bindings, "read_only", &.{try s.text("cells cannot be written while a factory runs")});
            const instance = c.JS_IsInstanceOf(engine.context, ctx, try s.get(bindings, "CtxImpl"));
            if (instance < 0) return js.capture(engine);
            if (instance != 0) _ = try h.invoke(&s, ctx, "check", &.{host});
            if (try h.flag(&s, try s.get(ctx, "signal"), "aborted")) return h.throwValue(&s, try h.errorValue(&s, bindings, "aborted", &.{try s.text("write with an aborted ctx")}, c.pi_js_undefined()));
            if (try s.equal(try s.get(receiver, "status"), "disposed")) return h.throwValue(&s, try h.errorValue(&s, bindings, "gone", &.{ try s.get(receiver, "address"), try s.text(" is disposed") }, c.pi_js_undefined()));
            if (c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(ctx, "rootId"), "startsWith", &.{try s.text("task:")})) == 0) _ = try h.invoke(&s, receiver, "admit", &.{ctx});
            return c.pi_js_undefined();
        },
    }
}
pub fn workFor(s: *Scope, record: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const work = try s.record();
    try h.field(s, work, "object", record);
    try h.field(s, work, "bindings", bindings);
    return work;
}
fn run(s: *Scope, record: c.JSValue, service: c.JSValue, previous: c.JSValue, bindings: c.JSValue) anyerror!c.JSValue {
    const self = try h.construct(s, bindings, "SelfImpl", &.{ record, previous });
    const empty = try h.invoke(s, self, "run", &.{c.pi_js_undefined()});
    const decls = try s.get(empty, "decls");
    _ = try h.invoke(s, try s.get(record, "pending"), "add", &.{decls});
    const host = try s.get(record, "host");
    var depth: f64 = undefined;
    if (c.JS_ToFloat64(s.engine.context, &depth, try s.get(host, "inFactory")) < 0) return js.capture(s.engine);
    try h.field(s, host, "inFactory", c.JS_NewFloat64(s.engine.context, depth + 1));
    const behavior = js.call(s.engine, try s.get(service, "factory"), service, &.{ try s.get(record, "input"), try s.get(record, "principal"), self }) catch |err| {
        try h.field(s, host, "inFactory", c.JS_NewFloat64(s.engine.context, depth));
        try discard(s, record, empty);
        return err;
    };
    _ = try s.keep(behavior);
    try h.field(s, host, "inFactory", c.JS_NewFloat64(s.engine.context, depth));
    const result = try h.invoke(s, self, "run", &.{behavior});
    @import("native_chord_object_schema.zig").validate(s.engine, bindings, service, behavior) catch |err| {
        try discard(s, record, result);
        return err;
    };
    return s.result(result);
}
fn discard(s: *Scope, record: c.JSValue, run_value: c.JSValue) !void {
    _ = try h.invoke(s, try s.get(record, "pending"), "delete", &.{try s.get(run_value, "decls")});
    const cleanup = try h.invoke(s, record, "unwind", &.{run_value});
    try background(s, record, cleanup);
}
pub fn background(s: *Scope, record: c.JSValue, promise: c.JSValue) !void {
    var data = [_]c.JSValue{try s.get(record, "host")};
    const observer = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, reportFailure, "", 1, 0, 1, &data)));
    _ = try h.invoke(s, promise, "catch", &.{observer});
}
fn reportFailure(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return js.invoke(engine, data[0], "report", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn abandoned(s: *Scope, record: c.JSValue, bindings: c.JSValue) !c.JSValue {
    return h.errorValue(s, bindings, "aborted", &.{ try s.get(record, "address"), try s.text(" abandoned") }, c.pi_js_undefined());
}
fn activate(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const record = try s.get(work, "object");
    const bindings = try s.get(work, "bindings");
    const host = try s.get(record, "host");
    if (stage == 2) {
        if (rejected) _ = try h.invoke(&s, host, "report", &.{value});
        _ = try h.invoke(&s, try s.get(record, "pending"), "delete", &.{try s.get(try s.get(work, "run"), "decls")});
        return h.throwValue(&s, try s.get(work, "failure"));
    }
    if (stage == 3) {
        const cleanup = try h.invoke(&s, record, "unwind", &.{try s.get(work, "run")});
        return h.wait(activate, engine, work, cleanup, 2);
    }
    if (stage == 0) {
        const signal = try s.get(try s.get(record, "activationAbort"), "signal");
        if (try h.flag(&s, signal, "aborted")) return h.throwValue(&s, try abandoned(&s, record, bindings));
        const service = try h.invoke(&s, host, "service", &.{try s.get(record, "typeName")});
        if (c.JS_IsUndefined(service)) {
            const options = try s.record();
            try h.field(&s, options, "reason", try s.text("unknown_type"));
            return h.throwValue(&s, try h.errorValue(&s, bindings, "unavailable", &.{ try s.get(record, "typeName"), try s.text(" is not served") }, options));
        }
        try h.field(&s, record, "service", service);
        const run_value = try h.invoke(&s, record, "run", &.{ service, c.pi_js_undefined() });
        try h.field(&s, work, "run", run_value);
        const created = try s.get(run_value, "created");
        const opening = try h.invoke(&s, record, "open", &.{ try s.get(created, "resources"), try s.get(created, "refs"), signal });
        return h.wait(activate, engine, work, opening, 1);
    }
    if (!rejected) {
        finalize(&s, record, bindings, try s.get(work, "run")) catch |err| {
            if (err != error.JavaScriptException) return err;
            return activationFailure(&s, work, engine.captured_exception orelse return err);
        };
        _ = try h.invoke(&s, try s.get(record, "pending"), "delete", &.{try s.get(try s.get(work, "run"), "decls")});
        return c.pi_js_undefined();
    }
    return activationFailure(&s, work, value);
}
fn activationFailure(s: *Scope, work: c.JSValue, failure: c.JSValue) anyerror!c.JSValue {
    const record = try s.get(work, "object");
    const bindings = try s.get(work, "bindings");
    try h.field(s, work, "failure", failure);
    _ = try h.invoke(s, try s.get(record, "callAbort"), "abort", &.{failure});
    _ = try h.invoke(s, record, "stopListeners", &.{});
    _ = try h.invoke(s, record, "stopTasks", &.{});
    const registered = try nonempty(s, try s.get(try s.get(record, "decls"), "registrations")) and !try h.flag(s, record, "deferredRuntime");
    _ = try h.invoke(s, try s.get(record, "implementations"), "clear", &.{});
    try h.field(s, record, "decls", try h.construct(s, bindings, "Decls", &.{}));
    if (registered) _ = try h.invoke(s, try s.get(record, "host"), "registriesChanged", &.{});
    const data = try state(s, record, bindings);
    const jobs = try h.snapshot(s, try s.get(data, "invocations"));
    const stopped = try h.snapshot(s, try s.get(data, "stopped"));
    const all = try h.invoke(s, jobs, "concat", &.{stopped});
    return h.wait(activate, s.engine, work, try h.invoke(s, try s.keep(try js.global(s.engine, "Promise")), "allSettled", &.{all}), 3);
}
pub fn nonempty(s: *Scope, value: c.JSValue) !bool {
    return !c.JS_IsStrictEqual(s.engine.context, try s.get(value, "size"), c.JS_NewInt32(s.engine.context, 0));
}
fn finalize(s: *Scope, record: c.JSValue, bindings: c.JSValue, run_value: c.JSValue) anyerror!void {
    const signal = try s.get(try s.get(record, "activationAbort"), "signal");
    if (try h.flag(s, signal, "aborted")) {
        _ = try h.throwValue(s, try abandoned(s, record, bindings));
    }
    const host = try s.get(record, "host");
    const service = try s.get(record, "service");
    const decls = try s.get(run_value, "decls");
    _ = try h.invoke(s, host, "checkRegistrations", &.{ record, decls });
    try h.field(s, record, "decls", decls);
    const behaviors = try s.get(record, "implementations");
    var retained = try @import("native_chord_reload_values.zig").iterate(s, try h.invoke(s, host, "retainedCodeVersions", &.{}));
    defer retained.deinit();
    errdefer retained.closePreserving();
    while (try retained.next()) |entry| {
        defer s.engine.freeValue(entry);
        const epoch = try s.at(entry, 0);
        const services = try s.at(entry, 1);
        if (!c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, services, "get", &.{try s.get(record, "typeName")}), service)) continue;
        const installed = try s.record();
        try h.field(s, installed, "codeVersion", epoch);
        try h.field(s, installed, "service", service);
        try h.field(s, installed, "implementation", try s.get(run_value, "implementation"));
        try h.field(s, installed, "decls", decls);
        _ = try h.invoke(s, behaviors, "set", &.{ epoch, installed });
    }
    const current = try h.invoke(s, host, "currentCodeVersion", &.{});
    const pending = try h.invoke(s, host, "pendingCodeVersion", &.{});
    const has_current = c.JS_ToBool(s.engine.context, try h.invoke(s, behaviors, "has", &.{current})) != 0;
    if (!has_current and (c.JS_IsUndefined(pending) or c.JS_ToBool(s.engine.context, try h.invoke(s, behaviors, "has", &.{pending})) == 0)) {
        _ = try h.throwValue(s, try h.errorValue(s, bindings, "superseded", &.{ try s.get(record, "address"), try s.text(": code changed during activation") }, c.pi_js_undefined()));
    }
    const derives = try s.get(try s.get(run_value, "created"), "derives");
    for (0..try h.length(s, derives)) |index| _ = try h.invoke(s, try s.at(derives, index), "attach", &.{});
    _ = try h.invoke(s, record, "refreshSchemas", &.{});
    try h.field(s, record, "deferredRuntime", c.pi_js_bool(s.engine.context, @intFromBool(!has_current)));
    if (has_current) {
        if (try nonempty(s, try s.get(decls, "registrations"))) _ = try h.invoke(s, host, "registriesChanged", &.{record});
        _ = try h.invoke(s, record, "startRuntime", &.{});
    }
    if (try h.flag(s, signal, "aborted")) {
        _ = try h.throwValue(s, try abandoned(s, record, bindings));
    }
    try h.field(s, record, "status", try s.text("live"));
}
fn startedResult(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const record = try s.get(work, "object");
    const bindings = try s.get(work, "bindings");
    if (!rejected) {
        const holds = try h.snapshot(&s, try s.get(record, "refs"));
        for (0..try h.length(&s, holds)) |index| _ = try h.invoke(&s, try s.at(holds, index), "live", &.{});
        try maybeIdle(engine, record, bindings);
        return c.pi_js_undefined();
    }
    if (try s.equal(try s.get(record, "status"), "activating")) try h.field(&s, record, "status", try s.text("failed"));
    _ = try h.invoke(&s, try s.get(record, "host"), "forget", &.{record});
    const label = try s.keep(try @import("native_utf16.zig").concat(engine, &.{ try s.text("activating "), try s.get(record, "address") }));
    const failure = try h.invoke(&s, try s.get(bindings, "errors"), "asChordError", &.{ value, label });
    const holds = try h.snapshot(&s, try s.get(record, "refs"));
    for (0..try h.length(&s, holds)) |index| _ = try h.invoke(&s, try s.at(holds, index), "gone", &.{failure});
    return h.throwValue(&s, failure);
}
pub fn cancelLinger(s: *Scope, owned: c.JSValue) !void {
    const timer = try s.get(owned, "linger");
    if (!c.JS_IsUndefined(timer)) {
        const clear = try s.keep(try js.global(s.engine, "clearTimeout"));
        _ = try s.keep(try js.call(s.engine, clear, c.pi_js_undefined(), &.{timer}));
    }
    try h.field(s, owned, "linger", c.pi_js_undefined());
}
fn idleCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    idle(engine, data[0], data[1]) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_undefined();
}
fn idle(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = try state(&s, record, bindings);
    try h.field(&s, data, "linger", c.pi_js_undefined());
    try maybeIdle(engine, record, bindings);
}
pub fn maybeIdle(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = try state(&s, record, bindings);
    if (try nonempty(&s, try s.get(record, "refs")) or try nonempty(&s, try s.get(data, "invocations")) or !c.JS_IsUndefined(try s.get(data, "linger"))) return;
    const activating = try s.equal(try s.get(record, "status"), "activating");
    if (!activating and !try s.equal(try s.get(record, "status"), "live")) return;
    const service = try s.get(record, "service");
    const raw = if (h.nullish(service)) c.pi_js_undefined() else try s.get(try s.get(service, "options"), "linger");
    var linger: f64 = 0;
    if (!h.nullish(raw) and c.JS_ToFloat64(engine.context, &linger, raw) < 0) return js.capture(engine);
    if (activating or linger <= 0) {
        try background(&s, record, try h.invoke(&s, record, "dispose", &.{c.pi_js_bool(engine.context, 0)}));
        return;
    }
    var captures = [_]c.JSValue{ record, bindings };
    const function = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, idleCallback, "", 0, 0, 2, &captures)));
    const set_timeout = try s.keep(try js.global(engine, "setTimeout"));
    const timer = try s.keep(try js.call(engine, set_timeout, c.pi_js_undefined(), &.{ function, raw }));
    try h.field(&s, data, "linger", timer);
    if (c.JS_IsObject(timer) and c.JS_IsFunction(engine.context, try s.get(timer, "unref"))) _ = try h.invoke(&s, timer, "unref", &.{});
}
fn boundGuard(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return invoke(engine, data[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, .guard, data[1]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = values[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .ObjectImpl));
    const owned = try state(&s, result, bindings);
    try h.field(&s, result, "host", h.arg(args, 0));
    inline for (.{ "address", "typeName", "input", "principal", "hostLifetime" }) |name| try h.field(&s, result, name, try s.get(h.arg(args, 1), name));
    try h.field(&s, result, "status", try s.text("activating"));
    try h.field(&s, result, "ready", try s.keep(try h.resolved(engine, c.pi_js_undefined())));
    try h.field(&s, result, "service", c.pi_js_undefined());
    try h.field(&s, result, "minCodeVersion", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, result, "decls", try h.construct(&s, bindings, "Decls", &.{}));
    try h.field(&s, result, "pending", try h.set(&s));
    try h.field(&s, result, "implementations", try h.map(&s));
    try h.field(&s, result, "refs", try h.set(&s));
    try h.field(&s, result, "leases", try h.map(&s));
    try h.field(&s, result, "openOrder", try s.list());
    inline for (.{ "callAbort", "activationAbort" }) |name| try h.field(&s, result, name, try s.keep(try js.builtin(engine, "AbortController", &.{})));
    try h.field(&s, result, "gate", c.pi_js_undefined());
    try h.field(&s, result, "deferredRuntime", c.pi_js_bool(engine.context, 0));
    inline for (.{ "subscriptions", "tasks" }) |name| try h.field(&s, owned, name, try h.map(&s));
    try h.field(&s, owned, "invocations", try h.set(&s));
    try h.field(&s, owned, "stopped", try h.set(&s));
    try h.field(&s, owned, "taskRuns", c.JS_NewInt32(engine.context, 0));
    inline for (.{ "linger", "disposal" }) |name| try h.field(&s, owned, name, c.pi_js_undefined());
    var captures = [_]c.JSValue{ result, bindings };
    try js.define(engine, result, "guard", try engine.checked(c.JS_NewCFunctionData2(engine.context, boundGuard, "guard", 1, 0, 2, &captures)));
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .ObjectImpl);
    const prototype = try s.record();
    try js.define(engine, bindings, "ObjectImpl", try @import("native_class.zig").constructor(engine, "ObjectImpl", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "start", Method.start, 1, false }, .{ "run", Method.run, 2, false }, .{ "open", Method.open, 3, true }, .{ "unwind", Method.unwind, 1, true }, .{ "currentInstalled", Method.currentInstalled, 0, false }, .{ "refreshSchemas", Method.refreshSchemas, 0, false }, .{ "allDecls", Method.allDecls, 0, false }, .{ "stageListeners", Method.stageListeners, 1, false }, .{ "startRuntime", Method.startRuntime, 0, false }, .{ "startTasks", Method.startTasks, 0, false }, .{ "stopListeners", Method.stopListeners, 0, false }, .{ "stopTasks", Method.stopTasks, 0, false }, .{ "openGate", Method.openGate, 0, false }, .{ "admit", Method.admit, 1, false }, .{ "lease", Method.lease, 1, false }, .{ "call", Method.call, 4, true }, .{ "rootEnded", Method.rootEnded, 1, false }, .{ "addRef", Method.addRef, 1, false }, .{ "release", Method.release, 1, false }, .{ "dispose", Method.dispose, 2, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], false, item[3]);
}
