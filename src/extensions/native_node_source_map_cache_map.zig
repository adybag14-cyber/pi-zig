// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual internal/source_map/source_map_cache_map.js class and lexical debug
//! binding. Real Map, WeakRef and FinalizationRegistry objects own all entries.
//! The caller supplies the genuine internal/util/debuglog.debuglog collaborator;
//! no support flag, environment default, logger no-op or source-map parser lives here.
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const classes = @import("native_node_error_class.zig");
const sync = @import("native_sync_arguments.zig");
pub const Inputs = struct { debuglog: c.JSValue };
const SetFrame = a.frames.Frame(enum { weak_ref });
const GetFrame = a.frames.Frame(enum { weak_ref, module_instance });
const CleanupFrame = a.frames.Frame(enum { ref });
const NextFrame = a.frames.Frame(enum { result, key, weak_ref, module_instance, value });

fn intrinsic(s: *Scope, name: [*:0]const u8) !c.JSValue {
    return s.get(s.engine.intrinsic_clone_operations, name);
}
fn privateSymbol(s: *Scope, name: [*:0]const u8) !c.JSValue {
    const generation = try s.beforeAllocation();
    return s.checkedAllocation(c.JS_NewPrivateSymbol(s.engine.context, name), generation);
}
fn typeError(s: *Scope, message: [*:0]const u8) !c.JSValue {
    const generation = try s.beforeAllocation();
    return s.checkedAllocation(c.JS_ThrowTypeError(s.engine.context, "%s", message), generation);
}
fn privateSet(s: *Scope, receiver: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    // The actual own-private Set consumes its value on every path and bypasses
    // Proxy/prototype traps. An existing native accessor may execute guest code.
    try s.pending();
    const status = c.JS_PiSetPrivateProperty(s.engine.context, receiver, key, a.duplicate(s.engine, value));
    try s.pending();
    if (status < 0) return error.MissingActualSourceMapPrivateSetReason;
}
fn ownPrivate(s: *Scope, receiver: c.JSValue, key: c.JSValue, require_brand: bool) !c.JSValue {
    if (!c.JS_IsObject(receiver)) {
        if (require_brand or c.JS_IsNull(receiver) or c.JS_IsUndefined(receiver))
            return typeError(s, "Receiver has no SourceMapCacheMap private field");
        // A nonregistered Symbol may pass WeakRef before a failed strict Set.
        // A later primitive property Get has no own internal private storage.
        return c.pi_js_undefined();
    }
    // A missing private slot must not fall through to an exotic descriptor
    // trap or to a Proxy target. The genuine own-private producer also retains
    // an accessor callee through self-removal and preserves its actual result.
    var found: c_int = 0;
    try s.pending();
    const value = try s.checked(c.JS_PiGetOwnPrivateProperty(
        s.engine.context, receiver, key, &found));
    if (found == 0) {
        if (require_brand) return typeError(s, "Receiver has no SourceMapCacheMap private field");
        return c.pi_js_undefined();
    }
    return a.duplicate(s.engine, value);
}
fn branded(s: *Scope, owner: c.JSValue, receiver: c.JSValue, field: [*:0]const u8) !c.JSValue {
    const key = try s.get(owner, field);
    return s.own(try a.expression(s.engine, ownPrivate, .{ receiver, key, true }));
}
fn defineSymbol(s: *Scope, receiver: c.JSValue, key: c.JSValue, value: c.JSValue, flags: c_int) !void {
    try s.pending();
    const atom = c.JS_ValueToAtom(s.engine.context, key);
    s.pending() catch |err| { if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom); return err; };
    if (atom == c.JS_ATOM_NULL) return error.MissingActualSourceMapSymbolAtomReason;
    defer c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    const status = c.JS_DefinePropertyValue(s.engine.context, receiver, atom, a.duplicate(s.engine, value), flags | c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualSourceMapSymbolDefinitionReason;
}
fn defineSize(s: *Scope, prototype_value: c.JSValue, getter: c.JSValue) !void {
    const generation = try s.beforeAllocation();
    const atom = c.JS_NewAtom(s.engine.context, "size");
    s.boundary.checkPendingSince(generation) catch |err| { if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom); return err; };
    if (atom == c.JS_ATOM_NULL) return error.MissingActualSourceMapSizeAtomReason;
    defer c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    const status = c.JS_DefinePropertyGetSet(s.engine.context, prototype_value, atom,
        a.duplicate(s.engine, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualSourceMapSizeDefinitionReason;
}

fn debugAssignment(s: *Scope, owner: c.JSValue, value: c.JSValue) !c.JSValue {
    if (!s.truthy(try s.get(owner, "debug_ready"))) {
        const generation = try s.beforeAllocation();
        return s.checkedAllocation(c.JS_ThrowReferenceError(s.engine.context, "Cannot access 'debug' before initialization"), generation);
    }
    try s.put(owner, "debug", value);
    return c.pi_js_undefined();
}
fn debugCallback(engine: *v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, debugAssignment, .{ roots[0], args.get(0) });
}
/// Return the owned actual class constructor. The enclosing real Module graph
/// must supply its real debuglog owner; there is no implicit policy/fallback.
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, createBody, .{inputs});
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    const owner = try s.objectProto(c.pi_js_null());
    try s.define(owner, "map_key", try privateSymbol(s, "SourceMapCacheMap.#weakModuleMap"), 0);
    try s.define(owner, "cleanup_key", try privateSymbol(s, "SourceMapCacheMap.#cleanup"), 0);
    try s.define(owner, "registry_key", try privateSymbol(s, "SourceMapCacheMap.#finalizationRegistry"), 0);
    try s.define(owner, "debug", c.pi_js_undefined(), c.JS_PROP_WRITABLE);
    try s.define(owner, "debug_ready", a.boolean(s, false), c.JS_PROP_WRITABLE);
    const assign_debug = try s.own(try functions.createWithArguments(s.engine, "", 1, false,
        .{ .formal_count = 1, .callback = debugCallback }, &.{owner}));
    // The real lazy debuglog result and callback share the mutable lexical
    // binding. A callback before initialization observes the original TDZ.
    const debug_value = try s.call(inputs.debuglog, c.pi_js_undefined(), &.{ try s.text("source_map"), assign_debug });
    try s.put(owner, "debug", debug_value);
    try s.put(owner, "debug_ready", a.boolean(s, true));
    const prototype_value = try s.object();
    const function_prototype = try s.checked(c.JS_GetFunctionProto(s.engine.context));
    const constructor_value = try s.own(try classes.create(s.engine, "SourceMapCacheMap", 0,
        prototype_value, function_prototype, constructClass, &.{owner}));
    const set_method = try s.own(try functions.createWithArguments(s.engine, "set", 3, false,
        .{ .formal_count = 3, .callback = setCallback, .hooks = sync.frameHooks(SetFrame) }, &.{owner}));
    const get_method = try s.own(try functions.createWithArguments(s.engine, "get", 1, false,
        .{ .formal_count = 1, .callback = getCallback, .hooks = sync.frameHooks(GetFrame) }, &.{owner}));
    const size_getter = try s.own(try functions.createWithArguments(s.engine, "get size", 0, false,
        .{ .formal_count = 0, .callback = sizeCallback }, &.{owner}));
    const iterator_method = try s.own(try functions.createWithArguments(s.engine, "[Symbol.iterator]", 0, false,
        .{ .formal_count = 0, .callback = iteratorCallback }, &.{owner}));
    try s.define(prototype_value, "set", set_method, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try s.define(prototype_value, "get", get_method, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try defineSize(s, prototype_value, size_getter);
    try defineSymbol(s, prototype_value, try intrinsic(s, "Symbol.iterator"), iterator_method, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    _ = try s.call(try intrinsic(s, "Object.freeze"), c.pi_js_undefined(), &.{prototype_value});
    return a.duplicate(s.engine, constructor_value);
}
fn initializeMap(s: *Scope, owner: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const map_value = try s.construct(try intrinsic(s, "Map"), &.{});
    try privateSet(s, receiver, try s.get(owner, "map_key"), map_value);
    return c.pi_js_undefined();
}
fn initializeCleanup(s: *Scope, owner: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const cleanup = try s.own(try functions.createWithArguments(s.engine, "#cleanup", 1, false,
        .{ .formal_count = 1, .callback = cleanupCallback }, &.{ owner, receiver }));
    try privateSet(s, receiver, try s.get(owner, "cleanup_key"), cleanup);
    return c.pi_js_undefined();
}
fn initializeRegistry(s: *Scope, owner: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const callback = try branded(s, owner, receiver, "cleanup_key");
    const registry = try s.construct(try intrinsic(s, "FinalizationRegistry"), &.{callback});
    try privateSet(s, receiver, try s.get(owner, "registry_key"), registry);
    return c.pi_js_undefined();
}
fn constructBody(s: *Scope, target: c.JSValue, owner: c.JSValue) !c.JSValue {
    try s.pending();
    const prototype_value = try s.checked(c.JS_PiGetObjectPrototypeFromConstructor(s.engine.context, target));
    const receiver = try s.objectProto(prototype_value);
    _ = try a.expression(s.engine, initializeMap, .{ owner, receiver });
    _ = try a.expression(s.engine, initializeCleanup, .{ owner, receiver });
    _ = try a.expression(s.engine, initializeRegistry, .{ owner, receiver });
    return a.duplicate(s.engine, receiver);
}
fn constructClass(engine: *v.em.Engine, _: c.JSValue, target: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, constructBody, .{ target, roots[0] });
}

fn weakReference(s: *Scope, target: c.JSValue) !c.JSValue {
    const constructor_value = s.engine.native_weak_ref_constructor orelse return error.ActualPristineWeakRefRequired;
    return a.duplicate(s.engine, try s.construct(constructor_value, &.{target}));
}
fn dereference(s: *Scope, reference: c.JSValue) !c.JSValue {
    const function = s.engine.native_weak_ref_deref orelse return error.ActualPristineWeakRefDerefRequired;
    return a.duplicate(s.engine, try s.call(function, reference, &.{}));
}
fn setOne(s: *Scope, owner: c.JSValue, receiver: c.JSValue, weak_ref: c.JSValue, key: c.JSValue) !c.JSValue {
    const map_value = try branded(s, owner, receiver, "map_key");
    return a.duplicate(s.engine, try s.call(try intrinsic(s, "Map.insert"), map_value, &.{ key, weak_ref }));
}
fn setKeyCallback(engine: *v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, setOne, .{ roots[0], roots[1], roots[2], args.get(0) });
}
fn setKeys(s: *Scope, owner: c.JSValue, receiver: c.JSValue, keys: c.JSValue, weak_ref: c.JSValue) !c.JSValue {
    const callback = try s.own(try functions.createWithArguments(s.engine, "", 1, false,
        .{ .formal_count = 1, .callback = setKeyCallback }, &.{ owner, receiver, weak_ref }));
    _ = try s.call(try intrinsic(s, "Array.forEach"), keys, &.{callback});
    return c.pi_js_undefined();
}
fn setData(s: *Scope, module_instance: c.JSValue, source_map_data: c.JSValue) !c.JSValue {
    try privateSet(s, module_instance, try intrinsic(s, "Node.source_map_data_private_symbol"), source_map_data);
    return c.pi_js_undefined();
}
fn registerModule(s: *Scope, owner: c.JSValue, receiver: c.JSValue, module_instance: c.JSValue, keys: c.JSValue) !c.JSValue {
    const registry = try branded(s, owner, receiver, "registry_key");
    const register = try intrinsic(s, "FinalizationRegistry.register");
    const held = try s.object();
    try s.define(held, "keys", keys, c.JS_PROP_C_W_E);
    _ = try s.call(register, registry, &.{ module_instance, held });
    return c.pi_js_undefined();
}
fn setBody(s: *Scope, owner: c.JSValue, receiver: c.JSValue, args: *sync.Arguments, frame: *SetFrame) !c.JSValue {
    try frame.take(.weak_ref, a.expression(s.engine, weakReference, .{args.get(2)}));
    _ = try a.expression(s.engine, setKeys, .{ owner, receiver, args.get(0), frame.get(.weak_ref) });
    _ = try a.expression(s.engine, setData, .{ args.get(2), args.get(1) });
    _ = try a.expression(s.engine, registerModule, .{ owner, receiver, args.get(2), args.get(0) });
    return c.pi_js_undefined();
}
fn setCallback(engine: *v.em.Engine, receiver: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = args.createFrame(&s.values, SetFrame) catch |err| return s.finish(@as(anyerror!c.JSValue, err));
    return s.finish(setBody(&s, roots[0], receiver, args, frame));
}
fn lookup(s: *Scope, owner: c.JSValue, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    const map_value = try branded(s, owner, receiver, "map_key");
    return a.duplicate(s.engine, try s.call(try intrinsic(s, "Map.get"), map_value, &.{key}));
}
fn moduleData(s: *Scope, module_instance: c.JSValue) !c.JSValue {
    const key = try intrinsic(s, "Node.source_map_data_private_symbol");
    return ownPrivate(s, module_instance, key, false);
}
fn getBody(s: *Scope, owner: c.JSValue, receiver: c.JSValue, args: *sync.Arguments, frame: *GetFrame) !c.JSValue {
    try frame.take(.weak_ref, a.expression(s.engine, lookup, .{ owner, receiver, args.get(0) }));
    const weak_ref = frame.get(.weak_ref);
    if (!c.JS_IsUndefined(weak_ref) and !c.JS_IsNull(weak_ref))
        try frame.take(.module_instance, a.expression(s.engine, dereference, .{weak_ref}));
    if (c.JS_IsUndefined(frame.get(.module_instance))) return c.pi_js_undefined();
    return a.expression(s.engine, moduleData, .{frame.get(.module_instance)});
}
fn getCallback(engine: *v.em.Engine, receiver: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = args.createFrame(&s.values, GetFrame) catch |err| return s.finish(@as(anyerror!c.JSValue, err));
    return s.finish(getBody(&s, roots[0], receiver, args, frame));
}
fn sizeBody(s: *Scope, owner: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const map_value = try branded(s, owner, receiver, "map_key");
    return a.duplicate(s.engine, try s.call(try intrinsic(s, "Map.size"), map_value, &.{}));
}
fn sizeCallback(engine: *v.em.Engine, receiver: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, sizeBody, .{ roots[0], receiver });
}

