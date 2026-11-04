//! One live Promise construction's genuine first-event holder. Only a stable
//! Engine NativeInvocation.first can publish; callback inputs/flags cannot.
const x = @import("native_sdk_exec_values.zig");
const c = x.c;
const State = struct { engine: *x.em.Engine, active: bool = false, first: ?c.JSValue = null, first_fatal: bool = false, terminated: bool = false };
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
    var id: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Private SDK exec constructor event", .gc_mark = mark, .finalizer = retire };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const generation = try o.beforeAllocation();
    const owner = try o.allocation(c.JS_NewObjectClass(engine.context, id), generation);
    data.* = .{ .engine = engine }; _ = c.JS_SetOpaque(owner, data); attached = true; return owner;
}
pub fn record(owner: c.JSValue, invocation: *const x.em.Engine.NativeInvocation) void {
    const self = state(owner);
    if (!self.active) return;
    self.terminated = self.terminated or invocation.terminated;
    if (self.first == null) if (invocation.first) |reason| {
        self.first = c.JS_DupValue(self.engine.context, reason);
        // NativeInvocation.first is independently retained actual authority.
        // Private priority remains dynamic; all other first events are generic fatal.
        self.first_fatal = !c.JS_PiIsExecutionTermination(reason);
    };
}
pub fn construct(o: *x.Ops, constructor: c.JSValue, executor: c.JSValue, owner: c.JSValue) !c.JSValue {
    const self = state(owner); const engine = o.s.engine;
    var operation: x.guest.Boundary = .{ .engine = engine };
    try operation.begin();
    self.active = true; var args = [_]c.JSValue{executor};
    const result = c.JS_CallConstructor(engine.context, constructor, 1, &args);
    self.active = false; // A retained executor's later calls cannot poison this construction.
    // Observe an actual private token before earlier first-event selection.
    // This preserves uniform history and does not poll a new request.
    engine.releaseNativeValue(c.pi_js_undefined());
    if (self.first != null or self.terminated or engine.nativeTerminationObserved()) {
        // Keep the later actual tuple in the slot while restoring the earlier
        // independently owned event. Both cached classes stay paired.
        if (self.first) |reason| _ = c.JS_PiThrowNativePending(engine.context,
            c.JS_DupValue(engine.context, reason), self.first_fatal);
        const err: anyerror = if (self.terminated or engine.nativeTerminationObserved())
            error.ExecutionTerminated else error.JavaScriptException;
        var completion = x.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        if (!c.JS_IsException(result)) completion.release(result);
        return operation.finishValue(o.s, completion.finishValue());
    }
    return operation.finishValue(o.s, result);
}
