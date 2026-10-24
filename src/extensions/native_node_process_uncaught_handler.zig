// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete capture-callback and global-uncaught-handler declarations from
//! internal/process/execution.js. Required bootstrap inputs remain explicit.
//! This private owner is not the whole execution module or the native
//! TriggerUncaughtException Message/report/exit adapter.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const functions = @import("native_node_module_callable.zig");
const publication = @import("native_node_fs_private_publication.zig");
const af = @import("native_agent_af_values.zig");
const c = a.c;
const Scope = a.Scope;
const key = "pi-native:private/process-uncaught-handler";
const k_generic_user_error: i32 = 1; // node_exit_code.h: GenericUserError.
const Frame = a.frames.Frame(enum { event_type });

pub const Inputs = struct {
    process: c.JSValue,
    require: c.JSValue,
    should_abort_on_uncaught_toggle: c.JSValue,
    invalid_arg_type: c.JSValue,
    capture_already_set: c.JSValue,
    execution_async_id: c.JSValue,
    clear_default_trigger_async_id: c.JSValue,
    clear_async_id_stack: c.JSValue,
    has_async_id_stack: c.JSValue,
    after_hooks_exist: c.JSValue,
    emit_after: c.JSValue,
    pop_async_context: c.JSValue,
};

const State = struct {
    engine: *a.v.em.Engine,
    inputs: Inputs,
    lexical: c.JSValue,
    noop_function: c.JSValue,
    exported: c.JSValue,
};
fn finalize(_: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const data: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    const engine = data.engine;
    inline for (std.meta.fields(Inputs)) |field| c.JS_FreeValueRT(engine.runtime, @field(data.inputs, field.name));
    c.JS_FreeValueRT(engine.runtime, data.lexical);
    c.JS_FreeValueRT(engine.runtime, data.noop_function);
    c.JS_FreeValueRT(engine.runtime, data.exported);
    engine.gpa.destroy(data);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const data: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    inline for (std.meta.fields(Inputs)) |field| c.JS_MarkValue(runtime, @field(data.inputs, field.name), marker);
    c.JS_MarkValue(runtime, data.lexical, marker);
    c.JS_MarkValue(runtime, data.noop_function, marker);
    c.JS_MarkValue(runtime, data.exported, marker);
}
fn ownerState(engine: *a.v.em.Engine, known: c.JSValue) !*State {
    // Only the private cache or this owner's known callable captures reach here.
    const data: *State = @ptrCast(@alignCast(c.JS_GetOpaque(known, c.JS_GetClassID(known)) orelse return error.ActualUncaughtOwnerRequired));
    if (data.engine != engine) return error.ActualUncaughtOwnerEngineMismatch;
    return data;
}
fn capture(s: *Scope, known: c.JSValue) !*State {
    const retained = try s.own(a.duplicate(s.engine, known));
    try s.pending();
    return ownerState(s.engine, retained);
}
fn sameInputs(s: *Scope, data: *State, inputs: Inputs) !void {
    inline for (std.meta.fields(Inputs)) |field|
        if (!s.equal(@field(data.inputs, field.name), @field(inputs, field.name)))
            return error.ActualUncaughtOwnerInputsConflict;
}
fn knownBody(s: *Scope, known: c.JSValue, inputs: Inputs) !c.JSValue {
    const data = try capture(s, known);
    try sameInputs(s, data, inputs);
    return a.duplicate(s.engine, known);
}
fn acquireHolder(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |known|
        return a.expression(engine, knownBody, .{ known, inputs });
    const candidate = try a.expression(engine, createBody, .{inputs});
    // Construction retirement can reenter. Retain the winning exact owner
    // before the losing candidate retires; neither incomplete owner is public.
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.expression(engine, knownBody, .{ known, inputs }));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
pub fn create(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    const holder = try acquireHolder(engine, inputs);
    var s = Scope.init(engine);
    const retained = s.own(holder) catch |err| return s.finish(err);
    return s.finish(exportsBody(&s, retained));
}
fn exportsBody(s: *Scope, holder: c.JSValue) !c.JSValue {
    const data = try ownerState(s.engine, holder);
    return a.duplicate(s.engine, data.exported);
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    try s.pending();
    inline for (std.meta.fields(Inputs)) |field|
        _ = try s.own(a.duplicate(s.engine, @field(inputs, field.name)));
    if (!c.JS_IsObject(inputs.process)) return error.ActualUncaughtProcessRequired;
    if (c.JS_GetTypedArrayType(inputs.should_abort_on_uncaught_toggle) != c.JS_TYPED_ARRAY_UINT32)
        return error.ActualUncaughtAbortToggleRequired;
    inline for (std.meta.fields(Inputs)) |field| {
        if (comptime !std.mem.eql(u8, field.name, "process") and
            !std.mem.eql(u8, field.name, "should_abort_on_uncaught_toggle"))
            if (!c.JS_IsFunction(s.engine.context, @field(inputs, field.name)))
                return error.ActualUncaughtBootstrapCallableRequired;
    }
    // This is the actual ordinary literal, including its normal prototype,
    // own writable/enumerable/configurable fields and observable callback this.
    const lexical = try s.object();
    try s.define(lexical, "captureFn", c.pi_js_null(), c.JS_PROP_C_W_E);
    try s.define(lexical, "reportFlag", a.boolean(s, false), c.JS_PROP_C_W_E);
    const noop_function = try s.own(try functions.create(s.engine, "noop", 0, true, noop, &.{}));
    const exported = try s.object();
    if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(State)) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(State));
    const data = try s.engine.gpa.create(State);
    errdefer if (!attached) s.engine.gpa.destroy(data);
    var class_id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native uncaught declaration owner", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    const generation = try s.beforeAllocation();
    const holder = try s.checkedAllocation(c.JS_NewObjectProtoClass(s.engine.context, c.pi_js_null(), class_id), generation);
    data.* = .{ .engine = s.engine, .inputs = inputs,
        .lexical = a.duplicate(s.engine, lexical), .noop_function = a.duplicate(s.engine, noop_function),
        .exported = a.duplicate(s.engine, exported) };
    inline for (std.meta.fields(Inputs)) |field|
        @field(data.inputs, field.name) = a.duplicate(s.engine, @field(inputs, field.name));
    _ = c.JS_SetOpaque(holder, data);
    attached = true;
    inline for (.{
        .{ "setUncaughtExceptionCaptureCallback", 1, setCapture },
        .{ "hasUncaughtExceptionCaptureCallback", 0, hasCapture },
        .{ "createOnGlobalUncaughtException", 0, createHandler },
    }) |entry| {
        const function_value = try s.own(try functions.create(s.engine, entry[0], entry[1], true, entry[2], &.{holder}));
        try s.define(exported, entry[0], function_value, c.JS_PROP_C_W_E);
    }
    return a.duplicate(s.engine, holder);
}
fn noop(_: *a.v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_undefined();
}