fn deadReference(s: *Scope, ref: c.JSValue) !c.JSValue {
    const target = try s.own(try a.expression(s.engine, dereference, .{ref}));
    return a.boolean(s, c.JS_IsUndefined(target));
}
fn debugObsolete(s: *Scope, owner: c.JSValue, key: c.JSValue) !c.JSValue {
    // Resolve the lexical callee BEFORE template interpolation. ToString is
    // observable even if the real logger is currently disabled or is noncallable.
    const function = try s.get(owner, "debug");
    const prefix = try s.text("Cleanup obsolete source map cache entry with key: ");
    const key_text = try s.toString(key);
    const message = try a.add(s, prefix, key_text);
    _ = try s.call(function, c.pi_js_undefined(), &.{message});
    return c.pi_js_undefined();
}
fn deleteKey(s: *Scope, owner: c.JSValue, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    const map_value = try branded(s, owner, receiver, "map_key");
    _ = try s.call(try intrinsic(s, "Map.delete"), map_value, &.{key});
    return c.pi_js_undefined();
}
fn cleanupKeyBody(s: *Scope, owner: c.JSValue, receiver: c.JSValue, key: c.JSValue, frame: *CleanupFrame) !c.JSValue {
    try frame.take(.ref, a.expression(s.engine, lookup, .{ owner, receiver, key }));
    if (s.truthy(frame.get(.ref)) and try a.condition(s.engine, deadReference, .{frame.get(.ref)})) {
        _ = try a.expression(s.engine, debugObsolete, .{ owner, key });
        // Reacquire the private Map after logging. Reentrant replacement from
        // key coercion/debug does not undo the original unconditional delete.
        _ = try a.expression(s.engine, deleteKey, .{ owner, receiver, key });
    }
    return c.pi_js_undefined();
}
fn cleanupKeyCallback(engine: *v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = args.createFrame(&s.values, CleanupFrame) catch |err| return s.finish(@as(anyerror!c.JSValue, err));
    return s.finish(cleanupKeyBody(&s, roots[0], roots[1], args.get(0), frame));
}
fn cleanupBody(s: *Scope, owner: c.JSValue, receiver: c.JSValue, args: *sync.Arguments) !c.JSValue {
    // The original parameter is ({ keys }), not a snapshot of the keys array.
    try args.take(0, a.field(s.engine, args.get(0), "keys"));
    const callback = try s.own(try functions.createWithArguments(s.engine, "", 1, false,
        .{ .formal_count = 1, .callback = cleanupKeyCallback, .hooks = sync.frameHooks(CleanupFrame) }, &.{ owner, receiver }));
    _ = try s.call(try intrinsic(s, "Array.forEach"), args.get(0), &.{callback});
    return c.pi_js_undefined();
}
fn cleanupCallback(engine: *v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, cleanupBody, .{ roots[0], roots[1], args });
}

