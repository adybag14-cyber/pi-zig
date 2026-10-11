//! Original loader runtime state and pre-bind bodies, retained as real JS refs.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
const Method = enum(c_int) { notInitialized, refreshTools, setModel, assertActive, invalidate, trackEventBusSubscription, registerProvider, registerNativeProvider, unregisterProvider, registerVirtualModel, unregisterVirtualModel };
pub fn create(engine: *em.Engine, private_scope: c.JSValue) !c.JSValue {
    const state = try sdk.object(engine);
    defer engine.freeValue(state);
    const subscriptions = try js.builtin(engine, "Set", &.{});
    defer engine.freeValue(subscriptions);
    const runtime = try sdk.object(engine);
    errdefer engine.freeValue(runtime);
    var roots = [_]c.JSValue{ runtime, state, subscriptions, private_scope };
    const uninitialized = try function(engine, "notInitialized", 0, .notInitialized, &roots);
    defer engine.freeValue(uninitialized);
    inline for (.{ "sendMessage", "sendUserMessage", "appendEntry", "setSessionName", "getSessionName", "setLabel", "getActiveTools", "getAllTools", "getSettings", "setActiveTools", "refreshTools", "getCommands", "setModel", "getThinkingLevel", "setThinkingLevel" }) |name| {
        const value = if (comptime std.mem.eql(u8, name, "refreshTools")) try function(engine, name, 0, .refreshTools, &roots) else if (comptime std.mem.eql(u8, name, "setModel")) try function(engine, name, 0, .setModel, &roots) else c.JS_DupValue(engine.context, uninitialized);
        try sdk.put(engine, runtime, name, value);
    }
    try sdk.put(engine, runtime, "flagValues", try js.builtin(engine, "Map", &.{}));
    try sdk.put(engine, runtime, "pendingProviderRegistrations", try sdk.array(engine));
    try sdk.put(engine, runtime, "pendingNativeProviderRegistrations", try sdk.array(engine));
    try sdk.put(engine, runtime, "mcpServers", try @import("native_sdk_mcp_registry.zig").create(engine));
    try sdk.put(engine, runtime, "pendingVirtualModelRegistrations", try sdk.array(engine));
    try sdk.put(engine, runtime, "createContext", c.JS_DupValue(engine.context, uninitialized));
    inline for (.{ .{ "assertActive", Method.assertActive, 0 }, .{ "invalidate", Method.invalidate, 1 }, .{ "trackEventBusSubscription", Method.trackEventBusSubscription, 1 }, .{ "registerProvider", Method.registerProvider, 2 }, .{ "registerNativeProvider", Method.registerNativeProvider, 1 }, .{ "unregisterProvider", Method.unregisterProvider, 1 }, .{ "registerVirtualModel", Method.registerVirtualModel, 1 }, .{ "unregisterVirtualModel", Method.unregisterVirtualModel, 2 } }) |entry| try sdk.put(engine, runtime, entry[0], try function(engine, entry[0], entry[2], entry[1], &roots));
    return runtime;
}
fn function(engine: *em.Engine, name: [*:0]const u8, arity: c_int, kind: Method, roots: []c.JSValue) !c.JSValue {
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, arity, @intFromEnum(kind), @intCast(roots.len), roots.ptr));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots) catch |err| sdk.fail(engine, err);
}
fn throwMessage(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, try js.builtin(engine, "Error", &.{message})));
}
fn invoke(engine: *em.Engine, kind: Method, args: []const c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    switch (kind) {
        .notInitialized => return @import("native_sdk_resource_owners.zig").uninitialized(engine),
        .refreshTools => return c.pi_js_undefined(), // Source explicitly does nothing before binding.
        .setModel => {
            const promise = try js.global(engine, "Promise");
            defer engine.freeValue(promise);
            const reject = try sdk.get(engine, promise, "reject");
            defer engine.freeValue(reject);
            const message = try sdk.text(engine, "Extension runtime not initialized");
            defer engine.freeValue(message);
            const reason = try js.builtin(engine, "Error", &.{message});
            defer engine.freeValue(reason);
            return js.call(engine, reject, promise, &.{reason});
        },
        .assertActive => {
            const stale = try sdk.get(engine, roots[1], "staleMessage");
            defer engine.freeValue(stale);
            if (c.JS_ToBool(engine.context, stale) == 1) return throwMessage(engine, stale);
        },
        .invalidate => {
            const previous = try sdk.get(engine, roots[1], "staleMessage");
            defer engine.freeValue(previous);
            if (c.JS_ToBool(engine.context, previous) == 1) return c.pi_js_undefined();
            const message = if (c.JS_IsNull(first) or c.JS_IsUndefined(first)) try sdk.text(engine, @import("native_context_lifetime.zig").default_message) else c.JS_DupValue(engine.context, first);
            const invalidated = c.JS_ToBool(engine.context, message) == 1;
            if (c.JS_SetPropertyStr(engine.context, roots[1], "staleMessage", message) < 0) return js.capture(engine);
            if (invalidated and c.JS_IsObject(roots[3]) and engine.native_sdk_resource_scope_class != 0) {
                // This root is the constructor-captured private owner value,
                // not a public JSON field. Pure runtime invalidation remains
                // callable when its group has retired; privileged Pi admission
                // independently checks the original native owner/lease.
                if (c.JS_GetOpaque(roots[3], engine.native_sdk_resource_scope_class)) |raw| {
                    const scope: *@import("native_sdk_resource_owners.zig").Scope = @ptrCast(@alignCast(raw));
                    if (scope.engine != engine) return error.InvalidSDKResourceOwner;
                    scope.runtime_invalidated = true;
                }
            }
            const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
            defer engine.freeValue(symbol);
            var iterator = try js.Iterator.init(engine, roots[2], symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |subscription| {
                defer engine.freeValue(subscription);
                const ignored = try js.call(engine, subscription, c.pi_js_undefined(), &.{});
                engine.freeValue(ignored);
            }
            const cleared = try js.invoke(engine, roots[2], "clear", &.{});
            engine.freeValue(cleared);
        },
        .trackEventBusSubscription => {
            const active = try sdk.object(engine);
            defer engine.freeValue(active);
            try sdk.put(engine, active, "active", c.pi_js_bool(engine.context, 1));
            var retained = [_]c.JSValue{ roots[2], first, active };
            const tracked = try engine.checked(c.JS_NewCFunctionData2(engine.context, unsubscribeCallback, "trackedUnsubscribe", 0, 0, retained.len, &retained));
            errdefer engine.freeValue(tracked);
            try sdk.put(engine, active, "function", c.JS_DupValue(engine.context, tracked));
            const added = try js.invoke(engine, roots[2], "add", &.{tracked});
            engine.freeValue(added);
            return tracked;
        },
        .registerProvider, .registerNativeProvider, .registerVirtualModel => {
            const queue = try sdk.get(engine, roots[0], switch (kind) {
                .registerProvider => "pendingProviderRegistrations",
                .registerNativeProvider => "pendingNativeProviderRegistrations",
                else => "pendingVirtualModelRegistrations",
            });
            defer engine.freeValue(queue);
            const push = try sdk.get(engine, queue, "push");
            defer engine.freeValue(push);
            const entry = try sdk.object(engine);
            defer engine.freeValue(entry);
            try sdk.put(engine, entry, if (kind == .registerProvider) "name" else if (kind == .registerNativeProvider) "provider" else "definition", c.JS_DupValue(engine.context, first));
            if (kind == .registerProvider) try sdk.put(engine, entry, "config", c.JS_DupValue(engine.context, second));
            const index: usize = if (kind == .registerProvider) 2 else 1;
            try sdk.put(engine, entry, "extensionPath", if (args.len <= index or c.JS_IsUndefined(args[index])) try sdk.text(engine, "<unknown>") else c.JS_DupValue(engine.context, args[index]));
            const pushed = try js.call(engine, push, queue, &.{entry});
            engine.freeValue(pushed);
        },
        .unregisterProvider, .unregisterVirtualModel => {
            const fields: []const [:0]const u8 = if (kind == .unregisterProvider) &.{ "pendingProviderRegistrations", "pendingNativeProviderRegistrations" } else &.{"pendingVirtualModelRegistrations"};
            for (fields, 0..) |field, index| {
                const queue = try sdk.get(engine, roots[0], field);
                defer engine.freeValue(queue);
                var retained = [_]c.JSValue{ first, second };
                const mode: c_int = if (kind == .unregisterVirtualModel) 2 else @intCast(index);
                const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, keepRegistration, "", 1, mode, retained.len, &retained));
                defer engine.freeValue(predicate);
                const filtered = try js.invoke(engine, queue, "filter", &.{predicate});
                if (c.JS_SetPropertyStr(engine.context, roots[0], field, filtered) < 0) return js.capture(engine);
            }
        },
    }
    return c.pi_js_undefined();
}
fn unsubscribeCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return unsubscribe(engine, roots) catch |err| sdk.fail(engine, err);
}
fn unsubscribe(engine: *em.Engine, roots: [*c]c.JSValue) !c.JSValue {
    const active = try sdk.get(engine, roots[2], "active");
    defer engine.freeValue(active);
    if (c.JS_ToBool(engine.context, active) != 1) return c.pi_js_undefined();
    if (c.JS_SetPropertyStr(engine.context, roots[2], "active", c.pi_js_bool(engine.context, 0)) < 0) return js.capture(engine);
    const remove = try sdk.get(engine, roots[0], "delete");
    defer engine.freeValue(remove);
    const current = try sdk.get(engine, roots[2], "function");
    defer engine.freeValue(current);
    const removed = try js.call(engine, remove, roots[0], &.{current});
    engine.freeValue(removed);
    const ignored = try js.call(engine, roots[1], c.pi_js_undefined(), &.{});
    engine.freeValue(ignored);
    return c.pi_js_undefined();
}
fn keepRegistration(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return keep(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic, roots) catch |err| sdk.fail(engine, err);
}
fn keep(engine: *em.Engine, entry: c.JSValue, mode: c_int, roots: [*c]c.JSValue) !c.JSValue {
    const nested = if (mode == 0) c.JS_DupValue(engine.context, entry) else try sdk.get(engine, entry, if (mode == 1) "provider" else "definition");
    defer engine.freeValue(nested);
    const id = try sdk.get(engine, nested, if (mode == 0) "name" else if (mode == 1) "id" else "provider");
    defer engine.freeValue(id);
    if (!c.JS_IsStrictEqual(engine.context, id, roots[0])) return c.pi_js_bool(engine.context, 1);
    if (mode != 2) return c.pi_js_bool(engine.context, 0);
    const name = try sdk.get(engine, nested, "id");
    defer engine.freeValue(name);
    return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsStrictEqual(engine.context, name, roots[1])));
}
