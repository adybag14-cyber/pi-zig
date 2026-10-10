//! Source input reducers keep one current value and construct a fresh event for
//! each handler. Guest event mutation does not become a transform result.
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = engine_mod.c;

pub fn initialize(engine: *engine_mod.Engine, state: c.JSValue, event: c.JSValue) !void {
    try sdk.put(engine, state, "inputInitialText", try sdk.get(engine, event, "text"));
    try sdk.put(engine, state, "inputInitialImages", try sdk.get(engine, event, "images"));
}

pub fn reduce(engine: *engine_mod.Engine, state: c.JSValue, value: c.JSValue) !void {
    if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) return;
    if (try isAction(engine, value, "handled")) {
        try sdk.put(engine, state, "inputHandled", c.JS_DupValue(engine.context, value));
        const event = try sdk.get(engine, state, "event");
        defer engine.freeValue(event);
        try sdk.put(engine, event, "_nativeInputHandled", c.JS_DupValue(engine.context, value));
    } else if (try isAction(engine, value, "transform")) {
        const event = try sdk.get(engine, state, "event");
        defer engine.freeValue(event);
        try sdk.put(engine, event, "text", try sdk.get(engine, value, "text"));
        const images = try sdk.get(engine, value, "images");
        defer engine.freeValue(images);
        if (!c.JS_IsNull(images) and !c.JS_IsUndefined(images)) try sdk.put(engine, event, "images", c.JS_DupValue(engine.context, images));
    }
}

fn isAction(engine: *engine_mod.Engine, value: c.JSValue, expected: []const u8) !bool {
    const action = try sdk.get(engine, value, "action");
    defer engine.freeValue(action);
    if (!c.JS_IsString(action)) return false;
    const name = try engine.toString(action);
    defer engine.gpa.free(name);
    return @import("std").mem.eql(u8, name, expected);
}

pub fn handled(engine: *engine_mod.Engine, state: c.JSValue) !bool {
    const value = try sdk.get(engine, state, "inputHandled");
    defer engine.freeValue(value);
    return !c.JS_IsUndefined(value);
}

pub fn nextEvent(engine: *engine_mod.Engine, state: c.JSValue) !c.JSValue {
    const original = try sdk.get(engine, state, "event");
    defer engine.freeValue(original);
    const event = try sdk.object(engine);
    errdefer engine.freeValue(event);
    inline for (.{ "type", "text", "images", "source", "streamingBehavior" }) |name| try sdk.put(engine, event, name, try sdk.get(engine, original, name));
    return event;
}

pub fn result(engine: *engine_mod.Engine, state: c.JSValue) !c.JSValue {
    const stopped = try sdk.get(engine, state, "inputHandled");
    if (!c.JS_IsUndefined(stopped)) return stopped;
    engine.freeValue(stopped);
    const event = try sdk.get(engine, state, "event");
    defer engine.freeValue(event);
    const handled_result = try sdk.get(engine, event, "_nativeInputHandled");
    if (!c.JS_IsUndefined(handled_result)) return handled_result;
    engine.freeValue(handled_result);
    const initial_text = try sdk.get(engine, state, "inputInitialText");
    defer engine.freeValue(initial_text);
    const initial_images = try sdk.get(engine, state, "inputInitialImages");
    defer engine.freeValue(initial_images);
    const current_text = try sdk.get(engine, event, "text");
    defer engine.freeValue(current_text);
    const current_images = try sdk.get(engine, event, "images");
    defer engine.freeValue(current_images);
    const changed = !c.JS_IsStrictEqual(engine.context, initial_text, current_text) or !c.JS_IsStrictEqual(engine.context, initial_images, current_images);
    const output = try sdk.object(engine);
    errdefer engine.freeValue(output);
    try sdk.put(engine, output, "action", try sdk.text(engine, if (changed) "transform" else "continue"));
    if (changed) {
        try sdk.put(engine, output, "text", c.JS_DupValue(engine.context, current_text));
        try sdk.put(engine, output, "images", c.JS_DupValue(engine.context, current_images));
    }
    return output;
}

pub fn finish(engine: *engine_mod.Engine, state: c.JSValue, pending: c.JSValue, promise_then: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{state};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, finishCallback, "sdkInputResult", 0, 0, data.len, &data));
    defer engine.freeValue(callback);
    var callbacks = [_]c.JSValue{callback};
    return engine.checked(c.JS_Call(engine.context, promise_then, pending, callbacks.len, &callbacks));
}

fn finishCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return result(engine, data[0]) catch |err| sdk.fail(engine, err);
}
