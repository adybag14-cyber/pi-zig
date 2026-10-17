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
pub fn callbackFailure(engine: *em.Engine, owner: c.JSValue, err: anyerror, generation: u64) anyerror {
    var failure_error = err;
    if (err == error.OutOfMemory) {
        failure_error = p.callbackFailure(engine, err);
    } else if (err == error.JavaScriptException) {
        if (engine.captured_exception) |reason| p.body.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| { failure_error = fatal; };
    }
    if (failure_error == error.JavaScriptException) if (engine.captured_exception) |reason| {
        const tagged = c.pi_js_native_allocation_error_generation(reason);
        const distance = tagged -% generation;
        const fresh = tagged != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation;
        if (c.JS_IsUncatchableError(reason) and (err == error.OutOfMemory or fresh)) {
            const holder = data(owner);
            if (holder.first == null) holder.first = c.JS_DupValue(engine.context, reason);
        }
    };
    return failure_error;
}
fn drain(engine: *em.Engine) void {
    while (c.JS_HasException(engine.context)) {
        const displaced = c.JS_GetException(engine.context);
        engine.freeValue(displaced);
    }
}
/// Check the retained callback event BEFORE checking the constructor result.
/// This includes a custom constructor throwing after super(executor). Keep the
/// selected reason owned outside pending/captured slots while freeing results
/// and displaced reasons; cleanup cannot replace the first executor fatal.
pub fn construct(s: *p.Scope, constructor: c.JSValue, args: []const c.JSValue, owner: c.JSValue) !c.JSValue {
    const engine = s.engine;
    const generation = engine.native_allocation_generation;
    const result = c.JS_CallConstructor(engine.context, constructor, @intCast(args.len), @constCast(args.ptr));
    if (data(owner).first) |first| {
        const reason = c.JS_DupValue(engine.context, first);
        const pending: ?c.JSValue = if (c.JS_HasException(engine.context)) c.JS_GetException(engine.context) else null;
        const captured = engine.captured_exception;
        engine.captured_exception = null;
        engine.freeValue(result);
        drain(engine);
        if (pending) |old| { engine.freeValue(old); drain(engine); }
        if (captured) |old| { engine.freeValue(old); drain(engine); }
        c.JS_SetUncatchableError(engine.context, reason);
        return engine.checked(c.JS_Throw(engine.context, reason));
    }
    const checked = try p.guard(engine, generation, engine.checked(result));
    var owned = true;
    errdefer if (owned) engine.freeValue(checked);
    // Retain the ordinary constructor's existing pending/fresh-exit policy.
    if (c.JS_HasException(engine.context)) return p.guard(engine, generation, engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context))));
    if (engine.captured_exception) |reason| if (c.JS_IsUncatchableError(reason)) try p.body.rethrowRecognizedAllocation(engine, reason, generation);
    owned = false;
    return s.own(checked);
}
