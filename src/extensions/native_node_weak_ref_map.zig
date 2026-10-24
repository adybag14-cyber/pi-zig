//! Complete private diagnostics_channel WeakRefMap class (original lines 36-65).
//! Real SafeMap storage, one genuine FinalizationRegistry per instance, and the
//! canonical internal/util WeakReference supplied explicitly by its owner.
//! This leaf does not publish channels or choose any tracing/process policy.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const functions = @import("native_node_module_callable.zig");
const classes = @import("native_node_error_class.zig");
const collections = @import("native_node_fs_collections.zig");

pub const Inputs = struct {
    /// Required actual internal/util import. The canonical util owner retains
    /// one class evaluation; this consumer never fabricates a replacement.
    weak_reference: c.JSValue,
};

fn typeError(s: *a.Scope, message: [*:0]const u8) !c.JSValue {
    const generation = try s.beforeAllocation();
    return s.checkedAllocation(c.JS_ThrowTypeError(s.engine.context, "%s", message), generation);
}

fn privateRead(s: *a.Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(receiver))
        return typeError(s, "Cannot read private member #finalizers from an object whose class did not declare it");
    var found: c_int = 0;
    try s.pending();
    const value = try s.checked(c.JS_PiGetOwnPrivateProperty(
        s.engine.context, receiver, key, &found));
    if (found == 0)
        return typeError(s, "Cannot read private member #finalizers from an object whose class did not declare it");
    return value;
}

fn initializePrivate(s: *a.Scope, receiver: c.JSValue,
    key: c.JSValue, value: c.JSValue) !void
{
    // The field initializer has already run. Check the receiver's own private
    // brand only now, including an object returned by a changed superclass.
    var found: c_int = 0;
    try s.pending();
    _ = try s.checked(c.JS_PiGetOwnPrivateProperty(
        s.engine.context, receiver, key, &found));
    if (found != 0) {
        _ = try typeError(s, "Cannot initialize #finalizers twice on the same object");
        return error.ActualWeakRefMapPrivateReinitializationRequired;
    }
    try s.pending();
    const status = c.JS_PiSetPrivateProperty(s.engine.context, receiver, key,
        a.duplicate(s.engine, value));
    try s.pending();
    if (status < 0) return error.MissingActualWeakRefMapPrivateDefinitionReason;
}

/// Resolve the current [[Prototype]] of the method's actual home object, then
/// perform Get with the original receiver. Ordinary parent.get would give a
/// superclass accessor or Proxy the wrong receiver.
fn superMethod(s: *a.Scope, home: c.JSValue, receiver: c.JSValue,
    comptime name: [*:0]const u8) !c.JSValue
{
    const base = try s.prototype(home);
    const generation = try s.beforeAllocation();
    const atom = c.JS_NewAtom(s.engine.context, name);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try s.boundary.checkPendingSince(generation);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    try s.pending();
    return s.checked(c.JS_PiGetPropertyReceiver(s.engine.context, base, atom, receiver));
}

fn cleanupHas(s: *a.Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    const method = try s.get(receiver, "has");
    return a.boolean(s, s.truthy(try s.call(method, receiver, &.{key})));
}
fn cleanupDelete(s: *a.Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    const method = try s.get(receiver, "delete");
    _ = try s.call(method, receiver, &.{key});
    return c.pi_js_undefined();
}
fn cleanup(engine: *a.v.em.Engine, _: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    // Original arrow lexical this survives callback receiver changes. Retire
    // the condition expression before looking up delete on the live object.
    const key = a.arg(args, 0);
    if (!try a.condition(engine, cleanupHas, .{roots[0], key}))
        _ = try a.expression(engine, cleanupDelete, .{roots[0], key});
    return c.pi_js_undefined();
}

