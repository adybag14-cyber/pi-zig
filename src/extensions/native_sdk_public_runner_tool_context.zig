//! Real public nested tool contexts, preserving descriptor and Promise rules.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
pub fn create(engine: *em.Engine, runner: c.JSValue, caller: c.JSValue, signal: c.JSValue) !c.JSValue {
    const result = try js.invoke(engine, runner, "createContext", &.{});
    errdefer engine.releaseNativeValue(result);
    var roots = [_]c.JSValue{ runner, caller, signal };
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, tools, "get", 0, 0, roots.len, &roots));
    const atom = c.JS_NewAtom(engine.context, "tools");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, result, atom, getter, c.pi_js_undefined(), 0) < 0) return js.capture(engine);
    const execute = try engine.checked(c.JS_NewCFunctionData2(engine.context, executeTool, "value", 2, 0, roots.len, &roots));
    if (c.JS_DefinePropertyValueStr(engine.context, result, "executeTool", execute, 0) < 0) return js.capture(engine);
    return result;
}
fn tools(context: ?*c.JSContext, ignored0: c.JSValue, ignored1: c_int, ignored2: [*c]c.JSValue, ignored3: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(toolsOwnedBody(context, ignored0, ignored1, ignored2, ignored3, roots));
}
fn toolsOwnedBody(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const checked = js.invoke(engine, roots[0], "assertActive", &.{}) catch |err| return sdk.fail(engine, err);
    engine.releaseNativeValue(checked);
    return js.invoke(engine, roots[0], "getCallableToolsFn", &.{}) catch |err| sdk.fail(engine, err);
}
fn executeTool(context: ?*c.JSContext, ignored0: c.JSValue, argc: c_int, argv: [*c]c.JSValue, ignored1: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(executeToolOwnedBody(context, ignored0, argc, argv, ignored1, roots));
}
fn executeToolOwnedBody(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var functions: [2]c.JSValue = undefined;
    const promise = engine.checked(c.JS_NewPromiseCapability(context, &functions)) catch |err| return sdk.fail(engine, err);
    defer for (functions) |function| engine.releaseNativeValue(function);
    const result = invoke(engine, roots, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
        const reason = @import("native_agent_async.zig").reason(engine, err) catch |fatal| {
            engine.releaseNativeValue(promise);
            return sdk.fail(engine, fatal);
        };
        defer engine.releaseNativeValue(reason);
        const ignored = js.call(engine, functions[1], c.pi_js_undefined(), &.{reason}) catch |failure| {
            engine.releaseNativeValue(promise);
            return sdk.fail(engine, failure);
        };
        engine.releaseNativeValue(ignored);
        return promise;
    };
    defer engine.releaseNativeValue(result);
    const ignored = js.call(engine, functions[0], c.pi_js_undefined(), &.{result}) catch |err| {
        engine.releaseNativeValue(promise);
        return sdk.fail(engine, err);
    };
    engine.releaseNativeValue(ignored);
    return promise;
}
fn invoke(engine: *em.Engine, roots: [*c]c.JSValue, args: []const c.JSValue) !c.JSValue {
    const options = if (args.len < 3 or c.JS_IsUndefined(args[2])) try sdk.object(engine) else c.JS_DupValue(engine.context, args[2]);
    defer engine.releaseNativeValue(options);
    const checked = try js.invoke(engine, roots[0], "assertActive", &.{});
    engine.releaseNativeValue(checked);
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const supplied = if (args.len > 1) args[1] else c.pi_js_undefined();
    const available = try sdk.get(engine, roots[0], "executeToolFn");
    defer engine.releaseNativeValue(available);
    if (c.JS_ToBool(engine.context, available) != 1) return fallback(engine, roots[1], first);
    // Read the call target before evaluating the argument object, just as the
    // actual Source method call does. The truthiness guard read it separately.
    const function = try sdk.get(engine, roots[0], "executeToolFn");
    defer engine.releaseNativeValue(function);
    const copied = try js.spread(engine, options);
    defer engine.releaseNativeValue(copied);
    const signal = try sdk.get(engine, options, "signal");
    defer engine.releaseNativeValue(signal);
    try sdk.put(engine, copied, "signal", c.JS_DupValue(engine.context, if (c.JS_IsNull(signal) or c.JS_IsUndefined(signal)) roots[2] else signal));
    return js.call(engine, function, roots[0], &.{ roots[1], first, supplied, copied });
}
fn fallback(engine: *em.Engine, caller: c.JSValue, name: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.releaseNativeValue(result);
    const tool_call = try sdk.object(engine);
    defer engine.releaseNativeValue(tool_call);
    try sdk.put(engine, tool_call, "type", try sdk.text(engine, "toolCall"));
    const suffix = try sdk.text(engine, "/0");
    defer engine.releaseNativeValue(suffix);
    try sdk.put(engine, tool_call, "id", try @import("native_select_list.zig").concat(engine, &.{ caller, suffix }));
    try sdk.put(engine, tool_call, "name", c.JS_DupValue(engine.context, name));
    try sdk.put(engine, tool_call, "arguments", try sdk.object(engine));
    try sdk.put(engine, result, "toolCall", c.JS_DupValue(engine.context, tool_call));
    const payload = try sdk.object(engine);
    defer engine.releaseNativeValue(payload);
    const content = try sdk.array(engine);
    defer engine.releaseNativeValue(content);
    const text = try sdk.object(engine);
    defer engine.releaseNativeValue(text);
    try sdk.put(engine, text, "type", try sdk.text(engine, "text"));
    try sdk.put(engine, text, "text", try sdk.text(engine, "Nested tool calls are not available in this context"));
    try sdk.append(engine, content, c.JS_DupValue(engine.context, text));
    try sdk.put(engine, payload, "content", c.JS_DupValue(engine.context, content));
    try sdk.put(engine, payload, "details", try sdk.object(engine));
    try sdk.put(engine, result, "result", c.JS_DupValue(engine.context, payload));
    try sdk.put(engine, result, "isError", c.pi_js_bool(engine.context, 1));
    return result;
}
