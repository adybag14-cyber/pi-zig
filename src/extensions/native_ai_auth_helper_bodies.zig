//! Exact auth/helpers.ts and auth/context.ts native AsyncFunction bodies.
//! Await actions correspond only to Source AwaitExpressions; returned values
//! are adopted by the VM. No Promise owner or host .then continuation is used.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const Stage = enum(i32) { login, env, lazy, file_module, file_os, file_access };

fn returned(o: *x.Ops, value: c.JSValue) af.Action { return .{ .returned = c.JS_DupValue(o.s.engine.context, value) }; }
fn awaited(o: *x.Ops, state: c.JSValue, stage: Stage, value: c.JSValue) !af.Action {
    try o.put(state, "stage", c.JS_NewInt32(o.s.engine.context, @intFromEnum(stage)));
    return .{ .awaited = c.JS_DupValue(o.s.engine.context, value) };
}
fn stageOf(o: *x.Ops, state: c.JSValue) !Stage {
    var raw: i32 = 0;
    if (c.JS_ToInt32(o.s.engine.context, &raw, try o.get(state, "stage")) < 0) return @import("native_js_values.zig").capture(o.s.engine);
    return @enumFromInt(raw);
}
fn initialize(o: *x.Ops, state: *c.JSValue) !c.JSValue {
    const next = try o.cell();
    af.replaceState(o.s.engine, state, c.JS_DupValue(o.s.engine.context, next));
    try o.s.engine.checkNativeEntry();
    return next;
}
fn abort(engine: *x.em.Engine, value: c.JSValue, interaction: bool) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, abortBody(&o, value, interaction));
}
fn abortBody(o: *x.Ops, value: c.JSValue, interaction: bool) !void {
    const signal = if (interaction) try o.get(value, "signal") else value;
    _ = try o.invoke(signal, "throwIfAborted", &.{});
}

