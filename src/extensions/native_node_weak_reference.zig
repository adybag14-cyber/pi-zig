//! Complete private internal/util WeakReference class (Node util.js 906-937).
//! A class evaluation owns one unforgeable VM brand; instances own the genuine
//! captured WeakRef object and the optional strong root. No namespace or policy
//! is published here. The caller owns the returned class constructor.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const functions = @import("native_node_module_callable.zig");
const classes = @import("native_node_error_class.zig");

const Instance = struct {
    engine: *a.v.em.Engine,
    weak: c.JSValue,
    strong: c.JSValue,
    // Original #refCount is a JavaScript Number, including negative values.
    // IEEE binary64 addition/subtraction preserves its rounding semantics.
    ref_count: f64 = 0,
};

fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *Instance = @ptrCast(@alignCast(
        c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = self.engine;
    const weak = self.weak;
    const strong = self.strong;
    self.weak = c.pi_js_null();
    self.strong = c.pi_js_null();
    _ = c.JS_SetOpaque(value, null);
    c.JS_FreeValueRT(runtime, weak);
    c.JS_FreeValueRT(runtime, strong);
    engine.gpa.destroy(self);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Instance));
}

fn mark(runtime: ?*c.JSRuntime, value: c.JSValue,
    visitor: ?*const c.JS_MarkFunc) callconv(.c) void
{
    const self: *Instance = @ptrCast(@alignCast(
        c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    // Mark the actual WeakRef wrapper, never its weak referent. The VM owns
    // WeakRef target collection and constructor/deref kept-object behavior.
    c.JS_MarkValue(runtime, self.weak, visitor);
    c.JS_MarkValue(runtime, self.strong, visitor);
}

fn classId(s: *a.Scope, retained_id: c.JSValue) !c.JSClassID {
    try s.pending();
    var id: u32 = 0;
    const status = c.JS_ToUint32(s.engine.context, &id, retained_id);
    try s.pending();
    if (status < 0 or id == 0) return error.ActualWeakReferenceBrandRequired;
    return id;
}

fn instance(s: *a.Scope, receiver: c.JSValue, retained_id: c.JSValue,
    comptime field: [*:0]const u8) !*Instance
{
    // The live receiver is retained through all root retirement/reentry.
    _ = try s.own(a.duplicate(s.engine, receiver));
    const id = try classId(s, retained_id);
    const raw = c.JS_GetOpaque(receiver, id) orelse {
        const generation = try s.beforeAllocation();
        _ = try s.checkedAllocation(c.JS_ThrowTypeError(s.engine.context,
            "Cannot read private member %s from an object whose class did not declare it",
            field), generation);
        return error.ActualWeakReferenceBrandRejectionRequired;
    };
    const self: *Instance = @ptrCast(@alignCast(raw));
    if (self.engine != s.engine) return error.ForeignWeakReferenceInstance;
    return self;
}

fn construct(engine: *a.v.em.Engine, _: c.JSValue, new_target: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, constructBody, .{new_target, args, roots});
}

fn constructBody(s: *a.Scope, new_target: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    try s.pending();
    const id = try classId(s, roots[0]);
    // Base-class receiver allocation precedes field initialization and the
    // SafeWeakRef call; the actual new.target realm supplies fallback Object.
    const prototype = try s.checked(
        c.JS_PiGetObjectPrototypeFromConstructor(s.engine.context, new_target));
    const generation = try s.beforeAllocation();
    const receiver = try s.checkedAllocation(
        c.JS_NewObjectProtoClass(s.engine.context, prototype, id), generation);
    const charge = @sizeOf(Instance);
    if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, charge) == 0)
        return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached)
        c.pi_js_native_memory_release(s.engine.native_memory_owner, charge);
    const self = try s.engine.gpa.create(Instance);
    self.* = .{ .engine = s.engine, .weak = c.pi_js_null(),
        .strong = c.pi_js_null() };
    _ = c.JS_SetOpaque(receiver, self);
    attached = true;
    const weak = try s.construct(roots[1], &.{a.arg(args, 0)});
    self.weak = a.duplicate(s.engine, weak);
    return a.duplicate(s.engine, receiver);
}

fn increase(engine: *a.v.em.Engine, receiver: c.JSValue,
    _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, increaseBody, .{receiver, roots});
}

fn increaseBody(s: *a.Scope, receiver: c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    const self = try instance(s, receiver, roots[0], "#refCount");
    self.ref_count += 1;
    if (self.ref_count == 1) {
        const derefed = try s.call(roots[1], self.weak, &.{});
        if (!c.JS_IsUndefined(derefed)) {
            var previous = self.strong;
            self.strong = a.duplicate(s.engine, derefed);
            // Publish the private assignment before retiring the old root.
            s.boundary.release(&previous);
        }
    }
    // Read again after the genuine deref/assignment; reentry may change it.
    return c.JS_NewFloat64(s.engine.context, self.ref_count);
}

fn decrease(engine: *a.v.em.Engine, receiver: c.JSValue,
    _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, decreaseBody, .{receiver, roots});
}

fn decreaseBody(s: *a.Scope, receiver: c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    const self = try instance(s, receiver, roots[0], "#refCount");
    self.ref_count -= 1;
    if (self.ref_count == 0) {
        var previous = self.strong;
        self.strong = c.pi_js_null();
        s.boundary.release(&previous);
    }
    return c.JS_NewFloat64(s.engine.context, self.ref_count);
}

fn read(engine: *a.v.em.Engine, receiver: c.JSValue,
    _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, readBody, .{receiver, roots});
}

fn readBody(s: *a.Scope, receiver: c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    const self = try instance(s, receiver, roots[0], "#weak");
    return a.duplicate(s.engine, try s.call(roots[1], self.weak, &.{}));
}

/// One actual class evaluation. A future canonical internal/util owner must
/// retain this class once; calling create again intentionally creates a fresh
/// private brand, just as a distinct evaluation of the original declaration.
pub fn create(engine: *a.v.em.Engine) !c.JSValue {
    return a.expression(engine, createBody, .{});
}

fn createBody(s: *a.Scope) !c.JSValue {
    try s.pending();
    try s.engine.checkNativeEntry();
    const weak_constructor = s.engine.native_weak_ref_constructor orelse
        return error.ActualCapturedWeakRefConstructorRequired;
    const weak_deref = s.engine.native_weak_ref_deref orelse
        return error.ActualCapturedWeakRefDerefRequired;
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native WeakReference",
        .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(s.engine.runtime, id, &definition) < 0)
        return error.OutOfMemory;
    const retained_id = c.JS_NewUint32(s.engine.context, id);
    const prototype = try s.object();
    const function_prototype = try s.checked(c.JS_GetFunctionProto(s.engine.context));
    const constructor_value = try s.own(try classes.create(s.engine,
        "WeakReference", 1, prototype, function_prototype, construct,
        &.{retained_id, weak_constructor}));
    const roots = [_]c.JSValue{retained_id, weak_deref};
    inline for (.{ .{"incRef", increase}, .{"decRef", decrease}, .{"get", read} })
        |definition_value|
    {
        const method = try s.own(try functions.create(s.engine,
            definition_value[0], 0, false, definition_value[1], &roots));
        try s.define(prototype, definition_value[0], method,
            c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    }
    return a.duplicate(s.engine, constructor_value);
}
