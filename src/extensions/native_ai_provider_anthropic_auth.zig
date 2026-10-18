//! Actual c268154c providers/anthropic.ts anthropicApiKeyAuth only.
//! Two genuine async arrows: login has one Await; resolve has four lexical
//! Await sites, executing zero through eight env Awaits on its actual paths.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const af = x.af;
const Stage = enum(i32) { prompt, auth_token, keys, required, optional };
const keys = .{ "ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY" };
const required = .{ "ANTHROPIC_FEDERATION_RULE_ID", "ANTHROPIC_ORGANIZATION_ID", "ANTHROPIC_IDENTITY_TOKEN_FILE" };
const optional = .{ "ANTHROPIC_SERVICE_ACCOUNT_ID", "ANTHROPIC_WORKSPACE_ID" };
fn returned(engine: *x.em.Engine, value: c.JSValue) af.Action { return .{ .returned = c.JS_DupValue(engine.context, value) }; }
fn awaited(o: *x.Ops, state: c.JSValue, stage: Stage, value: c.JSValue) !af.Action {
    try o.put(state, "stage", c.JS_NewInt32(o.s.engine.context, @intFromEnum(stage)));
    return .{ .awaited = c.JS_DupValue(o.s.engine.context, value) };
}
fn stageOf(o: *x.Ops, state: c.JSValue) !Stage {
    var raw: i32 = 0;
    if (c.JS_ToInt32(o.s.engine.context, &raw, try o.get(state, "stage")) < 0) return o.failed();
    return @enumFromInt(raw);
}
fn initialize(o: *x.Ops, state: *c.JSValue) !c.JSValue {
    const job = try o.cell(); af.replaceState(o.s.engine, state, c.JS_DupValue(o.s.engine.context, job));
    try o.s.engine.checkNativeEntry(); return job;
}
pub fn create(engine: *x.em.Engine) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.finishInvocation(engine, &invocation, x.owned.finishValue(&s, createBody(&o)));
}
fn createBody(o: *x.Ops) !c.JSValue {
    const result = try o.object(); try o.put(result, "name", try o.text("Anthropic API key"));
    try o.put(result, "login", try o.own(try af.createResumableArrow(o.s.engine, "login", 1, login, &.{}, c.pi_js_undefined())));
    try o.put(result, "resolve", try o.own(try af.createResumableArrow(o.s.engine, "resolve", 1, resolve, &.{}, c.pi_js_undefined())));
    return c.JS_DupValue(o.s.engine.context, result);
}
fn abort(engine: *x.em.Engine, receiver: c.JSValue, interaction: bool) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, abortBody(&o, receiver, interaction));
}
fn abortBody(o: *x.Ops, receiver: c.JSValue, interaction: bool) !void {
    const signal = if (interaction) try o.get(receiver, "signal") else receiver;
    _ = try o.invoke(signal, "throwIfAborted", &.{});
}
fn login(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishAction(&s, loginBody(&o, args, state, completion, input));
}
fn loginBody(o: *x.Ops, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) { try @import("native_async_body.zig").enterRejectedContinuation(o.s.engine); return .{ .thrown = c.JS_DupValue(o.s.engine.context, input) }; }
    if (completion == .start) {
        const job = try initialize(o, state); const interaction = x.arg(args, 0); try o.put(job, "interaction", interaction);
        try abort(o.s.engine, interaction, true);
        const prompt = try o.get(interaction, "prompt");
        const options = try o.object(); try o.put(options, "type", try o.text("secret")); try o.put(options, "message", try o.text("Enter Anthropic API key"));
        return awaited(o, job, .prompt, try o.call(prompt, interaction, &.{options}));
    }
    try abort(o.s.engine, try o.get(state.*, "interaction"), true);
    const result = try o.object(); try o.put(result, "type", try o.text("api_key")); try o.put(result, "key", input);
    return returned(o.s.engine, result);
}
fn resolve(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    var captured = x.owned.Completion.initAction(engine, resolveBody(&o, args, state, completion, input));
    const selected = captured.finishAction() catch |err| return x.owned.finishAction(&s, @as(anyerror!af.Action, err));
    const final: anyerror!af.Action = if (selected == .thrown) preserveThrowClose(&o, state.*, selected.thrown) else selected;
    return x.owned.finishAction(&s, final);
}
fn resolveBody(o: *x.Ops, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) { try @import("native_async_body.zig").enterRejectedContinuation(o.s.engine); return .{ .thrown = c.JS_DupValue(o.s.engine.context, input) }; }
    if (completion == .start) {
        const argument = x.arg(args, 0); const ctx = try o.get(argument, "ctx"); const credential = try o.get(argument, "credential"); const signal = try o.get(argument, "signal");
        const job = try initialize(o, state); try o.put(job, "ctx", ctx); try o.put(job, "credential", credential); try o.put(job, "signal", signal);
        try abort(o.s.engine, signal, false);
        if (!x.nullish(credential) and try propertyTruth(o.s.engine, credential, "key")) return returned(o.s.engine, try stored(o, credential));
        return env(o, job, .auth_token, try o.text("ANTHROPIC_AUTH_TOKEN"));
    }
    try abort(o.s.engine, try o.get(state.*, "signal"), false);
    const stage = try stageOf(o, state.*);
    if (stage == .auth_token) {
        if (o.truthy(input)) {
            const auth = try o.object(); const headers = try o.object();
            try o.put(headers, "Authorization", try o.binary(0, try o.text("Bearer "), try o.stringify(input))); try o.put(auth, "headers", headers);
            return returned(o.s.engine, try result(o, auth, c.pi_js_undefined(), try o.text("ANTHROPIC_AUTH_TOKEN")));
        }
        try startLoop(o.s.engine, state.*, .keys, keys); return nextEnv(o, state.*, .keys);
    }
    if (stage == .keys and o.truthy(input)) {
        const auth = try o.object(); try o.put(auth, "apiKey", input);
        // The pending return value remains owned across Source IteratorClose.
        const value = try o.own(try resultWithName(o.s.engine, auth, state.*));
        return closeReturning(o, state.*, value);
    }
    if (stage == .required and !o.truthy(input)) return closeReturning(o, state.*, c.pi_js_undefined());
    if (stage == .required or (stage == .optional and o.truthy(input))) try assignFederation(o.s.engine, state.*, input);
    return nextEnv(o, state.*, stage);
}
fn stored(o: *x.Ops, credential: c.JSValue) !c.JSValue {
    const auth = try o.object(); try o.put(auth, "apiKey", try o.get(credential, "key"));
    const value = try o.object(); try o.put(value, "auth", auth); try o.put(value, "env", try o.get(credential, "env")); try o.put(value, "source", try o.text("stored credential"));
    return value;
}
fn result(o: *x.Ops, auth: c.JSValue, environment: c.JSValue, source: c.JSValue) !c.JSValue {
    const value = try o.object(); try o.put(value, "auth", auth);
    if (!c.JS_IsUndefined(environment)) try o.put(value, "env", environment);
    try o.put(value, "source", source); return value;
}
fn env(o: *x.Ops, state: c.JSValue, stage: Stage, name: c.JSValue) !af.Action {
    return awaited(o, state, stage, try o.invoke(try o.get(state, "ctx"), "env", &.{name}));
}
fn literal(o: *x.Ops, comptime names: anytype) !c.JSValue {
    const generation = try o.beforeAllocation();
    const array = try o.allocation(c.JS_NewArray(o.s.engine.context), generation);
    inline for (names, 0..) |name, index| {
        const text = try o.text(name);
        try x.guest.index(o.s, array, index, text);
    }
    return array;
}
fn startLoop(engine: *x.em.Engine, state: c.JSValue, stage: Stage, comptime names: anytype) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, startLoopBody(&o, state, stage, names));
}
fn startLoopBody(o: *x.Ops, state: c.JSValue, stage: Stage, comptime names: anytype) !void {
    const array = try literal(o, names); const symbol = try o.accept(c.JS_GetIteratorSymbol(o.s.engine.context));
    const iterator = try o.call(try o.getKey(array, symbol), array, &.{});
    if (!c.JS_IsObject(iterator)) return @import("native_js_values.zig").typeError(o.s.engine, "Iterator is not an object");
    const next = try o.get(iterator, "next");
    try o.put(state, "iterator", iterator); try o.put(state, "next", next); try o.put(state, "closed", c.pi_js_bool(o.s.engine.context, 1));
    try o.put(state, "envName", c.pi_js_undefined());
    try o.put(state, "stage", c.JS_NewInt32(o.s.engine.context, @intFromEnum(stage)));
}
fn propertyTruth(engine: *x.em.Engine, receiver: c.JSValue, name: [*:0]const u8) !bool {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    const pending: anyerror!c.JSValue = if (o.get(receiver, name)) |value| c.pi_js_bool(engine.context, @intFromBool(o.truthy(value))) else |err| err;
    return c.JS_ToBool(engine.context, try x.owned.finishValue(&s, pending)) == 1;
}
fn nextValue(engine: *x.em.Engine, state: c.JSValue) !bool {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return c.JS_ToBool(engine.context, try x.owned.finishValue(&s, nextValueBody(&o, state))) == 1;
}
fn nextValueBody(o: *x.Ops, state: c.JSValue) !c.JSValue {
    const entry = try o.call(try o.get(state, "next"), try o.get(state, "iterator"), &.{});
    if (!c.JS_IsObject(entry)) return @import("native_js_values.zig").typeError(o.s.engine, "Iterator result is not an object");
    if (try propertyTruth(o.s.engine, entry, "done")) return c.pi_js_bool(o.s.engine.context, 0);
    const name = try o.get(entry, "value"); try o.put(state, "closed", c.pi_js_bool(o.s.engine.context, 0)); try o.put(state, "envName", name);
    return c.pi_js_bool(o.s.engine.context, 1);
}
fn retireLoop(o: *x.Ops, state: c.JSValue) !void {
    try o.put(state, "envName", c.pi_js_undefined()); try o.put(state, "iterator", c.pi_js_undefined()); try o.put(state, "next", c.pi_js_undefined());
}
fn nextEnv(o: *x.Ops, state: c.JSValue, stage: Stage) !af.Action {
    try o.put(state, "envName", c.pi_js_undefined()); try o.put(state, "closed", c.pi_js_bool(o.s.engine.context, 1));
    if (try nextValue(o.s.engine, state)) return env(o, state, stage, try o.get(state, "envName"));
    try retireLoop(o, state);
    if (stage == .keys) { try o.put(state, "federation", try o.object()); try startLoop(o.s.engine, state, .required, required); return nextEnv(o, state, .required); }
    if (stage == .required) { try startLoop(o.s.engine, state, .optional, optional); return nextEnv(o, state, .optional); }
    return returned(o.s.engine, try result(o, try o.object(), try o.get(state, "federation"), try o.text("workload identity federation")));
}
fn resultWithName(engine: *x.em.Engine, auth: c.JSValue, state: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, resultWithNameBody(&o, auth, state));
}
fn resultWithNameBody(o: *x.Ops, auth: c.JSValue, state: c.JSValue) !c.JSValue { return c.JS_DupValue(o.s.engine.context, try result(o, auth, c.pi_js_undefined(), try o.get(state, "envName"))); }
fn assignFederation(engine: *x.em.Engine, state: c.JSValue, input: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, assignFederationBody(&o, state, input));
}
fn assignFederationBody(o: *x.Ops, state: c.JSValue, input: c.JSValue) !void {
    const target = try o.get(state, "federation"); const key = try o.get(state, "envName");
    var coercion: x.guest.Boundary = .{ .engine = o.s.engine };
    try coercion.begin();
    const atom = c.JS_ValueToAtom(o.s.engine.context, key);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(o.s.engine.context, atom);
    try coercion.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    // Source assignment uses [[Set]], including live inherited setters.
    var assignment: x.guest.Boundary = .{ .engine = o.s.engine };
    try assignment.begin();
    return assignment.finishStatus(c.JS_SetProperty(o.s.engine.context, target, atom, c.JS_DupValue(o.s.engine.context, input)));
}
fn closeLoop(o: *x.Ops, state: c.JSValue) !void {
    if (x.nullish(state)) return;
    const iterator = try o.get(state, "iterator"); if (x.nullish(iterator)) return;
    try o.put(state, "envName", c.pi_js_undefined());
    if (o.truthy(try o.get(state, "closed"))) return;
    try o.put(state, "closed", c.pi_js_bool(o.s.engine.context, 1)); const close = try o.get(iterator, "return");
    if (!x.nullish(close)) { const value = try o.call(close, iterator, &.{}); if (!c.JS_IsObject(value)) return @import("native_js_values.zig").typeError(o.s.engine, "Iterator return is not an object"); }
    try retireLoop(o, state);
}
fn closeReturning(o: *x.Ops, state: c.JSValue, value: c.JSValue) !af.Action { try closeLoop(o, state); return returned(o.s.engine, value); }
fn preserveThrowClose(o: *x.Ops, state: c.JSValue, reason: c.JSValue) !af.Action {
    var closing = x.owned.Completion.initVoid(o.s.engine, closeLoop(o, state));
    const action = closing.finishAction() catch |err| { var failed = x.owned.Completion.initAction(o.s.engine, @as(anyerror!af.Action, err)); failed.release(reason); return failed.finishAction(); };
    var original = x.owned.Completion.initAction(o.s.engine, .{ .thrown = reason });
    switch (action) { .returned, .thrown => |value| original.release(value), .awaited => unreachable }
    return original.finishAction();
}
