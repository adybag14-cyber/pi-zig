//! AgentSession model mutation with actual async auth and retained model identity.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
// A direct native allocator outcome is a producer before deferred JS roots
// can publish a later cleanup event. Other typed failures retain their class.
fn nativeAllocation(engine: anytype, result: anytype) @TypeOf(result) {
    return result catch |err| {
        if (@as(anyerror, err) == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
        return err;
    };
}
fn nativeText(engine: anytype, value: c.JSValue) anyerror![]u8 {
    try engine.checkNativeEntry();
    return nativeAllocation(engine, engine.toString(value));
}

pub fn set(engine: *em.Engine, session: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    return prepare(engine, session, model, options) catch |err| rejected(engine, err);
}
fn rejected(engine: *em.Engine, err: anyerror) !c.JSValue {
    const reason = try @import("native_agent_async.zig").reason(engine, err);
    defer engine.releaseNativeValue(reason);
    var functions: [2]c.JSValue = undefined;
    const pending = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.releaseNativeValue(pending);
    defer for (functions) |function| engine.releaseNativeValue(function);
    var args = [_]c.JSValue{reason};
    try engine.checkNativeEntry();
    const ignored = try engine.checked(c.JS_Call(engine.context, functions[1], c.pi_js_undefined(), args.len, &args));
    engine.releaseNativeValue(ignored);
    return pending;
}
fn prepare(engine: *em.Engine, session: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, session);
    const runtime = try sdk.get(engine, owner.data, "modelRuntime");
    defer engine.releaseNativeValue(runtime);
    const provider = try sdk.get(engine, model, "provider");
    defer engine.releaseNativeValue(provider);
    const checked = try sdk.invoke(engine, runtime, "checkAuth", &.{provider});
    defer engine.releaseNativeValue(checked);
    const pending = try sdk.promise(engine, checked);
    defer engine.releaseNativeValue(pending);
    var data = [_]c.JSValue{ session, model, options };
    const continuation = try engine.checked(c.JS_NewCFunctionData2(engine.context, checkedAuth, "sdkSetModelAfterAuth", 1, 0, data.len, &data));
    defer engine.releaseNativeValue(continuation);
    try engine.checkNativeEntry();
    return engine.checked(c.JS_PromiseThen(engine.context, pending, continuation, c.pi_js_undefined()));
}
fn checkedAuth(context: ?*c.JSContext, ignored0: c.JSValue, argc: c_int, argv: [*c]c.JSValue, ignored1: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(checkedAuthOwnedBody(context, ignored0, argc, argv, ignored1, data));
}
fn checkedAuthOwnedBody(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return afterAuth(engine, data[0], data[1], data[2], argc > 0 and c.JS_ToBool(context, argv[0]) == 1) catch |err| sdk.fail(engine, err);
}
fn afterAuth(engine: *em.Engine, session: c.JSValue, model: c.JSValue, options: c.JSValue, authenticated: bool) !c.JSValue {
    if (!authenticated) {
        const provider = try sdk.get(engine, model, "provider");
        defer engine.releaseNativeValue(provider);
        const id = try sdk.get(engine, model, "id");
        defer engine.releaseNativeValue(id);
        const p = try nativeText(engine, provider);
        defer engine.gpa.free(p);
        const m = try nativeText(engine, id);
        defer engine.gpa.free(m);
        const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "No API key for {s}/{s}", .{ p, m }));
        defer engine.gpa.free(message);
        const reason = try engine.checked(c.JS_NewError(engine.context));
        var consumed = false;
        errdefer if (!consumed) engine.releaseNativeValue(reason);
        try sdk.put(engine, reason, "message", try sdk.text(engine, message));
        consumed = true;
        return engine.checked(c.JS_PiThrowExceptionData(engine.context, reason));
    }
    const owner = try sdk.state(engine, session);
    const previous = try sdk.agentField(owner, "model");
    defer engine.releaseNativeValue(previous);
    const settings = try sdk.publicField(owner, "settingsManager");
    defer engine.releaseNativeValue(settings);
    var thinking = try invokePair(engine, settings, "getModelThinkingLevel", model);
    defer engine.releaseNativeValue(thinking);
    if (c.JS_IsUndefined(thinking)) {
        engine.releaseNativeValue(thinking);
        thinking = try sdk.invoke(engine, settings, "getDefaultThinkingLevel", &.{});
        if (c.JS_IsUndefined(thinking) or c.JS_IsNull(thinking)) {
            engine.releaseNativeValue(thinking);
            thinking = try sdk.agentField(owner, "thinkingLevel");
            if (c.JS_IsUndefined(thinking) or c.JS_IsNull(thinking)) {
                engine.releaseNativeValue(thinking);
                thinking = try sdk.text(engine, "medium");
            }
        }
    }
    try sdk.setAgentField(owner, "model", model);
    const manager = try sdk.publicField(owner, "sessionManager");
    defer engine.releaseNativeValue(manager);
    const recorded = try invokePair(engine, manager, "appendModelChange", model);
    engine.releaseNativeValue(recorded);
    const persist = if (c.JS_IsUndefined(options)) c.pi_js_undefined() else try sdk.get(engine, options, "persist");
    defer engine.releaseNativeValue(persist);
    if (c.JS_ToBool(engine.context, persist) == 1) {
        const saved = try invokePair(engine, settings, "setDefaultModelAndProvider", model);
        engine.releaseNativeValue(saved);
        try addPersistedScope(engine, owner, settings, model);
    }
    try @import("native_sdk_thinking.zig").set(engine, session, thinking, c.pi_js_undefined());
    if (try equal(engine, previous, model)) return sdk.promise(engine, c.pi_js_undefined());
    const event = try sdk.object(engine);
    defer engine.releaseNativeValue(event);
    try sdk.put(engine, event, "model", c.JS_DupValue(engine.context, model));
    try sdk.put(engine, event, "previousModel", c.JS_DupValue(engine.context, previous));
    try sdk.put(engine, event, "source", try sdk.text(engine, "set"));
    const resources = try sdk.get(engine, owner.data, "resourceLoader");
    defer engine.releaseNativeValue(resources);
    return @import("native_sdk_resources.zig").emitValue(engine, resources, owner.data, "model_select", event);
}
fn invokePair(engine: *em.Engine, receiver: c.JSValue, name: [*:0]const u8, model: c.JSValue) !c.JSValue {
    const provider = try sdk.get(engine, model, "provider");
    defer engine.releaseNativeValue(provider);
    const id = try sdk.get(engine, model, "id");
    defer engine.releaseNativeValue(id);
    return sdk.invoke(engine, receiver, name, &.{ provider, id });
}
fn equal(engine: *em.Engine, left: c.JSValue, right: c.JSValue) !bool {
    if (c.JS_IsNull(left) or c.JS_IsUndefined(left) or c.JS_IsNull(right) or c.JS_IsUndefined(right)) return false;
    inline for (.{ "type", "id", "provider" }) |key| {
        const a = try sdk.get(engine, left, key);
        defer engine.releaseNativeValue(a);
        const b = try sdk.get(engine, right, key);
        defer engine.releaseNativeValue(b);
        if (comptime std.mem.eql(u8, key, "type")) {
            const av = if (c.JS_IsUndefined(a) or c.JS_IsNull(a)) try sdk.text(engine, "chat") else c.JS_DupValue(engine.context, a);
            defer engine.releaseNativeValue(av);
            const bv = if (c.JS_IsUndefined(b) or c.JS_IsNull(b)) try sdk.text(engine, "chat") else c.JS_DupValue(engine.context, b);
            defer engine.releaseNativeValue(bv);
            if (!c.JS_IsStrictEqual(engine.context, av, bv)) return false;
        } else if (!c.JS_IsStrictEqual(engine.context, a, b)) return false;
    }
    return true;
}
fn addPersistedScope(engine: *em.Engine, owner: *sdk.State, settings: c.JSValue, model: c.JSValue) !void {
    const scope = try sdk.get(engine, owner.data, "scopedModels");
    defer engine.releaseNativeValue(scope);
    if (!c.JS_IsArray(scope) or try sdk.length(engine, scope) == 0) return;
    const updated = try sdk.array(engine);
    defer engine.releaseNativeValue(updated);
    for (0..try sdk.length(engine, scope)) |index| {
        try engine.checkNativeEntry();
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, scope, @intCast(index)));
        defer engine.releaseNativeValue(row);
        const selected = try sdk.get(engine, row, "model");
        defer engine.releaseNativeValue(selected);
        if (try equal(engine, selected, model)) return;
        try sdk.append(engine, updated, c.JS_DupValue(engine.context, row));
    }
    const added = try sdk.object(engine);
    defer engine.releaseNativeValue(added);
    try sdk.put(engine, added, "model", c.JS_DupValue(engine.context, model));
    try sdk.append(engine, updated, c.JS_DupValue(engine.context, added));
    try sdk.put(engine, owner.data, "scopedModels", c.JS_DupValue(engine.context, updated));
    const enabled = try sdk.invoke(engine, settings, "getEnabledModels", &.{});
    defer engine.releaseNativeValue(enabled);
    if (!c.JS_IsArray(enabled) or try sdk.length(engine, enabled) == 0) return;
    const provider = try sdk.get(engine, model, "provider");
    defer engine.releaseNativeValue(provider);
    const p = try nativeText(engine, provider);
    defer engine.gpa.free(p);
    const id = try sdk.get(engine, model, "id");
    defer engine.releaseNativeValue(id);
    const m = try nativeText(engine, id);
    defer engine.gpa.free(m);
    const raw = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "{s}/{s}", .{ p, m }));
    defer engine.gpa.free(raw);
    const reference = try sdk.text(engine, raw);
    defer engine.releaseNativeValue(reference);
    const lower = try sdk.invoke(engine, reference, "toLowerCase", &.{});
    defer engine.releaseNativeValue(lower);
    const patterns = try sdk.array(engine);
    defer engine.releaseNativeValue(patterns);
    for (0..try sdk.length(engine, enabled)) |index| {
        try engine.checkNativeEntry();
        const pattern = try engine.checked(c.JS_GetPropertyUint32(engine.context, enabled, @intCast(index)));
        defer engine.releaseNativeValue(pattern);
        const pattern_lower = try sdk.invoke(engine, pattern, "toLowerCase", &.{});
        defer engine.releaseNativeValue(pattern_lower);
        if (c.JS_IsStrictEqual(engine.context, pattern_lower, lower)) return;
        try sdk.append(engine, patterns, c.JS_DupValue(engine.context, pattern));
    }
    try sdk.append(engine, patterns, c.JS_DupValue(engine.context, reference));
    const saved = try sdk.invoke(engine, settings, "setEnabledModels", &.{patterns});
    engine.releaseNativeValue(saved);
}

