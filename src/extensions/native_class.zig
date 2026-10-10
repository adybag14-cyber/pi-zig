//! Native constructors for ordinary observable JavaScript component objects.
const std = @import("std");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
pub const Construct = *const fn (*Engine, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
const State = struct { engine: *Engine, prototype: c.JSValue, name: [:0]const u8, create: Construct, values: []c.JSValue };
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    for (state.values) |item| c.JS_FreeValueRT(runtime, item);
    state.engine.gpa.free(state.values);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, visit);
    for (state.values) |item| c.JS_MarkValue(runtime, item, visit);
}
fn call(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)) orelse return c.JS_ThrowTypeError(context, "Invalid native constructor")));
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Class constructor %s cannot be invoked without 'new'", state.name.ptr);
    return state.create(engine, target, if (argc == 0) &.{} else argv[0..@intCast(argc)], state.values) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return c.JS_ThrowTypeError(context, "Native %s: %s", state.name.ptr, @as([*:0]const u8, @errorName(err)));
    };
}
pub fn constructor(engine: *Engine, name: [:0]const u8, length: c_int, prototype: c.JSValue, create: Construct, values: []const c.JSValue) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native Component Constructor", .finalizer = finalizer, .gc_mark = mark, .call = call };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const function = try js.global(engine, "Function");
    defer engine.freeValue(function);
    const function_prototype = try js.get(engine, function, "prototype");
    defer engine.freeValue(function_prototype);
    const result = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, class));
    errdefer engine.freeValue(result);
    const owned = try engine.gpa.alloc(c.JSValue, values.len);
    var attached = false;
    errdefer if (!attached) engine.gpa.free(owned);
    const state = try engine.gpa.create(State);
    for (values, owned) |value, *slot| slot.* = c.JS_DupValue(engine.context, value);
    state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype), .name = name, .create = create, .values = owned };
    _ = c.JS_SetOpaque(result, state);
    attached = true;
    _ = c.JS_SetConstructorBit(engine.context, result, true);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "name", try engine.checked(c.JS_NewString(engine.context, name.ptr)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, result, "prototype", c.JS_DupValue(engine.context, prototype), 0) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, result), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return result;
}
pub fn object(engine: *Engine, target: c.JSValue) !c.JSValue {
    const prototype = try js.get(engine, target, "prototype");
    defer engine.freeValue(prototype);
    return engine.checked(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(engine.context, prototype) else c.JS_NewObject(engine.context));
}
