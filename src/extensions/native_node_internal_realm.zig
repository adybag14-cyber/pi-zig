// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual private realm for internal/util.getInternalGlobal's RegExp operation.
//! It shares the Engine runtime and its pending exception, while its intrinsic
//! RegExp.prototype is independent of mutable guest main-realm prototypes.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
const owned = @import("native_sdk_owned_completion.zig");
const publication = @import("native_node_fs_private_publication.zig");
const cache_key = "\x00native.internal.realm";
const State = struct {
    engine: *v.em.Engine,
    context: ?*c.JSContext = null,
    global_value: c.JSValue,
    regexp_exec: c.JSValue,
};
fn state(holder: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)).?));
}
fn finalizer(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    c.JS_FreeValueRT(runtime, self.regexp_exec);
    c.JS_FreeValueRT(runtime, self.global_value);
    if (self.context) |context| c.JS_FreeContext(context);
    const engine = self.engine;
    engine.gpa.destroy(self);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    c.JS_MarkValue(runtime, self.global_value, visit);
    c.JS_MarkValue(runtime, self.regexp_exec, visit);
}
fn createBody(s: *Scope) !c.JSValue {
    try s.pending();
    var class_id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native Node internal realm", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    const holder_generation = try s.beforeAllocation();
    const holder = try s.checkedAllocation(c.JS_NewObjectClass(s.engine.context, class_id), holder_generation);
    if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    const self = s.engine.gpa.create(State) catch |err| {
        c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(State));
        return err;
    };
    self.* = .{ .engine = s.engine, .global_value = c.pi_js_undefined(), .regexp_exec = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(holder, self);
    // The attached owner receives every successful native context before a
    // completion check, so later failure retires it only after selecting B1.
    const context_generation = try s.beforeAllocation();
    self.context = c.JS_NewContext(s.engine.runtime);
    try s.boundary.checkPendingSince(context_generation);
    const context = self.context orelse return error.OutOfMemory;
    c.JS_SetContextOpaque(context, s.engine);
    const global_value = try s.checked(c.JS_GetGlobalObject(context));
    self.global_value = c.JS_DupValue(context, global_value);
    const constructor = try s.checked(c.JS_GetPropertyStr(context, global_value, "RegExp"));
    const prototype_value = try s.checked(c.JS_GetPropertyStr(context, constructor, "prototype"));
    const exec = try s.checked(c.JS_GetPropertyStr(context, prototype_value, "exec"));
    self.regexp_exec = c.JS_DupValue(context, exec);
    return c.JS_DupValue(s.engine.context, holder);
}
pub fn acquire(engine: *v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |known| return c.JS_DupValue(engine.context, known);
    var s = Scope.init(engine);
    const candidate = try s.finish(createBody(&s));
    if (engine.native_module_values.get(cache_key)) |known| {
        var completion = owned.Completion.initValue(engine, c.JS_DupValue(engine.context, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, cache_key, candidate);
}
pub fn global(holder: c.JSValue) c.JSValue { return state(holder).global_value; }
/// Same-runtime JS calls already share rt.current_exception. Do not fetch and
/// rethrow a reason merely because this function comes from the private realm.
pub fn regexpExec(s: *Scope, holder: c.JSValue, expression: c.JSValue, input: c.JSValue) !c.JSValue {
    const self = state(holder);
    const args = [_]c.JSValue{input};
    try s.pending();
    // Argument ToString is guest-capable; no allocation-generation span.
    return s.checked(c.JS_Call(self.context.?, self.regexp_exec, expression, 1, &args));
}
