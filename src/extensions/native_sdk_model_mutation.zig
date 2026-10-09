//! AgentSession model mutation with actual async auth and retained model identity.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
pub fn set(engine: *em.Engine, session: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    return prepare(engine, session, model, options) catch |err| rejected(engine, err);
}
fn rejected(engine: *em.Engine, err: anyerror) !c.JSValue {
    _ = sdk.fail(engine, err);
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    var functions: [2]c.JSValue = undefined;
    const pending = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(pending);
    defer for (functions) |function| engine.freeValue(function);
    var args = [_]c.JSValue{reason};
    const ignored = try engine.checked(c.JS_Call(engine.context, functions[1], c.pi_js_undefined(), args.len, &args));
    engine.freeValue(ignored);
    return pending;
}
fn prepare(engine: *em.Engine, session: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, session);
    const runtime = try sdk.get(engine, owner.data, "modelRuntime");
    defer engine.freeValue(runtime);
    const provider = try sdk.get(engine, model, "provider");
    defer engine.freeValue(provider);
    const checked = try sdk.invoke(engine, runtime, "checkAuth", &.{provider});
    defer engine.freeValue(checked);
    const pending = try sdk.promise(engine, checked);
    defer engine.freeValue(pending);
    var data = [_]c.JSValue{ session, model, options };
    const continuation = try engine.checked(c.JS_NewCFunctionData2(engine.context, checkedAuth, "sdkSetModelAfterAuth", 1, 0, data.len, &data));
    defer engine.freeValue(continuation);
    return engine.checked(c.JS_PromiseThen(engine.context, pending, continuation, c.pi_js_undefined()));
}
fn checkedAuth(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return afterAuth(engine, data[0], data[1], data[2], argc > 0 and c.JS_ToBool(context, argv[0]) == 1) catch |err| sdk.fail(engine, err);
}
fn afterAuth(engine: *em.Engine, session: c.JSValue, model: c.JSValue, options: c.JSValue, authenticated: bool) !c.JSValue {
    if (!authenticated) {
        const provider = try sdk.get(engine, model, "provider");
        defer engine.freeValue(provider);
        const id = try sdk.get(engine, model, "id");
        defer engine.freeValue(id);
        const p = try engine.toString(provider);
        defer engine.gpa.free(p);
        const m = try engine.toString(id);
        defer engine.gpa.free(m);
        const message = try std.fmt.allocPrint(engine.gpa, "No API key for {s}/{s}", .{ p, m });
        defer engine.gpa.free(message);
        const reason = try engine.checked(c.JS_NewError(engine.context));
        var consumed = false;
        errdefer if (!consumed) engine.freeValue(reason);
        try sdk.put(engine, reason, "message", try sdk.text(engine, message));
        consumed = true;
        return engine.checked(c.JS_Throw(engine.context, reason));
    }
    const owner = try sdk.state(engine, session);
    const previous = try sdk.agentField(owner, "model");
    defer engine.freeValue(previous);
    const settings = try sdk.get(engine, owner.data, "settingsManager");
    defer engine.freeValue(settings);
    var thinking = try invokePair(engine, settings, "getModelThinkingLevel", model);
    defer engine.freeValue(thinking);
    if (c.JS_IsUndefined(thinking)) {
        engine.freeValue(thinking);
        thinking = try sdk.invoke(engine, settings, "getDefaultThinkingLevel", &.{});
        if (c.JS_IsUndefined(thinking) or c.JS_IsNull(thinking)) {
            engine.freeValue(thinking);
            thinking = try sdk.agentField(owner, "thinkingLevel");
            if (c.JS_IsUndefined(thinking) or c.JS_IsNull(thinking)) {
                engine.freeValue(thinking);
                thinking = try sdk.text(engine, "medium");
            }
        }
    }
    try sdk.setAgentField(owner, "model", model);
    const manager = try sdk.get(engine, owner.data, "sessionManager");
    defer engine.freeValue(manager);
    const recorded = try invokePair(engine, manager, "appendModelChange", model);
    engine.freeValue(recorded);
    const persist = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "persist");
    defer engine.freeValue(persist);
    if (c.JS_ToBool(engine.context, persist) == 1) {
        const saved = try invokePair(engine, settings, "setDefaultModelAndProvider", model);
        engine.freeValue(saved);
        try addPersistedScope(engine, owner, settings, model);
    }
    try @import("native_sdk_thinking.zig").set(engine, session, thinking, c.pi_js_undefined());
    if (try equal(engine, previous, model)) return sdk.promise(engine, c.pi_js_undefined());
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "model", c.JS_DupValue(engine.context, model));
    try sdk.put(engine, event, "previousModel", c.JS_DupValue(engine.context, previous));
    try sdk.put(engine, event, "source", try sdk.text(engine, "set"));
    const resources = try sdk.get(engine, owner.data, "resourceLoader");
    defer engine.freeValue(resources);
    return @import("native_sdk_resources.zig").emitValue(engine, resources, owner.data, "model_select", event);
}
fn invokePair(engine: *em.Engine, receiver: c.JSValue, name: [*:0]const u8, model: c.JSValue) !c.JSValue {
    const provider = try sdk.get(engine, model, "provider");
    defer engine.freeValue(provider);
    const id = try sdk.get(engine, model, "id");
    defer engine.freeValue(id);
    return sdk.invoke(engine, receiver, name, &.{ provider, id });
}
fn equal(engine: *em.Engine, left: c.JSValue, right: c.JSValue) !bool {
    if (c.JS_IsNull(left) or c.JS_IsUndefined(left) or c.JS_IsNull(right) or c.JS_IsUndefined(right)) return false;
    inline for (.{ "type", "id", "provider" }) |key| {
        const a = try sdk.get(engine, left, key);
        defer engine.freeValue(a);
        const b = try sdk.get(engine, right, key);
        defer engine.freeValue(b);
        if (comptime std.mem.eql(u8, key, "type")) {
            const av = if (c.JS_IsUndefined(a) or c.JS_IsNull(a)) try sdk.text(engine, "chat") else c.JS_DupValue(engine.context, a);
            defer engine.freeValue(av);
            const bv = if (c.JS_IsUndefined(b) or c.JS_IsNull(b)) try sdk.text(engine, "chat") else c.JS_DupValue(engine.context, b);
            defer engine.freeValue(bv);
            if (!c.JS_IsStrictEqual(engine.context, av, bv)) return false;
        } else if (!c.JS_IsStrictEqual(engine.context, a, b)) return false;
    }
    return true;
}
fn addPersistedScope(engine: *em.Engine, owner: *sdk.State, settings: c.JSValue, model: c.JSValue) !void {
    const scope = try sdk.get(engine, owner.data, "scopedModels");
    defer engine.freeValue(scope);
    if (!c.JS_IsArray(scope) or try sdk.length(engine, scope) == 0) return;
    const updated = try sdk.array(engine);
    defer engine.freeValue(updated);
    for (0..try sdk.length(engine, scope)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, scope, @intCast(index)));
        defer engine.freeValue(row);
        const selected = try sdk.get(engine, row, "model");
        defer engine.freeValue(selected);
        if (try equal(engine, selected, model)) return;
        try sdk.append(engine, updated, c.JS_DupValue(engine.context, row));
    }
    const added = try sdk.object(engine);
    defer engine.freeValue(added);
    try sdk.put(engine, added, "model", c.JS_DupValue(engine.context, model));
    try sdk.append(engine, updated, c.JS_DupValue(engine.context, added));
    try sdk.put(engine, owner.data, "scopedModels", c.JS_DupValue(engine.context, updated));
    const enabled = try sdk.invoke(engine, settings, "getEnabledModels", &.{});
    defer engine.freeValue(enabled);
    if (!c.JS_IsArray(enabled) or try sdk.length(engine, enabled) == 0) return;
    const provider = try sdk.get(engine, model, "provider");
    defer engine.freeValue(provider);
    const p = try engine.toString(provider);
    defer engine.gpa.free(p);
    const id = try sdk.get(engine, model, "id");
    defer engine.freeValue(id);
    const m = try engine.toString(id);
    defer engine.gpa.free(m);
    const raw = try std.fmt.allocPrint(engine.gpa, "{s}/{s}", .{ p, m });
    defer engine.gpa.free(raw);
    const reference = try sdk.text(engine, raw);
    defer engine.freeValue(reference);
    const lower = try sdk.invoke(engine, reference, "toLowerCase", &.{});
    defer engine.freeValue(lower);
    const patterns = try sdk.array(engine);
    defer engine.freeValue(patterns);
    for (0..try sdk.length(engine, enabled)) |index| {
        const pattern = try engine.checked(c.JS_GetPropertyUint32(engine.context, enabled, @intCast(index)));
        defer engine.freeValue(pattern);
        const pattern_lower = try sdk.invoke(engine, pattern, "toLowerCase", &.{});
        defer engine.freeValue(pattern_lower);
        if (c.JS_IsStrictEqual(engine.context, pattern_lower, lower)) return;
        try sdk.append(engine, patterns, c.JS_DupValue(engine.context, pattern));
    }
    try sdk.append(engine, patterns, c.JS_DupValue(engine.context, reference));
    const saved = try sdk.invoke(engine, settings, "setEnabledModels", &.{patterns});
    engine.freeValue(saved);
}

pub fn setFromPi(engine: *em.Engine, session: c.JSValue, model: c.JSValue) !c.JSValue {
    return preparePi(engine, session, model) catch |err| rejected(engine, err);
}
fn preparePi(engine: *em.Engine, session: c.JSValue, model: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, session);
    const runtime = try sdk.get(engine, owner.data, "modelRuntime");
    defer engine.freeValue(runtime);
    const provider = try sdk.get(engine, model, "provider");
    defer engine.freeValue(provider);
    const configured = try sdk.invoke(engine, runtime, "hasConfiguredAuth", &.{provider});
    defer engine.freeValue(configured);
    if (c.JS_ToBool(engine.context, configured) != 1) return sdk.promise(engine, c.pi_js_bool(engine.context, 0));
    const pending = try set(engine, session, model, c.pi_js_undefined());
    defer engine.freeValue(pending);
    const yes = try engine.checked(c.JS_NewCFunction2(engine.context, fulfilledTrue, "sdkModelSelected", 0, c.JS_CFUNC_generic, 0));
    defer engine.freeValue(yes);
    return engine.checked(c.JS_PromiseThen(engine.context, pending, yes, c.pi_js_undefined()));
}
fn fulfilledTrue(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, 1);
}
