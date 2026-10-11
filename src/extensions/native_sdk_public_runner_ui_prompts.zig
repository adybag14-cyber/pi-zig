//! Actual synchronous prompt nesting and dynamic finally, with queued emit.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
fn assign(engine: *em.Engine, runner: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, runner, name, value) < 0) return js.capture(engine);
}
pub fn withPrompt(engine: *em.Engine, runner: c.JSValue, kind: c.JSValue, title: c.JSValue, run: c.JSValue) !c.JSValue {
    const original = try sdk.get(engine, runner, "uiPromptDepth");
    defer engine.freeValue(original);
    // Postfix ++ compares its old ToNumeric value, not the original object or
    // string. Incrementing the numeric value cannot invoke a second hook.
    const numeric = try engine.checked(c.JS_PiToNumeric(engine.context, original));
    defer engine.freeValue(numeric);
    const incremented = try engine.checked(c.JS_PiIncrement(engine.context, numeric));
    try assign(engine, runner, "uiPromptDepth", incremented);
    if (c.JS_IsStrictEqual(engine.context, numeric, c.JS_NewInt32(engine.context, 0))) {
        const active = try sdk.object(engine);
        defer engine.freeValue(active);
        try sdk.put(engine, active, "kind", c.JS_DupValue(engine.context, kind));
        try sdk.put(engine, active, "title", c.JS_DupValue(engine.context, title));
        try assign(engine, runner, "activeUIPrompt", c.JS_DupValue(engine.context, active));
        const emit = try sdk.get(engine, runner, "emitUIPromptEvent");
        defer engine.freeValue(emit);
        const event = try promptEvent(engine, "ui_prompt_start", kind, title);
        defer engine.freeValue(event);
        const ignored = try js.call(engine, emit, runner, &.{event});
        engine.freeValue(ignored);
    }
    var roots = [_]c.JSValue{ runner, kind, title };
    const finish = try engine.checked(c.JS_NewCFunctionData2(engine.context, finishCall, "finish", 0, 0, roots.len, &roots));
    defer engine.freeValue(finish);
    return invokeFinally(engine, run, finish) catch |err| {
        _ = sdk.fail(engine, err);
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        _ = try finishPrompt(engine, runner, kind, title);
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    };
}
fn invokeFinally(engine: *em.Engine, run: c.JSValue, finish: c.JSValue) !c.JSValue {
    const result = try js.call(engine, run, c.pi_js_undefined(), &.{});
    defer engine.freeValue(result);
    return js.invoke(engine, result, "finally", &.{finish});
}
fn promptEvent(engine: *em.Engine, event_type: []const u8, kind: c.JSValue, title: c.JSValue) !c.JSValue {
    const event = try sdk.object(engine);
    errdefer engine.freeValue(event);
    try sdk.put(engine, event, "type", try sdk.text(engine, event_type));
    try sdk.put(engine, event, "reason", try sdk.text(engine, "ui_prompt"));
    try sdk.put(engine, event, "kind", c.JS_DupValue(engine.context, kind));
    if (c.JS_ToBool(engine.context, title) == 1) try sdk.put(engine, event, "title", c.JS_DupValue(engine.context, title));
    return event;
}
fn finishCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return finishPrompt(engine, roots[0], roots[1], roots[2]) catch |err| sdk.fail(engine, err);
}
fn finishPrompt(engine: *em.Engine, runner: c.JSValue, kind: c.JSValue, title: c.JSValue) !c.JSValue {
    const original = try sdk.get(engine, runner, "uiPromptDepth");
    defer engine.freeValue(original);
    const numeric = try engine.checked(c.JS_PiToNumeric(engine.context, original));
    defer engine.freeValue(numeric);
    const one = if (c.JS_IsBigInt(numeric)) try engine.checked(c.JS_NewBigInt64(engine.context, 1)) else c.JS_NewInt32(engine.context, 1);
    defer engine.freeValue(one);
    const decremented = try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, numeric, one));
    defer engine.freeValue(decremented);
    try assign(engine, runner, "uiPromptDepth", c.JS_DupValue(engine.context, decremented));
    const nested = try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, decremented, c.JS_NewInt32(engine.context, 0)));
    defer engine.freeValue(nested);
    if (c.JS_ToBool(engine.context, nested) == 1) return c.pi_js_undefined();
    try assign(engine, runner, "uiPromptDepth", c.JS_NewInt32(engine.context, 0));
    var prompt = try sdk.get(engine, runner, "activeUIPrompt");
    defer engine.freeValue(prompt);
    if (c.JS_IsNull(prompt) or c.JS_IsUndefined(prompt)) {
        engine.freeValue(prompt);
        prompt = try sdk.object(engine);
        try sdk.put(engine, prompt, "kind", c.JS_DupValue(engine.context, kind));
        try sdk.put(engine, prompt, "title", c.JS_DupValue(engine.context, title));
    }
    try assign(engine, runner, "activeUIPrompt", c.pi_js_undefined());
    const emit = try sdk.get(engine, runner, "emitUIPromptEvent");
    defer engine.freeValue(emit);
    const event = try sdk.object(engine);
    defer engine.freeValue(event);
    try sdk.put(engine, event, "type", try sdk.text(engine, "ui_prompt_end"));
    try sdk.put(engine, event, "reason", try sdk.text(engine, "ui_prompt"));
    try sdk.put(engine, event, "kind", try sdk.get(engine, prompt, "kind"));
    const first_title = try sdk.get(engine, prompt, "title");
    defer engine.freeValue(first_title);
    if (c.JS_ToBool(engine.context, first_title) == 1) try sdk.put(engine, event, "title", try sdk.get(engine, prompt, "title"));
    const ignored = try js.call(engine, emit, runner, &.{event});
    engine.freeValue(ignored);
    return c.pi_js_undefined();
}
pub fn queue(engine: *em.Engine, runner: c.JSValue, event: c.JSValue) !c.JSValue {
    const enqueue = try js.global(engine, "queueMicrotask");
    defer engine.freeValue(enqueue);
    var roots = [_]c.JSValue{ runner, event };
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, emitQueued, "", 0, 0, roots.len, &roots));
    defer engine.freeValue(callback);
    const ignored = try js.call(engine, enqueue, c.pi_js_undefined(), &.{callback});
    engine.freeValue(ignored);
    return c.pi_js_undefined();
}
fn emitQueued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const ignored = js.invoke(engine, roots[0], "emit", &.{roots[1]}) catch |err| return sdk.fail(engine, err);
    engine.freeValue(ignored);
    return c.pi_js_undefined();
}
