//! Actual Agent constructor field initialization and option lookup order.
//! The core installer supplies its real lexical queue constructor and default
//! stream getter; this module does not invent a fallback stream implementation.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;

pub fn create(engine: *em.Engine, target: c.JSValue, options: c.JSValue, queue_constructor: c.JSValue, default_stream_getter: c.JSValue, default_converter: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.get(target, "prototype");
    const agent = try scope.own(try engine.checked(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(engine.context, prototype) else c.JS_NewObject(engine.context)));
    // JavaScript class field initializers establish every own key before the
    // constructor reads options, including the genuine listeners Set.
    inline for (fields) |name| try scope.put(agent, name, if (comptime @import("std").mem.eql(u8, name, "listeners")) try scope.own(try js.builtin(engine, "Set", &.{})) else c.pi_js_undefined());
    const runtime_options = if (temp.nullish(options)) try scope.object() else options;
    try scope.set(agent, "_state", try scope.own(try @import("native_agent_state.zig").create(engine, try scope.get(runtime_options, "initialState"))));
    const converter = try scope.get(runtime_options, "convertToLlm");
    try scope.set(agent, "convertToLlm", if (temp.nullish(converter)) default_converter else converter);
    try scope.set(agent, "transformContext", try scope.get(runtime_options, "transformContext"));
    const stream = try scope.get(runtime_options, "streamFn");
    try scope.set(agent, "streamFunction", if (temp.nullish(stream)) try scope.call(default_stream_getter, c.pi_js_undefined(), &.{}) else stream);
    inline for (.{ "getApiKey", "onPayload", "onResponse", "onProviderStreamEvent", "beforeToolCall", "afterToolCall", "finishTurn", "prepareRequest", "prepareNextTurn", "prepareNextTurnWithContext" }) |name| try scope.set(agent, name, try scope.get(runtime_options, name));
    inline for (.{ "steeringMode", "followUpMode" }, .{ "steeringQueue", "followUpQueue" }) |mode_name, queue_name| {
        const mode = try scope.get(runtime_options, mode_name);
        var args = [_]c.JSValue{if (temp.nullish(mode)) try scope.text("one-at-a-time") else mode};
        const queue = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, queue_constructor, args.len, &args)));
        try scope.set(agent, queue_name, queue);
    }
    inline for (.{ "sessionId", "thinkingBudgets", "transport", "maxRetryDelayMs", "toolExecution" }) |name| {
        const value = try scope.get(runtime_options, name);
        const fallback: ?[]const u8 = if (comptime @import("std").mem.eql(u8, name, "transport")) "auto" else if (comptime @import("std").mem.eql(u8, name, "toolExecution")) "parallel" else null;
        try scope.set(agent, name, if (fallback != null and temp.nullish(value)) try scope.text(fallback.?) else value);
    }
    return c.JS_DupValue(engine.context, agent);
}

pub fn defaultConverter(engine: *em.Engine) !c.JSValue {
    // Source610 observes the module's one shared regular function, including
    // its constructibility and ordinary writable prototype descriptor.
    const function = try engine.checked(c.JS_NewCFunction2(engine.context, convertToLlm, "defaultConvertToLlm", 1, c.JS_CFUNC_constructor_or_func, 0));
    errdefer engine.freeValue(function);
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "prototype", c.JS_DupValue(engine.context, prototype), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    return function;
}

fn convertToLlm(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return filter(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}

fn filter(engine: *em.Engine, messages: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const filter_function = try scope.get(messages, "filter");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, llmRole, "", 1)));
    return c.JS_DupValue(engine.context, try scope.call(filter_function, messages, &.{predicate}));
}

fn llmRole(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return allowed(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}

fn allowed(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "system", "user", "assistant", "toolResult" }) |role| {
        if (scope.equal(try scope.get(message, "role"), try scope.text(role))) return c.pi_js_bool(engine.context, 1);
    }
    return c.pi_js_bool(engine.context, 0);
}

const fields = .{ "_state", "listeners", "steeringQueue", "followUpQueue", "convertToLlm", "transformContext", "streamFunction", "getApiKey", "onPayload", "onResponse", "onProviderStreamEvent", "beforeToolCall", "afterToolCall", "finishTurn", "prepareRequest", "prepareNextTurn", "prepareNextTurnWithContext", "activeRun", "sessionId", "thinkingBudgets", "transport", "maxRetryDelayMs", "toolExecution" };
