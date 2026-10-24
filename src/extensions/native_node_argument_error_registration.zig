// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual function-message NodeError registration and hideStackFrames bodies.
//! This helper creates classes; the single argument-error owner caches them.
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const classes = @import("native_node_error_class.zig");
const functions = @import("native_node_module_callable.zig");
const caught = @import("native_agent_af_values.zig").caught;
const HideFrame = a.frames.Frame(enum { rest, limit, receiver });
const ConstructorFrame = a.frames.Frame(enum { rest });
const CatchFrame = a.frames.Frame(enum { rest, reason });

fn getter(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    return a.duplicate(engine, roots[0]);
}
fn accessor(s: *Scope, target: c.JSValue, key: c.JSValue, name: [*:0]const u8, returned: c.JSValue) !void {
    const function = try s.own(try functions.create(s.engine, name, 0, false, getter, &.{returned}));
    try s.pending();
    const atom = c.JS_ValueToAtom(s.engine.context, key);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    if (atom == c.JS_ATOM_NULL) return error.MissingActualArgumentAccessorKeyReason;
    const status = c.JS_DefinePropertyGetSet(s.engine.context, target, atom, a.duplicate(s.engine, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualArgumentAccessorReason;
}
fn errorString(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, errorStringBody, .{receiver, roots[0]});
}
fn errorStringBody(s: *Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    const name = try s.own(try a.fieldText(s.engine, receiver, "name"));
    var result = try a.add(s, name, try s.text(" ["));
    result = try a.add(s, result, key);
    result = try a.add(s, result, try s.text("]: "));
    const message = try s.own(try a.fieldText(s.engine, receiver, "message"));
    return a.duplicate(s.engine, try a.add(s, result, message));
}
fn minimumArguments(s: *Scope, message: c.JSValue, args: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(5, try s.get(message, "length"), try s.get(args, "length"))));
}
fn messageBody(s: *Scope, message: c.JSValue, assertion: c.JSValue, apply: c.JSValue, key: c.JSValue, receiver: c.JSValue, args: c.JSValue) !c.JSValue {
    const valid = try a.condition(s.engine, minimumArguments, .{message, args});
    var assertion_message = try a.add(s, try s.text("Code: "), key);
    assertion_message = try a.add(s, assertion_message, try s.text("; The provided arguments length ("));
    assertion_message = try a.add(s, assertion_message, try s.own(try a.fieldText(s.engine, args, "length")));
    assertion_message = try a.add(s, assertion_message, try s.text(") does not match the required ones ("));
    const required = try s.own(try a.fieldText(s.engine, message, "length"));
    assertion_message = try a.add(s, assertion_message, required);
    assertion_message = try a.add(s, assertion_message, try s.text(")."));
    _ = try s.own(try a.call(s.engine, assertion, c.pi_js_undefined(), &.{a.boolean(s, valid), assertion_message}));
    return a.call(s.engine, apply, c.pi_js_undefined(), &.{message, receiver, args});
}
fn construct(engine: *v.em.Engine, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = ConstructorFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, constructBody(&s, frame, callee, target, args, roots));
}
fn constructBody(s: *Scope, frame: *ConstructorFrame, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try frame.take(.rest, a.expression(s.engine, restBody, .{args}));
    const receiver = try classes.superConstruct(&s.values, callee, target, &.{});
    // Source's public code field initializer runs immediately after super().
    try s.define(receiver, "code", roots[0], c.JS_PROP_C_W_E);
    const message = try s.own(try a.expression(s.engine, messageBody, .{roots[1], roots[2], roots[3], roots[0], receiver, frame.get(.rest)}));
    try s.define(receiver, "message", message, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    return a.duplicate(s.engine, receiver);
}
pub fn register(s: *Scope, base: c.JSValue, key: []const u8, message: c.JSValue, marker: c.JSValue, assertion: c.JSValue, apply: c.JSValue) !c.JSValue {
    const prototype = try s.objectProto(try s.get(base, "prototype"));
    const code = try s.text(key);
    const function = try s.own(try classes.create(s.engine, "NodeError", 0, prototype, base, construct, &.{code, message, assertion, apply}));
    try accessor(s, prototype, try s.text("constructor"), "get constructor", base);
    try accessor(s, prototype, marker, "get [kIsNodeError]", a.boolean(s, true));
    const stringifier = try s.own(try functions.create(s.engine, "toString", 0, false, errorString, &.{code}));
    try s.define(prototype, "toString", stringifier, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    return function;
}
fn stackLimitWritable(s: *Scope, error_class: c.JSValue) !c.JSValue {
    // The real native process is not V8's startup-snapshot builder.
    var descriptor = try s.descriptor(error_class, try s.text("stackTraceLimit")) orelse {
        try s.pending();
        const extensible = c.JS_IsExtensible(s.engine.context, error_class);
        try s.pending();
        if (extensible < 0) return error.MissingActualErrorExtensibilityReason;
        return a.boolean(s, extensible != 0);
    };
    defer s.releaseDescriptor(&descriptor);
    return a.boolean(s, if (descriptor.flags & c.JS_PROP_GETSET == 0) descriptor.flags & c.JS_PROP_WRITABLE != 0 else !c.JS_IsUndefined(descriptor.setter));
}
fn hideConstruct(engine: *v.em.Engine, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = HideFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, hideBody(&s, frame, callee, target, args, roots[0]));
}
fn restBody(s: *Scope, args: []const c.JSValue) !c.JSValue {
    // This is the actual OP_rest producer over borrowed native callback args.
    // It neither reads global Array nor consults an iterator.
    const generation = try s.beforeAllocation();
    const rest = try s.checkedAllocation(c.JS_PiCreateRestArray(s.engine.context, @intCast(args.len), @constCast(args.ptr)), generation);
    return a.duplicate(s.engine, rest);
}
fn hideBody(s: *Scope, frame: *HideFrame, callee: c.JSValue, target: c.JSValue, args: []const c.JSValue, error_class: c.JSValue) !c.JSValue {
    // The rest binding is initialized before the first constructor statement.
    try frame.take(.rest, a.expression(s.engine, restBody, .{args}));
    if (try a.condition(s.engine, stackLimitWritable, .{error_class})) {
        try frame.take(.limit, a.field(s.engine, error_class, "stackTraceLimit"));
        try s.put(error_class, "stackTraceLimit", c.JS_NewInt32(s.engine.context, 0));
        const receiver = try classes.superConstructSpread(&s.values, callee, target, frame.get(.rest));
        try frame.copy(.receiver, receiver);
        // There is intentionally no Source finally. Throwing super leaves zero.
        try s.put(error_class, "stackTraceLimit", frame.get(.limit));
        return a.duplicate(s.engine, frame.get(.receiver));
    }
    return a.duplicate(s.engine, try classes.superConstructSpread(&s.values, callee, target, frame.get(.rest)));
}
pub fn hide(s: *Scope, base: c.JSValue, original_base: c.JSValue, error_class: c.JSValue) !c.JSValue {
    const prototype = try s.objectProto(try s.get(base, "prototype"));
    const hidden = try s.own(try classes.create(s.engine, "HideStackFramesError", 0, prototype, base, hideConstruct, &.{error_class}));
    try accessor(s, prototype, try s.text("constructor"), "get constructor", original_base);
    try s.put(base, "HideStackFramesError", hidden);
    return hidden;
}
fn stringRaw(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, stringBody, .{args, roots[0]});
}
fn stringBody(s: *Scope, args: []const c.JSValue, error_class: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(a.arg(args, 0)))
        return a.raise(s, try s.construct(error_class, &.{a.arg(args, 1), try s.text("string"), a.arg(args, 0)}));
    return c.pi_js_undefined();
}
fn abortRaw(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, abortBody, .{args, roots[0]});
}
fn abortBody(s: *Scope, args: []const c.JSValue, error_class: c.JSValue) !c.JSValue {
    const signal = a.arg(args, 0);
    if (!c.JS_IsUndefined(signal) and
        (c.JS_IsNull(signal) or !c.JS_IsObject(signal) or c.JS_IsFunction(s.engine.context, signal) or
            !try s.hasKey(signal, try s.text("aborted"))))
        return a.raise(s, try s.construct(error_class, &.{a.arg(args, 1), try s.text("AbortSignal"), signal}));
    return c.pi_js_undefined();
}
fn wrapped(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = CatchFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, wrappedBody(&s, frame, receiver, args, roots));
}
fn captureBody(s: *Scope, capture: c.JSValue, lexical: c.JSValue, reason: c.JSValue) !c.JSValue {
    _ = try s.call(capture, c.pi_js_undefined(), &.{reason, try s.get(lexical, "wrapper")});
    return c.pi_js_undefined();
}
fn wrappedBody(s: *Scope, frame: *CatchFrame, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    // Parameter rest creation precedes the try statement, so its failure is
    // outside this Source catch. ReflectApply uses the real VM argument list.
    try frame.take(.rest, a.expression(s.engine, restBody, .{args}));
    return a.call(s.engine, roots[4], c.pi_js_undefined(), &.{roots[0], receiver, frame.get(.rest)}) catch |err| {
        // The inner expression completes before this actual Source catch.
        // caught() consults actual pending/invocation provenance, never the
        // birth generation or private flag of a diagnostic-only reason.
        try frame.take(.reason, caught(s.engine, err));
        if (try a.condition(s.engine, a.fieldTruthy, .{roots[1], @as([*:0]const u8, "stackTraceLimit")}))
            _ = try a.expression(s.engine, captureBody, .{roots[2], roots[3], frame.get(.reason)});
        return a.raise(s, frame.get(.reason));
    };
}
pub fn wrap(s: *Scope, raw: c.JSValue, error_class: c.JSValue, capture: c.JSValue, apply: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(s.engine.context, capture)) return error.RequiredActualNativeErrorCaptureStackTrace;
    const lexical = try s.objectProto(c.pi_js_null());
    const wrapper = try s.own(try functions.create(s.engine, "wrappedFn", 0, true, wrapped, &.{raw, error_class, capture, lexical, apply}));
    try s.put(wrapper, "withoutStackTrace", raw);
    try s.put(lexical, "wrapper", wrapper);
    return wrapper;
}
pub fn makeValidateString(s: *Scope, hidden: c.JSValue, error_class: c.JSValue, capture: c.JSValue, apply: c.JSValue) !c.JSValue {
    const raw = try s.own(try functions.create(s.engine, "", 2, false, stringRaw, &.{hidden}));
    return wrap(s, raw, error_class, capture, apply);
}
pub fn makeValidateAbortSignal(s: *Scope, hidden: c.JSValue, error_class: c.JSValue, capture: c.JSValue, apply: c.JSValue) !c.JSValue {
    const raw = try s.own(try functions.create(s.engine, "", 2, false, abortRaw, &.{hidden}));
    return wrap(s, raw, error_class, capture, apply);
}

