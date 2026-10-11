//! Actual per-runtime MCP registry bodies, over ordinary JS Map and refs.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
const Method = enum(c_int) { register, unregister, get, list, setChangeListener };
pub fn create(engine: *em.Engine) !c.JSValue {
    const prototype = try getPrototype(engine);
    defer engine.freeValue(prototype);
    return constructValue(engine, prototype);
}
fn constructValue(engine: *em.Engine, prototype: c.JSValue) !c.JSValue {
    const value = try engine.checked(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(engine.context, prototype) else c.JS_NewObject(engine.context));
    errdefer engine.freeValue(value);
    try sdk.put(engine, value, "servers", try js.builtin(engine, "Map", &.{}));
    try sdk.put(engine, value, "changeListener", c.pi_js_undefined());
    return value;
}
fn construct(context: ?*c.JSContext, target: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const prototype = sdk.get(engine, target, "prototype") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(prototype);
    return constructValue(engine, prototype) catch |err| sdk.fail(engine, err);
}
fn getPrototype(engine: *em.Engine) !c.JSValue {
    if (engine.native_sdk_mcp_registry_prototype) |prototype| return c.JS_DupValue(engine.context, prototype);
    const prototype = try sdk.object(engine);
    errdefer engine.freeValue(prototype);
    const constructor = try engine.checked(c.JS_NewCFunction2(engine.context, construct, "McpServerRegistry", 0, c.JS_CFUNC_constructor, 0));
    defer engine.freeValue(constructor);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return js.capture(engine);
    inline for (@import("std").meta.fields(Method)) |field| {
        const arity: c_int = if (field.value == @intFromEnum(Method.unregister)) 2 else if (field.value == @intFromEnum(Method.list)) 0 else 1;
        const function = try engine.checked(c.pi_js_function_magic(engine.context, callback, field.name, arity, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    engine.native_sdk_mcp_registry_prototype = c.JS_DupValue(engine.context, prototype);
    return prototype;
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, receiver, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn changed(engine: *em.Engine, receiver: c.JSValue) !void {
    const listener = try sdk.get(engine, receiver, "changeListener");
    defer engine.freeValue(listener);
    if (c.JS_IsNull(listener) or c.JS_IsUndefined(listener)) return;
    const ignored = try js.call(engine, listener, receiver, &.{});
    engine.freeValue(ignored);
}
fn invoke(engine: *em.Engine, receiver: c.JSValue, kind: Method, args: []const c.JSValue) !c.JSValue {
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    if (kind == .setChangeListener) {
        if (c.JS_SetPropertyStr(engine.context, receiver, "changeListener", c.JS_DupValue(engine.context, first)) < 0) return js.capture(engine);
        return c.pi_js_undefined();
    }
    const servers = try sdk.get(engine, receiver, "servers");
    defer engine.freeValue(servers);
    switch (kind) {
        .register => {
            const setter = try sdk.get(engine, servers, "set");
            defer engine.freeValue(setter);
            const name = try sdk.get(engine, first, "name");
            defer engine.freeValue(name);
            const ignored = try js.call(engine, setter, servers, &.{ name, first });
            engine.freeValue(ignored);
            try changed(engine, receiver);
        },
        .unregister => {
            const server = try js.invoke(engine, servers, "get", &.{first});
            defer engine.freeValue(server);
            const path = if (c.JS_IsNull(server) or c.JS_IsUndefined(server)) c.pi_js_undefined() else try sdk.get(engine, server, "extensionPath");
            defer engine.freeValue(path);
            if (!c.JS_IsStrictEqual(engine.context, path, second)) return c.pi_js_undefined();
            const current = try sdk.get(engine, receiver, "servers");
            defer engine.freeValue(current);
            const ignored = try js.invoke(engine, current, "delete", &.{first});
            engine.freeValue(ignored);
            try changed(engine, receiver);
        },
        .get => return js.invoke(engine, servers, "get", &.{first}),
        .list => {
            const values = try js.invoke(engine, servers, "values", &.{});
            defer engine.freeValue(values);
            const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
            defer engine.freeValue(symbol);
            const array = try js.collect(engine, values, symbol);
            defer engine.freeValue(array);
            const mapper = try engine.checked(c.pi_js_function_magic(engine.context, copyServer, "", 1, 0));
            defer engine.freeValue(mapper);
            return js.invoke(engine, array, "map", &.{mapper});
        },
        .setChangeListener => unreachable,
    }
    return c.pi_js_undefined();
}
fn copyServer(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return copied(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn copied(engine: *em.Engine, server: c.JSValue) !c.JSValue {
    const result = try js.spread(engine, server);
    errdefer engine.freeValue(result);
    const clone = try js.global(engine, "structuredClone");
    defer engine.freeValue(clone);
    const config = try sdk.get(engine, server, "config");
    defer engine.freeValue(config);
    try sdk.put(engine, result, "config", try js.call(engine, clone, c.pi_js_undefined(), &.{config}));
    return result;
}
