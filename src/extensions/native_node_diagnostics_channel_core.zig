// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete diagnostics_channel Channel/ActiveChannel and public registry core.
//! One canonical weak registry per Engine. TracingChannel and public module
//! admission remain separate work; this owner publishes no partial namespace.
//! Actual process/uncaught-error/util bindings are mandatory explicit inputs.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const functions = @import("native_node_module_callable.zig");
const classes = @import("native_node_error_class.zig");
const collections = @import("native_node_fs_collections.zig");
const weak_maps = @import("native_node_weak_ref_map.zig");
const errors = @import("native_node_argument_errors.zig");
const publication = @import("native_node_fs_private_publication.zig");
const Iterator = @import("native_public_values.zig").Iterator;
const caught = @import("native_agent_af_values.zig").caught;
const key = "pi-native:private/diagnostics-channel-core";
const Assembly = struct { engine: *a.v.em.Engine, previous: ?*const Assembly };
threadlocal var assembling: ?*const Assembly = null;

pub const Inputs = struct {
    process: c.JSValue,
    trigger_uncaught_exception: c.JSValue,
    weak_reference: c.JSValue,
};

fn callField(s: *a.Scope, receiver: c.JSValue, name: [*:0]const u8,
    args: []const c.JSValue) !c.JSValue
{
    const method = try s.get(receiver, name);
    return a.duplicate(s.engine, try s.call(method, receiver, args));
}
fn discardField(s: *a.Scope, receiver: c.JSValue, name: [*:0]const u8,
    args: []const c.JSValue) !c.JSValue
{
    _ = try s.call(try s.get(receiver, name), receiver, args);
    return c.pi_js_undefined();
}
fn assign(s: *a.Scope, receiver: c.JSValue, name: [*:0]const u8,
    value: c.JSValue) !c.JSValue
{
    try s.put(receiver, name, value);
    return c.pi_js_undefined();
}
fn prototypeChange(s: *a.Scope, state: c.JSValue, receiver: c.JSValue,
    name: [*:0]const u8) !c.JSValue
{
    _ = try s.call(try s.get(state, "setPrototypeOf"), c.pi_js_undefined(),
        &.{receiver, try s.get(try s.get(state, name), "prototype")});
    return c.pi_js_undefined();
}
fn emptySubscribers(s: *a.Scope, receiver: c.JSValue) !c.JSValue {
    try s.put(receiver, "_subscribers", try a.array(s));
    return c.pi_js_undefined();
}
fn emptyStores(s: *a.Scope, state: c.JSValue, receiver: c.JSValue) !c.JSValue {
    try s.put(receiver, "_stores", try s.construct(try s.get(state, "SafeMap"), &.{}));
    return c.pi_js_undefined();
}
fn markActive(engine: *a.v.em.Engine, state: c.JSValue, receiver: c.JSValue) !void {
    _ = try a.expression(engine, prototypeChange, .{state, receiver, @as([*:0]const u8, "ActiveChannel")});
    _ = try a.expression(engine, emptySubscribers, .{receiver});
    _ = try a.expression(engine, emptyStores, .{state, receiver});
}
fn nonemptyField(s: *a.Scope, receiver: c.JSValue, field: [*:0]const u8,
    property: [*:0]const u8) !c.JSValue
{
    return a.boolean(s, s.truthy(try s.get(try s.get(receiver, field), property)));
}
fn maybeMarkInactive(engine: *a.v.em.Engine, state: c.JSValue, receiver: c.JSValue) !void {
    if (try a.condition(engine, nonemptyField,
        .{receiver, @as([*:0]const u8, "_subscribers"), @as([*:0]const u8, "length")})) return;
    if (try a.condition(engine, nonemptyField,
        .{receiver, @as([*:0]const u8, "_stores"), @as([*:0]const u8, "size")})) return;
    _ = try a.expression(engine, prototypeChange, .{state, receiver, @as([*:0]const u8, "Channel")});
    _ = try a.expression(engine, assign, .{receiver, @as([*:0]const u8, "_subscribers"), c.pi_js_undefined()});
    _ = try a.expression(engine, assign, .{receiver, @as([*:0]const u8, "_stores"), c.pi_js_undefined()});
}
fn registryRef(s: *a.Scope, state: c.JSValue, receiver: c.JSValue,
    name: [*:0]const u8) !c.JSValue
{
    const registry = try s.get(state, "channels");
    const method = try s.get(registry, name);
    _ = try s.call(method, registry, &.{try s.get(receiver, "name")});
    return c.pi_js_undefined();
}

