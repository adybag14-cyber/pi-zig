//! Original request-authentication and model-routing bodies over ordinary
//! session fields. Imported native functions are lexical VM roots, not stubs.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const Method = enum(c_int) { _getRequiredRequestAuth, _getSummarizationRequestAuth, _modelForMessage, _recordSelection };
const Stage = enum(c_int) { required, routed, optional, selected_required };
pub fn install(engine: *em.Engine, prototype: c.JSValue, dependencies: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{ try scope.get(dependencies, "streamSimple"), try scope.get(dependencies, "convertToLlm") };
    for (roots) |function| if (!c.JS_IsFunction(engine.context, function)) return error.NativeSessionAuthImportMissing;
    inline for (std.meta.fields(Method)) |field| {
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value < 2) 2 else if (field.value == 2) 1 else 0, field.value, roots.len, &roots)));
        if (field.value < 2) {
            const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const first = if (argc > 0) argv[0] else c.pi_js_undefined();
    const second = if (argc > 1) argv[1] else c.pi_js_undefined();
    const method: Method = @enumFromInt(magic);
    if (magic < 2) return begin(engine, session, method, first, second, roots[0], roots[1]) catch |err| sdk.fail(engine, err);
    return (if (method == ._modelForMessage) modelForMessage(engine, session, first) else recordSelection(engine, session)) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, session: c.JSValue, method: Method, model: c.JSValue, signal: c.JSValue, stream: c.JSValue, convert: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, method, model, signal, stream, convert) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, method: Method, model: c.JSValue, signal: c.JSValue, stream: c.JSValue, convert: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
    try scope.put(owner, "model", model);
    try scope.put(owner, "signal", signal);
    try scope.put(owner, "stream", stream);
    try scope.put(owner, "convert", convert);
    if (method == ._getRequiredRequestAuth) return auth(engine, owner, .required);
    if (try virtual(&scope, model)) {
        const session = try scope.get(owner, "agent");
        const runtime = try scope.get(session, "_modelRuntime");
        const resolver = try scope.get(runtime, "resolveModel");
        const messages = try scope.call(convert, c.pi_js_undefined(), &.{try scope.get(session, "messages")});
        const options = try scope.object();
        try scope.put(options, "reason", try scope.text("direct"));
        try scope.put(options, "thinkingLevel", try scope.get(session, "thinkingLevel"));
        try scope.put(options, "signal", signal);
        return wait(engine, owner, try scope.call(resolver, runtime, &.{ model, messages, options }), .routed);
    }
    try scope.put(owner, "thinking", try scope.get(try scope.get(owner, "agent"), "thinkingLevel"));
    try summaryAuth(engine, owner);
}
fn wait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(advance, engine, owner, value, @intFromEnum(stage));
}
fn auth(engine: *em.Engine, owner: c.JSValue, stage: Stage) !void {
    const generation = engine.native_allocation_generation;
    invokeAuth(engine, owner, stage) catch |err| {
        if (err == error.OutOfMemory or engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        const raw = flow.reason(engine, err);
        defer engine.freeValue(raw);
        return rejected(engine, owner, stage, raw);
    };
}
fn invokeAuth(engine: *em.Engine, owner: c.JSValue, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const runtime = try scope.get(try scope.get(owner, "agent"), "_modelRuntime");
    const get_auth = try scope.get(runtime, "getAuth");
    const options = try scope.object();
    try scope.put(options, "signal", try scope.get(owner, "signal"));
    const result = try scope.call(get_auth, runtime, &.{ try scope.get(owner, "model"), options });
    try wait(engine, owner, result, stage);
}
fn advance(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, failed: bool, raw_stage: c_int) !void {
    const stage: Stage = @enumFromInt(raw_stage);
    if (failed) return rejected(engine, owner, stage, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (stage) {
        .routed => {
            try scope.put(owner, "model", try scope.get(value, "model"));
            try scope.put(owner, "thinking", try scope.get(value, "thinkingLevel"));
            try summaryAuth(engine, owner);
        },
        .selected_required => {
            const result = try scope.own(try js.spread(engine, value));
            try scope.put(result, "thinkingLevel", try scope.get(owner, "thinking"));
            try flow.settle(engine, owner, false, result);
        },
        .required => {
            if (scope.truthy(value) and (scope.truthy(try scope.get(try scope.get(value, "auth"), "apiKey")) or scope.truthy(try scope.get(try scope.get(value, "auth"), "headers")))) {
                return flow.settle(engine, owner, false, try requestResult(&scope, owner, value, false));
            }
            const runtime = try scope.get(try scope.get(owner, "agent"), "_modelRuntime");
            const oauth = try scope.get(runtime, "isUsingOAuth");
            const provider = try scope.get(try scope.get(owner, "model"), "provider");
            if (scope.truthy(try scope.call(oauth, runtime, &.{provider}))) return oauthError(&scope, try scope.get(owner, "model"));
            try noKey(&scope, try scope.get(owner, "model"));
        },
        .optional => {
            // Source's try covers response getters, spread and header filtering.
            const result = optionalResult(&scope, owner, value) catch |err| {
                const reason = flow.reason(engine, err);
                defer engine.freeValue(reason);
                return rejected(engine, owner, .optional, reason);
            };
            try flow.settle(engine, owner, false, result);
        },
    }
}
fn summaryAuth(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    if (scope.equal(try scope.get(try scope.get(session, "agent"), "streamFunction"), try scope.get(owner, "stream"))) {
        const required = try scope.get(session, "_getRequiredRequestAuth");
        return wait(engine, owner, try scope.call(required, session, &.{ try scope.get(owner, "model"), try scope.get(owner, "signal") }), .selected_required);
    }
    // Every property lookup and synchronous getAuth call belongs to the try.
    try auth(engine, owner, .optional);
}
fn fallback(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "model", try scope.get(owner, "model"));
    try scope.put(result, "thinkingLevel", try scope.get(owner, "thinking"));
    return result;
}
fn optionalResult(scope: *Scope, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    return if (!scope.truthy(value)) fallback(scope, owner) else requestResult(scope, owner, value, true);
}
fn requestResult(scope: *Scope, owner: c.JSValue, value: c.JSValue, thinking: bool) !c.JSValue {
    var model = try scope.get(owner, "model");
    if (scope.truthy(try scope.get(try scope.get(value, "auth"), "baseUrl"))) {
        model = try scope.own(try js.spread(scope.engine, model));
        try scope.put(model, "baseUrl", try scope.get(try scope.get(value, "auth"), "baseUrl"));
    }
    const result = try scope.object();
    try scope.put(result, "model", model);
    try scope.put(result, "apiKey", try scope.get(try scope.get(value, "auth"), "apiKey"));
    try scope.put(result, "headers", try headers(scope, try scope.get(try scope.get(value, "auth"), "headers")));
    try scope.put(result, "env", try scope.get(value, "env"));
    if (thinking) try scope.put(result, "thinkingLevel", try scope.get(owner, "thinking"));
    return result;
}
fn headers(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (!scope.truthy(value)) return c.pi_js_undefined();
    const object = try scope.global("Object");
    const from_entries = try scope.get(object, "fromEntries");
    const entries = try scope.invoke(try scope.global("Object"), "entries", &.{value});
    const filter = try scope.get(entries, "filter");
    const predicate = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, keepHeader, "", 1)));
    const filtered = try scope.call(filter, entries, &.{predicate});
    return scope.call(from_entries, object, &.{filtered});
}
fn keepHeader(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const value = js.getKey(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), c.JS_NewInt32(engine.context, 1)) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(value);
    return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsNull(value)));
}
fn rejected(engine: *em.Engine, owner: c.JSValue, stage: Stage, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // Preserve native allocator failure identity across asynchronous Source
    // catches. Old retained native errors and ordinary guest lookalikes still
    // follow the original catch behavior.
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(engine.context, &generation, try scope.get(owner, "generation")) < 0) return js.capture(engine);
    const tagged = c.pi_js_native_allocation_error_generation(value);
    const distance = tagged -% generation;
    if (tagged != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation) return flow.settle(engine, owner, true, value);
    if (stage == .required) {
        const error_class = try scope.global("Error");
        const is_error = c.JS_IsInstanceOf(engine.context, value, error_class);
        if (is_error < 0) return js.capture(engine);
        const cause = if (is_error != 0) try scope.get(value, "cause") else c.pi_js_undefined();
        const cause_error = c.JS_IsInstanceOf(engine.context, cause, try scope.global("Error"));
        if (cause_error < 0) return js.capture(engine);
        if (cause_error != 0 and scope.equal(try scope.get(cause, "message"), try scope.text("authHeader requires a resolved API key"))) return noKey(&scope, try scope.get(owner, "model"));
    } else if (stage == .optional) {
        const signal = try scope.get(owner, "signal");
        if (temp.nullish(signal) or !scope.truthy(try scope.get(signal, "aborted"))) return flow.settle(engine, owner, false, try fallback(&scope, owner));
    }
    try flow.settle(engine, owner, true, value);
}
fn raise(scope: *Scope, constructor: c.JSValue, message: c.JSValue) !void {
    const error_value = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, @constCast(&[_]c.JSValue{message}))));
    _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, error_value)));
}
fn noKey(scope: *Scope, model: c.JSValue) !void {
    const constructor = try scope.global("Error");
    const provider = try scope.get(model, "provider");
    const display = if (scope.equal(provider, try scope.text("unknown"))) try scope.text("the selected model") else provider;
    const prefix = try scope.concat(try scope.concat(try scope.text("No API key found for "), try scope.stringify(display)), try scope.text(".\n\n"));
    const help = try @import("native_sdk_prompt_auth.zig").loginHelp(scope);
    const message = try scope.concat(prefix, try scope.stringify(help));
    try raise(scope, constructor, message);
}
fn oauthError(scope: *Scope, model: c.JSValue) !void {
    const constructor = try scope.global("Error");
    var message = try scope.concat(try scope.concat(try scope.text("Authentication failed for \""), try scope.stringify(try scope.get(model, "provider"))), try scope.text("\". Credentials may have expired or network is unavailable. Run '/login "));
    message = try scope.concat(try scope.concat(message, try scope.stringify(try scope.get(model, "provider"))), try scope.text("' to re-authenticate."));
    try raise(scope, constructor, message);
}
fn virtual(scope: *Scope, model: c.JSValue) !bool {
    return scope.equal(try scope.get(model, "api"), try scope.text("pi-virtual"));
}
fn modelForMessage(engine: *em.Engine, session: c.JSValue, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const model = try scope.get(session, "model");
    if (scope.truthy(model) and try virtual(&scope, model)) {
        const runtime = try scope.get(session, "_modelRuntime");
        const getter = try scope.get(runtime, "getPhysicalModel");
        return js.call(engine, getter, runtime, &.{ try scope.get(message, "provider"), try scope.get(message, "model") });
    }
    const provider = if (temp.nullish(model)) c.pi_js_undefined() else try scope.get(model, "provider");
    const matches = scope.equal(provider, try scope.get(message, "provider")) and scope.equal(try scope.get(model, "id"), try scope.get(message, "model"));
    return if (matches) c.JS_DupValue(engine.context, model) else c.pi_js_undefined();
}
fn lookup(scope: *Scope, session: c.JSValue, provider: c.JSValue, id: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.get(session, "_modelRuntime"), "getModel", &.{ provider, id });
}
fn at(scope: *Scope, branch: c.JSValue, index: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, branch, index));
}
fn budget(engine: *em.Engine, steps: usize) !void {
    if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and block: {
        engine.interrupts +|= 1;
        break :block engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}
fn priorChange(scope: *Scope, branch: c.JSValue, index: c.JSValue) !c.JSValue {
    var cursor = try arithmetic.binary(scope.engine, .subtract, index, c.JS_NewInt32(scope.engine.context, 1));
    defer scope.engine.freeValue(cursor);
    var steps: usize = 0;
    while (try arithmetic.compare(scope.engine, .greater_equal, cursor, c.JS_NewInt32(scope.engine.context, 0))) {
        steps +|= 1;
        try budget(scope.engine, steps);
        var iteration: Scope = .{ .engine = scope.engine };
        defer iteration.deinit();
        const entry = try at(&iteration, branch, cursor);
        if (iteration.equal(try iteration.get(entry, "type"), try iteration.text("model_change"))) {
            const result = try scope.object();
            try scope.put(result, "provider", try iteration.get(entry, "provider"));
            try scope.put(result, "modelId", try iteration.get(entry, "modelId"));
            return result;
        }
        const next = try arithmetic.binary(scope.engine, .subtract, cursor, c.JS_NewInt32(scope.engine.context, 1));
        scope.engine.freeValue(cursor);
        cursor = next;
    }
    return c.pi_js_undefined();
}
fn branchSelection(scope: *Scope, session: c.JSValue, branch: c.JSValue) !c.JSValue {
    var cursor = try arithmetic.binary(scope.engine, .subtract, try scope.get(branch, "length"), c.JS_NewInt32(scope.engine.context, 1));
    defer scope.engine.freeValue(cursor);
    var steps: usize = 0;
    while (try arithmetic.compare(scope.engine, .greater_equal, cursor, c.JS_NewInt32(scope.engine.context, 0))) {
        steps +|= 1;
        try budget(scope.engine, steps);
        var iteration: Scope = .{ .engine = scope.engine };
        defer iteration.deinit();
        const entry = try at(&iteration, branch, cursor);
        if (iteration.equal(try iteration.get(entry, "type"), try iteration.text("model_change"))) {
            const result = try scope.object();
            try scope.put(result, "provider", try iteration.get(entry, "provider"));
            try scope.put(result, "modelId", try iteration.get(entry, "modelId"));
            return result;
        }
        if (iteration.equal(try iteration.get(entry, "type"), try iteration.text("message")) and iteration.equal(try iteration.get(try iteration.get(entry, "message"), "role"), try iteration.text("assistant")) and !try virtual(&iteration, try iteration.get(entry, "message"))) {
            const response = try scope.object();
            try scope.put(response, "provider", try iteration.get(try iteration.get(entry, "message"), "provider"));
            try scope.put(response, "modelId", try iteration.get(try iteration.get(entry, "message"), "model"));
            const change = try priorChange(scope, branch, cursor);
            const model = if (scope.truthy(change)) try lookup(scope, session, try scope.get(change, "provider"), try scope.get(change, "modelId")) else change;
            return if (scope.truthy(change) and scope.truthy(model) and try virtual(scope, model)) change else response;
        }
        const next = try arithmetic.binary(scope.engine, .subtract, cursor, c.JS_NewInt32(scope.engine.context, 1));
        scope.engine.freeValue(cursor);
        cursor = next;
    }
    return c.pi_js_undefined();
}
fn recordSelection(engine: *em.Engine, session: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const model = try scope.get(session, "model");
    if (!scope.truthy(model)) return c.pi_js_undefined();
    const recorded = try branchSelection(&scope, session, try scope.invoke(try scope.get(session, "sessionManager"), "getBranch", &.{}));
    if (!scope.truthy(recorded) or (scope.equal(try scope.get(recorded, "provider"), try scope.get(model, "provider")) and scope.equal(try scope.get(recorded, "modelId"), try scope.get(model, "id")))) return c.pi_js_undefined();
    const recorded_model = try lookup(&scope, session, try scope.get(recorded, "provider"), try scope.get(recorded, "modelId"));
    if (!try virtual(&scope, model) and !(scope.truthy(recorded_model) and try virtual(&scope, recorded_model))) return c.pi_js_undefined();
    const manager = try scope.get(session, "sessionManager");
    const append = try scope.get(manager, "appendModelChange");
    _ = try scope.call(append, manager, &.{ try scope.get(model, "provider"), try scope.get(model, "id") });
    return c.pi_js_undefined();
}
