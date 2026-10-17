//! Proposal-only genuine native AsyncFunction bodies. No prototype branding or
//! JavaScript wrapper is used. QuickJS owns each outer Promise and real Await.
const em = @import("engine.zig");
const c = em.c;
pub const Callback = *const fn (*em.Engine, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
pub const Completion = enum(c_int) {
    start = c.JS_PI_AF_START,
    fulfilled = c.JS_PI_AF_AWAIT_FULFILLED,
    rejected = c.JS_PI_AF_AWAIT_REJECTED,
};
/// Every payload is owned. returned means `return expression` (adoption);
/// awaited means a real suspension; thrown preserves the raw reason.
pub const Action = union(enum) { returned: c.JSValue, awaited: c.JSValue, thrown: c.JSValue };
pub const Body = *const fn (*em.Engine, c.JSValue, []const c.JSValue, []const c.JSValue, *c.JSValue, Completion, c.JSValue) anyerror!Action;
const Implementation = union(enum) { callback: Callback, body: Body };
const Captures = struct { engine: *em.Engine, implementation: Implementation, values: []c.JSValue };
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const captures: *Captures = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (captures.values) |root| c.JS_FreeValueRT(runtime, root);
    captures.engine.gpa.free(captures.values);
    captures.engine.gpa.destroy(captures);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const captures: *Captures = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (captures.values) |root| c.JS_MarkValue(runtime, root, visit);
}
fn fail(engine: *em.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemoryFatal();
    return c.JS_ThrowTypeError(engine.context, "Native async body: %s", @as([*:0]const u8, @errorName(err)));
}
fn invoke(_: ?*c.JSContext, owner: c.JSValue, receiver: c.JSValue, argc: c_int, argv: [*c]const c.JSValue, raw: c_int, input: c.JSValue, state: [*c]c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue {
    const captures: *Captures = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
    const engine = captures.engine;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const args: []const c.JSValue = if (argc == 0) &.{} else argv[0..@intCast(argc)];
    const completion: Completion = @enumFromInt(raw);
    const result: Action = switch (captures.implementation) {
        .callback => |callback| blk: {
            if (completion != .start) return c.JS_ThrowInternalError(engine.context, "Simple native async body resumed");
            break :blk .{ .returned = callback(engine, receiver, args, captures.values) catch |err| return fail(engine, err) };
        },
        .body => |body| body(engine, receiver, args, captures.values, @ptrCast(state), completion, input) catch |err| return fail(engine, err),
    };
    return switch (result) {
        .returned => |value| resultValue(action, c.JS_PI_AF_RETURN, value),
        .awaited => |value| resultValue(action, c.JS_PI_AF_AWAIT, value),
        .thrown => |value| resultValue(action, c.JS_PI_AF_THROW, value),
    };
}
fn resultValue(action: [*c]c_int, kind: c_int, value: c.JSValue) c.JSValue {
    action[0] = kind;
    return value;
}
/// Replace the owned per-invocation state slot, consuming next. Borrowed roots,
/// arguments, receiver and input must be duplicated before storing or returning.
pub fn replaceState(engine: *em.Engine, state: *c.JSValue, next: c.JSValue) void {
    engine.freeValue(state.*);
    state.* = next;
}
pub fn create(engine: *em.Engine, name: [*:0]const u8, length: c_int, callback: Callback, roots: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, .{ .callback = callback }, roots, c.pi_js_undefined(), false);
}
pub fn createArrow(engine: *em.Engine, name: [*:0]const u8, length: c_int, callback: Callback, roots: []const c.JSValue, lexical_this: c.JSValue) !c.JSValue {
    return createKind(engine, name, length, .{ .callback = callback }, roots, lexical_this, true);
}
pub fn createResumable(engine: *em.Engine, name: [*:0]const u8, length: c_int, body: Body, roots: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, .{ .body = body }, roots, c.pi_js_undefined(), false);
}
pub fn createResumableArrow(engine: *em.Engine, name: [*:0]const u8, length: c_int, body: Body, roots: []const c.JSValue, lexical_this: c.JSValue) !c.JSValue {
    return createKind(engine, name, length, .{ .body = body }, roots, lexical_this, true);
}
fn createKind(engine: *em.Engine, name: [*:0]const u8, length: c_int, implementation: Implementation, roots: []const c.JSValue, lexical_this: c.JSValue, arrow: bool) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Private native AsyncFunction captures", .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, class));
    defer engine.freeValue(owner);
    const values = try engine.gpa.alloc(c.JSValue, roots.len);
    var attached = false;
    errdefer if (!attached) engine.gpa.free(values);
    const captures = try engine.gpa.create(Captures);
    for (roots, values) |root, *destination| destination.* = c.JS_DupValue(engine.context, root);
    captures.* = .{ .engine = engine, .implementation = implementation, .values = values };
    _ = c.JS_SetOpaque(owner, captures);
    attached = true;
    // From attachment onward the private holder's finalizer owns host storage.
    // A C factory failure releases its partial roots before owner is released.
    return engine.checked(c.JS_PiNewNativeAsyncFunction(engine.context, invoke, owner, lexical_this, if (arrow) c.JS_PI_AF_LEXICAL_THIS else 0, name, length));
}