pub fn envFactory(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.finishInvocation(engine, &invocation, x.owned.finishValue(&s, envFactoryBody(&o, x.arg(args, 0), x.arg(args, 1))));
}
fn envFactoryBody(o: *x.Ops, name: c.JSValue, env_vars: c.JSValue) !c.JSValue {
    const result = try o.object(); try o.put(result, "name", name);
    try o.put(result, "login", try o.own(try af.createResumableArrow(o.s.engine, "login", 1, login, &.{name}, c.pi_js_undefined())));
    try o.put(result, "resolve", try o.own(try af.createResumableArrow(o.s.engine, "resolve", 1, resolve, &.{env_vars}, c.pi_js_undefined())));
    return c.JS_DupValue(o.s.engine.context, result);
}
fn login(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishAction(&s, loginBody(&o, args, roots[0], state, completion, input));
}
fn loginBody(o: *x.Ops, args: []const c.JSValue, name: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) { try @import("native_async_body.zig").enterRejectedContinuation(o.s.engine); return .{ .thrown = c.JS_DupValue(o.s.engine.context, input) }; }
    if (completion == .start) {
        const job = try initialize(o, state); const interaction = x.arg(args, 0);
        try o.put(job, "interaction", interaction);
        try abort(o.s.engine, interaction, true);
        const prompt = try o.get(interaction, "prompt"); // Source callee first.
        const options = try o.object(); try o.put(options, "type", try o.text("secret"));
        try o.put(options, "message", try o.binary(0, try o.text("Enter "), try o.stringify(name)));
        return awaited(o, job, .login, try o.call(prompt, interaction, &.{options}));
    }
    try abort(o.s.engine, try o.get(state.*, "interaction"), true);
    const credential = try o.object(); try o.put(credential, "type", try o.text("api_key")); try o.put(credential, "key", input);
    return returned(o, credential);
}
fn resolve(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    const result = resolveBody(&o, args, roots[0], state, completion, input);
    // Hold actual outcome before IteratorClose and before native roots retire.
    var captured = x.owned.Completion.initAction(engine, result);
    const selected = captured.finishAction() catch |err| return x.owned.finishAction(&s, @as(anyerror!af.Action, err));
    const final: anyerror!af.Action = if (selected == .thrown) preserveThrowClose(&o, state.*, selected.thrown) else selected;
    return x.owned.finishAction(&s, final);
}
fn resolveBody(o: *x.Ops, args: []const c.JSValue, env_vars: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) { try @import("native_async_body.zig").enterRejectedContinuation(o.s.engine); return .{ .thrown = c.JS_DupValue(o.s.engine.context, input) }; }
    if (completion == .start) {
        // Destructured parameters are read in Source order before body effects.
        const argument = x.arg(args, 0); const ctx = try o.get(argument, "ctx");
        const credential = try o.get(argument, "credential"); const signal = try o.get(argument, "signal");
        const job = try initialize(o, state); try o.put(job, "ctx", ctx); try o.put(job, "signal", signal);
        try abort(o.s.engine, signal, false);
        if (!x.nullish(credential) and o.truthy(try o.get(credential, "key"))) {
            const result = try o.object(); const auth = try o.object();
            try o.put(auth, "apiKey", try o.get(credential, "key")); try o.put(result, "auth", auth);
            try o.put(result, "env", try o.get(credential, "env")); try o.put(result, "source", try o.text("stored credential"));
            return returned(o, result); // Source zero-Await path.
        }
        try initializeIterator(o.s.engine, job, env_vars);
        return nextEnv(o, job);
    }
    try abort(o.s.engine, try o.get(state.*, "signal"), false);
    if (!o.truthy(input)) return nextEnv(o, state.*);
    const result = try o.object(); const auth = try o.object(); try o.put(auth, "apiKey", input); try o.put(result, "auth", auth);
    try setResultSource(o.s.engine, result, state.*);
    try o.put(state.*, "envName", c.pi_js_undefined());
    try closeIterator(o, state.*);
    return returned(o, result);
}
fn nextEnv(o: *x.Ops, state: c.JSValue) !af.Action {
    // The completed iteration's lexical envVar ends before IteratorStep.
    try o.put(state, "envName", c.pi_js_undefined());
    // Abrupt IteratorStep/IteratorValue does not invoke IteratorClose.
    try o.put(state, "closed", c.pi_js_bool(o.s.engine.context, 1));
    if (!try nextValue(o.s.engine, state)) return returned(o, c.pi_js_undefined());
    const name = try o.get(state, "envName");
    return awaited(o, state, .env, try o.invoke(try o.get(state, "ctx"), "env", &.{name}));
}
fn initializeIterator(engine: *x.em.Engine, state: c.JSValue, iterable: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, initializeIteratorBody(&o, state, iterable));
}
fn initializeIteratorBody(o: *x.Ops, state: c.JSValue, iterable: c.JSValue) !void {
    const symbol = try o.accept(c.JS_GetIteratorSymbol(o.s.engine.context));
    const method = try o.getKey(iterable, symbol); const iterator = try o.call(method, iterable, &.{});
    if (!c.JS_IsObject(iterator)) return @import("native_js_values.zig").typeError(o.s.engine, "Iterator is not an object");
    const next = try o.get(iterator, "next");
    try o.put(state, "iterator", iterator); try o.put(state, "next", next); try o.put(state, "closed", c.pi_js_bool(o.s.engine.context, 1));
}
fn propertyTruth(engine: *x.em.Engine, receiver: c.JSValue, name: [*:0]const u8) !bool {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    const result: anyerror!c.JSValue = if (o.get(receiver, name)) |value| c.pi_js_bool(engine.context, @intFromBool(o.truthy(value))) else |err| err;
    const boolean = try x.owned.finishValue(&s, result);
    return c.JS_ToBool(engine.context, boolean) == 1;
}
fn nextValue(engine: *x.em.Engine, state: c.JSValue) !bool {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    const value = try x.owned.finishValue(&s, nextValueBody(&o, state));
    return c.JS_ToBool(engine.context, value) == 1;
}
fn nextValueBody(o: *x.Ops, state: c.JSValue) !c.JSValue {
    const entry = try o.call(try o.get(state, "next"), try o.get(state, "iterator"), &.{});
    if (!c.JS_IsObject(entry)) return @import("native_js_values.zig").typeError(o.s.engine, "Iterator result is not an object");
    if (try propertyTruth(o.s.engine, entry, "done")) return c.pi_js_bool(o.s.engine.context, 0);
    const name = try o.get(entry, "value");
    try o.put(state, "closed", c.pi_js_bool(o.s.engine.context, 0)); try o.put(state, "envName", name);
    return c.pi_js_bool(o.s.engine.context, 1);
}
fn closeIterator(o: *x.Ops, state: c.JSValue) !void {
    if (x.nullish(state)) return;
    const iterator = try o.get(state, "iterator"); if (x.nullish(iterator) or o.truthy(try o.get(state, "closed"))) return;
    try o.put(state, "closed", c.pi_js_bool(o.s.engine.context, 1));
    const close = try o.get(iterator, "return"); if (x.nullish(close)) return;
    const result = try o.call(close, iterator, &.{});
    if (!c.JS_IsObject(result)) return @import("native_js_values.zig").typeError(o.s.engine, "Iterator return is not an object");
}
fn setResultSource(engine: *x.em.Engine, result: c.JSValue, state: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, setResultSourceBody(&o, result, state));
}
fn setResultSourceBody(o: *x.Ops, result: c.JSValue, state: c.JSValue) !void { return o.put(result, "source", try o.get(state, "envName")); }
fn endIterationAndClose(o: *x.Ops, state: c.JSValue) !void {
    if (!x.nullish(state)) try o.put(state, "envName", c.pi_js_undefined());
    return closeIterator(o, state);
}
fn preserveThrowClose(o: *x.Ops, state: c.JSValue, reason: c.JSValue) !af.Action {
    // Original Source throw wins over ordinary close errors. Fresh actual
    // native fatal events remain authoritative through the completion helper.
    var closing = x.owned.Completion.initVoid(o.s.engine, endIterationAndClose(o, state));
    const action = closing.finishAction() catch |err| {
        var failed = x.owned.Completion.initAction(o.s.engine, @as(anyerror!af.Action, err));
        failed.release(reason);
        return failed.finishAction();
    };
    var original = x.owned.Completion.initAction(o.s.engine, .{ .thrown = reason });
    switch (action) { .returned, .thrown => |value| original.release(value), .awaited => unreachable }
    return original.finishAction();
}

