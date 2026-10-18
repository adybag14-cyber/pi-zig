//! One internal/errors ErrnoException on the actual shared system-error record.
//! Reuse/adopt an existing genuine TTY class or create the Source class once for
//! a fresh cross-platform bootstrap. No util carrier, fake map or Error alias.
const js = @import("native_js_values.zig");
const c = js.c;
const local = @import("native_node_socket_scope.zig");
const Scope = local.Scope;
const functions = @import("native_node_socket_function.zig");
const classes = @import("native_node_error_class.zig");
const systems = @import("native_node_system_errors.zig");
const Entry = struct { engine: *js.Engine, previous: ?*Entry };
threadlocal var initializing: ?*Entry = null;
pub const Inputs = struct {
    /// Actual bootstrap-captured Error; source constructor getter captures it.
    error_type: c.JSValue,
    /// Genuine existing module require, used lazily for builtin util.
    require: c.JSValue,
    /// Typed host graph may adopt the exact already-built shared TTY class.
    existing: ?c.JSValue = null,
};
fn argument(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
fn directFailure(engine: *js.Engine, err: anyerror) anyerror {
    const thrown = if (err == error.OutOfMemory) engine.throwNativeOutOfMemoryFatal() else if (err == error.JavaScriptException or c.JS_HasException(engine.context)) engine.throwCaptured() else return err;
    _ = engine.checked(thrown) catch |actual| return actual; unreachable;
}
fn constructorGetter(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return c.JS_DupValue(engine.context, roots[0]); }
fn constructInner(engine: *js.Engine, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    var util = try scope.get(roots[0], "util");
    if (nullish(util)) {
        util = try scope.call(roots[1], c.pi_js_undefined(), &.{try scope.text("util")});
        try scope.set(roots[0], "util", util);
    }
    const code = try scope.call(try scope.get(util, "getSystemErrorName"), util, &.{argument(args, 0)});
    // Actual template-literal coercion order, repeated only in chosen branch.
    var message = try scope.concat(try scope.stringify(argument(args, 1)), try scope.text(" "));
    message = try scope.concat(message, try scope.stringify(code));
    if (scope.truthy(argument(args, 2))) {
        message = try scope.concat(message, try scope.text(" "));
        message = try scope.concat(message, try scope.stringify(argument(args, 2)));
    }
    // Source super resolves DECLARED class's LIVE [[Prototype]], passes through
    // real derived new.target, and actually constructs Error (no name branding).
    const base_generation = engine.native_allocation_generation;
    const base = try scope.ownSince(c.JS_GetPrototype(engine.context, callee), base_generation);
    const generation = engine.native_allocation_generation;
    var parameters = [_]c.JSValue{message};
    const value = try scope.ownSince(c.JS_CallConstructor2(engine.context, base, target, 1, &parameters), generation);
    try scope.set(value, "errno", argument(args, 0));
    try scope.set(value, "code", code);
    try scope.set(value, "syscall", argument(args, 1));
    return c.JS_DupValue(engine.context, value);
}
fn construct(engine: *js.Engine, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = constructInner(engine, callee, target, args, roots) catch |err| {
        const failure = directFailure(engine, err);
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |actual| return @as(anyerror!c.JSValue, actual);
        return @as(anyerror!c.JSValue, failure);
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn acquireInner(engine: *js.Engine, inputs: Inputs) !c.JSValue {
    var cursor = initializing; while (cursor) |prior| : (cursor = prior.previous) if (prior.engine == engine) return error.NativeErrnoExceptionInitializing;
    var entry: Entry = .{ .engine = engine, .previous = initializing }; initializing = &entry; defer initializing = entry.previous;
    if (!c.JS_IsConstructor(engine.context, inputs.error_type) or !c.JS_IsFunction(engine.context, inputs.require)) return error.RequiredActualErrnoExceptionDependencies;
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const core = try @import("native_node_stream.zig").owner(engine); try engine.checkNativeEntry();
    if (!scope.equal(try scope.get(core, "Error"), inputs.error_type)) return error.RequiredPristineErrnoErrorConstructor;
    const record = try systems.registry(engine); try engine.checkNativeEntry();
    const existing = try scope.get(record, "ErrnoException");
    if (!c.JS_IsUndefined(existing)) {
        if (!scope.equal(try scope.get(record, "errno/Error"), inputs.error_type) or !scope.equal(try scope.get(record, "errno/require"), inputs.require)) return error.NativeErrnoExceptionAuthorityChanged;
        if (inputs.existing) |actual| if (!scope.equal(existing, actual)) return error.NativeErrnoExceptionIdentityChanged;
        return c.JS_DupValue(engine.context, existing);
    }
    var result: c.JSValue = undefined;
    if (inputs.existing) |actual| {
        if (!c.JS_IsConstructor(engine.context, actual)) return error.RequiredActualErrnoExceptionConstructor;
        result = actual; // Actual shared class, no wrapper/clone/metadata test.
    } else {
        const lexical = try scope.object(); try scope.put(lexical, "util", c.pi_js_undefined());
        const base_prototype = try scope.get(inputs.error_type, "prototype");
        const prototype = try scope.objectProto(base_prototype);
        result = try scope.own(try classes.create(engine, "ErrnoException", 3, prototype, inputs.error_type, construct, &.{lexical, inputs.require}));
        try engine.checkNativeEntry();
        const getter = try scope.own(try functions.createMethod(engine, "get constructor", 0, constructorGetter, &.{inputs.error_type}));
        const atom = c.JS_NewAtom(engine.context, "constructor"); if (atom == c.JS_ATOM_NULL) return @as(anyerror!c.JSValue, js.capture(engine)); defer c.JS_FreeAtom(engine.context, atom);
        const status = c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW);
        try engine.checkNativeEntry(); if (status < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    }
    // Shared record is private/unregistered. Publish the actual class last;
    // older argument/SystemError/marker entries and their identities stay exact.
    try scope.put(record, "errno/Error", inputs.error_type);
    try scope.put(record, "errno/require", inputs.require);
    try scope.put(record, "ErrnoException", result);
    return c.JS_DupValue(engine.context, result);
}
pub fn acquire(engine: *js.Engine, inputs: Inputs) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = acquireInner(engine, inputs) catch |err| {
        const failure = directFailure(engine, err);
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |actual| return @as(anyerror!c.JSValue, actual);
        return @as(anyerror!c.JSValue, failure);
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