fn setCapture(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, setCaptureBody, .{ roots[0], a.arg(args, 0) });
}
fn setCaptureBody(s: *Scope, holder: c.JSValue, callback_value: c.JSValue) !c.JSValue {
    const data = try capture(s, holder);
    if (c.JS_IsNull(callback_value)) {
        _ = try a.expression(s.engine, assignCaptureBody, .{ data.lexical, callback_value });
        _ = try a.expression(s.engine, toggleBody, .{ data.inputs.should_abort_on_uncaught_toggle, @as(i32, 1) });
        _ = try a.expression(s.engine, restoreReportBody, .{ data.inputs.process, data.lexical });
        return c.pi_js_undefined();
    }
    if (!c.JS_IsFunction(s.engine.context, callback_value))
        return a.expression(s.engine, invalidTypeBody, .{ data.inputs.invalid_arg_type, callback_value });
    if (try a.condition(s.engine, capturePresentBody, .{data.lexical}))
        return a.expression(s.engine, alreadySetBody, .{data.inputs.capture_already_set});
    _ = try a.expression(s.engine, assignCaptureBody, .{ data.lexical, callback_value });
    _ = try a.expression(s.engine, toggleBody, .{ data.inputs.should_abort_on_uncaught_toggle, @as(i32, 0) });
    _ = try a.expression(s.engine, saveReportBody, .{ data.inputs.process, data.lexical });
    _ = try a.expression(s.engine, disableReportBody, .{data.inputs.process});
    return c.pi_js_undefined();
}
fn assignCaptureBody(s: *Scope, lexical: c.JSValue, callback_value: c.JSValue) !c.JSValue {
    try s.put(lexical, "captureFn", callback_value);
    return c.pi_js_undefined();
}
fn toggleBody(s: *Scope, toggle: c.JSValue, number: i32) !c.JSValue {
    try s.pending();
    const status = c.JS_SetPropertyUint32(s.engine.context, toggle, 0, c.JS_NewInt32(s.engine.context, number));
    try s.pending();
    if (status < 0) return error.ActualUncaughtAbortToggleWriteReason;
    return c.pi_js_undefined();
}
fn restoreReportBody(s: *Scope, process_value: c.JSValue, lexical: c.JSValue) !c.JSValue {
    // Source resolves process.report on the assignment's left side first.
    const report = try s.get(process_value, "report");
    const value = try s.get(lexical, "reportFlag");
    try s.put(report, "reportOnUncaughtException", value);
    return c.pi_js_undefined();
}
fn invalidTypeBody(s: *Scope, constructor_value: c.JSValue, callback_value: c.JSValue) !c.JSValue {
    const expected = try a.array(s);
    try a.index(s, expected, 0, try s.text("Function"));
    try a.index(s, expected, 1, try s.text("null"));
    const reason = try s.construct(constructor_value, &.{ try s.text("fn"), expected, callback_value });
    return a.raise(s, reason);
}
fn alreadySetBody(s: *Scope, constructor_value: c.JSValue) !c.JSValue {
    const reason = try s.construct(constructor_value, &.{});
    return a.raise(s, reason);
}
fn capturePresentBody(s: *Scope, lexical: c.JSValue) !c.JSValue {
    return a.boolean(s, !c.JS_IsNull(try s.get(lexical, "captureFn")));
}
fn saveReportBody(s: *Scope, process_value: c.JSValue, lexical: c.JSValue) !c.JSValue {
    const report = try s.get(process_value, "report");
    const enabled = s.equal(try s.get(report, "reportOnUncaughtException"), a.boolean(s, true));
    try s.put(lexical, "reportFlag", a.boolean(s, enabled));
    return c.pi_js_undefined();
}
fn disableReportBody(s: *Scope, process_value: c.JSValue) !c.JSValue {
    try s.put(try s.get(process_value, "report"), "reportOnUncaughtException", a.boolean(s, false));
    return c.pi_js_undefined();
}
fn hasCapture(engine: *a.v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, hasCaptureBody, .{roots[0]});
}
fn hasCaptureBody(s: *Scope, holder: c.JSValue) !c.JSValue {
    const data = try capture(s, holder);
    return a.expression(s.engine, capturePresentBody, .{data.lexical});
}
fn createHandler(engine: *a.v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, createHandlerBody, .{roots[0]});
}
fn createHandlerBody(s: *Scope, holder: c.JSValue) !c.JSValue {
    _ = try capture(s, holder);
    // The Source returns a fresh anonymous arrow on every factory call.
    return a.duplicate(s.engine, try s.own(try functions.create(s.engine, "", 2, false, handle, &.{holder})));
}

