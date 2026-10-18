//! One live Promise construction's genuine first-event holder. Only a stable
//! Engine NativeInvocation.first can publish; callback inputs/flags cannot.
const x = @import("native_sdk_exec_values.zig");
const c = x.c;
const State = struct { engine: *x.em.Engine, active: bool = false, first: ?c.JSValue = null };
fn state(owner: c.JSValue) *State { return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?)); }
fn retire(rt: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    if (self.first) |reason| c.JS_FreeValueRT(rt, reason);
    const engine = self.engine; engine.gpa.destroy(self); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(rt: ?*c.JSRuntime, owner: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    if (self.first) |reason| c.JS_MarkValue(rt, reason, visit);
}
pub fn create(o: *x.Ops) !c.JSValue {
    const engine = o.s.engine;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    const data = try engine.gpa.create(State); errdefer if (!attached) engine.gpa.destroy(data);
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Private SDK exec constructor event", .gc_mark = mark, .finalizer = retire };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const owner = try o.own(try engine.checked(c.JS_NewObjectClass(engine.context, id)));
    data.* = .{ .engine = engine }; _ = c.JS_SetOpaque(owner, data); attached = true; return owner;
}
pub fn record(owner: c.JSValue, invocation: *const x.em.Engine.NativeInvocation) void {
    const self = state(owner);
    if (self.active and self.first == null) {
        if (invocation.first) |reason| self.first = c.JS_DupValue(self.engine.context, reason);
    }
}
pub fn construct(o: *x.Ops, constructor: c.JSValue, executor: c.JSValue, owner: c.JSValue) !c.JSValue {
    const self = state(owner); const engine = o.s.engine;
    try engine.checkNativeEntry(); const generation = engine.native_allocation_generation;
    self.active = true; var args = [_]c.JSValue{executor};
    const result = c.JS_CallConstructor(engine.context, constructor, 1, &args);
    self.active = false; // A retained executor's later calls cannot poison this construction.
    if (self.first) |reason| {
        // The actual callback event has independent ownership. Put it in the
        // stable completion before releasing result/captured/constructor errors.
        const old: ?c.JSValue = if (c.JS_HasException(engine.context)) c.JS_GetException(engine.context) else null;
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        var completion = x.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, error.JavaScriptException));
        if (!c.JS_IsException(result)) completion.release(result);
        if (old) |value| completion.release(value);
        return o.own(try completion.finishValue());
    }
    return o.accept(result, generation);
}
