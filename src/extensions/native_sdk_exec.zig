//! Actual Pi core/exec.ts: genuine AF return-adopts one live global Promise.
//! There is no Source Await and no private command/process transport here.
const x = @import("native_sdk_exec_values.zig");
const f = @import("native_node_function.zig");
const fatal = @import("native_sdk_exec_fatal.zig");
const c = x.c;
pub const Inputs = struct { spawn: c.JSValue, wait_for_child_process: c.JSValue };
const Callback = enum(i32) { kill, force_kill, timeout, stdout, stderr, fulfilled, rejected };
pub fn create(engine: *x.em.Engine, inputs: Inputs) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = createScoped(engine, inputs) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn createScoped(engine: *x.em.Engine, inputs: Inputs) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, createBody(&o, inputs));
}
fn createBody(o: *x.Ops, inputs: Inputs) !c.JSValue {
    const engine = o.s.engine;
    if (!c.JS_IsFunction(engine.context, inputs.spawn) or !c.JS_IsFunction(engine.context, inputs.wait_for_child_process)) return error.RequiredActualSdkExecImports;
    const imports = try o.cell(); try o.put(imports, "spawn", inputs.spawn); try o.put(imports, "waitForChildProcess", inputs.wait_for_child_process);
    const function = try o.own(try x.af.create(engine, "execCommand", 4, execute, &.{imports}));
    const namespace = try o.object(); try o.put(namespace, "execCommand", function);
    return c.JS_DupValue(engine.context, namespace);
}
fn execute(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, executeBody(&o, args, roots[0]));
}
fn executeBody(o: *x.Ops, args: []const c.JSValue, imports: c.JSValue) !c.JSValue {
    const constructor = try o.global("Promise"); // Source callee before executor argument.
    const holder = try fatal.create(o);
    const executor = try o.own(try f.createArrow(o.s.engine, "", 1, executePromise, &.{ imports, x.arg(args, 0), x.arg(args, 1), x.arg(args, 2), x.arg(args, 3), holder }));
    return c.JS_DupValue(o.s.engine.context, try fatal.construct(o, constructor, executor, holder));
}
fn executePromise(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    const result = x.owned.finishValue(&s, executorBody(&o, x.arg(args, 0), roots)) catch |err| {
        const failed = @import("native_sdk.zig").fail(engine, err);
        fatal.record(roots[5], &invocation);
        return engine.checked(engine.leaveNativeInvocation(&invocation, failed));
    };
    fatal.record(roots[5], &invocation);
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn callback(o: *x.Ops, job: c.JSValue, kind: Callback) !c.JSValue {
    const length: c_int = switch (kind) { .stdout, .stderr, .fulfilled, .rejected => 1, else => 0 };
    return o.own(try f.createArrow(o.s.engine, if (kind == .kill) "killProcess" else "", length, dispatch, &.{ job, c.JS_NewInt32(o.s.engine.context, @intFromEnum(kind)) }));
}
fn optionSignal(o: *x.Ops, options: c.JSValue) !c.JSValue { return if (x.nullish(options)) c.pi_js_undefined() else o.get(options, "signal"); }
fn optionTimeout(o: *x.Ops, options: c.JSValue) !c.JSValue { return if (x.nullish(options)) c.pi_js_undefined() else o.get(options, "timeout"); }
fn callKill(o: *x.Ops, job: c.JSValue) !void { _ = try o.call(try o.get(job, "killProcess"), c.pi_js_undefined(), &.{}); }
fn executorBody(o: *x.Ops, resolve: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const spawn = try o.get(roots[0], "spawn");
    const config = try o.object(); try o.put(config, "cwd", roots[3]); try o.put(config, "shell", c.pi_js_bool(o.s.engine.context, 0));
    const stdio = try o.array(); try o.index(stdio, 0, try o.text("ignore")); try o.index(stdio, 1, try o.text("pipe")); try o.index(stdio, 2, try o.text("pipe")); try o.put(config, "stdio", stdio);
    const proc = try o.call(spawn, c.pi_js_undefined(), &.{ roots[1], roots[2], config });
    const job = try o.cell();
    try o.put(job, "proc", proc); try o.put(job, "resolve", resolve); try o.put(job, "options", roots[4]);
    try o.put(job, "stdout", try o.text("")); try o.put(job, "stderr", try o.text("")); try o.put(job, "killed", c.pi_js_bool(o.s.engine.context, 0)); try o.put(job, "timeoutId", c.pi_js_undefined());
    const kill = try callback(o, job, .kill); try o.put(job, "killProcess", kill);
    if (o.truthy(try optionSignal(o, roots[4]))) {
        if (o.truthy(try o.get(try o.get(roots[4], "signal"), "aborted"))) try callKill(o, job)
        else {
            const signal = try o.get(roots[4], "signal"); const add = try o.get(signal, "addEventListener");
            const abort = try o.text("abort"); const once = try o.object(); try o.put(once, "once", c.pi_js_bool(o.s.engine.context, 1));
            _ = try o.call(add, signal, &.{ abort, kill, once });
        }
    }
    if (o.truthy(try optionTimeout(o, roots[4])) and o.truthy(try o.binary(6, try o.get(roots[4], "timeout"), c.JS_NewInt32(o.s.engine.context, 0)))) {
        const set_timeout = try o.global("setTimeout"); const on_timeout = try callback(o, job, .timeout);
        const delay = try o.get(roots[4], "timeout");
        try o.put(job, "timeoutId", try o.call(set_timeout, c.pi_js_undefined(), &.{ on_timeout, delay }));
    }
    const stdout = try o.get(proc, "stdout");
    if (!x.nullish(stdout)) { const on = try o.get(stdout, "on"); const event = try o.text("data"); const on_data = try callback(o, job, .stdout); _ = try o.call(on, stdout, &.{ event, on_data }); }
    const stderr = try o.get(proc, "stderr");
    if (!x.nullish(stderr)) { const on = try o.get(stderr, "on"); const event = try o.text("data"); const on_data = try callback(o, job, .stderr); _ = try o.call(on, stderr, &.{ event, on_data }); }
    const wait = try o.get(roots[0], "waitForChildProcess"); const waiting = try o.call(wait, c.pi_js_undefined(), &.{proc});
    const then = try o.get(waiting, "then"); const success = try callback(o, job, .fulfilled);
    const continued = try o.call(then, waiting, &.{success});
    const catch_method = try o.get(continued, "catch"); const failure = try callback(o, job, .rejected);
    _ = try o.call(catch_method, continued, &.{failure});
    return c.pi_js_undefined();
}
fn dispatch(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, dispatchBody(&o, args, roots));
}
fn cleanup(o: *x.Ops, job: c.JSValue) !void {
    if (o.truthy(try o.get(job, "timeoutId"))) {
        const clear = try o.global("clearTimeout"); _ = try o.call(clear, c.pi_js_undefined(), &.{try o.get(job, "timeoutId")});
    }
    const options = try o.get(job, "options");
    if (o.truthy(try optionSignal(o, options))) {
        const signal = try o.get(options, "signal"); const remove = try o.get(signal, "removeEventListener");
        _ = try o.call(remove, signal, &.{ try o.text("abort"), try o.get(job, "killProcess") });
    }
}
fn dispatchBody(o: *x.Ops, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var raw: i32 = 0; if (c.JS_ToInt32(o.s.engine.context, &raw, roots[1]) < 0) return @import("native_js_values.zig").capture(o.s.engine);
    const kind: Callback = @enumFromInt(raw); const job = roots[0];
    switch (kind) {
        .kill => if (!o.truthy(try o.get(job, "killed"))) {
            try o.put(job, "killed", c.pi_js_bool(o.s.engine.context, 1));
            const proc = try o.get(job, "proc"); _ = try o.invoke(proc, "kill", &.{try o.text("SIGTERM")});
            const set_timeout = try o.global("setTimeout"); const force = try callback(o, job, .force_kill);
            _ = try o.call(set_timeout, c.pi_js_undefined(), &.{ force, c.JS_NewInt32(o.s.engine.context, 5000) });
        },
        .force_kill => {
            const proc = try o.get(job, "proc");
            if (!o.truthy(try o.get(proc, "killed"))) _ = try o.invoke(proc, "kill", &.{try o.text("SIGKILL")});
        },
        .timeout => try callKill(o, job),
        .stdout, .stderr => {
            const name: [*:0]const u8 = if (kind == .stdout) "stdout" else "stderr";
            const left = try o.get(job, name); const data = x.arg(args, 0);
            const right = try o.invoke(data, "toString", &.{});
            try o.put(job, name, try o.binary(0, left, right));
        },
        .fulfilled, .rejected => {
            // Rejection input is ignored Source DATA, never bit/tag inspected.
            try cleanup(o, job);
            const resolve = try o.get(job, "resolve"); const result = try o.object();
            try o.put(result, "stdout", try o.get(job, "stdout")); try o.put(result, "stderr", try o.get(job, "stderr"));
            const code = if (kind == .rejected) c.JS_NewInt32(o.s.engine.context, 1) else if (x.nullish(x.arg(args, 0))) c.JS_NewInt32(o.s.engine.context, 0) else x.arg(args, 0);
            try o.put(result, "code", code); try o.put(result, "killed", try o.get(job, "killed"));
            _ = try o.call(resolve, c.pi_js_undefined(), &.{result});
        },
    }
    return c.pi_js_undefined();
}
