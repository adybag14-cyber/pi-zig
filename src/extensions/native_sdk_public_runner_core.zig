//! bindCore mutates the real shared runtime and retains actual provider refs.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
fn assign(engine: *em.Engine, target: c.JSValue, key: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, target, key, value) < 0) return js.capture(engine);
}
pub fn bind(engine: *em.Engine, runner: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const actions = if (args.len > 0) args[0] else c.pi_js_undefined();
    const contexts = if (args.len > 1) args[1] else c.pi_js_undefined();
    const providers = if (args.len > 2) args[2] else c.pi_js_undefined();
    inline for (.{ "sendMessage", "sendUserMessage", "appendEntry", "setSessionName", "getSessionName", "setLabel", "getActiveTools", "getAllTools", "getSettings", "setActiveTools", "refreshTools", "getCommands", "setModel", "getThinkingLevel", "setThinkingLevel" }) |key| {
        const runtime = try sdk.get(engine, runner, "runtime");
        defer engine.freeValue(runtime);
        try assign(engine, runtime, key, try sdk.get(engine, actions, key));
    }
    var context_roots = [_]c.JSValue{runner};
    {
        const runtime = try sdk.get(engine, runner, "runtime");
        defer engine.freeValue(runtime);
        try assign(engine, runtime, "createContext", try engine.checked(c.JS_NewCFunctionData2(engine.context, createContext, "", 0, 0, context_roots.len, &context_roots)));
    }
    inline for (.{ .{ "getModel", "getModel" }, .{ "getScopedModels", "getScopedModels" }, .{ "isIdle", "isIdleFn" }, .{ "isProjectTrusted", "isProjectTrustedFn" }, .{ "getSignal", "getSignalFn" }, .{ "abort", "abortFn" }, .{ "hasPendingMessages", "hasPendingMessagesFn" }, .{ "shutdown", "shutdownHandler" }, .{ "getContextUsage", "getContextUsageFn" }, .{ "compact", "compactFn" }, .{ "getSystemPrompt", "getSystemPromptFn" } }) |entry| try assign(engine, runner, entry[1], try sdk.get(engine, contexts, entry[0]));
    const options = try sdk.get(engine, contexts, "getSystemPromptOptions");
    defer engine.freeValue(options);
    try assign(engine, runner, "getSystemPromptOptionsFn", if (c.JS_IsUndefined(options) or c.JS_IsNull(options)) try engine.checked(c.JS_NewCFunctionData2(engine.context, fallback, "", 0, 0, context_roots.len, &context_roots)) else c.JS_DupValue(engine.context, options));
    try assign(engine, runner, "executeToolFn", try sdk.get(engine, contexts, "executeTool"));
    const callable = try sdk.get(engine, contexts, "getCallableTools");
    defer engine.freeValue(callable);
    try assign(engine, runner, "getCallableToolsFn", if (c.JS_IsUndefined(callable) or c.JS_IsNull(callable)) try engine.checked(c.JS_NewCFunctionData2(engine.context, fallback, "", 0, 1, 0, null)) else c.JS_DupValue(engine.context, callable));
    const mcp_runtime = try sdk.get(engine, runner, "runtime");
    defer engine.freeValue(mcp_runtime);
    const mcp = try sdk.get(engine, mcp_runtime, "mcpServers");
    defer engine.freeValue(mcp);
    const setter = try sdk.get(engine, mcp, "setChangeListener");
    defer engine.freeValue(setter);
    const listener = try engine.checked(c.JS_NewCFunctionData2(engine.context, mcpChange, "", 0, 0, context_roots.len, &context_roots));
    defer engine.freeValue(listener);
    const installed = try js.call(engine, setter, mcp, &.{listener});
    engine.freeValue(installed);
    try flush(engine, runner, providers, .registerProvider, "pendingProviderRegistrations");
    try flush(engine, runner, providers, .registerNativeProvider, "pendingNativeProviderRegistrations");
    try flush(engine, runner, providers, .registerVirtualModel, "pendingVirtualModelRegistrations");
    var roots = [_]c.JSValue{ runner, providers };
    inline for (std.meta.fields(Provider)) |field| {
        const kind: Provider = @enumFromInt(field.value);
        const count: c_int = if (kind == .registerProvider or kind == .unregisterVirtualModel) 2 else 1;
        const name = if (kind == .registerVirtualModel) "registerVirtualModel" else "";
        const runtime = try sdk.get(engine, runner, "runtime");
        defer engine.freeValue(runtime);
        try assign(engine, runtime, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, providerCall, name, count, field.value, roots.len, &roots)));
    }
    return c.pi_js_undefined();
}
const Provider = enum(c_int) { registerProvider, registerNativeProvider, unregisterProvider, registerVirtualModel, unregisterVirtualModel };
fn callProvider(engine: *em.Engine, runner: c.JSValue, providers: c.JSValue, kind: Provider, args: []const c.JSValue) !void {
    const available = if (c.JS_IsUndefined(providers) or c.JS_IsNull(providers)) c.pi_js_undefined() else try sdk.get(engine, providers, @tagName(kind));
    defer engine.freeValue(available);
    if (c.JS_ToBool(engine.context, available) == 1) {
        // The Source condition and method call each read the getter.
        const ignored = try js.invoke(engine, providers, @tagName(kind), args);
        engine.freeValue(ignored);
    } else {
        const registry = try sdk.get(engine, runner, "modelRegistry");
        defer engine.freeValue(registry);
        const ignored = try js.invoke(engine, registry, if (kind == .registerNativeProvider) "registerProvider" else @tagName(kind), args);
        engine.freeValue(ignored);
    }
}
fn providerCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const kind: Provider = @enumFromInt(magic);
    const count: usize = if (kind == .registerProvider or kind == .unregisterVirtualModel) 2 else 1;
    var args = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    for (0..@min(count, @as(usize, @intCast(argc)))) |index| args[index] = argv[index];
    callProvider(engine, roots[0], roots[1], kind, args[0..count]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn flush(engine: *em.Engine, runner: c.JSValue, providers: c.JSValue, kind: Provider, key: [*:0]const u8) !void {
    const runtime = try sdk.get(engine, runner, "runtime");
    defer engine.freeValue(runtime);
    const pending = try sdk.get(engine, runtime, key);
    defer engine.freeValue(pending);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, pending, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const first = try sdk.get(engine, entry, if (kind == .registerProvider) "name" else if (kind == .registerNativeProvider) "provider" else "definition");
        defer engine.freeValue(first);
        const config = if (kind == .registerProvider) try sdk.get(engine, entry, "config") else c.pi_js_undefined();
        defer engine.freeValue(config);
        const path = try sdk.get(engine, entry, "extensionPath");
        defer engine.freeValue(path);
        callProvider(engine, runner, providers, kind, if (kind == .registerProvider) &.{ first, config } else &.{first}) catch |err| {
            if (err != error.JavaScriptException) return err;
            const reason = c.JS_DupValue(engine.context, engine.captured_exception orelse return err);
            defer engine.freeValue(reason);
            try report(engine, runner, path, kind, reason);
        };
    }
    const current = try sdk.get(engine, runner, "runtime");
    defer engine.freeValue(current);
    try assign(engine, current, key, try sdk.array(engine));
}
fn report(engine: *em.Engine, runner: c.JSValue, path: c.JSValue, kind: Provider, reason: c.JSValue) !void {
    const value = try sdk.object(engine);
    defer engine.freeValue(value);
    try sdk.put(engine, value, "extensionPath", c.JS_DupValue(engine.context, path));
    try sdk.put(engine, value, "event", try sdk.text(engine, if (kind == .registerVirtualModel) "register_virtual_model" else "register_provider"));
    const is_error = c.JS_IsError(reason);
    const message = if (is_error) try sdk.get(engine, reason, "message") else string: {
        const converter = try js.global(engine, "String");
        defer engine.freeValue(converter);
        break :string try js.call(engine, converter, c.pi_js_undefined(), &.{reason});
    };
    try sdk.put(engine, value, "error", message);
    try sdk.put(engine, value, "stack", if (is_error) try sdk.get(engine, reason, "stack") else c.pi_js_undefined());
    const ignored = try js.invoke(engine, runner, "emitError", &.{value});
    engine.freeValue(ignored);
}
fn createContext(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, roots[0], "createContext", &.{}) catch |err| sdk.fail(engine, err);
}
fn fallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return (if (magic == 1) sdk.array(engine) else @import("native_sdk_public_runner.zig").defaultOptions(engine, roots[0])) catch |err| sdk.fail(engine, err);
}
fn mcpChange(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    mcpChanged(engine, roots[0]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn mcpChanged(engine: *em.Engine, runner: c.JSValue) !void {
    const emit = try sdk.get(engine, runner, "emit");
    defer engine.freeValue(emit);
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "type", try sdk.text(engine, "mcp_servers_change"));
    const runtime = try sdk.get(engine, runner, "runtime");
    defer engine.freeValue(runtime);
    const servers = try sdk.get(engine, runtime, "mcpServers");
    defer engine.freeValue(servers);
    try sdk.put(engine, event, "servers", try js.invoke(engine, servers, "list", &.{}));
    const emitted = try js.call(engine, emit, runner, &.{event});
    engine.freeValue(emitted);
    const reported = try js.invoke(engine, runner, "reportUnhandledMcpServers", &.{});
    engine.freeValue(reported);
}
