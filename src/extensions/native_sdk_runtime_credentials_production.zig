//! Actual ordinary RuntimeCredentials class over the caller's credential store.
//! All keys, values, methods, iterators and raw rejection reasons remain live.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Method = enum(c_int) { setRuntimeApiKey, removeRuntimeApiKey, hasRuntimeApiKey, read, list, modify, delete };
pub fn constructor(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    const ctor = try scope.own(try @import("native_class.zig").constructor(engine, "RuntimeCredentials", 1, prototype, construct, &.{}));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const arity: c_int = switch (method) {
            .setRuntimeApiKey, .read, .delete => 2,
            .modify => 3,
            else => 1,
        };
        const function = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, dispatch, field.name, arity, field.value)));
        if (asynchronous(method)) if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return c.JS_DupValue(engine.context, ctor);
}
fn construct(engine: *em.Engine, new_target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const instance = try scope.own(try @import("native_class.zig").object(engine, new_target));
    try scope.put(instance, "store", c.pi_js_undefined());
    try scope.put(instance, "overrides", try scope.own(try js.builtin(engine, "Map", &.{})));
    try scope.set(instance, "store", if (args.len > 0) args[0] else c.pi_js_undefined());
    return c.JS_DupValue(engine.context, instance);
}
fn asynchronous(method: Method) bool {
    return method == .read or method == .list or method == .delete;
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const method: Method = @enumFromInt(magic);
    return (if (asynchronous(method)) begin(engine, receiver, method, args) else sync(engine, receiver, method, args)) catch |err| sdk.fail(engine, err);
}
fn sync(engine: *em.Engine, receiver: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = arg(args, 0);
    switch (method) {
        .setRuntimeApiKey => _ = try scope.invoke(try scope.get(receiver, "overrides"), "set", &.{ first, arg(args, 1) }),
        .removeRuntimeApiKey => _ = try scope.invoke(try scope.get(receiver, "overrides"), "delete", &.{first}),
        .hasRuntimeApiKey => return js.invoke(engine, try scope.get(receiver, "overrides"), "has", &.{first}),
        .modify => return js.invoke(engine, try scope.get(receiver, "store"), "modify", &.{ first, arg(args, 1), arg(args, 2) }),
        else => unreachable,
    }
    return c.pi_js_undefined();
}
fn check(scope: *Scope, options: c.JSValue) !void {
    if (temp.nullish(options)) return;
    const signal = try scope.get(options, "signal");
    if (!temp.nullish(signal)) _ = try scope.invoke(signal, "throwIfAborted", &.{});
}
fn begin(engine: *em.Engine, receiver: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, receiver, method, args) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, method: Method, args: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const provider = arg(args, 0);
    switch (method) {
        .read => {
            const options = arg(args, 1);
            try check(&scope, options);
            const override = try scope.invoke(try scope.get(receiver, "overrides"), "get", &.{provider});
            const value = if (scope.truthy(override)) value: {
                const credential = try scope.object();
                try scope.put(credential, "type", try scope.text("api_key"));
                try scope.put(credential, "key", override);
                break :value credential;
            } else try scope.invoke(try scope.get(receiver, "store"), "read", &.{ provider, options });
            try flow.settle(engine, owner, false, value);
        },
        .list => {
            // Source resolves the Map constructor before awaiting store.list.
            try scope.put(owner, "Map", try scope.global("Map"));
            try scope.put(owner, "options", provider);
            return flow.wait(continueCredentials, engine, owner, try scope.invoke(try scope.get(receiver, "store"), "list", &.{provider}), @intFromEnum(Method.list));
        },
        .delete => {
            const options = arg(args, 1);
            try check(&scope, options);
            try scope.put(owner, "providerId", provider);
            return flow.wait(continueCredentials, engine, owner, try scope.invoke(try scope.get(receiver, "store"), "delete", &.{ provider, options }), @intFromEnum(Method.delete));
        },
        else => unreachable,
    }
}
fn continueCredentials(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    finish(engine, owner, value, @enumFromInt(stage)) catch |err| try flow.rejectError(engine, owner, err);
}
fn finish(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, method: Method) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    if (method == .delete) {
        const overrides = try scope.get(receiver, "overrides");
        const remove = try scope.get(overrides, "delete");
        _ = try scope.call(remove, overrides, &.{try scope.get(owner, "providerId")});
        return flow.settle(engine, owner, false, c.pi_js_undefined());
    }
    const map = try scope.get(value, "map");
    const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, providerPair, "", 1)));
    const rows = try scope.call(map, value, &.{callback});
    var args = [_]c.JSValue{rows};
    const entries = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(owner, "Map"), args.len, &args)));
    try check(&scope, try scope.get(owner, "options"));
    const keys = try scope.invoke(try scope.get(receiver, "overrides"), "keys", &.{});
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, keys, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |provider| {
        defer engine.freeValue(provider);
        var frame: Scope = .{ .engine = engine };
        defer frame.deinit();
        const set = try frame.get(entries, "set");
        const credential = try frame.object();
        try frame.put(credential, "providerId", provider);
        try frame.put(credential, "type", try frame.text("api_key"));
        _ = try frame.call(set, entries, &.{ provider, credential });
    }
    const result = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, try scope.invoke(entries, "values", &.{}), null));
    try flow.settle(engine, owner, false, result);
}
fn providerPair(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return pair(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn pair(engine: *em.Engine, entry: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const row = try scope.array();
    try scope.index(row, 0, try scope.get(entry, "providerId"));
    try scope.index(row, 1, entry);
    return c.JS_DupValue(engine.context, row);
}
