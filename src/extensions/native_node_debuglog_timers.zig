// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete original debugWithTimer over the shared initialized debuglog owner.
//! trace_events is a required original private binding input. This consumer
//! creates no trace registry, clock, enabled buffer, writer or public namespace.
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const sync = @import("native_sync_arguments.zig");
const ordinary = @import("native_node_debuglog.zig");
const collections = @import("native_node_fs_collections.zig");
const format_time = @import("native_node_debuglog_format_time.zig");
const time = @import("native_node_debuglog_time.zig");
const inspect_ops = @import("native_node_inspect_operations.zig");
const publication = @import("native_node_fs_private_publication.zig");
const c = a.c;
const Scope = a.Scope;
const key = "pi-native:private/original-debuglog-timers";
const Frame = a.frames.Frame(enum {
    log_impl, trace_category, trace_buffer, debug_enabled, flags, ensure,
    internal_start, internal_end, internal_log, init, start_timer, end_timer, log_timer,
});
const EmissionFrame = a.frames.Frame(enum { pid, colors, colored_pid });
const Root = enum(usize) { owner, set, callback, category, buffer, enabled, flags, log_impl, ensure, start, end, log, init };
const Kind = enum { start, end, log };
pub const Inputs = struct {
    /// The exact private exports produced by native_node_debuglog.acquire.
    debuglog_exports: c.JSValue,
    /// Actual bootstrap-captured internalBinding('trace_events'). Admission of
    /// that native binding and the process-wide tracing lifecycle is separate.
    /// Both named imports are captured once in original order; no replacement
    /// callback or manufactured Uint8Array is installed by this owner.
    trace_events: c.JSValue,
};
fn value(roots: []const c.JSValue, name: Root) c.JSValue { return roots[@intFromEnum(name)]; }
fn read(s: *Scope, roots: []const c.JSValue, name: Root) !c.JSValue {
    return if (name == .set or name == .callback) sync.read(&s.values, value(roots, name))
        else Frame.read(&s.values, value(roots, name));
}
fn intrinsic(s: *Scope, name: [*:0]const u8) !c.JSValue { return s.get(s.engine.intrinsic_clone_operations, name); }
fn shared(s: *Scope, owner: c.JSValue) !c.JSValue { return s.get(owner, "debugOwner"); }
fn processValue(s: *Scope, owner: c.JSValue) !c.JSValue { return s.get(try shared(s, owner), "process"); }
pub fn acquire(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, acquireBody, .{inputs});
}
fn acquireBody(s: *Scope, inputs: Inputs) anyerror!c.JSValue {
    const actual_debug = try s.own(try ordinary.requireSharedOwner(s.engine, inputs.debuglog_exports));
    if (!s.engine.native_module_values.contains("\x00native.fs.SafeMap"))
        return error.RequiredBootstrappedActualTimerSafeMap;
    const safe_map = try s.own(try collections.acquireSafeMap(s.engine));
    if (s.engine.native_module_values.get(key)) |known| {
        const owner = try s.own(a.duplicate(s.engine, known));
        if (!s.equal(try s.get(owner, "debugOwner"), actual_debug) or
            !s.equal(try s.get(owner, "traceBinding"), inputs.trace_events))
            return error.ActualDebuglogTimerInputIdentityChanged;
        return a.duplicate(s.engine, try s.get(owner, "exports"));
    }
    const candidate = try s.own(try a.expression(s.engine, createOwner, .{actual_debug, inputs.trace_events, safe_map}));
    const chosen = if (s.engine.native_module_values.get(key)) |known|
        try s.own(a.duplicate(s.engine, known))
    else try s.own(try publication.publish(s.engine, key, a.duplicate(s.engine, candidate)));
    if (!s.equal(try s.get(chosen, "debugOwner"), actual_debug) or
        !s.equal(try s.get(chosen, "traceBinding"), inputs.trace_events))
        return error.ActualDebuglogTimerInputIdentityChanged;
    return a.duplicate(s.engine, try s.get(chosen, "exports"));
}
fn createOwner(s: *Scope, debug_owner: c.JSValue, trace_binding: c.JSValue,
    safe_map: c.JSValue) anyerror!c.JSValue
{
    const owner = try s.objectProto(c.pi_js_null());
    try s.define(owner, "debugOwner", debug_owner, 0);
    try s.define(owner, "traceBinding", trace_binding, 0);
    // The original named import order is getCategoryEnabledBuffer then trace.
    try s.define(owner, "getCategoryEnabledBuffer", try s.get(trace_binding, "getCategoryEnabledBuffer"), 0);
    try s.define(owner, "trace", try s.get(trace_binding, "trace"), 0);
    try s.define(owner, "SafeMap", safe_map, 0);
    try s.define(owner, "tracesStores", c.pi_js_undefined(), c.JS_PROP_WRITABLE);
    const formatter = try s.own(try format_time.create(s.engine));
    const operations = try s.own(try time.create(s.engine, .{
        .process = try s.get(debug_owner, "process"),
        .trace = try s.get(owner, "trace"),
        .format_time = formatter,
    }));
    try s.define(owner, "operations", operations, 0);
    const factory = try s.own(try functions.createWithArguments(s.engine, "debugWithTimer", 2, true,
        .{ .formal_count = 2, .callback = factoryCallback, .hooks = sync.frameHooks(Frame) }, &.{owner}));
    const exports = try s.objectProto(c.pi_js_null());
    try s.define(exports, "kNone", c.JS_NewInt32(s.engine.context, 1), 0);
    try s.define(exports, "kSkipLog", c.JS_NewInt32(s.engine.context, 2), 0);
    try s.define(exports, "kSkipTrace", c.JS_NewInt32(s.engine.context, 4), 0);
    try s.define(exports, "formatTime", formatter, 0);
    inline for (.{ "time", "timeEnd", "timeLog" }) |name| try s.define(exports, name, try s.get(operations, name), 0);
    try s.define(exports, "debugWithTimer", factory, 0);
    try s.define(owner, "exports", exports, 0);
    return a.duplicate(s.engine, owner);
}
fn uppercase(s: *Scope, binding: c.JSValue) !c.JSValue {
    const method = try intrinsic(s, "String.toUpperCase");
    return a.duplicate(s.engine, try s.call(method, try sync.read(&s.values, binding), &.{}));
}
fn initializeStores(s: *Scope, owner: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(try s.get(owner, "tracesStores")))
        try s.put(owner, "tracesStores", try s.objectProto(c.pi_js_null()));
    return c.pi_js_undefined();
}
fn category(s: *Scope, set: c.JSValue) !c.JSValue {
    const lower = try s.call(try intrinsic(s, "String.toLowerCase"), set, &.{});
    return a.duplicate(s.engine, try a.add(s, try s.text("node,node."), try s.toString(lower)));
}
fn factoryCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, factoryBody, .{args, roots[0]});
}
fn factoryBody(s: *Scope, args: *sync.Arguments, owner: c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, Frame);
    const roots = [_]c.JSValue{
        owner, try args.capture(&s.values, 0), try args.capture(&s.values, 1),
        try frame.capture(&s.values, .trace_category, "traceCategory"),
        try frame.capture(&s.values, .trace_buffer, "traceCategoryBuffer"),
        try frame.capture(&s.values, .debug_enabled, "debugLogCategoryEnabled"),
        try frame.capture(&s.values, .flags, "timerFlags"),
        try frame.capture(&s.values, .log_impl, "logImpl"),
        try frame.capture(&s.values, .ensure, "ensureTimerFlagsAreUpdated"),
        try frame.capture(&s.values, .internal_start, "internalStartTimer"),
        try frame.capture(&s.values, .internal_end, "internalEndTimer"),
        try frame.capture(&s.values, .internal_log, "internalLogTimer"),
        try frame.capture(&s.values, .init, "init"),
    };
    // Hoisted original declarations capture the same Source cells before
    // executable set coercion. Later let/const slots retain their actual TDZ.
    try frame.take(.log_impl, functions.createWithArguments(s.engine, "logImpl", 3, true,
        .{ .formal_count = 3, .callback = emissionCallback, .hooks = sync.frameHooks(EmissionFrame) }, &roots));
    try frame.take(.ensure, functions.createWithArguments(s.engine, "ensureTimerFlagsAreUpdated", 0, true,
        .{ .formal_count = 0, .callback = ensureCallback }, &roots));
    try frame.take(.internal_start, functions.createWithArguments(s.engine, "internalStartTimer", 2, true,
        .{ .formal_count = 2, .callback = internalCallback(.start) }, &roots));
    try frame.take(.internal_end, functions.createWithArguments(s.engine, "internalEndTimer", 2, true,
        .{ .formal_count = 2, .callback = internalCallback(.end) }, &roots));
    try frame.take(.internal_log, functions.createWithArguments(s.engine, "internalLogTimer", 3, true,
        .{ .formal_count = 3, .callback = internalCallback(.log) }, &roots));
    try frame.take(.init, functions.createWithArguments(s.engine, "init", 0, true,
        .{ .formal_count = 0, .callback = initCallback }, &roots));
    try args.take(0, a.expression(s.engine, uppercase, .{value(&roots, .set)}));
    _ = try a.expression(s.engine, initializeStores, .{owner});
    try frame.take(.trace_category, a.expression(s.engine, category, .{args.get(0)}));
    try frame.clear(.trace_buffer);
    try frame.copy(.debug_enabled, a.boolean(s, false));
    try frame.copy(.flags, c.JS_NewInt32(s.engine.context, 1));
    try frame.take(.start_timer, functions.createWithArguments(s.engine, "startTimer", 2, false,
        .{ .formal_count = 2, .callback = outerCallback(.start) }, &roots));
    try frame.take(.end_timer, functions.createWithArguments(s.engine, "endTimer", 2, false,
        .{ .formal_count = 2, .callback = outerCallback(.end) }, &roots));
    try frame.take(.log_timer, functions.createWithArguments(s.engine, "logTimer", 3, false,
        .{ .formal_count = 3, .callback = outerCallback(.log) }, &roots));
    const result = try s.object();
    try s.define(result, "startTimer", frame.get(.start_timer), c.JS_PROP_C_W_E);
    try s.define(result, "endTimer", frame.get(.end_timer), c.JS_PROP_C_W_E);
    try s.define(result, "logTimer", frame.get(.log_timer), c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, result);
}
fn invokeEmpty(s: *Scope, binding: c.JSValue) !c.JSValue {
    _ = try s.call(try Frame.read(&s.values, binding), c.pi_js_undefined(), &.{});
    return c.pi_js_undefined();
}
fn flagsWith(s: *Scope, roots: []const c.JSValue, operation: i32, mask: i32) !c.JSValue {
    return a.duplicate(s.engine, try s.binary(operation, try read(s, roots, .flags), c.JS_NewInt32(s.engine.context, mask)));
}
fn bufferDisabled(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const buffer = try read(s, roots, .buffer);
    const state = try s.getKey(buffer, c.JS_NewInt32(s.engine.context, 0));
    return a.boolean(s, s.equal(state, c.JS_NewInt32(s.engine.context, 0)));
}
fn shouldSkip(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const masked = try s.binary(10, try read(s, roots, .flags), c.JS_NewInt32(s.engine.context, 6));
    return a.boolean(s, s.equal(masked, c.JS_NewInt32(s.engine.context, 6)));
}
fn ensureCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    try Frame.assign(value(roots, .flags), a.expression(engine, flagsWith, .{roots, @as(i32, 10), @as(i32, -5)}));
    if (try a.condition(engine, bufferDisabled, .{roots}))
        try Frame.assign(value(roots, .flags), a.expression(engine, flagsWith, .{roots, @as(i32, 11), @as(i32, 4)}));
    return c.pi_js_undefined();
}

