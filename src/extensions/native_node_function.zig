//! Native ordinary Node functions, including their real constructor behavior.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
pub const Callback = *const fn (*js.Engine, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
const State = struct { engine: *js.Engine, callback: Callback, values: []c.JSValue };
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (owned.values) |item| c.JS_FreeValueRT(runtime, item);
    owned.engine.gpa.free(owned.values);
    owned.engine.gpa.destroy(owned);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (owned.values) |item| c.JS_MarkValue(runtime, item, marker);
}
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Node function: %s", @as([*:0]const u8, @errorName(err)));
}
fn call(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    return invoke(engine, owned, target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, flags & c.JS_CALL_FLAG_CONSTRUCTOR != 0) catch |err| fail(engine, err);
}
fn invoke(engine: *js.Engine, owned: *State, target: c.JSValue, args: []const c.JSValue, constructing: bool) !c.JSValue {
    if (!constructing) return owned.callback(engine, target, args, owned.values);
    const receiver = try @import("native_class.zig").object(engine, target);
    defer engine.freeValue(receiver);
    const returned = try owned.callback(engine, receiver, args, owned.values);
    if (c.JS_IsObject(returned)) return returned;
    engine.freeValue(returned);
    return c.JS_DupValue(engine.context, receiver);
}
pub fn create(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native Node Function", .call = call, .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const prototype = try engine.checked(c.JS_GetFunctionProto(engine.context));
    defer engine.freeValue(prototype);
    const function = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, class));
    errdefer engine.freeValue(function);
    const owned_values = try engine.gpa.alloc(c.JSValue, values.len);
    var attached = false;
    errdefer if (!attached) engine.gpa.free(owned_values);
    const owned = try engine.gpa.create(State);
    for (values, owned_values) |value, *slot| slot.* = c.JS_DupValue(engine.context, value);
    owned.* = .{ .engine = engine, .callback = callback, .values = owned_values };
    _ = c.JS_SetOpaque(function, owned);
    attached = true;
    _ = c.JS_SetConstructorBit(engine.context, function, true);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "name", try engine.checked(c.JS_NewString(engine.context, name)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    const instance_prototype = try js.object(engine);
    defer engine.freeValue(instance_prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, instance_prototype, "constructor", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "prototype", c.JS_DupValue(engine.context, instance_prototype), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return function;
}
