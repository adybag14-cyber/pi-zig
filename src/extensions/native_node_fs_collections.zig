// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! The actual primordials makeSafe Map and Set subclasses.
//! Iterator probes retain Source call order and one shared captured next method.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
const functions = @import("native_node_module_callable.zig");
const classes = @import("native_node_fs_class.zig");
const publication = @import("native_node_fs_private_publication.zig");
const Collection = enum { map, set };
fn cacheKey(comptime collection: Collection) []const u8 {
    return if (collection == .map) "\x00native.fs.SafeMap" else "\x00native.fs.SafeSet";
}
fn constructCollection(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(constructCollectionBody(&s, target, args, roots[0]));
}
fn constructCollectionBody(s: *Scope, target: c.JSValue, args: []const c.JSValue, map: c.JSValue) !c.JSValue {
    try s.pending();
    return c.JS_DupValue(s.engine.context, try s.checked(c.JS_CallConstructor2(s.engine.context, map, target, @intCast(args.len), @constCast(args.ptr))));
}
fn freeze(s: *Scope, value: c.JSValue) !void {
    try s.pending();
    const status = c.JS_FreezeObject(s.engine.context, value);
    try s.pending();
    if (status < 0) return error.MissingActualFsCollectionFreezeReason;
}
fn setPrototype(s: *Scope, value: c.JSValue, prototype_value: c.JSValue) !void {
    try s.pending();
    const status = c.JS_SetPrototype(s.engine.context, value, prototype_value);
    try s.pending();
    if (status < 0) return error.MissingActualFsCollectionPrototypeReason;
}
fn define(s: *Scope, target: c.JSValue, atom: c.JSAtom, value: c.JSValue, flags: c_int) !void {
    try s.pending();
    const status = c.JS_DefinePropertyValue(s.engine.context, target, atom, c.JS_DupValue(s.engine.context, value), flags);
    try s.pending();
    if (status < 0) return error.MissingActualFsCollectionDefineReason;
}
fn iteratorConstruct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(iteratorConstructBody(&s, target, args, roots[0]));
}
fn iteratorConstructBody(s: *Scope, target: c.JSValue, args: []const c.JSValue, factory: c.JSValue) !c.JSValue {
    const prototype_value = try s.get(target, "prototype");
    const receiver = if (c.JS_IsObject(prototype_value)) try s.objectProto(prototype_value) else try s.object();
    const iterable = if (args.len == 0) c.pi_js_undefined() else args[0];
    const iterator = try s.call(factory, iterable, &.{});
    try s.put(receiver, "_iterator", iterator);
    return c.JS_DupValue(s.engine.context, receiver);
}
fn iteratorNext(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(iteratorNextBody(&s, receiver, roots[0]));
}
fn iteratorNextBody(s: *Scope, receiver: c.JSValue, next: c.JSValue) !c.JSValue {
    return c.JS_DupValue(s.engine.context, try s.call(next, try s.get(receiver, "_iterator"), &.{}));
}
fn iteratorSelf(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_DupValue(engine.context, receiver);
}
fn wrapIterator(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(wrapIteratorBody(&s, roots[0], receiver));
}
fn wrapIteratorBody(s: *Scope, constructor_value: c.JSValue, receiver: c.JSValue) !c.JSValue {
    return c.JS_DupValue(s.engine.context, try s.construct(constructor_value, &.{receiver}));
}
fn safeIterator(s: *Scope, factory: c.JSValue, next: c.JSValue, symbol: c.JSAtom) !c.JSValue {
    const prototype_value = try s.object();
    const constructor_value = try s.own(try classes.constructor(s.engine, "SafeIterator", 1, prototype_value, iteratorConstruct, &.{factory}));
    try s.define(prototype_value, "next", try s.own(try functions.create(s.engine, "next", 0, false, iteratorNext, &.{next})), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try define(s, prototype_value, symbol, try s.own(try functions.create(s.engine, "[Symbol.iterator]", 0, false, iteratorSelf, &.{})), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try setPrototype(s, prototype_value, c.pi_js_null());
    try freeze(s, prototype_value);
    try freeze(s, constructor_value);
    return constructor_value;
}
fn hasSymbol(s: *Scope, receiver: c.JSValue, symbol: c.JSAtom) !bool {
    if (!c.JS_IsObject(receiver)) {
        // The same VM's OP_in TypeError; primitive RHS is not boxed.
        const generation = try s.beforeAllocation();
        _ = try s.checkedAllocation(c.JS_ThrowTypeError(s.engine.context, "invalid 'in' operand"), generation);
        return error.ActualFsCollectionInDidNotThrow;
    }
    try s.pending();
    const status = c.JS_HasProperty(s.engine.context, receiver, symbol);
    try s.pending();
    if (status < 0) return error.MissingActualFsCollectionHasReason;
    return status != 0;
}
fn condition(engine: *v.em.Engine, operation: anytype, args: anytype) !bool {
    var s = Scope.init(engine);
    const result = @call(.auto, operation, .{&s} ++ args);
    const value = try s.finish(if (result) |yes| c.pi_js_bool(engine.context, @intFromBool(yes)) else |err| err);
    return c.JS_ToBool(engine.context, value) == 1;
}
fn prototypeHas(s: *Scope, unsafe: c.JSValue, symbol: c.JSAtom) !bool {
    return hasSymbol(s, try s.get(unsafe, "prototype"), symbol);
}
fn zeroLength(s: *Scope, function: c.JSValue) !bool {
    return s.equal(try s.get(function, "length"), c.JS_NewInt32(s.engine.context, 0));
}
fn iteratorProbe(s: *Scope, function: c.JSValue, dummy: c.JSValue, symbol: c.JSAtom) !bool {
    const result = try s.call(function, dummy, &.{});
    return hasSymbol(s, if (v.nullish(result)) try s.object() else result, symbol);
}
fn nextValue(engine: *v.em.Engine, function: c.JSValue, dummy: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(nextValueBody(&s, function, dummy));
}
fn nextValueBody(s: *Scope, function: c.JSValue, dummy: c.JSValue) !c.JSValue {
    // The first iterator method is called a SECOND time to capture .next.
    const iterator = try s.call(function, dummy, &.{});
    return c.JS_DupValue(s.engine.context, try s.get(iterator, "next"));
}
const IteratorState = struct { parent: *Scope, dummy: c.JSValue, next: ?c.JSValue = null };
fn copyProperty(engine: *v.em.Engine, from: c.JSValue, to: c.JSValue, atom: c.JSAtom, prototype_copy: bool, state: ?*IteratorState, symbol: c.JSAtom) !void {
    var s = Scope.init(engine);
    _ = try s.finish(copyPropertyBody(&s, from, to, atom, prototype_copy, state, symbol));
}
fn descriptorBody(s: *Scope, receiver: c.JSValue, prototype_lookup: bool, atom: c.JSAtom, output: *[3]c.JSValue, flags: *c_int) !bool {
    const source = if (prototype_lookup) try s.get(receiver, "prototype") else receiver;
    try s.pending();
    var item: c.JSPropertyDescriptor = undefined;
    const status = c.JS_GetOwnProperty(s.engine.context, &item, source, atom);
    if (status > 0) {
        // Adopt all three outputs before any post-operation check or destructor.
        output.* = .{ item.value, item.getter, item.setter };
        flags.* = item.flags;
    }
    try s.pending();
    if (status < 0) return error.MissingActualFsCollectionDescriptorReason;
    return status != 0;
}
fn descriptor(engine: *v.em.Engine, receiver: c.JSValue, prototype_lookup: bool, atom: c.JSAtom) !?c.JSPropertyDescriptor {
    var s = Scope.init(engine);
    var output = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined() };
    var flags: c_int = 0;
    var present = false;
    var failure: ?anyerror = null;
    if (descriptorBody(&s, receiver, prototype_lookup, atom, &output, &flags)) |yes| present = yes else |err| failure = err;
    // Source's unsafe.prototype argument retires before the next desc.value
    // condition. The descriptor's three returned owners survive that retirement.
    try s.boundary.finishMany(failure, &s.values, &output);
    return if (present) .{ .flags = flags, .value = output[0], .getter = output[1], .setter = output[2] } else null;
}
fn adoptDescriptor(s: *Scope, item: c.JSPropertyDescriptor) void {
    // Each property callback starts empty and consumes at most one descriptor.
    s.values.inline_values[0] = item.value;
    s.values.inline_values[1] = item.getter;
    s.values.inline_values[2] = item.setter;
    s.values.inline_count = 3;
}
fn copyPropertyBody(s: *Scope, from: c.JSValue, to: c.JSValue, atom: c.JSAtom, prototype_copy: bool, state: ?*IteratorState, symbol: c.JSAtom) !c.JSValue {
    if (try descriptor(s.engine, to, false, atom)) |present| {
        adoptDescriptor(s, present);
        return c.pi_js_undefined();
    }
    const item = try descriptor(s.engine, from, prototype_copy, atom) orelse return c.pi_js_undefined();
    adoptDescriptor(s, item);
    try s.pending();
    var value = item.value;
    if (state) |iterators| {
        if (c.JS_IsFunction(s.engine.context, value) and
            try condition(s.engine, zeroLength, .{value}) and
            try condition(s.engine, iteratorProbe, .{ value, iterators.dummy, symbol }))
        {
            if (iterators.next == null)
                iterators.next = try iterators.parent.own(try nextValue(s.engine, value, iterators.dummy));
            const constructor_value = try safeIterator(s, value, iterators.next.?, symbol);
            value = try s.own(try functions.create(s.engine, "", 0, true, wrapIterator, &.{constructor_value}));
        }
    }
    const flags = item.flags | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_ENUMERABLE |
        (if (item.flags & c.JS_PROP_GETSET != 0) c.JS_PROP_HAS_GET | c.JS_PROP_HAS_SET else c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_WRITABLE);
    try s.pending();
    const defined = c.JS_DefineProperty(s.engine.context, to, atom, value, item.getter, item.setter, flags);
    try s.pending();
    if (defined < 0) return error.MissingActualFsCollectionDefineReason;
    return c.pi_js_undefined();
}
const Keys = struct { values: [*c]c.JSPropertyEnum = null, count: u32 = 0 };
fn keysBody(s: *Scope, from: c.JSValue, prototype_copy: bool, keys: *Keys) !c.JSValue {
    const source = if (prototype_copy) try s.get(from, "prototype") else from;
    try s.pending();
    const status = c.JS_GetOwnPropertyNames(s.engine.context, &keys.values, &keys.count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
    try s.pending();
    if (status < 0) return error.MissingActualFsCollectionKeysReason;
    return c.pi_js_undefined();
}
fn copy(s: *Scope, from: c.JSValue, to: c.JSValue, prototype_copy: bool, state: ?*IteratorState, symbol: c.JSAtom) !void {
    var keys: Keys = .{};
    defer c.JS_FreePropertyEnum(s.engine.context, keys.values, keys.count);
    {
        var getter = Scope.init(s.engine);
        _ = try getter.finish(keysBody(&getter, from, prototype_copy, &keys));
    }
    for (keys.values[0..keys.count]) |key| try copyProperty(s.engine, from, to, key.atom, prototype_copy, state, symbol);
}
fn acquireBody(s: *Scope, comptime collection: Collection) !c.JSValue {
    const cache_key = comptime cacheKey(collection);
    try s.pending();
    if (s.engine.native_module_values.get(cache_key)) |known| return c.JS_DupValue(s.engine.context, known);
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const map = try s.get(global, if (collection == .map) "Map" else "Set");
    const unsafe_prototype = try s.get(map, "prototype");
    const symbol_value = try s.get(try s.get(global, "Symbol"), "iterator");
    const symbol = try v.js.atom(s.engine, symbol_value);
    defer c.JS_FreeAtom(s.engine.context, symbol);
    try s.pending();
    const prototype_value = try s.objectProto(unsafe_prototype);
    const constructor_value = try s.own(try classes.constructor(s.engine, if (collection == .map) "SafeMap" else "SafeSet", 0, prototype_value, constructCollection, &.{map}));
    try setPrototype(s, constructor_value, map);
    if (try condition(s.engine, prototypeHas, .{ map, symbol })) {
        var state: IteratorState = .{ .parent = s, .dummy = try s.construct(map, &.{}) };
        try copy(s, map, prototype_value, true, &state, symbol);
    } else try copy(s, map, prototype_value, true, null, symbol);
    try copy(s, map, constructor_value, false, null, symbol);
    try setPrototype(s, prototype_value, c.pi_js_null());
    try freeze(s, prototype_value);
    try freeze(s, constructor_value);
    return c.JS_DupValue(s.engine.context, constructor_value);
}
fn acquire(engine: *v.em.Engine, comptime collection: Collection) !c.JSValue {
    const cache_key = comptime cacheKey(collection);
    var s = Scope.init(engine);
    const result = try s.finish(acquireBody(&s, collection));
    if (engine.native_module_values.get(cache_key)) |known| {
        // Construction may have reentered and completed the actual owner.
        // Select its identity before the losing candidate can retire.
        var completion = @import("native_sdk_owned_completion.zig").Completion.initValue(engine, c.JS_DupValue(engine.context, known));
        completion.release(result);
        return completion.finishValue();
    }
    return publication.publish(engine, cache_key, result);
}

pub fn acquireSafeMap(engine: *v.em.Engine) !c.JSValue { return acquire(engine, .map); }
pub fn acquireSafeSet(engine: *v.em.Engine) !c.JSValue { return acquire(engine, .set); }