pub fn lazyFactory(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.finishInvocation(engine, &invocation, x.owned.finishValue(&s, lazyFactoryBody(&o, x.arg(args, 0))));
}
fn lazyFactoryBody(o: *x.Ops, input: c.JSValue) !c.JSValue {
    const shared = try o.cell(); try o.put(shared, "input", input); try o.put(shared, "promise", c.pi_js_undefined());
    const result = try o.object();
    inline for (.{ "name", "isSubscription", "loginLabel" }) |name| try o.put(result, name, try o.get(input, name));
    inline for (.{ "login", "refresh", "toAuth" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, value: c.JSValue) !af.Action {
                var s: x.Scope = .{ .engine = engine }; var local: x.Ops = .{ .s = &s };
                return x.owned.finishAction(&s, lazyBody(&local, args, roots[0], state, completion, value, name, index == 2));
            }
        };
        try o.put(result, name, try o.own(try af.createResumableArrow(o.s.engine, name, if (index == 2) 1 else 2, Adapter.call, &.{shared}, c.pi_js_undefined())));
    }
    return c.JS_DupValue(o.s.engine.context, result);
}
fn lazyBody(o: *x.Ops, args: []const c.JSValue, shared: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue, name: [*:0]const u8, one: bool) !af.Action {
    if (completion == .rejected) { try @import("native_async_body.zig").enterRejectedContinuation(o.s.engine); return .{ .thrown = c.JS_DupValue(o.s.engine.context, input) }; }
    if (completion == .start) {
        const job = try initialize(o, state); try o.put(job, "first", x.arg(args, 0));
        if (!one) try o.put(job, "second", x.arg(args, 1));
        var loaded = try o.get(shared, "promise");
        if (x.nullish(loaded)) { loaded = try o.invoke(try o.get(shared, "input"), "load", &.{}); try o.put(shared, "promise", loaded); }
        return awaited(o, job, .lazy, loaded);
    }
    const method = try o.get(input, name); const first = try o.get(state.*, "first");
    const result = if (one) try o.call(method, input, &.{first}) else try o.call(method, input, &.{ first, try o.get(state.*, "second") });
    return returned(o, result); // Tail return, never a second Await.
}

