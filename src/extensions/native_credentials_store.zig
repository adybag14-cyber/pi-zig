//! Source InMemoryCredentialStore: identity-preserving values and per-provider
//! async mutation chains. All continuation roots belong to the owning realm.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const c = em.c;
const Operation = enum(c_int) { read, list, modify, delete };
const Stage = enum(c_int) { previous, mutation, tail, cleanup };
fn intrinsics(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    const store = try scope.get(state, "store");
    return .{ .constructor = try scope.get(store, "constructor"), .resolve = try scope.get(store, "resolve"), .then_function = try scope.get(store, "then") };
}
fn wait(scope: *Scope, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var captured = try intrinsics(scope, state);
    return scope.own(try awaiting.continueWith(advance, scope.engine, &captured, state, value, @intFromEnum(stage)));
}
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const store = try scope.object();
    try scope.put(store, "values", try scope.own(try js.builtin(engine, "Map", &.{})));
    try scope.put(store, "chains", try scope.own(try js.builtin(engine, "Map", &.{})));
    const promise = try scope.global("Promise");
    try scope.put(store, "constructor", promise);
    try scope.put(store, "resolve", try scope.get(promise, "resolve"));
    try scope.put(store, "then", try scope.get(try scope.get(promise, "prototype"), "then"));
    const result = try scope.object();
    var data = [_]c.JSValue{store};
    inline for (@import("std").meta.fields(Operation)) |field| try scope.put(result, field.name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value == 2) 2 else if (field.value == 1) 0 else 1, field.value, data.len, &data))));
    return c.JS_DupValue(engine.context, result);
}
fn construct(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return create(engine) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    if (engine.abort_signal_class == 0) try @import("abort_signal.zig").install(engine);
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, construct, "InMemoryCredentialStore", 0, 0, 0, null));
    defer engine.freeValue(function);
    _ = c.JS_SetConstructorBit(engine.context, function, true);
    try js.define(engine, exports, "InMemoryCredentialStore", c.JS_DupValue(engine.context, function));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return execute(engine, data[0], @enumFromInt(raw), args[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn execute(engine: *em.Engine, store: c.JSValue, operation: Operation, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options_index: usize = if (operation == .modify) 2 else if (operation == .list) 0 else 1;
    const options = if (args.len > options_index) args[options_index] else c.pi_js_undefined();
    const supplied = if (c.JS_IsNull(options) or c.JS_IsUndefined(options)) c.pi_js_undefined() else try scope.get(options, "signal");
    const signal = if (c.JS_IsNull(supplied) or c.JS_IsUndefined(supplied)) try scope.own(try @import("abort_signal.zig").create(engine)) else supplied;
    const id = if (args.len > 0) args[0] else c.pi_js_undefined();
    const state = try scope.object();
    try scope.put(state, "store", store);
    try scope.put(state, "id", id);
    try scope.put(state, "signal", signal);
    if (operation == .read or operation == .list) {
        _ = try scope.invoke(signal, "throwIfAborted", &.{});
        var result = c.pi_js_undefined();
        const values = try scope.get(store, "values");
        if (operation == .read) result = try scope.invoke(values, "get", &.{id}) else {
            result = try scope.array();
            const iterator = try scope.invoke(values, "entries", &.{});
            var i: u32 = 0;
            while (true) {
                const entry = try scope.invoke(iterator, "next", &.{});
                if (scope.truthy(try scope.get(entry, "done"))) break;
                const pair = try scope.get(entry, "value");
                const key = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 0)));
                const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, pair, 1)));
                const row = try scope.object();
                try scope.put(row, "providerId", key);
                try scope.put(row, "type", try scope.get(value, "type"));
                try scope.index(result, i, row);
                i += 1;
            }
        }
        const captured = try intrinsics(&scope, state);
        var argument = [_]c.JSValue{result};
        return engine.checked(c.JS_Call(engine.context, captured.resolve, captured.constructor, 1, &argument));
    }
    try scope.put(state, "remove", c.pi_js_bool(engine.context, @intFromBool(operation == .delete)));
    if (operation == .modify) try scope.put(state, "callback", if (args.len > 1) args[1] else c.pi_js_undefined());
    const chains = try scope.get(store, "chains");
    const previous = try scope.invoke(chains, "get", &.{id});
    const queued = try wait(&scope, state, previous, .previous);
    const tail = try wait(&scope, state, queued, .tail);
    try scope.put(state, "tail", tail);
    _ = try scope.invoke(chains, "set", &.{ id, tail });
    _ = try wait(&scope, state, tail, .cleanup);
    return @import("native_models_refresh.zig").race(engine, queued, signal, c.pi_js_undefined());
}
fn advance(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    const store = try scope.get(state, "store");
    const id = try scope.get(state, "id");
    if (stage == .tail) return c.pi_js_undefined();
    if (stage == .cleanup) {
        const chains = try scope.get(store, "chains");
        if (scope.equal(try scope.invoke(chains, "get", &.{id}), try scope.get(state, "tail"))) _ = try scope.invoke(chains, "delete", &.{id});
        // Break the state->tail->continuation graph once the chain settles.
        try scope.put(state, "tail", c.pi_js_undefined());
        return c.pi_js_undefined();
    }
    if (rejected and stage != .previous) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    _ = try scope.invoke(try scope.get(state, "signal"), "throwIfAborted", &.{});
    const values = try scope.get(store, "values");
    if (stage == .previous) {
        if (scope.truthy(try scope.get(state, "remove"))) {
            _ = try scope.invoke(values, "delete", &.{id});
            return c.pi_js_undefined();
        }
        const current = try scope.invoke(values, "get", &.{id});
        try scope.put(state, "current", current);
        const pending = try scope.call(try scope.get(state, "callback"), c.pi_js_undefined(), &.{current});
        return c.JS_DupValue(engine.context, try wait(&scope, state, pending, .mutation));
    }
    if (!c.JS_IsUndefined(value)) _ = try scope.invoke(values, "set", &.{ id, value });
    return c.JS_DupValue(engine.context, if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) try scope.get(state, "current") else value);
}
