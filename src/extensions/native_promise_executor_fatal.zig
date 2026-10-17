//! Private first-event retention across one live global Promise construction.
//! No Engine fields, public properties, Promise replacement or rejection-DATA
//! inference. The actual executor calls recordFailure at its failed operation.
const em = @import("engine.zig");
const c = em.c;
const body = @import("native_async_body.zig");
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
pub fn create(engine: *em.Engine) !c.JSValue {
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Private Promise executor fatal", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, class)); errdefer engine.freeValue(owner);
    const holder = try engine.gpa.create(Holder); holder.* = .{ .engine = engine }; _ = c.JS_SetOpaque(owner, holder); return owner;
}
/// A producer failure, with the generation snapped immediately before THAT
/// get/set/call. A getter's caught private reason is historical to a later call.
pub fn failureSince(engine: *em.Engine, err: anyerror, generation: u64) anyerror {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    if (err == error.OutOfMemory) {
        _ = engine.throwNativeOutOfMemory(); const reason = c.JS_GetException(engine.context); c.JS_SetUncatchableError(engine.context, reason);
        _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |fatal| return fatal; unreachable;
    }
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| body.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
    return err;
}
pub fn recordFailure(engine: *em.Engine, owner: c.JSValue, err: anyerror, generation: u64) anyerror {
    const failure_error = failureSince(engine, err, generation);
    if (failure_error == error.JavaScriptException) if (engine.captured_exception) |reason| {
        const tagged = c.pi_js_native_allocation_error_generation(reason); const distance = tagged -% generation;
        const fresh = tagged != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation;
        if (c.JS_IsUncatchableError(reason) and (err == error.OutOfMemory or fresh)) {
            const holder = data(owner); if (holder.first == null) holder.first = c.JS_DupValue(engine.context, reason);
        }
    };
    return failure_error;
}
fn drain(engine: *em.Engine) void { while (c.JS_HasException(engine.context)) { const reason = c.JS_GetException(engine.context); engine.freeValue(reason); } }
/// Borrowed arguments and holder; owned return. The first callback fatal stays
/// outside mutable exception slots while releasing all displaced ownership.
pub fn constructOwned(engine: *em.Engine, constructor: c.JSValue, args: []const c.JSValue, owner: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    const result = c.JS_CallConstructor(engine.context, constructor, @intCast(args.len), @constCast(args.ptr));
    if (data(owner).first) |first| {
        const reason = c.JS_DupValue(engine.context, first);
        const pending: ?c.JSValue = if (c.JS_HasException(engine.context)) c.JS_GetException(engine.context) else null;
        const captured = engine.captured_exception; engine.captured_exception = null;
        engine.freeValue(result); drain(engine);
        if (pending) |old| { engine.freeValue(old); drain(engine); }
        if (captured) |old| { engine.freeValue(old); drain(engine); }
        c.JS_SetUncatchableError(engine.context, reason); return engine.checked(c.JS_Throw(engine.context, reason));
    }
    if (c.JS_HasException(engine.context) and !c.JS_IsException(result)) {
        const reason = c.JS_GetException(engine.context); engine.freeValue(result); drain(engine);
        return engine.checked(c.JS_Throw(engine.context, reason));
    }
    return engine.checked(result) catch |err| return failureSince(engine, err, generation);
}