pub fn contextEnv(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, contextEnvBody(&o, x.arg(args, 0)));
}
fn contextEnvBody(o: *x.Ops, name: c.JSValue) !c.JSValue {
    const process = try o.get(try o.global("globalThis"), "process");
    const env = if (x.nullish(process)) c.pi_js_undefined() else try o.get(process, "env");
    const value = if (x.nullish(env)) c.pi_js_undefined() else try o.getKey(env, name);
    var valid = false;
    if (c.JS_IsString(value)) valid = o.truthy(try o.binary(6, try o.get(try o.invoke(value, "trim", &.{}), "length"), c.JS_NewInt32(o.s.engine.context, 0)));
    return c.JS_DupValue(o.s.engine.context, if (valid) value else c.pi_js_undefined());
}
// Same raw queued-import ABI consumed by native_jiti_native_import.zig.
// Its qualification remains an external dependency, not a claim of this lane.
extern "c" fn JS_PiDynamicImportGraph0(context: ?*c.JSContext, physical_basename: c.JSValue, specifier: c.JSValue) c.JSValue;
fn importNodeModule(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    return JS_PiDynamicImportGraph0(context, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined());
}
/// The real AI module owner supplies its physical auth/context.ts URL. This
/// additive route is never auto-selected by the legacy default factory.
pub fn contextAt(engine: *x.em.Engine, physical_auth_context_url: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.finishInvocation(engine, &invocation, x.owned.finishValue(&s, contextAtBody(&o, physical_auth_context_url)));
}
fn contextAtBody(o: *x.Ops, physical_auth_context_url: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(physical_auth_context_url)) return error.RequiredPhysicalAuthContextUrl;
    var length: usize = 0;
    const bytes = c.JS_ToCStringLen(o.s.engine.context, &length, physical_auth_context_url);
    if (bytes == null) return o.failed();
    defer c.JS_FreeCString(o.s.engine.context, bytes);
    const std = @import("std");
    if (!std.mem.startsWith(u8, bytes[0..length], "file://") or std.mem.indexOfScalar(u8, bytes[0..length], 0) != null) return error.RequiredPhysicalAuthContextUrl;
    var roots = [_]c.JSValue{physical_auth_context_url};
    const importing = try o.accept(c.JS_NewCFunctionData2(o.s.engine.context, importNodeModule, "importNodeModule", 1, 0, roots.len, &roots));
    return contextBody(o, importing);
}
fn contextBody(o: *x.Ops, import_node_module: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(o.s.engine.context, import_node_module)) return error.RequiredActualAuthContextImport;
    const result = try o.object();
    try o.put(result, "env", try o.own(try af.create(o.s.engine, "env", 1, contextEnv, &.{})));
    try o.put(result, "fileExists", try o.own(try af.createResumable(o.s.engine, "fileExists", 1, fileExists, &.{import_node_module})));
    return c.JS_DupValue(o.s.engine.context, result);
}
fn fileExists(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    const body_result = fileBody(&o, args, roots[0], state, completion, input);
    var outcome = x.owned.Completion.initAction(engine, body_result);
    const action = outcome.finishAction() catch |err| return x.owned.finishAction(&s, @as(anyerror!af.Action, err));
    if (action == .thrown) {
        var caught = x.owned.Completion.initAction(engine, returned(&o, c.pi_js_bool(engine.context, 0)));
        caught.release(action.thrown);
        caught.releaseScope(&s);
        return caught.finishAction();
    }
    return x.owned.finishAction(&s, action);
}
fn fileBody(o: *x.Ops, args: []const c.JSValue, importing: c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) { try @import("native_async_body.zig").enterRejectedContinuation(o.s.engine); return returned(o, c.pi_js_bool(o.s.engine.context, 0)); }
    if (completion == .start) {
        const job = try initialize(o, state); try o.put(job, "path", x.arg(args, 0));
        return awaited(o, job, .file_module, try o.call(importing, c.pi_js_undefined(), &.{try o.text("node:fs/promises")}));
    }
    switch (try stageOf(o, state.*)) {
        .file_module => {
            try o.put(state.*, "fs", input); const path = try o.get(state.*, "path");
            if (o.truthy(try o.invoke(path, "startsWith", &.{try o.text("~")}))) return awaited(o, state.*, .file_os, try o.call(importing, c.pi_js_undefined(), &.{try o.text("node:os")}));
            return access(o, state.*, path);
        },
        .file_os => {
            const home = try o.invoke(input, "homedir", &.{});
            const tail = try o.invoke(try o.get(state.*, "path"), "slice", &.{c.JS_NewInt32(o.s.engine.context, 1)});
            return access(o, state.*, try o.binary(0, home, tail));
        },
        .file_access => return returned(o, c.pi_js_bool(o.s.engine.context, 1)),
        else => return error.InvalidAuthContextStage,
    }
}
fn access(o: *x.Ops, state: c.JSValue, path: c.JSValue) !af.Action {
    return awaited(o, state, .file_access, try o.invoke(try o.get(state, "fs"), "access", &.{path}));
}
