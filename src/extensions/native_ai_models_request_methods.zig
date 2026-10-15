//! Actual ModelsImpl request methods. Receiver/provider calls remain live;
//! only lexical Source imports are captured in the GC-visible owner graph.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const flow = @import("native_agent_async.zig");
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
    };
    const result = try functions.createMethod(engine, @tagName(kind), 3, Handler.call, &.{imports});
    errdefer engine.freeValue(result);
    if (kind != .stream and kind != .streamSimple and kind != .streamDeferred) {
        const prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
        defer engine.freeValue(prototype);
        if (c.JS_SetPrototype(engine.context, result, prototype) < 0) return v.js.capture(engine);
    }
    return result;
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return s.call(try s.get(imports, name), c.pi_js_undefined(), args);
}
fn wrapReturn(engine: *v.em.Engine, receiver: c.JSValue, method: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const stream = try s.invoke(receiver, method, &.{ arg(args, 0), arg(args, 1), arg(args, 2) });
    return @import("native_durable.zig").resolvedPromise(engine, try s.invoke(stream, "result", &.{}));
}
pub fn invoke(engine: *v.em.Engine, comptime kind: Kind, receiver: c.JSValue, args: []const c.JSValue, imports: c.JSValue) !c.JSValue {
    if (kind == .complete or kind == .completeSimple or kind == .fetchDeferred) {
        return wrapReturn(engine, receiver, switch (kind) {
            .complete => "stream",
            .completeSimple => "streamSimple",
            .fetchDeferred => "streamDeferred",
            else => unreachable,
        }, args) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
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
    if (kind == .stream or kind == .streamSimple or kind == .streamDeferred) {
        const Setup = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return start(host, roots[0]);
            }
        };
        const setup = try s.own(try @import("native_ai_auth_helpers.zig").asyncArrow(engine, "", 0, Setup.call, &.{state}));
        return c.JS_DupValue(engine.context, try imported(&s, imports, "lazyStream", &.{ model, setup }));
    }
    return start(engine, state);
}
fn mode(s: *Scope, owner: c.JSValue) !Kind {
    var value: i32 = 0;
    if (c.JS_ToInt32(s.engine.context, &value, try s.get(owner, "kind")) < 0) return v.js.capture(s.engine);
    return @enumFromInt(value);
}
fn start(engine: *v.em.Engine, state: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try s.put(pending.owner, "state", state);
    begin(&s, pending.owner, state) catch |err| try failed(&s, pending.owner, state, try s.own(flow.reason(engine, err)));
    return pending.promise;
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
fn begin(s: *Scope, owner: c.JSValue, state: c.JSValue) !void {
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
    try s.put(owner, "provider", provider);
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
    return flow.wait(continued, s.engine, owner, result, @intFromEnum(Stage.auth));
}
fn failed(s: *Scope, owner: c.JSValue, state: c.JSValue, reason: c.JSValue) !void {
    const kind = try mode(s, state);
    if (kind != .generateImages and kind != .classify) return flow.settle(s.engine, owner, true, reason);
    const imports = try s.get(state, "imports");
    const error_result = try s.get(imports, if (kind == .generateImages) "imageErrorResult" else "classifierErrorResult");
    const model = try s.get(state, "model");
    const options = try s.get(state, "options");
    const signal = try v.optional(s, options, "signal");
    const aborted = try v.optional(s, signal, "aborted");
    const result = s.call(error_result, c.pi_js_undefined(), &.{ model, reason, aborted }) catch |err| return flow.rejectError(s.engine, owner, err);
    return flow.settle(s.engine, owner, false, result);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.get(owner, "state");
    if (rejected) return failed(&s, owner, state, value);
    advance(&s, owner, state, value, @enumFromInt(raw)) catch |err| try failed(&s, owner, state, try s.own(flow.reason(engine, err)));
}
fn advance(s: *Scope, owner: c.JSValue, state: c.JSValue, value: c.JSValue, stage: Stage) !void {
    const kind = try mode(s, state);
    if (stage == .operation) return flow.settle(s.engine, owner, false, if (kind == .cancelDeferred) c.pi_js_undefined() else value);
    const request_model = try s.get(value, "requestModel");
    const request_options = try s.get(value, "requestOptions");
    const provider = try s.get(owner, "provider");
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
    if (kind == .stream or kind == .streamSimple or kind == .streamDeferred) return flow.settle(s.engine, owner, false, pending);
    return flow.wait(continued, s.engine, owner, pending, @intFromEnum(Stage.operation));
}
