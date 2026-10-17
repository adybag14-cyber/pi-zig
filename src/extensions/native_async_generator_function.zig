//! Genuine generator-function binding; requires the separately reviewed C API
//! proposal. No prototype branding, forwarding generator or generated JS body.
const em = @import("engine.zig");
const c = em.c;
const gen = @import("native_async_generator.zig");
const fatal = @import("native_promise_executor_fatal.zig");
pub const Factory = *const fn (*em.Engine, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
const Captures = struct { engine: *em.Engine, factory: Factory, values: []c.JSValue };
const CFactory = *const fn (?*c.JSContext, c.JSValue, c.JSValue, c_int, [*c]const c.JSValue) callconv(.c) c.JSValue;
extern "c" fn JS_PiNewNativeAsyncGeneratorFunction(?*c.JSContext, CFactory, *const c.JSPiAsyncGeneratorResume, c.JSValue, [*:0]const u8, c_int) c.JSValue;
fn finalizer(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const captures: *Captures = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for (captures.values) |value| c.JS_FreeValueRT(runtime, value);
    captures.engine.gpa.free(captures.values); captures.engine.gpa.destroy(captures);
}
fn mark(runtime: ?*c.JSRuntime, owner: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const captures: *Captures = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for (captures.values) |value| c.JS_MarkValue(runtime, value, visit);
}
fn createState(_: ?*c.JSContext, owner: c.JSValue, receiver: c.JSValue, argc: c_int, argv: [*c]const c.JSValue) callconv(.c) c.JSValue {
    const captures: *Captures = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
    captures.engine.native_exception_diagnostics_suppressed += 1;
    defer captures.engine.native_exception_diagnostics_suppressed -= 1;
    return captures.factory(captures.engine, receiver, if (argc == 0) &.{} else argv[0..@intCast(argc)], captures.values) catch |err| {
        return @import("native_sdk.zig").fail(captures.engine, if (err == error.OutOfMemory) fatal.failureSince(captures.engine, err, captures.engine.native_allocation_generation) else err);
    };
}
pub fn create(engine: *em.Engine, name: [*:0]const u8, length: c_int, factory: Factory, comptime body: gen.Resume, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn resume(context: ?*c.JSContext, state: c.JSValue, raw: c_int, input: c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue {
            const host = em.Engine.fromContext(context.?);
            host.native_exception_diagnostics_suppressed += 1;
            defer host.native_exception_diagnostics_suppressed -= 1;
            const step = body(host, state, @enumFromInt(raw), input) catch |err| return @import("native_sdk.zig").fail(host, if (err == error.OutOfMemory) fatal.failureSince(host, err, host.native_allocation_generation) else err);
            return switch (step) {
                .awaited => |value| result(action, c.JS_PI_AG_AWAIT, value), .yielded => |value| result(action, c.JS_PI_AG_YIELD, value),
                .returned => |value| result(action, c.JS_PI_AG_RETURN, value), .complete => |value| result(action, c.JS_PI_AG_COMPLETE, value), .thrown => |value| result(action, c.JS_PI_AG_THROW, value),
            };
        }
        fn result(action: [*c]c_int, kind: c_int, value: c.JSValue) c.JSValue { action[0] = kind; return value; }
    };
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Private native generator-function captures", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, class)); defer engine.freeValue(owner);
    const values = try engine.gpa.alloc(c.JSValue, roots.len); var attached = false; errdefer if (!attached) engine.gpa.free(values);
    const captures = try engine.gpa.create(Captures);
    for (roots, values) |root, *slot| slot.* = c.JS_DupValue(engine.context, root);
    captures.* = .{ .engine = engine, .factory = factory, .values = values }; _ = c.JS_SetOpaque(owner, captures); attached = true;
    return engine.checked(JS_PiNewNativeAsyncGeneratorFunction(engine.context, createState, Adapter.resume, owner, name, length));
}
