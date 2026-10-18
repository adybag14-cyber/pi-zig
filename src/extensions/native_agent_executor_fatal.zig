//! Private per-construction retention for the actual idle-Promise executor.
//! The global Promise constructor may consume an executor exception, then run
//! more user code. Engine's mutable diagnostic slot cannot retain that event.
const em = @import("engine.zig");
const p = @import("native_agent_af_values.zig");
const c = em.c;
const Holder = struct { engine: *em.Engine, first: ?c.JSValue = null };
fn data(owner: c.JSValue) *Holder { return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?)); }
fn finalizer(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const holder: *Holder = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    if (holder.first) |reason| c.JS_FreeValueRT(runtime, reason);
    holder.engine.gpa.destroy(holder);
}
fn mark(runtime: ?*c.JSRuntime, owner: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const holder: *Holder = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    if (holder.first) |reason| c.JS_MarkValue(runtime, reason, visit);
}
/// Owned private object; callback roots retain it even if a custom constructor
/// retains the executor. Nothing is exposed in a Source-visible object graph.
pub fn create(engine: *em.Engine) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Private Agent executor fatal", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, class));
    errdefer engine.freeValue(owner);
    const holder = try engine.gpa.create(Holder);
    holder.* = .{ .engine = engine };
    _ = c.JS_SetOpaque(owner, holder);
    return owner;
}
/// Only called on this executor's actual failed operation. No value supplied
/// as DATA is classified, and historical private tags remain ordinary.
pub fn callbackFailure(engine: *em.Engine, _: c.JSValue, err: anyerror, _: u64) anyerror {
    // The enclosing real constructor operation owns the stable invocation.
    // A captured flag or a generation change across the executor is DATA,
    // not proof of a producer. Only current actual pending/B1 may override.
    if (err == error.OutOfMemory) return p.callbackFailure(engine, err);
    engine.checkNativeEntry() catch |actual| return actual;
    return err;
}
pub fn construct(s: *p.Scope, constructor: c.JSValue, args: []const c.JSValue, _: c.JSValue) !c.JSValue {
    return p.construct(s, constructor, args);
}