fn handle(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = Frame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, handleBody(&s, frame, roots[0], a.arg(args, 0), a.arg(args, 1)));
}
fn eventTypeBody(s: *Scope, from_promise: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.text(if (s.truthy(from_promise)) "unhandledRejection" else "uncaughtException"));
}
fn callVoidBody(s: *Scope, function_value: c.JSValue, receiver: c.JSValue, arguments: []const c.JSValue) !c.JSValue {
    _ = try s.call(function_value, receiver, arguments);
    return c.pi_js_undefined();
}
fn callTruthyBody(s: *Scope, function_value: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(function_value, c.pi_js_undefined(), &.{})));
}
fn emitBody(s: *Scope, process_value: c.JSValue, event_name: []const u8, reason: c.JSValue, event_type: c.JSValue) !c.JSValue {
    const emit = try s.get(process_value, "emit");
    return a.boolean(s, s.truthy(try s.call(emit, process_value, &.{ try s.text(event_name), reason, event_type })));
}
fn callCaptureBody(s: *Scope, lexical: c.JSValue, reason: c.JSValue) !c.JSValue {
    // This is a second live get after the !== null condition, and this is
    // deliberately the ordinary exceptionHandlerState object.
    const callback_value = try s.get(lexical, "captureFn");
    _ = try s.call(callback_value, lexical, &.{reason});
    return c.pi_js_undefined();
}
fn exitBody(s: *Scope, process_value: c.JSValue) !c.JSValue {
    if (!try a.condition(s.engine, a.fieldTruthy, .{ process_value, @as([*:0]const u8, "_exiting") })) {
        _ = try a.expression(s.engine, putProcessBody, .{ process_value, @as([*:0]const u8, "_exiting"), a.boolean(s, true) });
        _ = try a.expression(s.engine, putProcessBody, .{ process_value, @as([*:0]const u8, "exitCode"), c.JS_NewInt32(s.engine.context, k_generic_user_error) });
        _ = try a.expression(s.engine, emitExitBody, .{process_value});
    }
    return c.pi_js_undefined();
}
fn putProcessBody(s: *Scope, process_value: c.JSValue, property: [*:0]const u8, value: c.JSValue) !c.JSValue {
    try s.put(process_value, property, value);
    return c.pi_js_undefined();
}
fn emitExitBody(s: *Scope, process_value: c.JSValue) !c.JSValue {
    const emit = try s.get(process_value, "emit");
    _ = try s.call(emit, process_value, &.{ try s.text("exit"), c.JS_NewInt32(s.engine.context, k_generic_user_error) });
    return c.pi_js_undefined();
}
fn immediateBody(s: *Scope, require_value: c.JSValue, noop_function: c.JSValue) !c.JSValue {
    const timers = try s.call(require_value, c.pi_js_undefined(), &.{try s.text("timers")});
    const immediate = try s.get(timers, "setImmediate");
    _ = try s.call(immediate, timers, &.{noop_function});
    return c.pi_js_undefined();
}
fn afterBody(s: *Scope, data: *State) !c.JSValue {
    // asyncId is lexical to this single do-body. Retire it before evaluating
    // the loop's live hasAsyncIdStack() condition.
    const async_id = try s.call(data.inputs.execution_async_id, c.pi_js_undefined(), &.{});
    if (s.equal(async_id, c.JS_NewInt32(s.engine.context, 0)))
        _ = try s.call(data.inputs.pop_async_context, c.pi_js_undefined(), &.{c.JS_NewInt32(s.engine.context, 0)})
    else
        _ = try s.call(data.inputs.emit_after, c.pi_js_undefined(), &.{async_id});
    return c.pi_js_undefined();
}
fn handleBody(s: *Scope, frame: *Frame, holder: c.JSValue, reason: c.JSValue, from_promise: c.JSValue) !c.JSValue {
    const data = try capture(s, holder);
    _ = try a.expression(s.engine, callVoidBody, .{ data.inputs.clear_default_trigger_async_id, c.pi_js_undefined(), @as([]const c.JSValue, &.{}) });
    try frame.take(.event_type, a.expression(s.engine, eventTypeBody, .{from_promise}));
    _ = try a.expression(s.engine, emitBody, .{ data.inputs.process, @as([]const u8, "uncaughtExceptionMonitor"), reason, frame.get(.event_type) });
    if (try a.condition(s.engine, capturePresentBody, .{data.lexical})) {
        _ = try a.expression(s.engine, callCaptureBody, .{ data.lexical, reason });
    } else if (!try a.condition(s.engine, emitBody, .{ data.inputs.process, @as([]const u8, "uncaughtException"), reason, frame.get(.event_type) })) {
        _ = a.expression(s.engine, exitBody, .{data.inputs.process}) catch |err| caught: {
            // Only the original catch{} consumes ordinary exceptions. Actual
            // pending fatal/OOM/termination remains uncatchable through caught.
            const caught_reason = try af.caught(s.engine, err);
            var completion = a.owned.Completion.initVoid(s.engine, {});
            completion.release(caught_reason);
            try completion.finishVoid();
            break :caught c.pi_js_undefined();
        };
        return a.boolean(s, false);
    }
    _ = try a.expression(s.engine, immediateBody, .{ data.inputs.require, data.noop_function });
    if (try a.condition(s.engine, callTruthyBody, .{data.inputs.after_hooks_exist})) {
        while (true) {
            _ = try a.expression(s.engine, afterBody, .{data});
            if (!try a.condition(s.engine, callTruthyBody, .{data.inputs.has_async_id_stack})) break;
        }
    }
    _ = try a.expression(s.engine, callVoidBody, .{ data.inputs.clear_async_id_stack, c.pi_js_undefined(), @as([]const c.JSValue, &.{}) });
    return a.boolean(s, true);
}