fn defaultTransform(engine: *a.v.em.Engine, _: c.JSValue,
    args: []const c.JSValue, _: []const c.JSValue) !c.JSValue
{
    try engine.checkNativeEntry();
    return a.duplicate(engine, a.arg(args, 0));
}
fn lateError(engine: *a.v.em.Engine, _: c.JSValue,
    _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, lateErrorBody, .{roots[0], roots[1]});
}
fn lateErrorBody(s: *a.Scope, trigger: c.JSValue, reason: c.JSValue) !c.JSValue {
    // The actual native binding is called, with original false origin flag.
    // No JS_Throw, replacement Error or private pending-error island is used.
    _ = try s.call(trigger, c.pi_js_undefined(), &.{reason, a.boolean(s, false)});
    return c.pi_js_undefined();
}
fn scheduleError(s: *a.Scope, state: c.JSValue, reason: c.JSValue) !c.JSValue {
    const process = try s.get(state, "process");
    const next_tick = try s.get(process, "nextTick");
    const trigger = try s.get(state, "trigger_uncaught_exception");
    const callback = try s.own(try functions.create(s.engine, "", 0, false,
        lateError, &.{trigger, reason}));
    _ = try s.call(next_tick, process, &.{callback});
    return c.pi_js_undefined();
}

fn validateSubscription(s: *a.Scope, state: c.JSValue, subscription: c.JSValue) !c.JSValue {
    _ = try s.call(try s.get(state, "validateFunction"), c.pi_js_undefined(),
        &.{subscription, try s.text("subscription")});
    return c.pi_js_undefined();
}
fn subscriberCopy(s: *a.Scope, state: c.JSValue, receiver: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(state, "slice"),
        try s.get(receiver, "_subscribers"), &.{}));
}
fn copySubscribers(s: *a.Scope, state: c.JSValue, receiver: c.JSValue) !c.JSValue {
    // The nested call's callee/argument temporaries retire before the outer
    // assignment can invoke a receiver setter.
    const value = try s.own(try a.expression(s.engine, subscriberCopy, .{state, receiver}));
    try s.put(receiver, "_subscribers", value);
    return c.pi_js_undefined();
}
fn pushSubscriber(s: *a.Scope, state: c.JSValue, receiver: c.JSValue,
    subscription: c.JSValue) !c.JSValue
{
    _ = try s.call(try s.get(state, "push"),
        try s.get(receiver, "_subscribers"), &.{subscription});
    return c.pi_js_undefined();
}
fn activeSubscribe(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    _ = try a.expression(engine, validateSubscription, .{roots[0], a.arg(args, 0)});
    _ = try a.expression(engine, copySubscribers, .{roots[0], receiver});
    _ = try a.expression(engine, pushSubscriber, .{roots[0], receiver, a.arg(args, 0)});
    _ = try a.expression(engine, registryRef, .{roots[0], receiver, @as([*:0]const u8, "incRef")});
    return c.pi_js_undefined();
}
fn subscriberIndex(s: *a.Scope, state: c.JSValue, receiver: c.JSValue,
    subscription: c.JSValue) !c.JSValue
{
    return a.duplicate(s.engine, try s.call(try s.get(state, "indexOf"),
        try s.get(receiver, "_subscribers"), &.{subscription}));
}
fn subscriberSlice(s: *a.Scope, state: c.JSValue, receiver: c.JSValue,
    index: c.JSValue, comptime after: bool) !c.JSValue
{
    const slice = try s.get(state, "slice");
    const subscribers = try s.get(receiver, "_subscribers");
    return a.duplicate(s.engine, if (after)
        try s.call(slice, subscribers, &.{try a.add(s, index, c.JS_NewInt32(s.engine.context, 1))})
    else
        try s.call(slice, subscribers, &.{c.JS_NewInt32(s.engine.context, 0), index}));
}
fn pushAfter(s: *a.Scope, state: c.JSValue, receiver: c.JSValue,
    after: c.JSValue) !c.JSValue
{
    // Primordial ArrayPrototypePushApply is the captured ReflectApply over the
    // captured push and the actual array-like after value, never JS spread.
    const target = try s.get(receiver, "_subscribers");
    _ = try s.call(try s.get(state, "apply"), c.pi_js_undefined(),
        &.{try s.get(state, "push"), target, after});
    return c.pi_js_undefined();
}
fn activeUnsubscribe(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, activeUnsubscribeBody, .{roots[0], receiver, a.arg(args, 0)});
}
fn activeUnsubscribeBody(s: *a.Scope, state: c.JSValue, receiver: c.JSValue,
    subscription: c.JSValue) !c.JSValue
{
    const index = try s.own(try a.expression(s.engine, subscriberIndex, .{state, receiver, subscription}));
    if (s.equal(index, c.JS_NewInt32(s.engine.context, -1))) return a.boolean(s, false);
    const before = try s.own(try a.expression(s.engine, subscriberSlice, .{state, receiver, index, false}));
    const after = try s.own(try a.expression(s.engine, subscriberSlice, .{state, receiver, index, true}));
    _ = try a.expression(s.engine, assign, .{receiver, @as([*:0]const u8, "_subscribers"), before});
    _ = try a.expression(s.engine, pushAfter, .{state, receiver, after});
    _ = try a.expression(s.engine, registryRef, .{state, receiver, @as([*:0]const u8, "decRef")});
    try maybeMarkInactive(s.engine, state, receiver);
    return a.boolean(s, true);
}
fn storeOperation(s: *a.Scope, receiver: c.JSValue, method: [*:0]const u8,
    args: []const c.JSValue) !c.JSValue
{
    return callField(s, try s.get(receiver, "_stores"), method, args);
}
fn discardStoreOperation(s: *a.Scope, receiver: c.JSValue, method: [*:0]const u8,
    args: []const c.JSValue) !c.JSValue
{
    return discardField(s, try s.get(receiver, "_stores"), method, args);
}
fn activeBind(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, activeBindBody, .{roots[0], receiver, a.arg(args, 0), a.arg(args, 1)});
}
fn activeBindBody(s: *a.Scope, state: c.JSValue, receiver: c.JSValue,
    store: c.JSValue, transform: c.JSValue) !c.JSValue
{
    // Keep the original replacing binding, including a possible object from
    // a live custom has method, until this method's lexical scope ends.
    const replacing = try s.own(try a.expression(s.engine, storeOperation,
        .{receiver, @as([*:0]const u8, "has"), @as([]const c.JSValue, &.{store})}));
    if (!s.truthy(replacing))
        _ = try a.expression(s.engine, registryRef, .{state, receiver, @as([*:0]const u8, "incRef")});
    _ = try a.expression(s.engine, discardStoreOperation,
        .{receiver, @as([*:0]const u8, "set"), @as([]const c.JSValue, &.{store, transform})});
    return c.pi_js_undefined();
}
fn storeHas(s: *a.Scope, receiver: c.JSValue, store: c.JSValue) !c.JSValue {
    const stores = try s.get(receiver, "_stores");
    return a.boolean(s, s.truthy(try s.call(try s.get(stores, "has"), stores, &.{store})));
}
fn activeUnbind(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    if (!try a.condition(engine, storeHas, .{receiver, a.arg(args, 0)}))
        return c.JS_NewBool(engine.context, false);
    _ = try a.expression(engine, discardStoreOperation,
        .{receiver, @as([*:0]const u8, "delete"), @as([]const c.JSValue, &.{a.arg(args, 0)})});
    _ = try a.expression(engine, registryRef, .{roots[0], receiver, @as([*:0]const u8, "decRef")});
    try maybeMarkInactive(engine, roots[0], receiver);
    return c.JS_NewBool(engine.context, true);
}
fn activeHas(engine: *a.v.em.Engine, _: c.JSValue,
    _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
{
    try engine.checkNativeEntry();
    return c.JS_NewBool(engine.context, true);
}
fn publishCondition(s: *a.Scope, subscribers: c.JSValue, index: f64) !c.JSValue {
    const length = if (c.JS_IsNull(subscribers) or c.JS_IsUndefined(subscribers))
        c.pi_js_undefined() else try s.get(subscribers, "length");
    const right = if (s.truthy(length)) length else c.JS_NewInt32(s.engine.context, 0);
    return a.boolean(s, s.truthy(try s.binary(4, c.JS_NewFloat64(s.engine.context, index), right)));
}
const PublishFrame = a.frames.Frame(enum { subscribers, on_message, reason });
fn messageAt(s: *a.Scope, subscribers: c.JSValue, index: f64) !c.JSValue {
    return a.duplicate(s.engine, try s.getKey(subscribers, c.JS_NewFloat64(s.engine.context, index)));
}
fn callMessage(s: *a.Scope, receiver: c.JSValue, on_message: c.JSValue,
    data: c.JSValue) !c.JSValue
{
    _ = try s.call(on_message, c.pi_js_undefined(), &.{data, try s.get(receiver, "name")});
    return c.pi_js_undefined();
}
fn publishOne(engine: *a.v.em.Engine, frame: *PublishFrame, receiver: c.JSValue,
    data: c.JSValue, index: f64) !void
{
    // The old local survives the preceding loop condition. Entering the next
    // try block resets it before the indexed Get, exactly OP_enter_scope.
    try frame.clear(.on_message);
    try frame.take(.on_message, a.expression(engine, messageAt, .{frame.get(.subscribers), index}));
    _ = try a.expression(engine, callMessage, .{receiver, frame.get(.on_message), data});
}
fn activePublish(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    var s = a.Scope.init(engine);
    const frame = PublishFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, activePublishBody(&s, frame, roots[0], receiver, a.arg(args, 0)));
}
fn activePublishBody(s: *a.Scope, frame: *PublishFrame, state: c.JSValue,
    receiver: c.JSValue, data: c.JSValue) !c.JSValue
{
    try frame.take(.subscribers, a.field(s.engine, receiver, "_subscribers"));
    var index: f64 = 0;
    var steps: usize = 0;
    while (try a.condition(s.engine, publishCondition, .{frame.get(.subscribers), index})) : (index += 1) {
        try @import("native_public_values.zig").poll(s.engine, &steps);
        publishOne(s.engine, frame, receiver, data, index) catch |err| {
            // The source catch local survives close_scope after its callback
            // captures it, including a nextTick override that drops the callback.
            try frame.take(.reason, caught(s.engine, err));
            _ = try a.expression(s.engine, scheduleError, .{state, frame.get(.reason)});
            continue;
        };
    }
    return c.pi_js_undefined();
}

