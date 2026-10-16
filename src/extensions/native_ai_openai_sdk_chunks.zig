//! Actual openai6.40 iterSSEChunks producer: each delimiter chunk is yielded
//! before scanning or slicing later data. No worker-side SSE interpretation.
const v = @import("native_ai_provider_values.zig");
const gen = @import("native_async_generator.zig");
const record = @import("native_ai_openai_sdk_iterator.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const flow = @import("native_agent_async.zig");
const Scope = v.Scope;
const c = v.c;
pub fn codec(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_ai_openai_sdk_codec) |value| return c.JS_DupValue(engine.context, value);
    const result = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
    engine.native_ai_openai_sdk_codec = c.JS_DupValue(engine.context, result);
    return result;
}
pub fn encode(scope: *Scope, owner: c.JSValue, text: c.JSValue) !c.JSValue {
    var cached = try scope.get(owner, "encodeUTF8");
    if (c.JS_IsUndefined(cached)) {
        const encoder = try scope.own(try v.js.builtin(scope.engine, "TextEncoder", &.{}));
        cached = try scope.invoke(try scope.get(encoder, "encode"), "bind", &.{encoder});
        try scope.put(owner, "encodeUTF8", cached);
    }
    return scope.call(cached, c.pi_js_undefined(), &.{text});
}
pub fn decode(scope: *Scope, owner: c.JSValue, bytes: c.JSValue) !c.JSValue {
    var cached = try scope.get(owner, "decodeUTF8");
    if (c.JS_IsUndefined(cached)) {
        const decoder = try scope.own(try v.js.builtin(scope.engine, "TextDecoder", &.{}));
        cached = try scope.invoke(try scope.get(decoder, "decode"), "bind", &.{decoder});
        try scope.put(owner, "decodeUTF8", cached);
    }
    return scope.call(cached, c.pi_js_undefined(), &.{bytes});
}
pub fn binary(scope: *Scope, owner: c.JSValue, chunk: c.JSValue) !c.JSValue {
    const array_buffer = try scope.global("ArrayBuffer");
    const is_buffer = c.JS_IsInstanceOf(scope.engine.context, chunk, array_buffer);
    if (is_buffer < 0) return v.js.capture(scope.engine);
    if (is_buffer != 0) return scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{chunk}));
    if (c.JS_IsString(chunk)) return encode(scope, owner, chunk);
    return chunk;
}
pub fn concat(scope: *Scope, first: c.JSValue, second: c.JSValue, explicit_first_offset: bool) !c.JSValue {
    const length = try scope.own(try arithmetic.binary(scope.engine, .add, try scope.get(first, "length"), try scope.get(second, "length")));
    const data = try scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{length}));
    if (explicit_first_offset) _ = try scope.invoke(data, "set", &.{ first, c.JS_NewInt32(scope.engine.context, 0) }) else _ = try scope.invoke(data, "set", &.{first});
    _ = try scope.invoke(data, "set", &.{ second, try scope.get(first, "length") });
    return data;
}
pub fn create(engine: *v.em.Engine, iterable: c.JSValue, shared_codec: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try record.state(&scope);
    try scope.put(owner, "iterable", iterable);
    try scope.put(owner, "codec", shared_codec);
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 0));
    return gen.create(engine, owner, advance, try scope.own(try gen.prototype(engine)));
}
fn phase(scope: *Scope, owner: c.JSValue) !i32 {
    var result: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &result, try scope.get(owner, "phase")) < 0) return v.js.capture(scope.engine);
    return result;
}
fn byte(scope: *Scope, data: c.JSValue, index: u32) !u32 {
    var result: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &result, try v.at(scope, data, index)) < 0) return v.js.capture(scope.engine);
    return result;
}
fn delimiter(engine: *v.em.Engine, data: c.JSValue) !?u32 {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const length = try v.length(&scope, data);
    var index: u32 = 0;
    while (index + 1 < length) : (index += 1) {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const first = try byte(&row, data, index);
        const second = try byte(&row, data, index + 1);
        if ((first == 10 and second == 10) or (first == 13 and second == 13)) return index + 2;
        if (first == 13 and second == 10 and index + 3 < length and try byte(&row, data, index + 2) == 13 and try byte(&row, data, index + 3) == 10) return index + 4;
    }
    return null;
}
fn advance(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try record.closed(&scope, owner, completion, input)) |action| return action;
    if (completion == .returned or completion == .thrown) return record.close(&scope, owner, input, completion == .thrown);
    if (completion == .rejected) return if (try phase(&scope, owner) == 1) .{ .thrown = c.JS_DupValue(engine.context, input) } else record.close(&scope, owner, input, true);
    return step(engine, owner, completion, input) catch |err| {
        if (err != error.JavaScriptException) return err;
        const reason = flow.reason(engine, err);
        defer engine.freeValue(reason);
        if (engine.captured_exception) |captured| {
            engine.captured_exception = null;
            engine.freeValue(captured);
        }
        return record.close(&scope, owner, reason, true);
    };
}
fn step(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const current = try phase(&scope, owner);
    if (completion == .start) {
        try scope.put(owner, "data", try scope.own(try v.js.builtin(engine, "Uint8Array", &.{})));
        try record.begin(&scope, owner, try scope.get(owner, "iterable"));
    } else if (current == 3) return .{ .complete = c.pi_js_undefined() } else if (current == 2) {
        try scope.put(owner, "data", try scope.invoke(try scope.get(owner, "data"), "slice", &.{try scope.get(owner, "patternIndex")}));
    } else if (completion == .fulfilled) {
        try record.validate(&scope, input);
        if (scope.truthy(try scope.get(input, "done"))) {
            const data = try scope.get(owner, "data");
            if (try v.length(&scope, data) > 0) {
                try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 3));
                return .{ .yielded = c.JS_DupValue(engine.context, data) };
            }
            return .{ .complete = c.pi_js_undefined() };
        }
        const chunk = try scope.get(input, "value");
        if (v.nullish(chunk)) return record.next(&scope, owner);
        try scope.put(owner, "data", try concat(&scope, try scope.get(owner, "data"), try binary(&scope, try scope.get(owner, "codec"), chunk), false));
    }
    const data = try scope.get(owner, "data");
    if (try delimiter(engine, data)) |index| {
        try scope.put(owner, "patternIndex", c.JS_NewUint32(engine.context, index));
        try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 2));
        return .{ .yielded = c.JS_DupValue(engine.context, try scope.invoke(data, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewUint32(engine.context, index) })) };
    }
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 1));
    return record.next(&scope, owner);
}