fn construct(engine: *a.v.em.Engine, lexical_class: c.JSValue,
    new_target: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, constructBody, .{lexical_class, new_target, args, roots});
}
fn constructBody(s: *a.Scope, lexical_class: c.JSValue,
    new_target: c.JSValue, args: []const c.JSValue,
    roots: []const c.JSValue) !c.JSValue
{
    // The implicit derived constructor forwards actual arguments without an
    // artificial rest-array iterator, and resolves the live lexical super.
    const base = try s.prototype(lexical_class);
    try s.pending();
    const receiver = try s.checked(c.JS_CallConstructor2(s.engine.context,
        base, new_target, @intCast(args.len), @constCast(args.ptr)));
    const callback = try s.own(try functions.create(s.engine, "", 1, false,
        cleanup, &.{receiver}));
    const registry = try s.construct(roots[1], &.{callback});
    try initializePrivate(s, receiver, roots[0], registry);
    return a.duplicate(s.engine, receiver);
}

fn registerBody(s: *a.Scope, receiver: c.JSValue, key: c.JSValue,
    value: c.JSValue, private_key: c.JSValue) !c.JSValue
{
    const registry = try privateRead(s, receiver, private_key);
    const method = try s.get(registry, "register");
    _ = try s.call(method, registry, &.{value, key});
    return c.pi_js_undefined();
}
fn setBody(s: *a.Scope, receiver: c.JSValue, key: c.JSValue,
    value: c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    // Resolve super.set before constructing its second argument.
    const method = try superMethod(s, roots[0], receiver, "set");
    const reference = try s.construct(roots[2], &.{value});
    return a.duplicate(s.engine, try s.call(method, receiver, &.{key, reference}));
}
fn set(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    const key = a.arg(args, 0);
    const value = a.arg(args, 1);
    _ = try a.expression(engine, registerBody, .{receiver, key, value, roots[1]});
    return a.expression(engine, setBody, .{receiver, key, value, roots});
}

fn throughReference(s: *a.Scope, receiver: c.JSValue, key: c.JSValue,
    home: c.JSValue, comptime name: [*:0]const u8) !c.JSValue
{
    const method = try superMethod(s, home, receiver, "get");
    const reference = try s.call(method, receiver, &.{key});
    if (c.JS_IsNull(reference) or c.JS_IsUndefined(reference))
        return c.pi_js_undefined();
    const operation = try s.get(reference, name);
    return a.duplicate(s.engine, try s.call(operation, reference, &.{}));
}
fn get(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, throughReference, .{receiver, a.arg(args, 0), roots[0], "get"});
}
fn increase(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, throughReference, .{receiver, a.arg(args, 0), roots[0], "incRef"});
}
fn decrease(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, throughReference, .{receiver, a.arg(args, 0), roots[0], "decRef"});
}
fn hasBody(s: *a.Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    const method = try s.get(receiver, "get");
    return a.boolean(s, s.truthy(try s.call(method, receiver, &.{key})));
}
fn has(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, _: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, hasBody, .{receiver, a.arg(args, 0)});
}

/// One complete original class evaluation. SafeCollections must be acquired
/// during actual primordial bootstrap before public constructors are replaced.
/// This does not initialize the canonical diagnostics_channel module by itself.
pub fn create(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, createBody, .{inputs});
}
fn createBody(s: *a.Scope, inputs: Inputs) !c.JSValue {
    try s.pending();
    try s.engine.checkNativeEntry();
    const weak_reference = try s.own(a.duplicate(s.engine, inputs.weak_reference));
    const safe_map = try s.own(try collections.acquireSafeMap(s.engine));
    const safe_finalizers = try s.own(try collections.acquireSafeFinalizationRegistry(s.engine));
    const generation = try s.beforeAllocation();
    const private_key = try s.checkedAllocation(
        c.JS_NewPrivateSymbol(s.engine.context, "#finalizers"), generation);
    const prototype = try s.objectProto(try s.get(safe_map, "prototype"));
    const constructor_value = try s.own(try classes.create(s.engine,
        "WeakRefMap", 0, prototype, safe_map, construct,
        &.{private_key, safe_finalizers}));
    const roots = [_]c.JSValue{prototype, private_key, weak_reference};
    inline for (.{ .{"set", 2, set}, .{"get", 1, get}, .{"has", 1, has},
        .{"incRef", 1, increase}, .{"decRef", 1, decrease} }) |definition|
    {
        const method = try s.own(try functions.create(s.engine,
            definition[0], definition[1], false, definition[2], &roots));
        try s.define(prototype, definition[0], method,
            c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    }
    return a.duplicate(s.engine, constructor_value);
}
