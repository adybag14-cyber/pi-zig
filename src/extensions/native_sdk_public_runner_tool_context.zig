//! Real public nested tool contexts, preserving descriptor and Promise rules.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
pub fn create(engine: *em.Engine, runner: c.JSValue, caller: c.JSValue, signal: c.JSValue) !c.JSValue {
    const result = try js.invoke(engine, runner, "createContext", &.{});
    errdefer engine.freeValue(result);
    var roots = [_]c.JSValue{ runner, caller, signal };
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, tools, "get", 0, 0, roots.len, &roots));
    const atom = c.JS_NewAtom(engine.context, "tools");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, result, atom, getter, c.pi_js_undefined(), 0) < 0) return js.capture(engine);
    const execute = try engine.checked(c.JS_NewCFunctionData2(engine.context, executeTool, "value", 2, 0, roots.len, &roots));
    if (c.JS_DefinePropertyValueStr(engine.context, result, "executeTool", execute, 0) < 0) return js.capture(engine);
    return result;
}
fn tools(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const checked = js.invoke(engine, roots[0], "assertActive", &.{}) catch |err| return sdk.fail(engine, err);
    engine.freeValue(checked);
    return js.invoke(engine, roots[0], "getCallableToolsFn", &.{}) catch |err| sdk.fail(engine, err);
}
fn executeTool(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var functions: [2]c.JSValue = undefined;
    const promise = engine.checked(c.JS_NewPromiseCapability(context, &functions)) catch |err| return sdk.fail(engine, err);
    defer for (functions) |function| engine.freeValue(function);
    const result = invoke(engine, roots, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
        _ = sdk.fail(engine, err);
        const reason = c.JS_GetException(context);
        defer engine.freeValue(reason);
        const ignored = js.call(engine, functions[1], c.pi_js_undefined(), &.{reason}) catch |failure| {
            engine.freeValue(promise);
            return sdk.fail(engine, failure);
        };
        engine.freeValue(ignored);
        return promise;
    };
    defer engine.freeValue(result);
    const ignored = js.call(engine, functions[0], c.pi_js_undefined(), &.{result}) catch |err| {
        engine.freeValue(promise);
        return sdk.fail(engine, err);
    };
    engine.freeValue(ignored);
    return promise;
}
fn invoke(engine: *em.Engine, roots: [*c]c.JSValue, args: []const c.JSValue) !c.JSValue {
    const options = if (args.len < 3 or c.JS_IsUndefined(args[2])) try sdk.object(engine) else c.JS_DupValue(engine.context, args[2]);
    defer engine.freeValue(options);
    const checked = try js.invoke(engine, roots[0], "assertActive", &.{});
    engine.freeValue(checked);
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const supplied = if (args.len > 1) args[1] else c.pi_js_undefined();
    const available = try sdk.get(engine, roots[0], "executeToolFn");
    defer engine.freeValue(available);
    if (c.JS_ToBool(engine.context, available) != 1) return fallback(engine, roots[1], first);
    // Read the call target before evaluating the argument object, just as the
    // actual Source method call does. The truthiness guard read it separately.
    const function = try sdk.get(engine, roots[0], "executeToolFn");
    defer engine.freeValue(function);
    const copied = try js.spread(engine, options);
    defer engine.freeValue(copied);
    const signal = try sdk.get(engine, options, "signal");
    defer engine.freeValue(signal);
    try sdk.put(engine, copied, "signal", c.JS_DupValue(engine.context, if (c.JS_IsNull(signal) or c.JS_IsUndefined(signal)) roots[2] else signal));
    return js.call(engine, function, roots[0], &.{ roots[1], first, supplied, copied });
}
fn fallback(engine: *em.Engine, caller: c.JSValue, name: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const tool_call = try sdk.object(engine);
    defer engine.freeValue(tool_call);
    try sdk.put(engine, tool_call, "type", try sdk.text(engine, "toolCall"));
    const suffix = try sdk.text(engine, "/0");
    defer engine.freeValue(suffix);
    try sdk.put(engine, tool_call, "id", try @import("native_select_list.zig").concat(engine, &.{ caller, suffix }));
    try sdk.put(engine, tool_call, "name", c.JS_DupValue(engine.context, name));
    try sdk.put(engine, tool_call, "arguments", try sdk.object(engine));
    try sdk.put(engine, result, "toolCall", c.JS_DupValue(engine.context, tool_call));
    const payload = try sdk.object(engine);
    defer engine.freeValue(payload);
    const content = try sdk.array(engine);
    defer engine.freeValue(content);
    const text = try sdk.object(engine);
    defer engine.freeValue(text);
    try sdk.put(engine, text, "type", try sdk.text(engine, "text"));
    try sdk.put(engine, text, "text", try sdk.text(engine, "Nested tool calls are not available in this context"));
    try sdk.append(engine, content, c.JS_DupValue(engine.context, text));
    try sdk.put(engine, payload, "content", c.JS_DupValue(engine.context, content));
    try sdk.put(engine, payload, "details", try sdk.object(engine));
    try sdk.put(engine, result, "result", c.JS_DupValue(engine.context, payload));
    try sdk.put(engine, result, "isError", c.pi_js_bool(engine.context, 1));
    return result;
}
