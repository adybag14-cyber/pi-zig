//! Actual Agent default state used by SDK construction; all refs stay in VM.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const replay = @import("native_sdk_transcript_replay.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
pub fn defaultModel(engine: *em.Engine) !c.JSValue {
    if (engine.native_sdk_agent_default_model) |model| return c.JS_DupValue(engine.context, model);
    const model = try sdk.jsonObject(engine, "{\"id\":\"unknown\",\"name\":\"unknown\",\"api\":\"unknown\",\"provider\":\"unknown\",\"baseUrl\":\"\",\"reasoning\":false,\"input\":[],\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0},\"contextWindow\":0,\"maxTokens\":0}");
    engine.native_sdk_agent_default_model = c.JS_DupValue(engine.context, model);
    return model;
}
pub fn create(engine: *em.Engine, model: c.JSValue, thinking: c.JSValue, tools: c.JSValue, messages: c.JSValue) !c.JSValue {
    const value = try sdk.object(engine);
    errdefer engine.freeValue(value);
    var roots = [_]c.JSValue{value};
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, prompt, "get systemPrompt", 0, 0, roots.len, &roots));
    const atom = c.JS_NewAtom(engine.context, "systemPrompt");
    if (atom == c.JS_ATOM_NULL) {
        engine.freeValue(getter);
        return js.capture(engine);
    }
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, value, atom, getter, c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    try sdk.put(engine, value, "model", if (c.JS_IsNull(model) or c.JS_IsUndefined(model)) try defaultModel(engine) else c.JS_DupValue(engine.context, model));
    try sdk.put(engine, value, "thinkingLevel", if (c.JS_IsNull(thinking) or c.JS_IsUndefined(thinking)) try sdk.text(engine, "off") else c.JS_DupValue(engine.context, thinking));
    try sdk.put(engine, value, "tools", c.JS_DupValue(engine.context, tools));
    try sdk.put(engine, value, "messages", c.JS_DupValue(engine.context, messages));
    try sdk.put(engine, value, "isStreaming", c.pi_js_bool(engine.context, 0));
    try sdk.put(engine, value, "streamingMessage", c.pi_js_undefined());
    try sdk.put(engine, value, "pendingToolCalls", try js.builtin(engine, "Set", &.{}));
    try sdk.put(engine, value, "errorMessage", c.pi_js_undefined());
    const viewed = try @import("native_sdk_session_state.zig").view(engine, value);
    engine.freeValue(viewed);
    return value;
}
fn prompt(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return promptValue(engine, roots[0]) catch |err| sdk.fail(engine, err);
}
fn promptValue(engine: *em.Engine, state: c.JSValue) !c.JSValue {
    const messages = try sdk.get(engine, state, "messages");
    defer engine.freeValue(messages);
    const message = try replay.currentSystemMessage(engine, messages);
    defer engine.freeValue(message);
    if (c.JS_ToBool(engine.context, message) != 1) return sdk.text(engine, "");
    const parts = try sdk.array(engine);
    defer engine.freeValue(parts);
    const content = try sdk.get(engine, message, "content");
    defer engine.freeValue(content);
    if (c.JS_DefinePropertyValueUint32(engine.context, parts, 0, try replay.contentText(engine, content), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    const object = try js.global(engine, "Object");
    defer engine.freeValue(object);
    const values = try sdk.get(engine, object, "values");
    defer engine.freeValue(values);
    var sections = try sdk.get(engine, message, "sections");
    defer engine.freeValue(sections);
    if (c.JS_IsNull(sections) or c.JS_IsUndefined(sections)) {
        const empty = try sdk.object(engine);
        engine.freeValue(sections);
        sections = empty;
    }
    const texts = try js.call(engine, values, object, &.{sections});
    defer engine.freeValue(texts);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, texts, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |text| {
        defer engine.freeValue(text);
        if (!c.JS_IsNull(text)) try js.push(engine, parts, text);
    }
    const predicate = try engine.checked(c.pi_js_function_magic(engine.context, nonempty, "", 1, 0));
    defer engine.freeValue(predicate);
    const filtered = try js.invoke(engine, parts, "filter", &.{predicate});
    defer engine.freeValue(filtered);
    const separator = try sdk.text(engine, "\n\n");
    defer engine.freeValue(separator);
    return js.invoke(engine, filtered, "join", &.{separator});
}
fn nonempty(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const length = sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "length") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(length);
    return c.JS_PiBinaryOperator(engine.context, 6, length, c.JS_NewInt32(engine.context, 0));
}
