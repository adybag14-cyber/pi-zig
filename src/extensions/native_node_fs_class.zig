//! Filesystem-private class construction with completion before retirement.
//! The callback/new-target contract is the actual native_class contract;
//! existing public class owners and registries are unchanged.
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
pub const Construct = *const fn (*js.Engine, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
const State = struct {
    engine: *js.Engine,
    name: [:0]const u8,
    create: Construct,
    values: []c.JSValue,
};
fn finalizer(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    for (state.values) |value| c.JS_FreeValueRT(runtime, value);
    state.engine.gpa.free(state.values);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    for (state.values) |value| c.JS_MarkValue(runtime, value, visit);
}
fn call(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)) orelse return c.JS_ThrowTypeError(context, "Invalid native constructor")));
    const engine = state.engine;
    engine.checkNativeEntry() catch return engine.throwCaptured();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: js.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    const result = if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0)
        c.JS_ThrowTypeError(context, "Class constructor %s cannot be invoked without 'new'", state.name.ptr)
    else state.create(engine, target, if (argc == 0) &.{} else argv[0..@intCast(argc)], state.values) catch |err|
        if (err == error.JavaScriptException) engine.throwCaptured()
        else if (err == error.OutOfMemory) engine.throwNativeOutOfMemoryFatal()
        else c.JS_ThrowTypeError(context, "Native %s: %s", state.name.ptr, @as([*:0]const u8, @errorName(err)));
    return engine.leaveNativeInvocation(&invocation, result);
}
pub fn constructor(engine: *js.Engine, name: [:0]const u8, length: c_int, prototype_value: c.JSValue, create: Construct, values: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(body(&s, name, length, prototype_value, create, values));
}
fn body(s: *Scope, name: [:0]const u8, length: c_int, prototype_value: c.JSValue, create: Construct, values: []const c.JSValue) !c.JSValue {
    const engine = s.engine;
    try s.pending();
    var class: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &class) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native filesystem constructor", .finalizer = finalizer, .gc_mark = mark, .call = call };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    try s.pending();
    const function_prototype = try s.checked(c.JS_GetFunctionProto(engine.context));
    const generation = try s.beforeAllocation();
    const result = try s.checkedAllocation(c.JS_NewObjectProtoClass(engine.context, function_prototype, class), generation);
    const captures = try engine.gpa.alloc(c.JSValue, values.len);
    var attached = false;
    errdefer if (!attached) engine.gpa.free(captures);
    const state = try engine.gpa.create(State);
    for (values, captures) |value, *slot| slot.* = c.JS_DupValue(engine.context, value);
    state.* = .{ .engine = engine, .name = name, .create = create, .values = captures };
    _ = c.JS_SetOpaque(result, state);
    attached = true;
    _ = c.JS_SetConstructorBit(engine.context, result, true);
    try s.define(result, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE);
    try s.define(result, "name", try s.text(name), c.JS_PROP_CONFIGURABLE);
    try s.define(result, "prototype", prototype_value, 0);
    try s.define(prototype_value, "constructor", result, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    return c.JS_DupValue(engine.context, result);
}
