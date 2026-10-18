//! Scoped ordinary Node.Module callables with traced, aggregate-charged roots.
//! This is not an AsyncFunction/constructor-name proxy or a JS host bridge.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
pub const Callback = *const fn (*v.em.Engine, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
const State = struct { engine: *v.em.Engine, callback: Callback, roots: []c.JSValue, constructible: bool, reserved: usize };
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = state.engine;
    const reserved = state.reserved;
    for (state.roots) |root| c.JS_FreeValueRT(engine.runtime, root);
    engine.gpa.free(state.roots);
    engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, reserved);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (state.roots) |root| c.JS_MarkValue(runtime, root, marker);
}
pub fn failure(engine: *v.em.Engine, err: anyerror, _: u64) c.JSValue {
    // Keep the caller API, but a callback-wide generation or captured DATA bit
    // is not producer evidence. Trusted host OOM is an actual new event.
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemoryFatal();
    _ = engine.nativeCallbackResult(c.pi_js_undefined());
    if (c.JS_HasException(engine.context)) return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
    if (err == error.JavaScriptException) {
        if (engine.captured_exception) |reason| {
            engine.captured_exception = null;
            return c.JS_Throw(engine.context, reason);
        }
        return engine.throwCaptured();
    }
    return c.JS_ThrowTypeError(engine.context, "Native Module operation: %s", @as([*:0]const u8, @errorName(err)));
}
fn call(_: ?*c.JSContext, function: c.JSValue, receiver_or_target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    const engine = state.engine;
    // Caller-stable owned frame before any receiver allocation or callback.
    // A nested callback/finalizer can publish first fatal independently of the
    // diagnostic slot; all receiver roots retire before this frame is popped.
    var scope = Scope.init(engine);
    return scope.finish(invoke(&scope, state, receiver_or_target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, flags & c.JS_CALL_FLAG_CONSTRUCTOR != 0)) catch |err| failure(engine, err, 0);
}
fn invoke(scope: *Scope, state: *State, receiver_or_target: c.JSValue, args: []const c.JSValue, constructing: bool) !c.JSValue {
    try scope.pending(); try state.engine.checkNativeEntry();
    if (!constructing) return invokeCallback(scope, state, receiver_or_target, args);
    if (!state.constructible) return v.js.typeError(state.engine, "Module method is not a constructor");
    // Retire object-expression temporaries at native_class.object's original
    // return boundary, then retain the receiver through callback completion.
    const receiver = try scope.own(try createReceiver(state.engine, receiver_or_target));
    try scope.pending(); try state.engine.checkNativeEntry();
    var returned = try invokeCallback(scope, state, receiver, args);
    if (c.JS_IsObject(returned)) return returned;
    scope.boundary.release(&returned);
    try scope.pending();
    return c.JS_DupValue(state.engine.context, receiver);
}
fn createReceiver(engine: *v.em.Engine, target: c.JSValue) !c.JSValue {
    var stage = Scope.init(engine); return stage.finish(receiverBody(&stage, target));
}
fn receiverBody(stage: *Scope, target: c.JSValue) !c.JSValue {
    // Same existing native_class.object algorithm, with separate guest-get and
    // proven non-guest object-allocation boundaries. Never classify getter DATA.
    const prototype = try stage.get(target, "prototype");
    const generation = try stage.beforeAllocation();
    const receiver = try stage.checkedAllocation(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(stage.engine.context, prototype) else c.JS_NewObject(stage.engine.context), generation);
    return c.JS_DupValue(stage.engine.context, receiver);
}
fn invokeCallback(scope: *Scope, state: *State, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var output = try state.callback(state.engine, receiver, args, state.roots);
    // Successful native return + actual pending/B1 is still failure. There is
    // no callback-wide private-generation qualification at this boundary.
    scope.pending() catch |err| { scope.boundary.release(&output); return err; };
    if (c.JS_IsException(output)) return error.MissingActualNativeModuleCallbackReason;
    return output;
}
pub fn create(engine: *v.em.Engine, name: [*:0]const u8, length: c_int, constructible: bool, callback: Callback, roots: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    const root_bytes = std.math.mul(usize, roots.len, @sizeOf(c.JSValue)) catch return error.OutOfMemory;
    const reserved = std.math.add(usize, @sizeOf(State), root_bytes) catch return error.OutOfMemory;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, reserved) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, reserved);
    const state = try engine.gpa.create(State);
    errdefer if (!attached) engine.gpa.destroy(state);
    const retained = try engine.gpa.alloc(c.JSValue, roots.len);
    errdefer if (!attached) engine.gpa.free(retained);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native Module Function", .call = call, .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const prototype = try engine.checked(c.JS_GetFunctionProto(engine.context));
    defer engine.freeValue(prototype);
    const function = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, id));
    errdefer engine.freeValue(function);
    for (roots, retained) |root, *slot| slot.* = c.JS_DupValue(engine.context, root);
    state.* = .{ .engine = engine, .callback = callback, .roots = retained, .constructible = constructible, .reserved = reserved };
    _ = c.JS_SetOpaque(function, state);
    attached = true;
    _ = c.JS_SetConstructorBit(engine.context, function, constructible);
    try define(engine, function, "name", try engine.checked(c.JS_NewString(engine.context, name)), c.JS_PROP_CONFIGURABLE);
    try define(engine, function, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE);
    if (constructible) {
        const instance_prototype = try v.js.object(engine);
        defer engine.freeValue(instance_prototype);
        try define(engine, instance_prototype, "constructor", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
        try define(engine, function, "prototype", c.JS_DupValue(engine.context, instance_prototype), c.JS_PROP_WRITABLE);
    }
    return function;
}
/// Only the Module factory's own cached callable is passed here. This is not
/// an entry point for casting a guest-provided function or ownership token.
pub fn capturedRoots(engine: *v.em.Engine, known_function: c.JSValue) ![]const c.JSValue {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(known_function, c.JS_GetClassID(known_function)) orelse return error.InvalidKnownModuleCallable));
    if (state.engine != engine) return error.InvalidKnownModuleCallable;
    return state.roots;
}
fn define(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, owned: c.JSValue, flags: c_int) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, owned, flags | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