fn rest(s: *a.Scope, args: []const c.JSValue) !c.JSValue {
    const values = if (args.len > 3) args[3..] else &.{};
    const generation = try s.beforeAllocation();
    return a.duplicate(s.engine, try s.checkedAllocation(
        c.JS_PiCreateRestArray(s.engine.context, @intCast(values.len), @constCast(values.ptr)), generation));
}
fn runBase(engine: *a.v.em.Engine, _: c.JSValue,
    _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    _ = try a.expression(engine, discardField,
        .{roots[1], @as([*:0]const u8, "publish"), @as([]const c.JSValue, &.{roots[2]})});
    return a.expression(engine, applyRest, .{roots[0], roots[3], roots[4], roots[5]});
}
fn applyRest(s: *a.Scope, state: c.JSValue, function: c.JSValue,
    receiver: c.JSValue, args: c.JSValue) !c.JSValue
{
    return a.duplicate(s.engine, try s.call(try s.get(state, "apply"),
        c.pi_js_undefined(), &.{function, receiver, args}));
}
fn wrappedStore(engine: *a.v.em.Engine, _: c.JSValue,
    _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, wrappedStoreBody, .{roots});
}
fn wrappedStoreBody(s: *a.Scope, roots: []const c.JSValue) !c.JSValue {
    const context = try s.own(a.call(s.engine, roots[4], c.pi_js_undefined(), &.{roots[2]}) catch |err| {
        const reason = try s.own(try caught(s.engine, err));
        _ = try a.expression(s.engine, scheduleError, .{roots[0], reason});
        return a.call(s.engine, roots[3], c.pi_js_undefined(), &.{});
    });
    return a.expression(s.engine, callField,
        .{roots[1], @as([*:0]const u8, "run"), @as([]const c.JSValue, &.{context, roots[3]})});
}
const RunFrame = a.frames.Frame(enum { args, run, entry, store, transform });
fn wrapStore(s: *a.Scope, state: c.JSValue, store: c.JSValue,
    data: c.JSValue, next: c.JSValue, supplied: c.JSValue) !c.JSValue
{
    const transform = if (c.JS_IsUndefined(supplied)) try s.get(state, "defaultTransform") else supplied;
    return functions.create(s.engine, "", 0, false, wrappedStore,
        &.{state, store, data, next, transform});
}
fn storeEntries(s: *a.Scope, receiver: c.JSValue) !c.JSValue {
    return callField(s, try s.get(receiver, "_stores"), "entries", &.{});
}
fn wrapEntries(engine: *a.v.em.Engine, state: c.JSValue, frame: *RunFrame,
    data: c.JSValue, iterator: *Iterator) !void
{
    while (try iterator.next()) |entry| {
        try frame.take(.entry, entry);
        // Block-local slots reset on the next body entry, not after a prior
        // body or before iterator.next. Retain successful store Get through
        // a failing transform Get and the resulting IteratorClose.
        try frame.clear(.store);
        try frame.clear(.transform);
        try frame.take(.store, a.field(engine, frame.get(.entry), "0"));
        try frame.take(.transform, a.field(engine, frame.get(.entry), "1"));
        try frame.take(.run, a.expression(engine, wrapStore,
            .{state, frame.get(.store), data, frame.get(.run), frame.get(.transform)}));
    }
}
fn activeRun(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    var s = a.Scope.init(engine);
    const frame = RunFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, activeRunBody(&s, frame, roots[0], receiver, args));
}
fn activeRunBody(s: *a.Scope, frame: *RunFrame, state: c.JSValue,
    receiver: c.JSValue, args: []const c.JSValue) !c.JSValue
{
    try frame.take(.args, a.expression(s.engine, rest, .{args}));
    try frame.take(.run, functions.create(s.engine, "run", 0, false, runBase,
        &.{state, receiver, a.arg(args, 0), a.arg(args, 1), a.arg(args, 2), frame.get(.args)}));
    var iterator = try Iterator.initOwned(s.engine, try a.expression(s.engine, storeEntries, .{receiver}));
    try iterator.finish(wrapEntries(s.engine, state, frame, a.arg(args, 0), &iterator));
    return a.call(s.engine, frame.get(.run), c.pi_js_undefined(), &.{});
}

