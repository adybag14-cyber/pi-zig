//! Actual ordinary callable/constructor with RootBfb producer ownership plus
//! Socket-local ordinary-reason escrow over the WHOLE invoke/receiver cleanup.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_node_socket_scope.zig").Scope;
pub const Callback = @import("native_node_function.zig").Callback;
const State = struct { engine: *js.Engine, callback: Callback, values: []c.JSValue, charged: usize, constructible: bool, arrow: bool };
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (state.values) |root| c.JS_FreeValueRT(runtime, root);
    const engine = state.engine; const charged = state.charged;
    engine.gpa.free(state.values); engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, charged);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (state.values) |root| c.JS_MarkValue(runtime, root, visitor);
}
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemoryFatal();
    if (c.JS_HasException(engine.context)) return engine.throwCaptured();
    return c.JS_ThrowTypeError(engine.context, "Native Socket function: %s", @as([*:0]const u8, @errorName(err)));
}
fn call(_: ?*c.JSContext, function: c.JSValue, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    const engine = state.engine;
    engine.checkNativeEntry() catch return engine.throwCaptured();
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = invoke(engine, state, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, flags & c.JS_CALL_FLAG_CONSTRUCTOR != 0) catch |err| fail(engine, err);
    return engine.leaveNativeInvocation(&invocation, result);
}
fn invoke(engine: *js.Engine, state: *State, target: c.JSValue, args: []const c.JSValue, constructing: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    errdefer |err| scope.captureUnwind(err);
    if (constructing and !state.constructible) return @as(anyerror!c.JSValue, js.typeError(engine, "Socket accessor is not a constructor"));
    const receiver = if (constructing) try scope.receiver(target) else if (state.arrow) c.pi_js_undefined() else target;
    const generation = engine.native_allocation_generation;
    const result = try scope.ownSince(try state.callback(engine, receiver, args, state.values), generation);
    return c.JS_DupValue(engine.context, if (constructing and !c.JS_IsObject(result)) receiver else result);
}
pub fn create(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, values, true, false);
}
pub fn createMethod(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, values, false, false);
}
pub fn createArrow(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, values, false, true);
}
fn createKind(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue, constructible: bool, arrow: bool) !c.JSValue {
    try engine.checkNativeEntry();
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    errdefer |err| scope.captureUnwind(err);
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Native Socket Function", .call = call, .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const prototype = try scope.own(c.JS_GetFunctionProto(engine.context));
    const function = try scope.own(c.JS_NewObjectProtoClass(engine.context, prototype, id));
    const roots_bytes = std.math.mul(usize, values.len, @sizeOf(c.JSValue)) catch return error.OutOfMemory;
    const charged = std.math.add(usize, @sizeOf(State), roots_bytes) catch return error.OutOfMemory;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, charged) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, charged);
    const roots = try engine.gpa.alloc(c.JSValue, values.len); errdefer if (!attached) engine.gpa.free(roots);
    const state = try engine.gpa.create(State);
    for (values, roots) |value, *root| root.* = c.JS_DupValue(engine.context, value);
    state.* = .{ .engine = engine, .callback = callback, .values = roots, .charged = charged, .constructible = constructible, .arrow = arrow };
    _ = c.JS_SetOpaque(function, state); attached = true;
    _ = c.JS_SetConstructorBit(engine.context, function, constructible);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    const actual_name = try scope.own(c.JS_NewString(engine.context, name));
    if (c.JS_DefinePropertyValueStr(engine.context, function, "name", c.JS_DupValue(engine.context, actual_name), c.JS_PROP_CONFIGURABLE) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    if (constructible) {
        const instance = try scope.object();
        if (c.JS_DefinePropertyValueStr(engine.context, instance, "constructor", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
        if (c.JS_DefinePropertyValueStr(engine.context, function, "prototype", c.JS_DupValue(engine.context, instance), c.JS_PROP_WRITABLE) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    }
    return c.JS_DupValue(engine.context, function);
}

test "actual Socket constructor receiver cleanup preserves ordinary B and promotes only current fatal C" {
    const owned = @import("native_node_socket_scope.zig");
    const Fixture = struct {
        var finalized: usize = 0;
        var armed: bool = false;
        fn callback(engine: *js.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            const witness = try owned.Testing.witness(engine, roots[1], &finalized, &armed);
            if (c.JS_DefinePropertyValueStr(engine.context, receiver, "nativeCleanup", witness, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, roots[0])));
        }
    };
    for ([_]bool{ false, true }) |cleanup_fatal| {
        const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const primary = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(primary);
        const cleanup = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(cleanup);
        if (cleanup_fatal) c.JS_SetUncatchableError(engine.context, cleanup);
        const constructor = try create(engine, "SocketReceiverCleanupControl", 0, Fixture.callback, &.{ primary, cleanup }); defer engine.freeValue(constructor);
        Fixture.finalized = 0; Fixture.armed = true; defer Fixture.armed = false;
        const result = c.JS_CallConstructor(engine.context, constructor, 0, null); defer engine.freeValue(result);
        try std.testing.expect(c.JS_IsException(result));
        const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, if (cleanup_fatal) cleanup else primary));
        try std.testing.expectEqual(@as(usize, 1), Fixture.finalized);
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
