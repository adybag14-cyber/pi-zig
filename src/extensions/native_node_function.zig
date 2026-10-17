//! Native ordinary Node functions, including their real constructor behavior.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const heap = @import("native_typebox_continuation.zig");
pub const Callback = *const fn (*js.Engine, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
const State = struct { engine: *js.Engine, callback: Callback, values: []c.JSValue, constructible: bool, arrow: bool };
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    heap.unregister(owned.engine, value, owned);
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
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemoryFatal();
    return c.JS_ThrowTypeError(engine.context, "Native Node function: %s", @as([*:0]const u8, @errorName(err)));
}
fn call(_: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    const engine = owned.engine;
    if (c.JS_HasException(engine.context)) return engine.throwCaptured();
    // A guest catch must receive the original exception before host diagnostic
    // formatting can invoke its observable toString/getters. Uncaught failures
    // are diagnosed by the outer Engine eval/await after this frame returns.
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = invoke(engine, function, owned, target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, flags & c.JS_CALL_FLAG_CONSTRUCTOR != 0) catch |err| return failFor(engine, function, err);
    return engine.nativeCallbackResult(result);
}
fn invoke(engine: *js.Engine, function: c.JSValue, owned: *State, target: c.JSValue, args: []const c.JSValue, constructing: bool) !c.JSValue {
    if (try heap.intercept(engine, function, provenance(function, owned), target, args, constructing)) |ack| return ack;
    if (!owned.constructible) return invokeBody(engine, function, owned, if (owned.arrow) c.pi_js_undefined() else target, args);
    if (!constructing) return invokeBody(engine, function, owned, target, args);
    const receiver = try @import("native_class.zig").object(engine, target);
    defer engine.freeValue(receiver);
    const returned = try invokeBody(engine, function, owned, receiver, args);
    if (c.JS_IsObject(returned)) return returned;
    engine.freeValue(returned);
    return c.JS_DupValue(engine.context, receiver);
}
fn provenance(function: c.JSValue, owned: *State) heap.Provenance {
    return .{ .state = owned, .callback = @intFromPtr(owned.callback), .class = c.JS_GetClassID(function), .roots = owned.values, .arrow = owned.arrow };
}
fn failFor(engine: *js.Engine, function: c.JSValue, err: anyerror) c.JSValue {
    return if (heap.isPlanned(engine, function)) heap.fail(engine, err) else fail(engine, err);
}
fn invokeBody(engine: *js.Engine, function: c.JSValue, owned: *State, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (try heap.invokeBody(engine, function, provenance(function, owned), receiver, args)) |result| return result;
    return owned.callback(engine, receiver, args, owned.values);
}
/// Plan selection is explicit at the known generated creation point. The weak
/// registry never discovers descriptors by name or callback-pointer scanning.
pub fn createPlanned(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue, arrow: bool, plan: *const heap.Plan) !c.JSValue {
    const function = try createKind(engine, name, length, callback, values, !arrow, arrow);
    errdefer engine.freeValue(function);
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    try heap.register(engine, function, provenance(function, owned), plan);
    return function;
}
pub fn create(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, values, true, false);
}
/// Source arrow functions retain callable metadata and GC-visible captures,
/// ignore a call/apply receiver, and have no constructor or own prototype.
pub fn createArrow(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, values, false, true);
}
/// Class/object methods retain the call receiver while remaining
/// nonconstructible and having no own prototype property.
pub fn createMethod(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, values, false, false);
}
fn createKind(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue, constructible: bool, arrow: bool) !c.JSValue {
    try engine.checkNativeEntry();
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
    owned.* = .{ .engine = engine, .callback = callback, .values = owned_values, .constructible = constructible, .arrow = arrow };
    _ = c.JS_SetOpaque(function, owned);
    attached = true;
    _ = c.JS_SetConstructorBit(engine.context, function, constructible);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "name", try engine.checked(c.JS_NewString(engine.context, name)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (constructible) {
        const instance_prototype = try js.object(engine);
        defer engine.freeValue(instance_prototype);
        if (c.JS_DefinePropertyValueStr(engine.context, instance_prototype, "constructor", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        if (c.JS_DefinePropertyValueStr(engine.context, function, "prototype", c.JS_DupValue(engine.context, instance_prototype), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return function;
}
