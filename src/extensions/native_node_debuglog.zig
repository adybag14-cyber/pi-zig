// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete initialized ordinary internal/util/debuglog producer.
//! The timer/trace-events exports are separate genuine dependencies; this
//! private producer does not publish an incomplete internal builtin namespace.
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const sync = @import("native_sync_arguments.zig");
const builtin_require = @import("native_node_internal_builtin_require.zig");
const inspect_binding = @import("native_node_internal_inspect_binding.zig");
const array_iterator = @import("native_node_safe_array_iterator.zig");
const inspect_ops = @import("native_node_inspect_operations.zig");
const publication = @import("native_node_fs_private_publication.zig");
const c = a.c;
const Scope = a.Scope;
const key = "pi-native:private/initialized-ordinary-debuglog";
const InitFrame = a.frames.Frame(enum { regex });
const LogFrame = a.frames.Frame(enum { init, debug, enabled, test, logger });
const ImplFrame = a.frames.Frame(enum { pid });
const RestFrame = a.frames.Frame(enum { args });
const EmissionFrame = a.frames.Frame(enum { args, colors, message, colored_pid });

pub const bindings = [_]builtin_require.Binding{
    .{ .id = "internal/util/colors", .module_name = "internal/util/colors" },
};
pub const Inputs = struct {
    /// Actual already-admitted private requireBuiltin. Its complete bootstrap
    /// owns module admission and evaluation timing, including lazy colors.
    require: c.JSValue,
};
fn intrinsic(s: *Scope, name: [*:0]const u8) anyerror!c.JSValue {
    return s.get(s.engine.intrinsic_clone_operations, name);
}
fn member(s: *Scope, owner: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
    return s.get(owner, name);
}
fn actualRequire(s: *Scope, supplied: c.JSValue) anyerror!c.JSValue {
    if (!s.engine.native_module_values.contains("pi-native:private/internal-builtin-require"))
        return error.RequiredBootstrappedActualDebuglogRequire;
    const expected = try s.own(try builtin_require.acquire(s.engine, .{ .bindings = &bindings }));
    if (!s.equal(expected, supplied)) return error.ActualDebuglogRequireIdentityChanged;
    return a.duplicate(s.engine, expected);
}
fn actualProcess(s: *Scope) anyerror!c.JSValue {
    const known = s.engine.native_module_values.get("node:process") orelse
        return error.RequiredActualDebuglogProcess;
    const record = try s.own(a.duplicate(s.engine, known));
    var descriptor = try s.descriptor(record, try s.text("default")) orelse
        return error.RequiredActualDebuglogProcessDefault;
    defer s.releaseDescriptor(&descriptor);
    if (descriptor.flags & c.JS_PROP_GETSET != 0 or !c.JS_IsObject(descriptor.value))
        return error.RequiredActualDebuglogProcessData;
    return a.duplicate(s.engine, descriptor.value);
}
/// A private construction record containing the actual initializeDebugEnv and
/// debuglog functions. Bootstrap calls initializeDebugEnv with the actual
/// initial process.env.NODE_DEBUG value at its original point. It is never
/// initialized implicitly and never polls a later environment as a default.
pub fn acquire(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, acquireBody, .{inputs});
}
fn acquireBody(s: *Scope, inputs: Inputs) anyerror!c.JSValue {
    try s.pending();
    const require_value = try s.own(try a.expression(s.engine, actualRequire, .{inputs.require}));
    if (s.engine.native_module_values.get(key)) |known| {
        const owner = try s.own(a.duplicate(s.engine, known));
        if (!s.equal(try member(s, owner, "require"), require_value))
            return error.ActualDebuglogRequireIdentityChanged;
        return a.duplicate(s.engine, try member(s, owner, "exports"));
    }
    const process = try s.own(try a.expression(s.engine, actualProcess, .{}));
    // The full actual inspector was captured by its genuine primordial
    // bootstrap. Cold consumer acquisition must not recapture guest globals.
    if (!s.engine.native_module_values.contains("pi-native:private/internal-inspect-binding"))
        return error.RequiredBootstrappedActualDebuglogInspector;
    const inspector = try s.own(try inspect_binding.acquire(s.engine));
    const safe_iterator = try s.own(try array_iterator.acquire(s.engine));
    const candidate = try s.own(try a.expression(s.engine, createOwner,
        .{process, require_value, inspector, safe_iterator}));
    const selected = if (s.engine.native_module_values.get(key)) |known|
        try s.own(a.duplicate(s.engine, known))
    else try s.own(try publication.publish(s.engine, key, a.duplicate(s.engine, candidate)));
    if (!s.equal(try member(s, selected, "require"), require_value))
        return error.ActualDebuglogRequireIdentityChanged;
    return a.duplicate(s.engine, try member(s, selected, "exports"));
}
fn createOwner(s: *Scope, process: c.JSValue, require_value: c.JSValue,
    inspector: c.JSValue, safe_iterator: c.JSValue) anyerror!c.JSValue
{
    const owner = try s.objectProto(c.pi_js_null());
    try s.define(owner, "process", process, 0);
    try s.define(owner, "require", require_value, 0);
    // Original named imports are captured once, in original order.
    inline for (.{ "inspect", "format", "formatWithOptions" }) |name|
        try s.define(owner, name, try s.get(inspector, name), 0);
    try s.define(owner, "SafeArrayIterator", safe_iterator, 0);
    try s.define(owner, "debugImpls", c.pi_js_undefined(), c.JS_PROP_WRITABLE);
    try s.define(owner, "testEnabled", c.pi_js_undefined(), c.JS_PROP_WRITABLE);
    const noop_value = try s.own(try functions.createWithArguments(s.engine, "noop", 0, false,
        .{ .formal_count = 0, .callback = noopCallback }, &.{}));
    try s.define(owner, "noop", noop_value, 0);
    try s.define(owner, "utilColors", c.pi_js_undefined(), c.JS_PROP_WRITABLE);
    const impl = try s.own(try functions.createWithArguments(s.engine, "debuglogImpl", 2, true,
        .{ .formal_count = 2, .callback = implCallback, .hooks = sync.frameHooks(ImplFrame) }, &.{owner}));
    try s.define(owner, "impl", impl, 0);
    const exports = try s.objectProto(c.pi_js_null());
    const initialize = try s.own(try functions.createWithArguments(s.engine, "initializeDebugEnv", 1, true,
        .{ .formal_count = 1, .callback = initializeCallback, .hooks = sync.frameHooks(InitFrame) }, &.{owner}));
    const factory = try s.own(try functions.createWithArguments(s.engine, "debuglog", 2, true,
        .{ .formal_count = 2, .callback = factoryCallback, .hooks = sync.frameHooks(LogFrame) }, &.{owner}));
    try s.define(exports, "initializeDebugEnv", initialize, 0);
    try s.define(exports, "debuglog", factory, 0);
    try s.define(owner, "exports", exports, 0);
    return a.duplicate(s.engine, owner);
}
fn noopCallback(_: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments,
    _: []const c.JSValue) anyerror!c.JSValue
{
    return c.pi_js_undefined();
}
fn falseCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments,
    _: []const c.JSValue) anyerror!c.JSValue
{
    return c.pi_js_bool(engine.context, 0);
}
fn emptyCache(s: *Scope, owner: c.JSValue) anyerror!c.JSValue {
    try s.put(owner, "debugImpls", try s.objectProto(c.pi_js_null()));
    return c.pi_js_undefined();
}
fn firstReplacement(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    const replace = try s.get(value, "replace");
    const pattern = try s.construct(s.engine.intrinsic_regexp_constructor,
        &.{ try s.text("[|\\\\{}()[\\]^$+?.]"), try s.text("g") });
    return a.duplicate(s.engine, try s.call(replace, value, &.{pattern, try s.text("\\$&")}));
}
fn secondReplacement(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    const first = try s.own(try a.expression(s.engine, firstReplacement, .{value}));
    const replace_all = try s.get(first, "replaceAll");
    return a.duplicate(s.engine, try s.call(replace_all, first, &.{try s.text("*"), try s.text(".*")}));
}
fn thirdReplacement(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    // Each preceding call/reference temporary retires before the next method
    // lookup; only the final chain value becomes the original formal.
    const second = try s.own(try a.expression(s.engine, secondReplacement, .{value}));
    const replace_all = try s.get(second, "replaceAll");
    return a.duplicate(s.engine, try s.call(replace_all, second, &.{try s.text(","), try s.text("$|^")}));
}
fn environmentRegex(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    const constructor = try intrinsic(s, "RegExp");
    const start = try s.text("^");
    const substitution = try s.toString(value);
    const prefix = try a.add(s, start, substitution);
    const pattern = try a.add(s, prefix, try s.text("$"));
    return a.duplicate(s.engine, try s.construct(constructor, &.{pattern, try s.text("i")}));
}
fn initializeCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, initializeBody, .{args, roots[0]});
}
fn initializeBody(s: *Scope, args: *sync.Arguments, owner: c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, InitFrame);
    _ = try a.expression(s.engine, emptyCache, .{owner});
    if (s.truthy(args.get(0))) {
        try args.take(0, a.expression(s.engine, thirdReplacement, .{args.get(0)}));
        try frame.take(.regex, a.expression(s.engine, environmentRegex, .{args.get(0)}));
        const binding = try frame.capture(&s.values, .regex, "debugEnvRegex");
        _ = try a.expression(s.engine, assignRegexTest, .{owner, binding});
    } else {
        _ = try a.expression(s.engine, assignFalseTest, .{owner});
    }
    return c.pi_js_undefined();
}
fn assignRegexTest(s: *Scope, owner: c.JSValue, binding: c.JSValue) anyerror!c.JSValue {
    const predicate = try s.own(try functions.createWithArguments(s.engine, "testEnabled", 1, false,
        .{ .formal_count = 1, .callback = regexTestCallback }, &.{binding}));
    try s.put(owner, "testEnabled", predicate);
    return c.pi_js_undefined();
}
fn assignFalseTest(s: *Scope, owner: c.JSValue) anyerror!c.JSValue {
    const predicate = try s.own(try functions.createWithArguments(s.engine, "testEnabled", 0, false,
        .{ .formal_count = 0, .callback = falseCallback }, &.{}));
    try s.put(owner, "testEnabled", predicate);
    return c.pi_js_undefined();
}
fn regexTestCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, regexTestBody, .{args, roots[0]});
}
fn regexTestBody(s: *Scope, args: *sync.Arguments, binding: c.JSValue) anyerror!c.JSValue {
    const method = try intrinsic(s, "RegExp.exec");
    const regex = try InitFrame.read(&s.values, binding);
    const result = try s.call(method, regex, &.{args.get(0)});
    return a.boolean(s, !c.JS_IsNull(result));
}
fn uppercaseSet(s: *Scope, binding: c.JSValue) anyerror!c.JSValue {
    const method = try intrinsic(s, "String.toUpperCase");
    const value = try sync.read(&s.values, binding);
    return a.duplicate(s.engine, try s.call(method, value, &.{}));
}
fn callEnabledTest(s: *Scope, owner: c.JSValue, set_binding: c.JSValue) anyerror!c.JSValue {
    const test = try member(s, owner, "testEnabled");
    const value = try sync.read(&s.values, set_binding);
    // Undefined is deliberately called before initializeDebugEnv. The actual
    // VM TypeError remains observable; no synthetic disabled state is supplied.
    return a.duplicate(s.engine, try s.call(test, c.pi_js_undefined(), &.{value}));
}
fn initCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    try sync.assign(engine, roots[1], a.expression(engine, uppercaseSet, .{roots[1]}));
    try LogFrame.assign(roots[2], a.expression(engine, callEnabledTest, .{roots[0], roots[1]}));
    return c.pi_js_undefined();
}
fn callInit(s: *Scope, init_binding: c.JSValue) anyerror!c.JSValue {
    const function = try LogFrame.read(&s.values, init_binding);
    _ = try s.call(function, c.pi_js_undefined(), &.{});
    return c.pi_js_undefined();
}
fn factoryCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, factoryBody, .{args, roots[0]});
}
fn factoryBody(s: *Scope, args: *sync.Arguments, owner: c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, LogFrame);
    const set_binding = try args.capture(&s.values, 0);
    const cb_binding = try args.capture(&s.values, 1);
    const init_binding = try frame.capture(&s.values, .init, "init");
    const debug_binding = try frame.capture(&s.values, .debug, "debug");
    const enabled_binding = try frame.capture(&s.values, .enabled, "enabled");
    const test_binding = try frame.capture(&s.values, .test, "test");
    try frame.take(.init, functions.createWithArguments(s.engine, "init", 0, true,
        .{ .formal_count = 0, .callback = initCallback }, &.{owner, set_binding, enabled_binding}));
    try frame.take(.debug, functions.createWithArguments(s.engine, "debug", 0, false,
        .{ .formal_count = 0, .callback = initialDebugCallback, .hooks = sync.frameHooks(RestFrame) },
        &.{owner, init_binding, debug_binding, enabled_binding, set_binding, cb_binding}));
    // Preserve the original let declaration point, including its TDZ before it.
    try frame.clear(.enabled);
    try frame.take(.test, functions.createWithArguments(s.engine, "test", 0, false,
        .{ .formal_count = 0, .callback = firstTestCallback }, &.{init_binding, test_binding, enabled_binding}));
    try frame.take(.logger, functions.createWithArguments(s.engine, "logger", 0, false,
        .{ .formal_count = 0, .callback = loggerCallback, .hooks = sync.frameHooks(RestFrame) },
        &.{owner, debug_binding, enabled_binding}));
    _ = try a.expression(s.engine, defineEnabledGetter,
        .{frame.get(.logger), test_binding, @as(bool, true)});
    return a.duplicate(s.engine, frame.get(.logger));
}
fn defineEnabledGetter(s: *Scope, target: c.JSValue, binding: c.JSValue,
    invoke_test: bool) anyerror!c.JSValue
{
    const define_property = try intrinsic(s, "Object.defineProperty");
    const property = try s.text("enabled");
    const descriptor = try s.objectProto(c.pi_js_null());
    const getter = try s.own(try functions.createWithArguments(s.engine, "get", 0, false,
        .{ .formal_count = 0, .callback = if (invoke_test) enabledTestGetter else enabledValueGetter }, &.{binding}));
    try s.define(descriptor, "get", getter, c.JS_PROP_C_W_E);
    try s.define(descriptor, "configurable", a.boolean(s, true), c.JS_PROP_C_W_E);
    try s.define(descriptor, "enumerable", a.boolean(s, true), c.JS_PROP_C_W_E);
    _ = try s.call(define_property, c.pi_js_undefined(), &.{target, property, descriptor});
    return c.pi_js_undefined();
}
fn enabledTestGetter(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, invokeTestBody, .{roots[0]});
}
fn invokeTestBody(s: *Scope, binding: c.JSValue) anyerror!c.JSValue {
    const function = try LogFrame.read(&s.values, binding);
    return a.duplicate(s.engine, try s.call(function, c.pi_js_undefined(), &.{}));
}
fn enabledValueGetter(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, enabledValueBody, .{roots[0]});
}
fn enabledValueBody(s: *Scope, binding: c.JSValue) anyerror!c.JSValue {
    return a.duplicate(s.engine, try LogFrame.read(&s.values, binding));
}
fn firstTestCallback(engine: *a.v.em.Engine, _: c.JSValue, _: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    _ = try a.expression(engine, callInit, .{roots[0]});
    try LogFrame.assign(roots[1], functions.createWithArguments(engine, "test", 0, false,
        .{ .formal_count = 0, .callback = enabledValueGetter }, &.{roots[2]}));
    return a.expression(engine, enabledValueBody, .{roots[2]});
}
fn restArray(s: *Scope, values: []const c.JSValue) anyerror!c.JSValue {
    const generation = try s.beforeAllocation();
    return a.duplicate(s.engine, try s.checkedAllocation(c.JS_PiCreateRestArray(s.engine.context,
        @intCast(values.len), @constCast(values.ptr)), generation));
}
fn invokeImpl(s: *Scope, owner: c.JSValue, enabled_binding: c.JSValue,
    set_binding: c.JSValue) anyerror!c.JSValue
{
    const function = try member(s, owner, "impl");
    const enabled = try LogFrame.read(&s.values, enabled_binding);
    const set = try sync.read(&s.values, set_binding);
    return a.duplicate(s.engine, try s.call(function, c.pi_js_undefined(), &.{enabled, set}));
}
fn callbackIsFunction(s: *Scope, binding: c.JSValue) anyerror!c.JSValue {
    return a.boolean(s, c.JS_IsFunction(s.engine.context, try sync.read(&s.values, binding)));
}
fn annotateDebug(s: *Scope, debug_binding: c.JSValue, enabled_binding: c.JSValue) anyerror!c.JSValue {
    const selected = try LogFrame.read(&s.values, debug_binding);
    _ = try a.expression(s.engine, defineEnabledGetter, .{selected, enabled_binding, @as(bool, false)});
    return c.pi_js_undefined();
}
fn invokeCallback(s: *Scope, cb_binding: c.JSValue, debug_binding: c.JSValue) anyerror!c.JSValue {
    const cb = try sync.read(&s.values, cb_binding);
    const debug = try LogFrame.read(&s.values, debug_binding);
    _ = try s.call(cb, c.pi_js_undefined(), &.{debug});
    return c.pi_js_undefined();
}
fn initialDebugCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, initialDebugBody, .{args, roots});
}
fn initialDebugBody(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, RestFrame);
    try frame.take(.args, a.expression(s.engine, restArray, .{args.initial}));
    _ = try a.expression(s.engine, callInit, .{roots[1]});
    try LogFrame.assign(roots[2], a.expression(s.engine, invokeImpl, .{roots[0], roots[3], roots[4]}));
    if (try a.condition(s.engine, callbackIsFunction, .{roots[5]})) {
        _ = try a.expression(s.engine, annotateDebug, .{roots[2], roots[3]});
        _ = try a.expression(s.engine, invokeCallback, .{roots[5], roots[2]});
    }
    return a.expression(s.engine, dispatch, .{roots[0], roots[2], frame.get(.args)});
}
fn loggerCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, loggerBody, .{args, roots});
}
fn loggerBody(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, RestFrame);
    try frame.take(.args, a.expression(s.engine, restArray, .{args.initial}));
    if (s.equal(try LogFrame.read(&s.values, roots[2]), a.boolean(s, false)))
        return c.pi_js_undefined();
    return a.expression(s.engine, dispatch, .{roots[0], roots[1], frame.get(.args)});
}
fn appendSpread(s: *Scope, arguments: c.JSValue, position: *u32,
    iterable: c.JSValue, safe_iterator: c.JSValue) anyerror!c.JSValue
{
    const source = if (c.JS_IsUndefined(safe_iterator)) iterable else
        try s.construct(safe_iterator, &.{iterable});
    try s.pending();
    const status = c.JS_PiArrayAppend(s.engine.context, arguments, position, source);
    try s.pending();
    if (status < 0) return error.MissingActualDebuglogSpreadReason;
    return c.pi_js_undefined();
}
fn spreadCall(s: *Scope, function: c.JSValue, prefix: []const c.JSValue,
    iterable: c.JSValue, safe_iterator: c.JSValue) anyerror!c.JSValue
{
    const arguments = try s.own(try a.expression(s.engine, restArray, .{prefix}));
    var position: u32 = @intCast(prefix.len);
    // The real OP_append owns iterator acquisition/advancement/failure. Its
    // SafeIterator temporary retires before the genuine argument-list call.
    _ = try a.expression(s.engine, appendSpread, .{arguments, &position, iterable, safe_iterator});
    try s.pending();
    return a.duplicate(s.engine, try s.checked(c.JS_PiCallArray(s.engine.context,
        function, c.pi_js_undefined(), arguments)));
}
fn dispatch(s: *Scope, owner: c.JSValue, binding: c.JSValue,
    arguments: c.JSValue) anyerror!c.JSValue
{
    const length = try s.get(arguments, "length");
    const function = try LogFrame.read(&s.values, binding);
    if (s.equal(length, c.JS_NewInt32(s.engine.context, 1))) {
        const first = try s.getKey(arguments, c.JS_NewInt32(s.engine.context, 0));
        return a.duplicate(s.engine, try s.call(function, c.pi_js_undefined(), &.{first}));
    }
    if (s.equal(length, c.JS_NewInt32(s.engine.context, 2))) {
        const first = try s.getKey(arguments, c.JS_NewInt32(s.engine.context, 0));
        const second = try s.getKey(arguments, c.JS_NewInt32(s.engine.context, 1));
        return a.duplicate(s.engine, try s.call(function, c.pi_js_undefined(), &.{first, second}));
    }
    return spreadCall(s, function, &.{}, arguments, try member(s, owner, "SafeArrayIterator"));
}
fn cachedImplementation(s: *Scope, owner: c.JSValue, set: c.JSValue) anyerror!c.JSValue {
    return a.duplicate(s.engine, try s.getKey(try member(s, owner, "debugImpls"), set));
}
fn implementationAbsent(s: *Scope, owner: c.JSValue, set: c.JSValue) anyerror!c.JSValue {
    return a.boolean(s, c.JS_IsUndefined(try s.getKey(try member(s, owner, "debugImpls"), set)));
}
fn warning(s: *Scope, owner: c.JSValue, set: c.JSValue) anyerror!c.JSValue {
    if (!s.equal(set, try s.text("HTTP")) and !s.equal(set, try s.text("HTTP2")))
        return c.pi_js_undefined();
    const process = try member(s, owner, "process");
    const method = try s.get(process, "emitWarning");
    const lower = try s.call(try intrinsic(s, "String.toLowerCase"), set, &.{});
    const start = try a.add(s, try s.text("Setting the NODE_DEBUG environment variable to '"), lower);
    const message = try a.add(s, start, try s.text("' can expose sensitive data (such as passwords, tokens and authentication headers) in the resulting log."));
    _ = try s.call(method, process, &.{message});
    return c.pi_js_undefined();
}
fn readPID(s: *Scope, owner: c.JSValue) anyerror!c.JSValue {
    return a.duplicate(s.engine, try s.get(try member(s, owner, "process"), "pid"));
}
fn implCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, implBody, .{args, roots[0]});
}
fn implBody(s: *Scope, args: *sync.Arguments, owner: c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, ImplFrame);
    if (try a.condition(s.engine, implementationAbsent, .{owner, args.get(1)})) {
        if (s.truthy(args.get(0))) {
            try frame.take(.pid, a.expression(s.engine, readPID, .{owner}));
            _ = try a.expression(s.engine, warning, .{owner, args.get(1)});
            _ = try a.expression(s.engine, storeDebug, .{args, frame, owner});
        } else {
            _ = try a.expression(s.engine, storeNoop, .{owner, args.get(1)});
        }
    }
    return a.expression(s.engine, cachedImplementation, .{owner, args.get(1)});
}
fn storeDebug(s: *Scope, args: *sync.Arguments, frame: *ImplFrame,
    owner: c.JSValue) anyerror!c.JSValue
{
    // Capture the assignment reference after warning reentry, before creating
    // its RHS. Return later re-reads the current cache exactly as Source does.
    const table = try member(s, owner, "debugImpls");
    const set = try s.own(a.duplicate(s.engine, args.get(1)));
    const set_binding = try args.capture(&s.values, 1);
    const pid_binding = try frame.capture(&s.values, .pid, "pid");
    const debug = try s.own(try functions.createWithArguments(s.engine, "debug", 0, true,
        .{ .formal_count = 0, .callback = emissionCallback, .hooks = sync.frameHooks(EmissionFrame) },
        &.{owner, set_binding, pid_binding}));
    try inspect_ops.setKey(&s.values, table, set, debug);
    return c.pi_js_undefined();
}
fn storeNoop(s: *Scope, owner: c.JSValue, set: c.JSValue) anyerror!c.JSValue {
    const table = try member(s, owner, "debugImpls");
    const value = try member(s, owner, "noop");
    try inspect_ops.setKey(&s.values, table, set, value);
    return c.pi_js_undefined();
}
fn lazyColors(s: *Scope, owner: c.JSValue) anyerror!c.JSValue {
    const known = try member(s, owner, "utilColors");
    if (c.JS_IsUndefined(known) or c.JS_IsNull(known)) {
        const require_value = try member(s, owner, "require");
        const actual = try s.call(require_value, c.pi_js_undefined(), &.{try s.text("internal/util/colors")});
        // Preserve ??= retry and outer assignment after nested require reentry.
        try s.put(owner, "utilColors", actual);
    }
    return a.duplicate(s.engine, try member(s, owner, "utilColors"));
}
fn selectColors(s: *Scope, owner: c.JSValue) anyerror!c.JSValue {
    const colors = try s.own(try a.expression(s.engine, lazyColors, .{owner}));
    const should = try s.get(colors, "shouldColorize");
    const stderr = try s.get(try member(s, owner, "process"), "stderr");
    return a.duplicate(s.engine, try s.call(should, colors, &.{stderr}));
}
fn formatMessage(s: *Scope, owner: c.JSValue, colors: c.JSValue,
    arguments: c.JSValue) anyerror!c.JSValue
{
    const formatter = try member(s, owner, "formatWithOptions");
    const options = try s.object();
    try s.define(options, "colors", colors, c.JS_PROP_C_W_E);
    // This original spread is deliberately ordinary ...args, unlike the
    // protected SafeArrayIterator paths in logger and its initial wrapper.
    return spreadCall(s, formatter, &.{options}, arguments, c.pi_js_undefined());
}
fn inspectPID(s: *Scope, owner: c.JSValue, binding: c.JSValue,
    colors: c.JSValue) anyerror!c.JSValue
{
    const inspector = try member(s, owner, "inspect");
    const pid = try ImplFrame.read(&s.values, binding);
    const options = try s.object();
    try s.define(options, "colors", colors, c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, try s.call(inspector, c.pi_js_undefined(), &.{pid, options}));
}
fn writeMessage(s: *Scope, owner: c.JSValue, set_binding: c.JSValue,
    colored_pid: c.JSValue, message: c.JSValue) anyerror!c.JSValue
{
    // Resolve the second live stderr and its write method BEFORE format().
    const stderr = try s.get(try member(s, owner, "process"), "stderr");
    const write = try s.get(stderr, "write");
    const formatter = try member(s, owner, "format");
    const format_text = try s.text("%s %s: %s\n");
    const set = try sync.read(&s.values, set_binding);
    const result = try s.call(formatter, c.pi_js_undefined(), &.{format_text, set, colored_pid, message});
    _ = try s.call(write, stderr, &.{result});
    return c.pi_js_undefined();
}
fn emissionCallback(engine: *a.v.em.Engine, _: c.JSValue, args: *sync.Arguments,
    roots: []const c.JSValue) anyerror!c.JSValue
{
    return a.expression(engine, emissionBody, .{args, roots});
}
fn emissionBody(s: *Scope, args: *sync.Arguments, roots: []const c.JSValue) anyerror!c.JSValue {
    const frame = try args.createFrame(&s.values, EmissionFrame);
    try frame.take(.args, a.expression(s.engine, restArray, .{args.initial}));
    try frame.take(.colors, a.expression(s.engine, selectColors, .{roots[0]}));
    try frame.take(.message, a.expression(s.engine, formatMessage, .{roots[0], frame.get(.colors), frame.get(.args)}));
    try frame.take(.colored_pid, a.expression(s.engine, inspectPID, .{roots[0], roots[2], frame.get(.colors)}));
    _ = try a.expression(s.engine, writeMessage, .{roots[0], roots[1], frame.get(.colored_pid), frame.get(.message)});
    return c.pi_js_undefined();
}