fn inactiveSubscribe(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    try markActive(engine, roots[0], receiver);
    _ = try a.expression(engine, discardField,
        .{receiver, @as([*:0]const u8, "subscribe"), @as([]const c.JSValue, &.{a.arg(args, 0)})});
    return c.pi_js_undefined();
}
fn inactiveBind(engine: *a.v.em.Engine, receiver: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    try markActive(engine, roots[0], receiver);
    _ = try a.expression(engine, discardField,
        .{receiver, @as([*:0]const u8, "bindStore"), @as([]const c.JSValue, &.{a.arg(args, 0), a.arg(args, 1)})});
    return c.pi_js_undefined();
}
fn inactiveFalse(engine: *a.v.em.Engine, _: c.JSValue,
    _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
{
    try engine.checkNativeEntry();
    return c.JS_NewBool(engine.context, false);
}
fn inactivePublish(engine: *a.v.em.Engine, _: c.JSValue,
    _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
{
    // This no-op is the actual original inactive Channel.publish declaration.
    try engine.checkNativeEntry();
    return c.pi_js_undefined();
}
fn inactiveRun(engine: *a.v.em.Engine, _: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, inactiveRunBody, .{roots[0], args});
}
fn inactiveRunBody(s: *a.Scope, state: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const rest_args = try s.own(try a.expression(s.engine, rest, .{args}));
    return a.expression(s.engine, applyRest, .{state, a.arg(args, 1), a.arg(args, 2), rest_args});
}
fn baseObject(s: *a.Scope, target: c.JSValue) !c.JSValue {
    try s.pending();
    const prototype = try s.checked(c.JS_PiGetObjectPrototypeFromConstructor(s.engine.context, target));
    return a.duplicate(s.engine, try s.objectProto(prototype));
}
fn activeConstruct(engine: *a.v.em.Engine, _: c.JSValue, target: c.JSValue,
    _: []const c.JSValue, _: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, baseObject, .{target});
}
fn channelConstruct(engine: *a.v.em.Engine, _: c.JSValue, target: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, channelConstructBody, .{target, a.arg(args, 0), roots[0]});
}
fn channelConstructBody(s: *a.Scope, target: c.JSValue, name: c.JSValue,
    state: c.JSValue) !c.JSValue
{
    const receiver = try s.own(try a.expression(s.engine, baseObject, .{target}));
    _ = try a.expression(s.engine, assign, .{receiver, @as([*:0]const u8, "_subscribers"), c.pi_js_undefined()});
    _ = try a.expression(s.engine, assign, .{receiver, @as([*:0]const u8, "_stores"), c.pi_js_undefined()});
    _ = try a.expression(s.engine, assign, .{receiver, @as([*:0]const u8, "name"), name});
    _ = try a.expression(s.engine, registerChannel, .{state, name, receiver});
    return a.duplicate(s.engine, receiver);
}
fn registerChannel(s: *a.Scope, state: c.JSValue, name: c.JSValue,
    receiver: c.JSValue) !c.JSValue
{
    return discardField(s, try s.get(state, "channels"), "set", &.{name, receiver});
}
fn hasInstance(engine: *a.v.em.Engine, _: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, hasInstanceBody, .{roots[0], a.arg(args, 0)});
}
fn hasInstanceBody(s: *a.Scope, state: c.JSValue, instance: c.JSValue) !c.JSValue {
    const prototype = try s.own(try a.call(s.engine, try s.get(state, "getPrototypeOf"),
        c.pi_js_undefined(), &.{instance}));
    if (s.equal(prototype, try s.get(try s.get(state, "Channel"), "prototype"))) return a.boolean(s, true);
    return a.boolean(s, s.equal(prototype, try s.get(try s.get(state, "ActiveChannel"), "prototype")));
}
fn registryGet(s: *a.Scope, state: c.JSValue, name: c.JSValue) !c.JSValue {
    return callField(s, try s.get(state, "channels"), "get", &.{name});
}
fn publicChannel(engine: *a.v.em.Engine, _: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, channelBody, .{roots[0], a.arg(args, 0)});
}
fn channelBody(s: *a.Scope, state: c.JSValue, name: c.JSValue) !c.JSValue {
    const channel = try s.own(try a.expression(s.engine, registryGet, .{state, name}));
    if (s.truthy(channel)) return a.duplicate(s.engine, channel);
    if (!c.JS_IsString(name) and !c.JS_IsSymbol(name)) {
        const expected = try a.array(s);
        try a.index(s, expected, 0, try s.text("string"));
        try a.index(s, expected, 1, try s.text("symbol"));
        return a.raise(s, try s.construct(try s.get(state, "ERR_INVALID_ARG_TYPE"),
            &.{try s.text("channel"), expected, name}));
    }
    return a.duplicate(s.engine, try s.construct(try s.get(state, "Channel"), &.{name}));
}
fn publicSubscribe(engine: *a.v.em.Engine, _: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, forwardPublic, .{roots[0], args, @as([*:0]const u8, "subscribe")});
}
fn publicUnsubscribe(engine: *a.v.em.Engine, _: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, forwardPublic, .{roots[0], args, @as([*:0]const u8, "unsubscribe")});
}
fn forwardPublic(s: *a.Scope, state: c.JSValue, args: []const c.JSValue,
    method: [*:0]const u8) !c.JSValue
{
    const channel = try s.own(try a.expression(s.engine, channelBody, .{state, a.arg(args, 0)}));
    return callField(s, channel, method, &.{a.arg(args, 1)});
}
fn publicHas(engine: *a.v.em.Engine, _: c.JSValue,
    args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, publicHasBody, .{roots[0], a.arg(args, 0)});
}
fn publicHasBody(s: *a.Scope, state: c.JSValue, name: c.JSValue) !c.JSValue {
    const channel = try s.own(try a.expression(s.engine, registryGet, .{state, name}));
    if (!s.truthy(channel)) return a.boolean(s, false);
    return a.duplicate(s.engine, try s.get(channel, "hasSubscribers"));
}