fn objectArray(s: *Scope, value: c.JSValue, is_array: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(is_array, c.pi_js_undefined(), &.{value})));
}
fn objectFlagUnset(s: *Scope, flag: i32, options: c.JSValue) !c.JSValue {
    const bits = try s.binary(@intFromEnum(@import("native_image_arithmetic.zig").Operation.bit_and),
        c.JS_NewInt32(s.engine.context, flag), options);
    return a.boolean(s, s.equal(bits, c.JS_NewInt32(s.engine.context, 0)));
}
fn invalidObject(s: *Scope, args: []const c.JSValue, error_class: c.JSValue) !c.JSValue {
    return a.raise(s, try s.construct(error_class,
        &.{a.arg(args, 1), try s.text("Object"), a.arg(args, 0)}));
}
fn objectRaw(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, objectBody, .{args, roots[0], roots[1]});
}
fn objectBody(s: *Scope, args: []const c.JSValue, error_class: c.JSValue, is_array: c.JSValue) !c.JSValue {
    const value = a.arg(args, 0);
    const options = if (c.JS_IsUndefined(a.arg(args, 2))) c.JS_NewInt32(s.engine.context, 0) else a.arg(args, 2);
    if (s.equal(options, c.JS_NewInt32(s.engine.context, 0))) {
        if (c.JS_IsNull(value) or try a.condition(s.engine, objectArray, .{value, is_array}))
            return invalidObject(s, args, error_class);
        if (!c.JS_IsObject(value) or c.JS_IsFunction(s.engine.context, value))
            return invalidObject(s, args, error_class);
    } else {
        // Each original bitwise expression performs its own actual conversion.
        const throw_on_nullable = try a.condition(s.engine, objectFlagUnset, .{@as(i32, 1), options});
        if (throw_on_nullable and c.JS_IsNull(value)) return invalidObject(s, args, error_class);
        const throw_on_array = try a.condition(s.engine, objectFlagUnset, .{@as(i32, 2), options});
        if (throw_on_array and try a.condition(s.engine, objectArray, .{value, is_array}))
            return invalidObject(s, args, error_class);
        const throw_on_function = try a.condition(s.engine, objectFlagUnset, .{@as(i32, 4), options});
        const typeof_object = c.JS_IsNull(value) or
            (c.JS_IsObject(value) and !c.JS_IsFunction(s.engine.context, value));
        if (!typeof_object and (throw_on_function or !c.JS_IsFunction(s.engine.context, value)))
            return invalidObject(s, args, error_class);
    }
    return c.pi_js_undefined();
}
/// Complete original validateObject, including default options, all three
/// flags, coercion/short-circuit order and the real hidden Error constructor.
pub fn makeValidateObject(s: *Scope, hidden: c.JSValue, error_class: c.JSValue,
    capture: c.JSValue, apply: c.JSValue, is_array: c.JSValue) !c.JSValue
{
    if (!c.JS_IsFunction(s.engine.context, is_array)) return error.ActualArrayIsArrayPrimordialRequired;
    const raw = try s.own(try functions.create(s.engine, "", 2, false, objectRaw, &.{hidden, is_array}));
    return wrap(s, raw, error_class, capture, apply);
}