fn iteratorSelf(engine: *v.em.Engine, receiver: c.JSValue, _: *sync.Arguments, _: []const c.JSValue) !c.JSValue {
    return a.duplicate(engine, receiver);
}
fn nextResult(s: *Scope, iterator_owner: c.JSValue) !c.JSValue {
    const iterator_value = try s.get(iterator_owner, "iterator");
    return a.duplicate(s.engine, try s.call(try intrinsic(s, "Map.next"), iterator_value, &.{}));
}
fn unpackResult(s: *Scope, frame: *NextFrame) !c.JSValue {
    // The original destructuring evaluates result.value once, then reads 0/1.
    const entry = try s.get(frame.get(.result), "value");
    try frame.take(.key, a.field(s.engine, entry, "0"));
    try frame.take(.weak_ref, a.field(s.engine, entry, "1"));
    return c.pi_js_undefined();
}
fn nextAgain(s: *Scope, iterator_owner: c.JSValue) !c.JSValue {
    // Preserve the actual recursive next call, including its original captured
    // function after the public iterator object's own next property is changed.
    const function = try s.get(iterator_owner, "next");
    return a.duplicate(s.engine, try s.call(function, c.pi_js_undefined(), &.{}));
}
fn yieldedPair(s: *Scope, key: c.JSValue, value: c.JSValue) !c.JSValue {
    const result = try s.object();
    try s.define(result, "done", a.boolean(s, false), c.JS_PROP_C_W_E);
    const pair = try a.array(s);
    try a.index(s, pair, 0, key);
    try a.index(s, pair, 1, value);
    try s.define(result, "value", pair, c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, result);
}
fn nextBody(s: *Scope, iterator_owner: c.JSValue, frame: *NextFrame) !c.JSValue {
    try frame.take(.result, a.expression(s.engine, nextResult, .{iterator_owner}));
    if (try a.condition(s.engine, a.fieldTruthy, .{ frame.get(.result), @as([*:0]const u8, "done") }))
        return a.duplicate(s.engine, frame.get(.result));
    _ = try a.expression(s.engine, unpackResult, .{frame});
    try frame.take(.module_instance, a.expression(s.engine, dereference, .{frame.get(.weak_ref)}));
    if (c.JS_IsUndefined(frame.get(.module_instance)) or c.JS_IsNull(frame.get(.module_instance)))
        return a.expression(s.engine, nextAgain, .{iterator_owner});
    try frame.take(.value, a.expression(s.engine, moduleData, .{frame.get(.module_instance)}));
    return a.expression(s.engine, yieldedPair, .{ frame.get(.key), frame.get(.value) });
}
fn nextCallback(engine: *v.em.Engine, _: c.JSValue, args: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = args.createFrame(&s.values, NextFrame) catch |err| return s.finish(@as(anyerror!c.JSValue, err));
    return s.finish(nextBody(&s, roots[0], frame));
}
fn iteratorBody(s: *Scope, owner: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const map_value = try branded(s, owner, receiver, "map_key");
    const iterator_value = try s.call(try intrinsic(s, "Map.iterate"), map_value, &.{});
    const iterator_owner = try s.objectProto(c.pi_js_null());
    try s.define(iterator_owner, "iterator", iterator_value, 0);
    const next = try s.own(try functions.createWithArguments(s.engine, "next", 0, false,
        .{ .formal_count = 0, .callback = nextCallback, .hooks = sync.frameHooks(NextFrame) }, &.{iterator_owner}));
    try s.define(iterator_owner, "next", next, 0);
    // This is an ordinary object literal, not a Map iterator/subclass/facade.
    const result = try s.object();
    const iterator_method = try s.own(try functions.createWithArguments(s.engine, "[Symbol.iterator]", 0, false,
        .{ .formal_count = 0, .callback = iteratorSelf }, &.{}));
    try defineSymbol(s, result, try intrinsic(s, "Symbol.iterator"), iterator_method, c.JS_PROP_C_W_E);
    try s.define(result, "next", next, c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, result);
}
fn iteratorCallback(engine: *v.em.Engine, receiver: c.JSValue, _: *sync.Arguments, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, iteratorBody, .{ roots[0], receiver });
}
