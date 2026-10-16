//! Source-only actual Models requests using the proposed genuine async ABI.
//! One VM outer Promise and direct resumable actions preserve each real Await.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const async_functions = @import("native_async_function.zig");
pub const Kind = enum(c_int) { stream, complete, streamSimple, completeSimple, streamDeferred, fetchDeferred, cancelDeferred, generateImages, classify };
const Stage = enum(c_int) { auth, operation };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
pub fn create(engine: *v.em.Engine, comptime kind: Kind, imports: c.JSValue) !c.JSValue {
    const Handler = struct {
        fn call(host: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return invoke(host, kind, receiver, args, roots[0]);
        }
        fn body(host: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: async_functions.Completion, input: c.JSValue) !async_functions.Action {
            if (completion == .start) async_functions.replaceState(host, slot, try invoke(host, kind, receiver, args, roots[0]));
            return resumeBody(host, slot.*, completion, input);
        }
    };
    if (kind == .stream or kind == .streamSimple or kind == .streamDeferred) return functions.createMethod(engine, @tagName(kind), 3, Handler.call, &.{imports});
    if (kind == .complete or kind == .completeSimple or kind == .fetchDeferred) return async_functions.create(engine, @tagName(kind), 3, Handler.call, &.{imports});
    return async_functions.createResumable(engine, @tagName(kind), 3, Handler.body, &.{imports});
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.call(try s.get(imports, name), c.pi_js_undefined(), args);
}
fn wrapReturn(engine: *v.em.Engine, receiver: c.JSValue, method: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stream = try s.invoke(receiver, method, &.{ arg(args, 0), arg(args, 1), arg(args, 2) });
    // The genuine async function adopts this raw expression through its one
    // existing outer Promise; no second resolvedPromise wrapper is created.
    return c.JS_DupValue(engine.context, try s.invoke(stream, "result", &.{}));
}
pub fn invoke(engine: *v.em.Engine, comptime kind: Kind, receiver: c.JSValue, args: []const c.JSValue, imports: c.JSValue) !c.JSValue {
    if (kind == .complete or kind == .completeSimple or kind == .fetchDeferred) {
        return wrapReturn(engine, receiver, switch (kind) {
            .complete => "stream",
            .completeSimple => "streamSimple",
            .fetchDeferred => "streamDeferred",
            else => unreachable,
        }, args);
    }
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const model = arg(args, 0);
    const context = if (kind == .stream or kind == .streamSimple) try imported(&s, imports, "normalizeContext", &.{arg(args, 1)}) else arg(args, 1);
    const state = try s.object();
    try s.put(state, "receiver", receiver);
    try s.put(state, "imports", imports);
    try s.put(state, "model", model);
    try s.put(state, "context", context);
    try s.put(state, "options", arg(args, 2));
    try s.put(state, "kind", c.JS_NewInt32(engine.context, @intFromEnum(kind)));
    try s.put(state, "nativeGeneration", try s.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
    if (kind == .stream or kind == .streamSimple or kind == .streamDeferred) {
        const Setup = struct {
            fn body(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: async_functions.Completion, input: c.JSValue) !async_functions.Action {
                if (completion == .start) async_functions.replaceState(host, slot, c.JS_DupValue(host.context, roots[0]));
                return resumeBody(host, slot.*, completion, input);
            }
        };
        const setup = try s.own(try async_functions.createResumableArrow(engine, "", 0, Setup.body, &.{state}, receiver));
        return c.JS_DupValue(engine.context, try imported(&s, imports, "lazyStream", &.{ model, setup }));
    }
    // Async Body owns this invocation state; no private outer promise exists.
    return c.JS_DupValue(engine.context, state);
}
fn mode(s: *Scope, owner: c.JSValue) !Kind {
    var value: i32 = 0;
    if (c.JS_ToInt32(s.engine.context, &value, try s.get(owner, "kind")) < 0) return v.js.capture(s.engine);
    return @enumFromInt(value);
}
fn resumeBody(engine: *v.em.Engine, state: c.JSValue, completion: async_functions.Completion, input: c.JSValue) !async_functions.Action {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (completion == .rejected) return failed(&s, state, input);
    const generation = engine.native_allocation_generation;
    return (if (completion == .start) begin(&s, state) else blk: {
        var raw: i32 = 0;
        if (c.JS_ToInt32(engine.context, &raw, try s.get(state, "stage")) < 0) return v.js.capture(engine);
        break :blk advance(&s, state, input, @enumFromInt(raw));
    }) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        return failed(&s, state, try s.own(@import("native_agent_async.zig").reason(engine, err)));
    };
}
fn unsupported(s: *Scope, imports: c.JSValue, model: c.JSValue, suffix: []const u8) anyerror {
    const constructor = s.get(imports, "ModelsError") catch |err| return err;
    const provider = s.own(s.engine.checked(c.JS_ToString(s.engine.context, s.get(model, "provider") catch |err| return err)) catch |err| return err) catch |err| return err;
    const message = s.concat(s.concat(s.text("Provider ") catch |err| return err, provider) catch |err| return err, s.text(suffix) catch |err| return err) catch |err| return err;
    var args = [_]c.JSValue{ s.text("provider") catch |err| return err, message };
    const reason = s.own(s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, args.len, &args)) catch |err| return err) catch |err| return err;
    _ = s.engine.checked(c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn begin(s: *Scope, state: c.JSValue) !async_functions.Action {
    const kind = try mode(s, state);
    const receiver = try s.get(state, "receiver");
    const imports = try s.get(state, "imports");
    const model = try s.get(state, "model");
    if (kind == .generateImages) _ = try imported(s, imports, "assertImageModel", &.{model});
    if (kind == .classify) {
        _ = try imported(s, imports, "assertClassifierModel", &.{model});
        _ = try imported(s, imports, "assertClassifierInputSupported", &.{ model, try s.get(state, "context") });
    }
    const provider = try s.invoke(receiver, if (kind == .generateImages or kind == .classify) "requireProvider" else "requireChatProvider", &.{model});
    try s.put(state, "provider", provider);
    if (kind == .streamDeferred or kind == .cancelDeferred or kind == .generateImages or kind == .classify) {
        const method = switch (kind) {
            .streamDeferred => "fetchDeferred",
            .cancelDeferred => "cancelDeferred",
            .generateImages => "generateImages",
            .classify => "classify",
            else => unreachable,
        };
        if (!s.truthy(try s.get(provider, method))) return unsupported(s, imports, model, switch (kind) {
            .streamDeferred, .cancelDeferred => " does not support deferred responses",
            .generateImages => " does not support image generation",
            .classify => " does not support classification",
            else => unreachable,
        });
    }
    const apply = try s.get(receiver, "applyAuth");
    const result = try s.call(apply, receiver, &.{ model, try s.get(state, "options") });
    try s.put(state, "stage", c.JS_NewInt32(s.engine.context, @intFromEnum(Stage.auth)));
    return .{ .awaited = c.JS_DupValue(s.engine.context, result) };
}
fn failed(s: *Scope, state: c.JSValue, reason: c.JSValue) !async_functions.Action {
    const kind = try mode(s, state);
    const tagged = c.pi_js_native_allocation_error_generation(reason);
    if (tagged != 0) {
        var generation: u64 = 0;
        if (c.JS_ToBigUint64(s.engine.context, &generation, try s.get(state, "nativeGeneration")) < 0) return v.js.capture(s.engine);
        const distance = tagged -% generation;
        if (distance != 0 and distance <= s.engine.native_allocation_generation -% generation) return error.OutOfMemory;
    }
    if (kind != .generateImages and kind != .classify) return .{ .thrown = c.JS_DupValue(s.engine.context, reason) };
    const imports = try s.get(state, "imports");
    const error_result = try s.get(imports, if (kind == .generateImages) "imageErrorResult" else "classifierErrorResult");
    const model = try s.get(state, "model");
    const options = try s.get(state, "options");
    const signal = try v.optional(s, options, "signal");
    const aborted = try v.optional(s, signal, "aborted");
    const result = try s.call(error_result, c.pi_js_undefined(), &.{ model, reason, aborted });
    return .{ .returned = c.JS_DupValue(s.engine.context, result) };
}
fn advance(s: *Scope, state: c.JSValue, value: c.JSValue, stage: Stage) !async_functions.Action {
    const kind = try mode(s, state);
    if (stage == .operation) return .{ .returned = c.JS_DupValue(s.engine.context, if (kind == .cancelDeferred) c.pi_js_undefined() else value) };
    const request_model = try s.get(value, "requestModel");
    const request_options = try s.get(value, "requestOptions");
    const provider = try s.get(state, "provider");
    const callback = try s.get(provider, switch (kind) {
        .stream => "stream",
        .streamSimple => "streamSimple",
        .streamDeferred => "fetchDeferred",
        .cancelDeferred => "cancelDeferred",
        .generateImages => "generateImages",
        .classify => "classify",
        else => unreachable,
    });
    const pending = try s.call(callback, provider, &.{ request_model, try s.get(state, "context"), request_options });
    if (kind == .stream or kind == .streamSimple or kind == .streamDeferred) return .{ .returned = c.JS_DupValue(s.engine.context, pending) };
    try s.put(state, "stage", c.JS_NewInt32(s.engine.context, @intFromEnum(Stage.operation)));
    return .{ .awaited = c.JS_DupValue(s.engine.context, pending) };
}
