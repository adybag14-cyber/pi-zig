//! Durable Source StreamDecoder using the native streaming TextDecoder.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = js.c;
const State = struct { engine: *js.Engine, decoder: c.JSValue, started: bool = false };
fn finalize(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.native_env_decoder_class) orelse return));
    c.JS_FreeValueRT(runtime, state.decoder);
    engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, object: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.native_env_decoder_class) orelse return));
    c.JS_MarkValue(runtime, state.decoder, visit);
}
fn construct(engine: *js.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const object = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, try scope.get(target, "prototype"), engine.native_env_decoder_class)));
    const options = try scope.object();
    try scope.put(options, "ignoreBOM", c.pi_js_bool(engine.context, 1));
    const decoder = try scope.own(try js.builtin(engine, "TextDecoder", &.{ try scope.text("utf-8"), options }));
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .decoder = c.JS_DupValue(engine.context, decoder) };
    _ = c.JS_SetOpaque(object, state);
    return c.JS_DupValue(engine.context, object);
}
fn decode(engine: *js.Engine, receiver: c.JSValue, input: c.JSValue) !c.JSValue {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, engine.native_env_decoder_class) orelse return js.capture(engine)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const text = if (c.JS_IsUndefined(input)) try scope.invoke(state.decoder, "decode", &.{}) else streamed: {
        const options = try scope.object();
        try scope.put(options, "stream", c.pi_js_bool(engine.context, 1));
        break :streamed try scope.invoke(state.decoder, "decode", &.{ input, options });
    };
    if (state.started or scope.equal(text, try scope.text(""))) return c.JS_DupValue(engine.context, text);
    state.started = true;
    return c.JS_DupValue(engine.context, if (scope.truthy(try scope.invoke(text, "startsWith", &.{try scope.text("\u{feff}")}))) try scope.invoke(text, "slice", &.{c.JS_NewInt32(engine.context, 1)}) else text);
}
fn invoke(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return decode(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn create(engine: *js.Engine) !c.JSValue {
    if (engine.text_decoder_class == 0) try @import("text_decoder.zig").install(engine);
    if (engine.native_env_decoder_class == 0) {
        _ = c.JS_NewClassID(engine.runtime, &engine.native_env_decoder_class);
        const definition: c.JSClassDef = .{ .class_name = "StreamDecoder", .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, engine.native_env_decoder_class, &definition) < 0) return error.OutOfMemory;
    }
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "StreamDecoder", 0, prototype, construct, &.{}));
    const function = try engine.checked(c.JS_NewCFunction(engine.context, invoke, "decode", 1));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "decode", function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, constructor);
}