pub fn setFromPi(engine: *em.Engine, session: c.JSValue, model: c.JSValue) !c.JSValue {
    return preparePi(engine, session, model) catch |err| rejected(engine, err);
}
fn preparePi(engine: *em.Engine, session: c.JSValue, model: c.JSValue) !c.JSValue {
    const owner = try sdk.state(engine, session);
    const runtime = try sdk.get(engine, owner.data, "modelRuntime");
    defer engine.releaseNativeValue(runtime);
    const provider = try sdk.get(engine, model, "provider");
    defer engine.releaseNativeValue(provider);
    const configured = try sdk.invoke(engine, runtime, "hasConfiguredAuth", &.{provider});
    defer engine.releaseNativeValue(configured);
    if (c.JS_ToBool(engine.context, configured) != 1) return sdk.promise(engine, c.pi_js_bool(engine.context, 0));
    const pending = try set(engine, session, model, c.pi_js_undefined());
    defer engine.releaseNativeValue(pending);
    const yes = try engine.checked(c.JS_NewCFunction2(engine.context, fulfilledTrue, "sdkModelSelected", 0, c.JS_CFUNC_generic, 0));
    defer engine.releaseNativeValue(yes);
    try engine.checkNativeEntry();
    return engine.checked(c.JS_PromiseThen(engine.context, pending, yes, c.pi_js_undefined()));
}
fn fulfilledTrue(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, 1);
}