/// The separately admitted original timer bodies share these exact module
/// cells and captures. This Zig-only handoff never publishes an extra JS API.
pub fn requireSharedOwner(engine: *a.v.em.Engine, expected_exports: c.JSValue) !c.JSValue {
    return a.expression(engine, requireSharedOwnerBody, .{expected_exports});
}
fn requireSharedOwnerBody(s: *Scope, expected_exports: c.JSValue) anyerror!c.JSValue {
    const known = s.engine.native_module_values.get(key) orelse
        return error.RequiredActualInitializedDebuglogOwner;
    const owner = try s.own(a.duplicate(s.engine, known));
    if (!s.equal(try member(s, owner, "exports"), expected_exports))
        return error.ActualInitializedDebuglogOwnerIdentityChanged;
    return a.duplicate(s.engine, owner);
}
pub fn emitSharedWarning(engine: *a.v.em.Engine, owner: c.JSValue, set: c.JSValue) !c.JSValue {
    return a.expression(engine, warning, .{owner, set});
}
pub fn acquireSharedColors(engine: *a.v.em.Engine, owner: c.JSValue) !c.JSValue {
    return a.expression(engine, lazyColors, .{owner});
}
pub fn sharedSpreadCall(engine: *a.v.em.Engine, function: c.JSValue, prefix: []const c.JSValue,
    iterable: c.JSValue, safe_iterator: c.JSValue) !c.JSValue
{
    return a.expression(engine, spreadCall, .{function, prefix, iterable, safe_iterator});
}