fn storeAbsent(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const stores = try s.get(value(roots, .owner), "tracesStores");
    return a.boolean(s, c.JS_IsUndefined(try s.getKey(stores, try read(s, roots, .set))));
}
fn createStore(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const owner = value(roots, .owner);
    // Preserve the original computed assignment reference before its new RHS.
    const stores = try s.get(owner, "tracesStores");
    const set = try read(s, roots, .set);
    const constructor = try s.get(owner, "SafeMap");
    const map = try s.construct(constructor, &.{});
    try inspect_ops.setKey(&s.values, stores, set, map);
    return c.pi_js_undefined();
}
fn warnSet(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const owner = try shared(s, value(roots, .owner));
    const set = try read(s, roots, .set);
    return ordinary.emitSharedWarning(s.engine, owner, set);
}
fn testCategory(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const owner = try shared(s, value(roots, .owner));
    const predicate = try s.get(owner, "testEnabled");
    const set = try read(s, roots, .set);
    return a.duplicate(s.engine, try s.call(predicate, c.pi_js_undefined(), &.{set}));
}
fn categoryBuffer(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const function = try s.get(value(roots, .owner), "getCategoryEnabledBuffer");
    const label = try read(s, roots, .category);
    return a.duplicate(s.engine, try s.call(function, c.pi_js_undefined(), &.{label}));
}
fn initiallyActive(s: *Scope) !c.JSValue { return c.JS_NewInt32(s.engine.context, 1); }
fn loggingDisabled(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    return a.boolean(s, !s.truthy(try read(s, roots, .enabled)));
}
fn publishInternalFunctions(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    const callback = try read(s, roots, .callback);
    const start = try read(s, roots, .start);
    const end = try read(s, roots, .end);
    const log = try read(s, roots, .log);
    // Original cb is unconditional, including noncallable/undefined values.
    _ = try s.call(callback, c.pi_js_undefined(), &.{start, end, log});
    return c.pi_js_undefined();
}
fn initCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    if (try a.condition(engine, storeAbsent, .{roots}))
        _ = try a.expression(engine, createStore, .{roots});
    _ = try a.expression(engine, warnSet, .{roots});
    try Frame.assign(value(roots, .enabled), a.expression(engine, testCategory, .{roots}));
    try Frame.assign(value(roots, .buffer), a.expression(engine, categoryBuffer, .{roots}));
    try Frame.assign(value(roots, .flags), a.expression(engine, initiallyActive, .{}));
    if (try a.condition(engine, loggingDisabled, .{roots}))
        try Frame.assign(value(roots, .flags), a.expression(engine, flagsWith, .{roots, @as(i32, 11), @as(i32, 2)}));
    if (try a.condition(engine, bufferDisabled, .{roots}))
        try Frame.assign(value(roots, .flags), a.expression(engine, flagsWith, .{roots, @as(i32, 11), @as(i32, 4)}));
    _ = try a.expression(engine, publishInternalFunctions, .{roots});
    return c.pi_js_undefined();
}
fn callOperation(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue,
    comptime kind: Kind) !c.JSValue
{
    const owner = value(roots, .owner);
    const operations = try s.get(owner, "operations");
    const function = try s.get(operations, switch (kind) { .start => "time", .end => "timeEnd", .log => "timeLog" });
    const stores = try s.get(owner, "tracesStores");
    const store = try s.getKey(stores, try read(s, roots, .set));
    const trace_category = try read(s, roots, .category);
    const implementation = try s.text(switch (kind) {
        .start => "debuglog.time", .end => "debuglog.timeEnd", .log => "debuglog.timeLog",
    });
    const flags = try read(s, roots, .flags);
    if (kind == .start) {
        _ = try s.call(function, c.pi_js_undefined(),
            &.{store, trace_category, implementation, flags, args.get(0), args.get(1)});
    } else {
        const logger = try read(s, roots, .log_impl);
        if (kind == .end) {
            _ = try s.call(function, c.pi_js_undefined(),
                &.{store, trace_category, implementation, flags, logger, args.get(0), args.get(1)});
        } else {
            _ = try s.call(function, c.pi_js_undefined(),
                &.{store, trace_category, implementation, flags, logger, args.get(0), args.get(1), args.get(2)});
        }
    }
    return c.pi_js_undefined();
}
fn internalCallback(comptime kind: Kind) sync.Callback {
    return struct {
        fn callback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
            roots: []const c.JSValue) anyerror!c.JSValue
        {
            _ = try a.expression(engine, invokeEmpty, .{value(roots, .ensure)});
            if (try a.condition(engine, shouldSkip, .{roots})) return c.pi_js_undefined();
            _ = try a.expression(engine, callOperation, .{args, roots, kind});
            return c.pi_js_undefined();
        }
    }.callback;
}
fn callInternal(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue,
    comptime kind: Kind) !c.JSValue
{
    const function = try read(s, roots, switch (kind) { .start => .start, .end => .end, .log => .log });
    if (kind == .log) {
        _ = try s.call(function, c.pi_js_undefined(), &.{args.get(0), args.get(1), args.get(2)});
    } else {
        _ = try s.call(function, c.pi_js_undefined(), &.{args.get(0), args.get(1)});
    }
    return c.pi_js_undefined();
}
fn outerCallback(comptime kind: Kind) sync.Callback {
    return struct {
        fn callback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
            roots: []const c.JSValue) anyerror!c.JSValue
        {
            _ = try a.expression(engine, invokeEmpty, .{value(roots, .init)});
            if (!try a.condition(engine, shouldSkip, .{roots}))
                _ = try a.expression(engine, callInternal, .{args, roots, kind});
            return c.pi_js_undefined();
        }
    }.callback;
}
fn currentPID(s: *Scope, owner: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.get(try processValue(s, owner), "pid"));
}
fn emissionColors(s: *Scope, owner: c.JSValue) !c.JSValue {
    // Object literal allocation precedes its property value expression.
    const options = try s.object();
    const debug_owner = try shared(s, owner);
    const colors = try s.own(try ordinary.acquireSharedColors(s.engine, debug_owner));
    const should = try s.get(colors, "shouldColorize");
    const stderr = try s.get(try processValue(s, owner), "stderr");
    const selected = try s.call(should, colors, &.{stderr});
    try s.define(options, "colors", selected, c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, options);
}
fn inspectCurrentPID(s: *Scope, owner: c.JSValue, frame: *EmissionFrame) !c.JSValue {
    const function = try s.get(try shared(s, owner), "inspect");
    return a.duplicate(s.engine, try s.call(function, c.pi_js_undefined(),
        &.{frame.get(.pid), frame.get(.colors)}));
}
fn writeTimerMessage(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue,
    frame: *EmissionFrame) !c.JSValue
{
    const owner = value(roots, .owner);
    // This is the second live stderr read. Resolve write before format's RHS.
    const stderr = try s.get(try processValue(s, owner), "stderr");
    const write = try s.get(stderr, "write");
    const debug_owner = try shared(s, owner);
    const formatter = try s.get(debug_owner, "format");
    const format_text = try s.text("%s %s %s: %s\n");
    const set = try read(s, roots, .set);
    const prefix = [_]c.JSValue{format_text, set, frame.get(.colored_pid), args.get(0), args.get(1)};
    const message = if (c.JS_IsUndefined(args.get(2)))
        try s.call(formatter, c.pi_js_undefined(), &prefix)
    else try s.own(try ordinary.sharedSpreadCall(s.engine, formatter, &prefix,
        args.get(2), try s.get(debug_owner, "SafeArrayIterator")));
    _ = try s.call(write, stderr, &.{message});
    return c.pi_js_undefined();
}
fn emissionCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, emissionBody, .{args, roots});
}
fn emissionBody(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, EmissionFrame);
    const owner = value(roots, .owner);
    try frame.take(.pid, a.expression(s.engine, currentPID, .{owner}));
    try frame.take(.colors, a.expression(s.engine, emissionColors, .{owner}));
    try frame.take(.colored_pid, a.expression(s.engine, inspectCurrentPID, .{owner, frame}));
    _ = try a.expression(s.engine, writeTimerMessage, .{args, roots, frame});
    return c.pi_js_undefined();
}