fn getter(s: *a.Scope, target: c.JSValue, callback: functions.Callback) !void {
    const function = try s.own(try functions.create(s.engine, "get hasSubscribers", 0, false, callback, &.{}));
    const generation = try s.beforeAllocation();
    const atom = c.JS_NewAtom(s.engine.context, "hasSubscribers");
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try s.boundary.checkPendingSince(generation);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    try s.pending();
    const status = c.JS_DefinePropertyGetSet(s.engine.context, target, atom,
        a.duplicate(s.engine, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualChannelGetterReason;
}
fn symbolMethod(s: *a.Scope, target: c.JSValue, symbol: c.JSValue,
    method: c.JSValue) !void
{
    try s.pending();
    const atom = c.JS_ValueToAtom(s.engine.context, symbol);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    if (atom == c.JS_ATOM_NULL) return error.MissingActualChannelSymbolReason;
    const status = c.JS_DefinePropertyValue(s.engine.context, target, atom,
        a.duplicate(s.engine, method), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE | c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualChannelSymbolDefinitionReason;
}
fn defineMethods(s: *a.Scope, state: c.JSValue, prototype: c.JSValue,
    comptime active: bool) !void
{
    inline for (.{
        .{"subscribe", 1, if (active) activeSubscribe else inactiveSubscribe},
        .{"unsubscribe", if (active) 1 else 0, if (active) activeUnsubscribe else inactiveFalse},
        .{"bindStore", 2, if (active) activeBind else inactiveBind},
        .{"unbindStore", if (active) 1 else 0, if (active) activeUnbind else inactiveFalse},
    }) |definition| {
        const method = try s.own(try functions.create(s.engine, definition[0], definition[1],
            false, definition[2], &.{state}));
        try s.define(prototype, definition[0], method, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    }
    try getter(s, prototype, if (active) activeHas else inactiveFalse);
    inline for (.{
        .{"publish", if (active) 1 else 0, if (active) activePublish else inactivePublish},
        .{"runStores", 3, if (active) activeRun else inactiveRun},
    }) |definition| {
        const method = try s.own(try functions.create(s.engine, definition[0], definition[1],
            false, definition[2], &.{state}));
        try s.define(prototype, definition[0], method, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    }
}

pub fn acquire(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    var cursor = assembling;
    while (cursor) |entry| : (cursor = entry.previous)
        if (entry.engine == engine) return error.DiagnosticsChannelCoreReentry;
    const attempt: Assembly = .{ .engine = engine, .previous = assembling };
    assembling = &attempt;
    defer assembling = attempt.previous;
    const was_cached = engine.native_module_values.contains(key);
    const record = try a.expression(engine, createBody, .{inputs});
    if (!was_cached and engine.native_module_values.contains(key)) {
        var completion = a.owned.Completion.initValue(engine,
            @as(anyerror!c.JSValue, error.DiagnosticsChannelCorePublicationConflict));
        completion.release(record);
        return completion.finishValue();
    }
    const selected = if (was_cached) record else try publication.publish(engine, key, record);
    return a.expression(engine, exportsOwned, .{selected});
}
fn exportsOwned(s: *a.Scope, incoming: c.JSValue) !c.JSValue {
    const record = try s.own(incoming);
    return a.duplicate(s.engine, try s.get(record, "exports"));
}
fn createBody(s: *a.Scope, inputs: Inputs) !c.JSValue {
    if (s.engine.native_module_values.get(key)) |known| {
        inline for (std.meta.fields(Inputs)) |field| {
            if (!s.equal(try s.get(known, field.name), @field(inputs, field.name)))
                return error.DiagnosticsChannelCoreInputConflict;
        }
        return a.duplicate(s.engine, known);
    }
    if (!c.JS_IsObject(inputs.process) or
        !c.JS_IsFunction(s.engine.context, inputs.trigger_uncaught_exception) or
        !c.JS_IsFunction(s.engine.context, inputs.weak_reference))
        return error.ActualDiagnosticsChannelInputsRequired;
    const process_record = s.engine.native_module_values.get("node:process") orelse
        return error.ActualDiagnosticsChannelProcessRequired;
    if (!s.equal(try s.get(process_record, "default"), inputs.process))
        return error.ActualDiagnosticsChannelProcessIdentityRequired;
    if (!s.engine.native_module_values.contains("\x00native.fs.SafeMap") or
        !s.engine.native_module_values.contains("\x00native.internal.SafeFinalizationRegistry"))
        return error.BootstrappedDiagnosticsChannelSafeCollectionsRequired;
    const state = try s.objectProto(c.pi_js_null());
    inline for (std.meta.fields(Inputs)) |field|
        try s.put(state, field.name, @field(inputs, field.name));
    inline for (.{
        .{"slice", "Array.slice"}, .{"indexOf", "Array.indexOf"}, .{"push", "Array.push"},
        .{"getPrototypeOf", "Object.getPrototypeOf"}, .{"setPrototypeOf", "Object.setPrototypeOf"},
    }) |pair| {
        const primordial = try s.get(s.engine.intrinsic_clone_operations, pair[1]);
        if (!c.JS_IsFunction(s.engine.context, primordial)) return error.ActualDiagnosticsChannelPrimordialRequired;
        try s.put(state, pair[0], primordial);
    }
    const error_exports = (try errors.acquire(s.engine)) orelse return error.ActualInternalErrorsNotInitialized;
    defer error_exports.deinit(s.engine);
    try s.put(state, "ERR_INVALID_ARG_TYPE", error_exports.invalid_arg_type);
    try s.put(state, "validateFunction", try s.own(try errors.validateFunction(s.engine)));
    try s.put(state, "apply", try s.own(try errors.reflectApply(s.engine)));
    try s.put(state, "SafeMap", try s.own(try collections.acquireSafeMap(s.engine)));
    const weak_map = try s.own(try weak_maps.create(s.engine, .{ .weak_reference = inputs.weak_reference }));
    // Original class declarations precede the one channels = new WeakRefMap.
    const function_prototype = try s.checked(c.JS_GetFunctionProto(s.engine.context));
    const active_prototype = try s.object();
    const active_class = try s.own(try classes.create(s.engine, "ActiveChannel", 0,
        active_prototype, function_prototype, activeConstruct, &.{}));
    try s.put(state, "ActiveChannel", active_class);
    const prototype = try s.object();
    const channel_class = try s.own(try classes.create(s.engine, "Channel", 1,
        prototype, function_prototype, channelConstruct, &.{state}));
    try s.put(state, "Channel", channel_class);
    try defineMethods(s, state, active_prototype, true);
    try defineMethods(s, state, prototype, false);
    const has_instance = try s.get(s.engine.intrinsic_clone_operations, "Symbol.hasInstance");
    if (!c.JS_IsSymbol(has_instance)) return error.ActualDiagnosticsChannelHasInstanceRequired;
    try symbolMethod(s, channel_class, has_instance, try s.own(try functions.create(
        s.engine, "[Symbol.hasInstance]", 1, false, hasInstance, &.{state})));
    try s.put(state, "defaultTransform", try s.own(try functions.create(
        s.engine, "defaultTransform", 1, true, defaultTransform, &.{})));
    try s.put(state, "channels", try s.construct(weak_map, &.{}));
    const result = try s.object();
    try s.define(result, "Channel", channel_class, c.JS_PROP_C_W_E);
    inline for (.{
        .{"channel", 1, publicChannel}, .{"hasSubscribers", 1, publicHas},
        .{"subscribe", 2, publicSubscribe}, .{"unsubscribe", 2, publicUnsubscribe},
    }) |definition| {
        const function = try s.own(try functions.create(s.engine, definition[0],
            definition[1], true, definition[2], &.{state}));
        try s.define(result, definition[0], function, c.JS_PROP_C_W_E);
    }
    try s.put(state, "exports", result);
    return a.duplicate(s.engine, state);
}
