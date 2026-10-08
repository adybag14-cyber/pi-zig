//! Owner-only model operations. The transport boundary contains bytes and a
//! generation-bound lease; QuickJS values never leave the owning Engine.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const signals = @import("abort_signal.zig");
const c = engine_mod.c;
pub const Lease = struct { generation: u64, runtime_id: u64 };
pub const Operation = enum { query, classify, generate_images };
pub const Control = struct {
    request_id: u64 = 0,
    abort_flag: *const std.atomic.Value(bool),
    /// Absolute std.Io.Clock.awake milliseconds in the owner process.
    deadline_ms: ?i64 = null,
};
const Status = enum { complete, failed, aborted, timed_out, retired };
const Frame = struct {
    lease: Lease,
    control: Control,
    signal: c.JSValue,
    status: Status = .complete,
    previous_context: ?*anyopaque,
    previous_pump: ?*const fn (*engine_mod.Engine) anyerror!bool,
};
fn registry(engine: *engine_mod.Engine) !c.JSValue {
    if (engine.native_sdk_model_bridge_registry) |value| return c.JS_DupValue(engine.context, value);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "live", try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map"));
    try sdk.put(engine, result, "retired", try @import("native_sdk_auth_snapshot.zig").collection(engine, "Set"));
    engine.native_sdk_model_bridge_registry = c.JS_DupValue(engine.context, result);
    return result;
}
fn key(engine: *engine_mod.Engine, lease: Lease) !c.JSValue {
    const text = try std.fmt.allocPrint(engine.gpa, "{d}:{d}", .{ lease.generation, lease.runtime_id });
    defer engine.gpa.free(text);
    return sdk.text(engine, text);
}
pub fn admit(engine: *engine_mod.Engine, runtime: c.JSValue, generation: u64) !Lease {
    const owner = try sdk.state(engine, runtime);
    if (owner.kind != .model_runtime or generation == 0 or owner.runtime_id == 0) return error.InvalidNativeSDKModelLease;
    const lease: Lease = .{ .generation = generation, .runtime_id = owner.runtime_id };
    const stored = try registry(engine);
    defer engine.freeValue(stored);
    const id = try key(engine, lease);
    defer engine.freeValue(id);
    const retired = try sdk.get(engine, stored, "retired");
    defer engine.freeValue(retired);
    const old = try sdk.invoke(engine, retired, "has", &.{id});
    defer engine.freeValue(old);
    if (c.JS_ToBool(engine.context, old) == 1) return error.RetiredNativeSDKModelLease;
    const live = try sdk.get(engine, stored, "live");
    defer engine.freeValue(live);
    const added = try sdk.invoke(engine, live, "set", &.{ id, runtime });
    engine.freeValue(added);
    return lease;
}
pub fn retire(engine: *engine_mod.Engine, lease: Lease) !void {
    if (lease.generation == 0 or lease.runtime_id == 0) return error.InvalidNativeSDKModelLease;
    const stored = try registry(engine);
    defer engine.freeValue(stored);
    const id = try key(engine, lease);
    defer engine.freeValue(id);
    const retired = try sdk.get(engine, stored, "retired");
    defer engine.freeValue(retired);
    const marked = try sdk.invoke(engine, retired, "add", &.{id});
    engine.freeValue(marked);
    const live = try sdk.get(engine, stored, "live");
    defer engine.freeValue(live);
    const deleted = try sdk.invoke(engine, live, "delete", &.{id});
    engine.freeValue(deleted);
}
fn lookup(engine: *engine_mod.Engine, lease: Lease) !c.JSValue {
    if (lease.generation == 0 or lease.runtime_id == 0) return error.InvalidNativeSDKModelLease;
    const stored = try registry(engine);
    defer engine.freeValue(stored);
    const live = try sdk.get(engine, stored, "live");
    defer engine.freeValue(live);
    const id = try key(engine, lease);
    defer engine.freeValue(id);
    return sdk.invoke(engine, live, "get", &.{id});
}
fn check(engine: *engine_mod.Engine, frame: *Frame) !void {
    if (frame.status != .complete) return error.NativeSDKModelOperationStopped;
    const runtime = try lookup(engine, frame.lease);
    defer engine.freeValue(runtime);
    if (!c.JS_IsObject(runtime)) frame.status = .retired else if (frame.control.abort_flag.load(.acquire)) frame.status = .aborted else if (frame.control.deadline_ms) |deadline| {
        const io = engine.native_io orelse return error.NativeSDKModelBridgeRequiresIO;
        if (std.Io.Clock.awake.now(io).toMilliseconds() >= deadline) frame.status = .timed_out;
    }
    if (frame.status == .complete) return;
    const reason = try sdk.text(engine, switch (frame.status) {
        .retired => "SDK model runtime lease retired",
        .aborted => "SDK model operation aborted",
        .timed_out => "SDK model operation deadline exceeded",
        else => unreachable,
    });
    defer engine.freeValue(reason);
    try signals.abort(engine, frame.signal, reason);
    return error.NativeSDKModelOperationStopped;
}
fn pump(engine: *engine_mod.Engine) !bool {
    const frame: *Frame = @ptrCast(@alignCast(engine.host_control_context orelse return error.NativeSDKModelBridgeControlMissing));
    var progressed = false;
    if (frame.previous_pump) |previous| {
        engine.host_control_context = frame.previous_context;
        engine.host_control_pump = previous;
        defer {
            engine.host_control_context = frame;
            engine.host_control_pump = pump;
        }
        progressed = try previous(engine);
    }
    try check(engine, frame);
    return progressed;
}
fn ignored(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn observe(engine: *engine_mod.Engine, value: c.JSValue) !void {
    if (c.JS_PromiseState(engine.context, value) == c.JS_PROMISE_FULFILLED and !c.JS_IsObject(value)) return;
    const promise = try sdk.promise(engine, value);
    defer engine.freeValue(promise);
    const handler = try engine.checked(c.JS_NewCFunction(engine.context, ignored, "observeModelBridgeOperation", 1));
    defer engine.freeValue(handler);
    const observed = try sdk.invoke(engine, promise, "catch", &.{handler});
    engine.freeValue(observed);
}
fn query(engine: *engine_mod.Engine, runtime: c.JSValue, request: c.JSValue, signal: c.JSValue) !c.JSValue {
    const method_value = try sdk.get(engine, request, "method");
    defer engine.freeValue(method_value);
    const method = if (c.JS_IsUndefined(method_value)) try engine.gpa.dupe(u8, "getAllModels") else try engine.toString(method_value);
    defer engine.gpa.free(method);
    var allowed = false;
    inline for (.{ "getModels", "getAllModels", "getModel", "getModelOfType", "getModelsOfType", "getAvailable", "getAllAvailable", "getAvailableOfType" }) |name| allowed = allowed or std.mem.eql(u8, method, name);
    if (!allowed) return error.NativeSDKModelBridgeQueryUnavailable;
    const raw_args = try sdk.get(engine, request, "args");
    defer engine.freeValue(raw_args);
    if (!c.JS_IsUndefined(raw_args) and !c.JS_IsArray(raw_args)) return error.InvalidNativeSDKModelRequest;
    var args: [4]c.JSValue = .{c.pi_js_undefined()} ** 4;
    defer for (args) |value| engine.freeValue(value);
    var count: usize = if (c.JS_IsArray(raw_args)) try sdk.length(engine, raw_args) else 0;
    if (count > args.len) return error.InvalidNativeSDKModelRequest;
    for (0..count) |index| args[index] = try engine.checked(c.JS_GetPropertyUint32(engine.context, raw_args, @intCast(index)));
    if (std.mem.eql(u8, method, "getAvailable") or std.mem.eql(u8, method, "getAllAvailable") or std.mem.eql(u8, method, "getAvailableOfType")) {
        const index: usize = if (std.mem.eql(u8, method, "getAvailableOfType")) 2 else 1;
        const options = prepared: {
            const value = try sdk.object(engine);
            errdefer engine.freeValue(value);
            try models.copy(engine, value, args[index]);
            try sdk.put(engine, value, "signal", c.JS_DupValue(engine.context, signal));
            break :prepared value;
        };
        engine.freeValue(args[index]);
        args[index] = options;
        count = @max(count, index + 1);
    }
    const name = try engine.gpa.dupeZ(u8, method);
    defer engine.gpa.free(name);
    return sdk.invoke(engine, runtime, name, args[0..count]);
}
fn typed(engine: *engine_mod.Engine, runtime: c.JSValue, operation: Operation, request: c.JSValue, signal: c.JSValue) !c.JSValue {
    const input = try sdk.get(engine, request, "model");
    defer engine.freeValue(input);
    if (!c.JS_IsObject(input)) return error.InvalidNativeSDKModelRequest;
    const provider = try sdk.get(engine, input, "provider");
    defer engine.freeValue(provider);
    const id = try sdk.get(engine, input, "id");
    defer engine.freeValue(id);
    if (!c.JS_IsString(provider) or !c.JS_IsString(id)) return error.InvalidNativeSDKModelRequest;
    const kind = try sdk.text(engine, if (operation == .classify) "classifier" else "image");
    defer engine.freeValue(kind);
    const model = try sdk.invoke(engine, runtime, "getModelOfType", &.{ kind, provider, id });
    defer engine.freeValue(model);
    if (!c.JS_IsObject(model)) return error.NativeSDKModelBridgeUnknownModel;
    const context = try sdk.get(engine, request, "context");
    defer engine.freeValue(context);
    const original_options = try sdk.get(engine, request, "options");
    defer engine.freeValue(original_options);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try models.copy(engine, options, original_options);
    try sdk.put(engine, options, "signal", c.JS_DupValue(engine.context, signal));
    return sdk.invoke(engine, runtime, if (operation == .classify) "classify" else "generateImages", &.{ model, context, options });
}
fn envelope(gpa: std.mem.Allocator, lease: Lease, control: Control, status: Status, payload: []const u8, failed: bool, undefined_value: bool) ![]u8 {
    return std.fmt.allocPrint(gpa, "{{\"version\":1,\"status\":\"{s}\",\"requestId\":{d},\"generation\":{d},\"runtimeId\":{d},\"undefined\":{s},\"{s}\":{s}}}", .{ @tagName(status), control.request_id, lease.generation, lease.runtime_id, if (undefined_value) "true" else "false", if (failed) "error" else "result", payload });
}
fn errorJson(engine: *engine_mod.Engine, err: anyerror) ![]u8 {
    const detail = try sdk.object(engine);
    defer engine.freeValue(detail);
    if (err == error.JavaScriptException and engine.captured_exception != null) {
        const failure = engine.captured_exception.?;
        if (c.JS_IsObject(failure)) {
            inline for (.{ "name", "message", "code" }) |field| try sdk.put(engine, detail, field, try sdk.get(engine, failure, field));
        } else try sdk.put(engine, detail, "message", c.JS_DupValue(engine.context, failure));
    } else {
        try sdk.put(engine, detail, "name", try sdk.text(engine, "Error"));
        try sdk.put(engine, detail, "message", try sdk.text(engine, @errorName(err)));
    }
    return engine.stringify(detail);
}
/// Returns a v1 JSON envelope. Query values/typed result payloads are unchanged;
/// failures expose only name/message/code. Native validation/OOM errors return
/// through the Zig error union. The caller owns the returned bytes with gpa.
pub fn dispatchJson(engine: *engine_mod.Engine, gpa: std.mem.Allocator, lease: Lease, operation: Operation, request_json: []const u8, control: Control) ![]u8 {
    if (request_json.len > 8 * 1024 * 1024) return error.NativeSDKModelBridgeRequestLimit;
    const runtime = try lookup(engine, lease);
    defer engine.freeValue(runtime);
    if (!c.JS_IsObject(runtime)) return error.RetiredNativeSDKModelLease;
    const request = try sdk.jsonObject(engine, request_json);
    defer engine.freeValue(request);
    if (!c.JS_IsObject(request) or c.JS_IsArray(request)) return error.InvalidNativeSDKModelRequest;
    const signal = try signals.create(engine);
    defer engine.freeValue(signal);
    var frame: Frame = .{ .lease = lease, .control = control, .signal = signal, .previous_context = engine.host_control_context, .previous_pump = engine.host_control_pump };
    const old_timeout = engine.options.host_await_timeout_ms;
    const old_deadline = engine.host_await_deadline_ms;
    defer {
        engine.host_control_context = frame.previous_context;
        engine.host_control_pump = frame.previous_pump;
        engine.options.host_await_timeout_ms = old_timeout;
        engine.host_await_deadline_ms = old_deadline;
    }
    engine.host_control_context = &frame;
    engine.host_control_pump = pump;
    // The operation's explicit absolute deadline cannot be extended by UI work.
    engine.options.host_await_timeout_ms = 0;
    engine.host_await_deadline_ms = null;
    check(engine, &frame) catch |err| {
        if (err != error.NativeSDKModelOperationStopped) return err;
        return envelope(gpa, lease, control, frame.status, "null", false, false);
    };
    const pending = (if (operation == .query) query(engine, runtime, request, signal) else typed(engine, runtime, operation, request, signal)) catch |err| {
        if (err == error.OutOfMemory) return err;
        const text = try errorJson(engine, err);
        defer engine.gpa.free(text);
        return envelope(gpa, lease, control, if (frame.status != .complete) frame.status else .failed, text, true, false);
    };
    defer engine.freeValue(pending);
    try observe(engine, pending);
    const value = engine.awaitValue(pending) catch |err| {
        if (err == error.OutOfMemory) return err;
        check(engine, &frame) catch |check_error| if (check_error != error.NativeSDKModelOperationStopped) return check_error;
        const text = try errorJson(engine, err);
        defer engine.gpa.free(text);
        return envelope(gpa, lease, control, if (frame.status != .complete) frame.status else .failed, text, true, false);
    };
    defer engine.freeValue(value);
    check(engine, &frame) catch |err| {
        if (err != error.NativeSDKModelOperationStopped) return err;
        return envelope(gpa, lease, control, frame.status, "null", false, false);
    };
    const text = if (c.JS_IsUndefined(value)) try engine.gpa.dupe(u8, "null") else try engine.stringify(value);
    defer engine.gpa.free(text);
    return envelope(gpa, lease, control, .complete, text, false, c.JS_IsUndefined(value));
}
