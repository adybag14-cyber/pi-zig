//! Owner-thread WHATWG TransformStream state machine, derived from Node24's
//! internal/webstreams/transformstream. Queues and brands belong to the genuine
//! native ReadableStream/WritableStream implementations; this owns no proxy queue.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const readable = @import("native_readable_stream.zig");
const writable = @import("native_writable_stream.zig");
const durable = @import("native_durable.zig");
const c = em.c;
const module_key = "pi-native:whatwg-transform-stream";
const Slot = enum { owner, readable, writable, controller, readable_controller, writable_controller, transformer, transform, flush, cancel, start_promise, start_resolve, start_reject, pressure_promise, pressure_resolve, pressure_reject, finish_promise, finish_resolve, finish_reject, stored_error };
const slot_count = @typeInfo(Slot).@"enum".fields.len;
const State = struct {
    engine: *em.Engine,
    values: [slot_count]c.JSValue,
    backpressure: bool = true,
    failed: bool = false,
    fn get(self: *State, slot: Slot) c.JSValue {
        return self.values[@intFromEnum(slot)];
    }
    fn set(self: *State, slot: Slot, value: c.JSValue) void {
        const replacement = c.JS_DupValue(self.engine.context, value);
        self.engine.freeValue(self.get(slot));
        self.values[@intFromEnum(slot)] = replacement;
    }
};
const Controller = struct { engine: *em.Engine, stream: c.JSValue };
const Op = enum(c_int) { readable_get, writable_get, desired_get, enqueue, error_stream, terminate, sink_start, source_start, source_pull, source_cancel, sink_write, sink_close, sink_abort, pressure_write, transform_rejected, finish_close_ok, finish_abort_ok, finish_cancel_ok, finish_close_bad, finish_abort_bad, finish_cancel_bad };
fn streamState(value: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (state.values) |root| c.JS_FreeValueRT(runtime, root);
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (state.values) |root| c.JS_MarkValue(runtime, root, visit);
}
fn finalizeController(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Controller = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.stream);
    state.engine.gpa.destroy(state);
}
fn markController(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Controller = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.stream, visit);
}
fn id(engine: *em.Engine, owner: c.JSValue, name: [*:0]const u8) !c.JSClassID {
    const value = try js.get(engine, owner, name);
    defer engine.freeValue(value);
    var result: u32 = 0;
    if (c.JS_ToUint32(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn errorValue(engine: *em.Engine, owner: c.JSValue, kind: [*:0]const u8, message: []const u8, code: []const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var args = [_]c.JSValue{try scope.text(message)};
    const result = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(owner, kind), 1, &args)));
    try scope.put(result, "code", try scope.text(code));
    return c.JS_DupValue(engine.context, result);
}
fn throwError(engine: *em.Engine, owner: c.JSValue, kind: [*:0]const u8, message: []const u8, code: []const u8) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, try errorValue(engine, owner, kind, message, code))) catch |err| return err;
    unreachable;
}
fn branded(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, controller: bool) !c.JSValue {
    const class_id = try id(engine, owner, if (controller) "controllerClass" else "streamClass");
    const handle = c.JS_GetOpaque(receiver, class_id);
    if (handle == null) return throwError(engine, owner, "TypeError", if (controller) "Value of \"this\" must be of type TransformStreamDefaultController" else "Value of \"this\" must be of type TransformStream", "ERR_INVALID_THIS");
    if (controller) {
        const state: *Controller = @ptrCast(@alignCast(handle.?));
        return state.stream;
    }
    return receiver;
}
pub fn isTransformStream(engine: *em.Engine, value: c.JSValue) !bool {
    const owner = engine.native_module_values.get(module_key) orelse return false;
    return c.JS_GetOpaque(value, try id(engine, owner, "streamClass")) != null;
}
pub fn readableNative(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    const owner = engine.native_module_values.get(module_key) orelse return error.TransformStreamNotInstalled;
    return c.JS_DupValue(engine.context, streamState(try branded(engine, owner, value, false)).get(.readable));
}
pub fn writableNative(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    const owner = engine.native_module_values.get(module_key) orelse return error.TransformStreamNotInstalled;
    return c.JS_DupValue(engine.context, streamState(try branded(engine, owner, value, false)).get(.writable));
}
fn callback(scope: *Scope, root: c.JSValue, op: Op, name: [*:0]const u8, length: c_int, extra: ?c.JSValue) !c.JSValue {
    var roots = [_]c.JSValue{ root, extra orelse c.pi_js_undefined() };
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(op), roots.len, &roots)));
}
fn capability(state: *State, promise: Slot, resolve: Slot, reject: Slot) !void {
    var functions: [2]c.JSValue = undefined;
    const value = try state.engine.checked(c.JS_NewPromiseCapability(state.engine.context, &functions));
    defer state.engine.freeValue(value);
    defer for (functions) |function| state.engine.freeValue(function);
    state.set(promise, value);
    state.set(resolve, functions[0]);
    state.set(reject, functions[1]);
}
fn settle(state: *State, function: Slot, value: c.JSValue) !void {
    const result = try js.call(state.engine, state.get(function), c.pi_js_undefined(), &.{value});
    state.engine.freeValue(result);
}
fn rejectedValue(engine: *em.Engine, reason: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    defer for (functions) |function| engine.freeValue(function);
    const result = try js.call(engine, functions[1], c.pi_js_undefined(), &.{reason});
    engine.freeValue(result);
    return promise;
}
fn pressure(state: *State, value: bool) !void {
    if (state.backpressure == value and !c.JS_IsUndefined(state.get(.pressure_promise))) return;
    if (!c.JS_IsUndefined(state.get(.pressure_resolve))) try settle(state, .pressure_resolve, c.pi_js_undefined());
    try capability(state, .pressure_promise, .pressure_resolve, .pressure_reject);
    state.backpressure = value;
}
fn clearAlgorithms(state: *State) void {
    inline for (.{ Slot.transform, Slot.flush, Slot.cancel, Slot.transformer }) |slot| state.set(slot, c.pi_js_undefined());
}
fn errorWritable(state: *State, reason: c.JSValue) !void {
    if (!state.failed) {
        state.failed = true;
        state.set(.stored_error, reason);
    }
    clearAlgorithms(state);
    try writable.controllerErrorNative(state.engine, state.get(.writable_controller), reason);
    if (state.backpressure) try pressure(state, false);
}
fn errorBoth(state: *State, reason: c.JSValue) !void {
    // Root the rejection before any operation that can replace the Engine's
    // captured exception during an allocation failure.
    if (!state.failed) {
        state.failed = true;
        state.set(.stored_error, reason);
    }
    try readable.errorDefaultNative(state.engine, state.get(.readable_controller), reason);
    try errorWritable(state, reason);
}
pub fn enqueueNative(engine: *em.Engine, controller: c.JSValue, chunk: c.JSValue) !void {
    const owner = engine.native_module_values.get(module_key) orelse return error.TransformStreamNotInstalled;
    const stream = try branded(engine, owner, controller, true);
    const state = streamState(stream);
    if (!try readable.controllerCanCloseOrEnqueueNative(engine, state.get(.readable_controller))) return throwError(engine, owner, "TypeError", "Invalid state: Unable to enqueue", "ERR_INVALID_STATE");
    readable.enqueueDefaultNative(engine, state.get(.readable_controller), chunk) catch |err| {
        if (err == error.JavaScriptException) {
            const reason = engine.captured_exception orelse return err;
            try errorWritable(state, reason);
        }
        return err;
    };
    if (try readable.controllerHasBackpressureNative(engine, state.get(.readable_controller))) try pressure(state, true);
}
pub fn errorNative(engine: *em.Engine, controller: c.JSValue, reason: c.JSValue) !void {
    const owner = engine.native_module_values.get(module_key) orelse return error.TransformStreamNotInstalled;
    try errorBoth(streamState(try branded(engine, owner, controller, true)), reason);
}
/// Run the same terminal transition as the captured controller method.
pub fn terminateNative(engine: *em.Engine, controller: c.JSValue) !void {
    const owner = engine.native_module_values.get(module_key) orelse return error.TransformStreamNotInstalled;
    const result = try invoke(engine, controller, &.{}, .terminate, owner, c.pi_js_undefined());
    engine.freeValue(result);
}
fn promiseCall(scope: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    // A transformer may call controller.error/terminate and collect while its
    // own callback is executing. Algorithm retirement must not free this frame.
    const kept_function = try scope.own(c.JS_DupValue(scope.engine.context, function));
    const kept_receiver = try scope.own(c.JS_DupValue(scope.engine.context, receiver));
    const result = js.call(scope.engine, kept_function, kept_receiver, args) catch |err| {
        if (err == error.JavaScriptException) return scope.own(try rejectedValue(scope.engine, scope.engine.captured_exception.?));
        return err;
    };
    defer scope.engine.freeValue(result);
    return scope.own(try durable.resolvedPromise(scope.engine, result));
}
fn perform(scope: *Scope, stream: c.JSValue, chunk: c.JSValue) !c.JSValue {
    const state = streamState(stream);
    if (state.failed) return rejectedValue(scope.engine, state.get(.stored_error));
    const pending = if (c.JS_IsUndefined(state.get(.transform))) blk: {
        enqueueNative(scope.engine, state.get(.controller), chunk) catch |err| {
            if (err == error.JavaScriptException) {
                try errorBoth(state, scope.engine.captured_exception.?);
                return rejectedValue(scope.engine, scope.engine.captured_exception.?);
            }
            return err;
        };
        break :blk try scope.own(try durable.resolvedPromise(scope.engine, c.pi_js_undefined()));
    } else try promiseCall(scope, state.get(.transform), state.get(.transformer), &.{ chunk, state.get(.controller) });
    const rejected = try callback(scope, stream, .transform_rejected, "", 1, null);
    return scope.engine.checked(c.JS_PromiseThen(scope.engine.context, pending, c.pi_js_undefined(), rejected));
}
fn finish(scope: *Scope, stream: c.JSValue, kind: Op, reason: c.JSValue) !c.JSValue {
    const state = streamState(stream);
    if (!c.JS_IsUndefined(state.get(.finish_promise))) return c.JS_DupValue(scope.engine.context, state.get(.finish_promise));
    try capability(state, .finish_promise, .finish_resolve, .finish_reject);
    const function = state.get(if (kind == .sink_close) .flush else .cancel);
    const pending = if (c.JS_IsUndefined(function)) try scope.own(try durable.resolvedPromise(scope.engine, c.pi_js_undefined())) else try promiseCall(scope, function, state.get(.transformer), if (kind == .sink_close) &.{state.get(.controller)} else &.{reason});
    clearAlgorithms(state);
    const ok: Op = switch (kind) {
        .sink_close => .finish_close_ok,
        .sink_abort => .finish_abort_ok,
        .source_cancel => .finish_cancel_ok,
        else => unreachable,
    };
    const bad: Op = switch (kind) {
        .sink_close => .finish_close_bad,
        .sink_abort => .finish_abort_bad,
        .source_cancel => .finish_cancel_bad,
        else => unreachable,
    };
    const fulfilled = try callback(scope, stream, ok, "", 1, reason);
    const rejected = try callback(scope, stream, bad, "", 1, reason);
    const observed = try scope.engine.checked(c.JS_PromiseThen(scope.engine.context, pending, fulfilled, rejected));
    scope.engine.freeValue(observed);
    return c.JS_DupValue(scope.engine.context, state.get(.finish_promise));
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), roots[0], roots[1]) catch |err| durable.reject(engine, err);
}
fn invoke(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, op: Op, root: c.JSValue, extra: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = if (args.len > 0) args[0] else c.pi_js_undefined();
    const stream = switch (op) {
        .readable_get, .writable_get => try branded(engine, root, receiver, false),
        .desired_get, .enqueue, .error_stream, .terminate => try branded(engine, root, receiver, true),
        else => root,
    };
    const state = streamState(stream);
    switch (op) {
        .readable_get => return c.JS_DupValue(contextOf(state), state.get(.readable)),
        .writable_get => return c.JS_DupValue(contextOf(state), state.get(.writable)),
        .desired_get => return readable.controllerDesiredSizeNative(engine, state.get(.readable_controller)),
        .enqueue => {
            try enqueueNative(engine, state.get(.controller), value);
            return c.pi_js_undefined();
        },
        .error_stream => {
            try errorBoth(state, value);
            return c.pi_js_undefined();
        },
        .terminate => {
            try readable.closeDefaultNative(engine, state.get(.readable_controller));
            const error_value = try scope.own(try errorValue(engine, state.get(.owner), "TypeError", "Invalid state: TransformStream has been terminated", "ERR_INVALID_STATE"));
            try errorWritable(state, error_value);
            return c.pi_js_undefined();
        },
        .sink_start, .source_start => {
            state.set(if (op == .sink_start) .writable_controller else .readable_controller, value);
            return c.JS_DupValue(engine.context, state.get(.start_promise));
        },
        .source_pull => {
            try pressure(state, false);
            return c.JS_DupValue(engine.context, state.get(.pressure_promise));
        },
        .sink_write => {
            if (state.backpressure) {
                const continuation = try callback(&scope, stream, .pressure_write, "", 0, value);
                return engine.checked(c.JS_PromiseThen(engine.context, state.get(.pressure_promise), continuation, c.pi_js_undefined()));
            }
            return perform(&scope, stream, value);
        },
        .pressure_write => {
            if (try writable.isErroringOrErroredNative(engine, state.get(.writable))) {
                const reason = try scope.own(try writable.streamStoredErrorNative(engine, state.get(.writable)));
                return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
            }
            return perform(&scope, stream, extra);
        },
        .transform_rejected => {
            try errorBoth(state, value);
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
        },
        .sink_close, .sink_abort, .source_cancel => return finish(&scope, stream, op, value),
        .finish_close_ok, .finish_abort_ok => {
            if (try readable.isErrored(engine, state.get(.readable))) {
                const reason = try scope.own(try readable.streamStoredErrorNative(engine, state.get(.readable)));
                try settle(state, .finish_reject, reason);
            } else {
                if (op == .finish_close_ok) try readable.closeDefaultNative(engine, state.get(.readable_controller)) else try readable.errorDefaultNative(engine, state.get(.readable_controller), extra);
                try settle(state, .finish_resolve, c.pi_js_undefined());
            }
            return c.pi_js_undefined();
        },
        .finish_cancel_ok => {
            if (try writable.isErrored(engine, state.get(.writable))) {
                const reason = try scope.own(try writable.streamStoredErrorNative(engine, state.get(.writable)));
                try settle(state, .finish_reject, reason);
            } else {
                try errorWritable(state, extra);
                try settle(state, .finish_resolve, c.pi_js_undefined());
            }
            return c.pi_js_undefined();
        },
        .finish_close_bad, .finish_abort_bad, .finish_cancel_bad => {
            if (op == .finish_cancel_bad) try errorWritable(state, value) else try readable.errorDefaultNative(engine, state.get(.readable_controller), value);
            try settle(state, .finish_reject, value);
            return c.pi_js_undefined();
        },
    }
}
fn contextOf(state: *State) ?*c.JSContext {
    return state.engine.context;
}
fn nullObject(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
}
fn objectInput(scope: *Scope, owner: c.JSValue, value: c.JSValue, name: []const u8, allow_null: bool) !c.JSValue {
    if (c.JS_IsUndefined(value)) return nullObject(scope);
    if (allow_null and c.JS_IsNull(value)) return value;
    if (!c.JS_IsObject(value) or c.JS_IsFunction(scope.engine.context, value)) {
        const received = try receivedDescription(scope.engine, value);
        defer scope.engine.gpa.free(received);
        const message = try std.fmt.allocPrint(scope.engine.gpa, "The \"{s}\" argument must be of type object. Received {s}", .{ name, received });
        defer scope.engine.gpa.free(message);
        return throwError(scope.engine, owner, "TypeError", message, "ERR_INVALID_ARG_TYPE");
    }
    return value;
}
fn optionalGet(scope: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (c.JS_IsNull(object)) c.pi_js_undefined() else scope.get(object, name);
}
fn highWaterMark(scope: *Scope, owner: c.JSValue, raw: c.JSValue, default: f64) !c.JSValue {
    if (c.JS_IsUndefined(raw)) return c.JS_NewFloat64(scope.engine.context, default);
    var value: f64 = 0;
    if (c.JS_ToFloat64(scope.engine.context, &value, raw) < 0) return js.capture(scope.engine);
    if (std.math.isNan(value) or value < 0) return invalidValue(scope, owner, "strategy.highWaterMark", c.JS_NewFloat64(scope.engine.context, value));
    return c.JS_NewFloat64(scope.engine.context, value);
}
fn validateCallback(scope: *Scope, owner: c.JSValue, value: c.JSValue, name: []const u8) !void {
    if (!c.JS_IsFunction(scope.engine.context, value)) {
        const received = try receivedDescription(scope.engine, value);
        defer scope.engine.gpa.free(received);
        const message = try std.fmt.allocPrint(scope.engine.gpa, "The \"{s}\" property must be of type function. Received {s}", .{ name, received });
        defer scope.engine.gpa.free(message);
        return throwError(scope.engine, owner, "TypeError", message, "ERR_INVALID_ARG_TYPE");
    }
}
pub fn receivedDescription(engine: *em.Engine, value: c.JSValue) ![]u8 {
    if (c.JS_IsUndefined(value)) return engine.gpa.dupe(u8, "undefined");
    if (c.JS_IsNull(value)) return engine.gpa.dupe(u8, "null");
    if (c.JS_IsString(value) or c.JS_IsNumber(value) or c.JS_IsBool(value) or c.JS_IsBigInt(value) or c.JS_IsSymbol(value)) {
        const inspected = try @import("node_event_inspect.zig").inspect(engine, value, 0);
        defer engine.gpa.free(inspected);
        const kind: []const u8 = if (c.JS_IsString(value)) "string" else if (c.JS_IsNumber(value)) "number" else if (c.JS_IsBool(value)) "boolean" else if (c.JS_IsBigInt(value)) "bigint" else "symbol";
        return std.fmt.allocPrint(engine.gpa, "type {s} ({s})", .{ kind, inspected });
    }
    if (c.JS_IsFunction(engine.context, value)) {
        const name = try js.get(engine, value, "name");
        defer engine.freeValue(name);
        const text = try engine.toString(name);
        defer engine.gpa.free(text);
        return std.fmt.allocPrint(engine.gpa, "function {s}", .{text});
    }
    return engine.gpa.dupe(u8, if (c.JS_IsArray(value)) "an instance of Array" else "an instance of Object");
}
fn invalidValue(scope: *Scope, owner: c.JSValue, name: []const u8, value: c.JSValue) anyerror {
    const inspected = try @import("node_event_inspect.zig").inspect(scope.engine, value, 2);
    defer scope.engine.gpa.free(inspected);
    const message = try std.fmt.allocPrint(scope.engine.gpa, "The property '{s}' is invalid. Received {s}", .{ name, inspected });
    defer scope.engine.gpa.free(message);
    return throwError(scope.engine, owner, "RangeError", message, "ERR_INVALID_ARG_VALUE");
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = roots[0];
    const transformer = try objectInput(&scope, owner, if (args.len > 0) args[0] else c.pi_js_undefined(), "transformer", false);
    const writable_strategy = try objectInput(&scope, owner, if (args.len > 1) args[1] else c.pi_js_undefined(), "writableStrategy", true);
    const readable_strategy = try objectInput(&scope, owner, if (args.len > 2) args[2] else c.pi_js_undefined(), "readableStrategy", true);
    const readable_type = try scope.get(transformer, "readableType");
    const writable_type = try scope.get(transformer, "writableType");
    const start = try scope.get(transformer, "start");
    if (!c.JS_IsUndefined(readable_type)) return invalidValue(&scope, owner, "transformer.readableType", readable_type);
    if (!c.JS_IsUndefined(writable_type)) return invalidValue(&scope, owner, "transformer.writableType", writable_type);
    const rh = try optionalGet(&scope, readable_strategy, "highWaterMark");
    const rs = try optionalGet(&scope, readable_strategy, "size");
    const wh = try optionalGet(&scope, writable_strategy, "highWaterMark");
    const ws = try optionalGet(&scope, writable_strategy, "size");
    const normalized_rh = try highWaterMark(&scope, owner, rh, 0);
    if (!c.JS_IsUndefined(rs)) try validateCallback(&scope, owner, rs, "strategy.size");
    const normalized_wh = try highWaterMark(&scope, owner, wh, 1);
    if (!c.JS_IsUndefined(ws)) try validateCallback(&scope, owner, ws, "strategy.size");
    const prototype = try scope.get(target, "prototype");
    const actual_prototype = if (c.JS_IsObject(prototype)) prototype else try scope.get(owner, "streamPrototype");
    const stream = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, actual_prototype, try id(engine, owner, "streamClass"))));
    const state = try engine.gpa.create(State);
    state.engine = engine;
    state.backpressure = true;
    state.failed = false;
    for (&state.values) |*value| value.* = c.pi_js_undefined();
    _ = c.JS_SetOpaque(stream, state);
    state.set(.owner, owner);
    state.set(.transformer, transformer);
    try capability(state, .start_promise, .start_resolve, .start_reject);
    const sink = try nullObject(&scope);
    try scope.put(sink, "start", try callback(&scope, stream, .sink_start, "", 1, null));
    try scope.put(sink, "write", try callback(&scope, stream, .sink_write, "", 1, null));
    try scope.put(sink, "close", try callback(&scope, stream, .sink_close, "", 0, null));
    try scope.put(sink, "abort", try callback(&scope, stream, .sink_abort, "", 1, null));
    const w_strategy = try nullObject(&scope);
    try scope.put(w_strategy, "highWaterMark", normalized_wh);
    if (!c.JS_IsUndefined(ws)) try scope.put(w_strategy, "size", ws);
    const w_stream = try scope.own(try writable.createNative(engine, sink, w_strategy));
    state.set(.writable, w_stream);
    const source = try nullObject(&scope);
    try scope.put(source, "start", try callback(&scope, stream, .source_start, "", 1, null));
    try scope.put(source, "pull", try callback(&scope, stream, .source_pull, "", 0, null));
    try scope.put(source, "cancel", try callback(&scope, stream, .source_cancel, "", 1, null));
    const r_strategy = try nullObject(&scope);
    try scope.put(r_strategy, "highWaterMark", normalized_rh);
    if (!c.JS_IsUndefined(rs)) try scope.put(r_strategy, "size", rs);
    const r_stream = try scope.own(try readable.createDefaultNative(engine, source, r_strategy));
    state.set(.readable, r_stream);
    try pressure(state, true);
    const controller_prototype = try scope.get(owner, "controllerPrototype");
    const controller = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, controller_prototype, try id(engine, owner, "controllerClass"))));
    const controller_state = try engine.gpa.create(Controller);
    controller_state.* = .{ .engine = engine, .stream = c.JS_DupValue(engine.context, stream) };
    _ = c.JS_SetOpaque(controller, controller_state);
    state.set(.controller, controller);
    const transform = try scope.get(transformer, "transform");
    const flush = try scope.get(transformer, "flush");
    const cancel = try scope.get(transformer, "cancel");
    inline for (.{ Slot.transform, Slot.flush, Slot.cancel }, .{ transform, flush, cancel }, .{ "transformer.transform", "transformer.flush", "transformer.cancel" }) |slot, function, name| {
        if (scope.truthy(function)) {
            try validateCallback(&scope, owner, function, name);
            state.set(slot, function);
        }
    }
    if (!c.JS_IsUndefined(start)) {
        const result = try scope.call(start, transformer, &.{controller});
        try settle(state, .start_resolve, result);
    } else try settle(state, .start_resolve, c.pi_js_undefined());
    return c.JS_DupValue(engine.context, stream);
}
fn illegal(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return throwError(engine, roots[0], "TypeError", "Illegal constructor", "ERR_ILLEGAL_CONSTRUCTOR");
}
fn defineGetter(scope: *Scope, prototype: c.JSValue, owner: c.JSValue, name: [*:0]const u8, function_name: [*:0]const u8, op: Op) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    const function = try callback(scope, owner, op, function_name, 0, null);
    if (c.JS_DefinePropertyGetSet(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, function), c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(scope.engine);
}
fn tag(scope: *Scope, prototype: c.JSValue, name: []const u8) !void {
    const atom = try js.atom(scope.engine, try scope.get(try scope.global("Symbol"), "toStringTag"));
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, try scope.text(name)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(scope.engine);
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(module_key)) return;
    try readable.install(engine);
    try writable.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try nullObject(&scope);
    try scope.put(owner, "TypeError", try scope.global("TypeError"));
    try scope.put(owner, "RangeError", try scope.global("RangeError"));
    var stream_id: c.JSClassID = 0;
    var controller_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &stream_id);
    _ = c.JS_NewClassID(engine.runtime, &controller_id);
    const stream_definition: c.JSClassDef = .{ .class_name = "TransformStream", .finalizer = finalize, .gc_mark = mark };
    const controller_definition: c.JSClassDef = .{ .class_name = "TransformStreamDefaultController", .finalizer = finalizeController, .gc_mark = markController };
    if (c.JS_NewClass(engine.runtime, stream_id, &stream_definition) < 0 or c.JS_NewClass(engine.runtime, controller_id, &controller_definition) < 0) return error.OutOfMemory;
    try scope.put(owner, "streamClass", c.JS_NewUint32(engine.context, stream_id));
    try scope.put(owner, "controllerClass", c.JS_NewUint32(engine.context, controller_id));
    const prototype = try scope.object();
    const controller_prototype = try scope.object();
    try scope.put(owner, "controllerPrototype", controller_prototype);
    try scope.put(owner, "streamPrototype", prototype);
    const class = @import("native_class.zig");
    const constructor = try scope.own(try class.constructor(engine, "TransformStream", 0, prototype, construct, &.{owner}));
    const controller_constructor = try scope.own(try class.constructor(engine, "TransformStreamDefaultController", 0, controller_prototype, illegal, &.{owner}));
    try scope.put(owner, "constructor", constructor);
    try scope.put(owner, "controllerConstructor", controller_constructor);
    try defineGetter(&scope, prototype, owner, "readable", "get readable", .readable_get);
    try defineGetter(&scope, prototype, owner, "writable", "get writable", .writable_get);
    try defineGetter(&scope, controller_prototype, owner, "desiredSize", "get desiredSize", .desired_get);
    inline for (.{ "enqueue", "error", "terminate" }, .{ Op.enqueue, Op.error_stream, Op.terminate }) |name, op| {
        const function = try callback(&scope, owner, op, name, 0, null);
        if (c.JS_DefinePropertyValueStr(engine.context, controller_prototype, name, c.JS_DupValue(engine.context, function), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    try tag(&scope, prototype, "TransformStream");
    try tag(&scope, controller_prototype, "TransformStreamDefaultController");
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    inline for (.{ "TransformStream", "TransformStreamDefaultController" }, .{ constructor, controller_constructor }) |name, value| {
        if (c.JS_DefinePropertyValueStr(engine.context, global, name, c.JS_DupValue(engine.context, value), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    try engine.registerValueModule(module_key, owner);
}
/// Real native TransformStream construction for native consumers, using the
/// captured class identity instead of a guest replacement of the global.
pub fn createNative(engine: *em.Engine, transformer: c.JSValue, writable_strategy: c.JSValue, readable_strategy: c.JSValue) !c.JSValue {
    try install(engine);
    const owner = engine.native_module_values.get(module_key).?;
    const constructor = try js.get(engine, owner, "constructor");
    defer engine.freeValue(constructor);
    var args = [_]c.JSValue{ transformer, writable_strategy, readable_strategy };
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
}
/// Actual default identity transform for native Body/Request transfer consumers.
pub fn createIdentityNative(engine: *em.Engine) !c.JSValue {
    return createNative(engine, c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined());
}
/// Owned namespace with the original two captured constructors. Public global
/// and prototype.constructor mutations do not alter native module identities.
pub fn exports(engine: *em.Engine) !c.JSValue {
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = engine.native_module_values.get(module_key).?;
    const result = try scope.object();
    try scope.put(result, "TransformStream", try scope.get(owner, "constructor"));
    try scope.put(result, "TransformStreamDefaultController", try scope.get(owner, "controllerConstructor"));
    return c.JS_DupValue(engine.context, result);
}
