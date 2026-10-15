//! Native fetch facade: actual Request/Response/Headers and shared HTTP worker.
//! Source-only. Redirect metadata, custom methods and duplex upload need the
//! transport owner's remaining seams; no second worker or substitute Response.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const request_api = @import("native_web_request.zig");
const response_api = @import("native_web_response.zig");
const body = @import("native_web_body.zig");
const http = @import("native_ai_http.zig");
const flow = @import("native_agent_async.zig");
const c = em.c;
const key = "\x00native-web-Fetch";
pub const Options = struct { headers_timeout_ms: ?u64 = 300_000 };
fn latin1(scope: *Scope, value: c.JSValue) ![]u8 {
    const units = try @import("native_utf16.zig").unitsAlloc(scope.engine, value);
    defer scope.engine.gpa.free(units);
    const output = try scope.engine.gpa.alloc(u8, units.len);
    errdefer scope.engine.gpa.free(output);
    for (units, output) |unit, *byte| {
        if (unit > 255) return error.NativeWebHeaderByteStringRequired;
        byte.* = @intCast(unit);
    }
    return output;
}
fn failed(scope: *Scope, reason: c.JSValue) !c.JSValue {
    const options = try scope.object();
    try scope.set(options, "cause", reason);
    return scope.own(try js.builtin(scope.engine, "TypeError", &.{ try scope.text("fetch failed"), options }));
}
fn reject(scope: *Scope, owner: c.JSValue, reason: c.JSValue, network: bool) !void {
    const request = try scope.get(owner, "request");
    if (!c.JS_IsUndefined(request)) {
        const view = try request_api.view(scope, request);
        if (scope.truthy(try scope.get(view.signal, "aborted"))) return flow.settle(scope.engine, owner, true, try scope.get(view.signal, "reason"));
    }
    try flow.settle(scope.engine, owner, true, if (network) try failed(scope, reason) else reason);
}
fn cleanupTransport(scope: *Scope, owner: c.JSValue) void {
    const transport = scope.get(owner, "transport") catch return;
    if (c.JS_IsUndefined(transport)) return;
    const result = scope.invoke(transport, "cancel", &.{}) catch return;
    if (c.JS_PromiseState(scope.engine.context, result) >= 0) c.JS_PromiseMarkAsHandled(scope.engine.context, result);
}
fn open(scope: *Scope, owner: c.JSValue, upload: c.JSValue) !void {
    const view = try request_api.view(scope, try scope.get(owner, "request"));
    if (scope.truthy(try scope.get(view.signal, "aborted"))) return reject(scope, owner, try scope.get(view.signal, "reason"), false);
    if (!c.JS_IsNull(view.dispatcher) and !c.JS_IsUndefined(view.dispatcher)) return error.NativeWebDispatcherTransportUnavailable;
    const url = try scope.engine.toString(view.url);
    defer scope.engine.gpa.free(url);
    const method = try scope.engine.toString(view.method);
    defer scope.engine.gpa.free(method);
    const native_method = std.meta.stringToEnum(std.http.Method, method) orelse return error.NativeWebCustomMethodTransportUnavailable;
    var headers: std.ArrayList(std.http.Header) = .empty;
    defer {
        for (headers.items) |header| {
            scope.engine.gpa.free(header.name);
            scope.engine.gpa.free(header.value);
        }
        headers.deinit(scope.engine.gpa);
    }
    const iterator = try scope.invoke(view.headers, "entries", &.{});
    while (true) {
        const row = try scope.invoke(iterator, "next", &.{});
        if (scope.truthy(try scope.get(row, "done"))) break;
        const pair = try scope.get(row, "value");
        const name = try latin1(scope, try @import("native_headers_webidl.zig").index(scope, pair, 0));
        errdefer scope.engine.gpa.free(name);
        const value = try latin1(scope, try @import("native_headers_webidl.zig").index(scope, pair, 1));
        errdefer scope.engine.gpa.free(value);
        try headers.append(scope.engine.gpa, .{ .name = name, .value = value });
    }
    var size: usize = 0;
    const bytes = c.JS_GetUint8Array(scope.engine.context, &size, upload);
    if (bytes == null and c.JS_HasException(scope.engine.context)) return js.capture(scope.engine);
    if (size != 0 and !native_method.requestHasBody()) return error.NativeWebMethodBodyTransportUnavailable;
    var timeout: i64 = -1;
    if (c.JS_ToInt64(scope.engine.context, &timeout, try scope.get(owner, "headers_timeout")) < 0) return js.capture(scope.engine);
    const transport = try scope.own(try http.openWithOptions(scope.engine, .{ .url = url, .payload = if (size == 0) &.{} else bytes[0..size], .headers = headers.items, .method = native_method, .framing = .bytes, .stream_error_bytes = true, .headers_timeout_only = true, .timeout_ms = if (timeout < 0) null else @intCast(timeout) }, view.signal, .{ .raw_header_pairs = true }));
    try scope.set(owner, "transport", transport);
    try flow.wait(continued, scope.engine, owner, try scope.get(transport, "ready"), 1);
}
fn continued(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        cleanupTransport(&scope, owner);
        return reject(&scope, owner, value, true);
    }
    if (stage == 0) return open(&scope, owner, value);
    const view = try request_api.view(&scope, try scope.get(owner, "request"));
    if (scope.truthy(try scope.get(view.signal, "aborted"))) {
        cleanupTransport(&scope, owner);
        return reject(&scope, owner, try scope.get(view.signal, "reason"), false);
    }
    var status: u32 = 0;
    if (c.JS_ToUint32(engine.context, &status, try scope.get(value, "status")) < 0) return js.capture(engine);
    if (status > 65535) return error.NativeWebTransportStatusInvalid;
    const transport = try scope.get(owner, "transport");
    const empty = status == 101 or status == 204 or status == 205 or status == 304 or scope.equal(view.method, try scope.text("HEAD"));
    const stream = if (empty) c.pi_js_null() else try scope.own(try @import("native_web_byte_source.zig").fromEvents(engine, try scope.get(transport, "events"), .{ .cancel = try scope.get(transport, "cancel"), .signal = view.signal }));
    if (empty) cleanupTransport(&scope, owner);
    const response = response_api.fromTransport(engine, .{ .body = stream, .status = @intCast(status), .status_text = try scope.get(value, "statusText"), .headers = try scope.get(value, "rawHeaders"), .url = view.url }) catch |err| {
        cleanupTransport(&scope, owner);
        return err;
    };
    defer engine.freeValue(response);
    try flow.settle(engine, owner, false, response);
}
/// Returns an owned Promise of an actual native Response. The internal owner
/// retains Request and worker handoff until the real response-head transition.
pub fn fetch(engine: *em.Engine, input: c.JSValue, init: c.JSValue, options: Options) !c.JSValue {
    const captured = engine.native_module_values.get(key) orelse return error.NativeWebFetchUnavailable;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, captured);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try scope.set(pending.owner, "headers_timeout", c.JS_NewInt64(engine.context, if (options.headers_timeout_ms) |timeout| @intCast(@min(timeout, std.math.maxInt(i64))) else -1));
    var args = [_]c.JSValue{ input, init };
    const request = scope.own(engine.checked(c.JS_CallConstructor(engine.context, try scope.get(captured, "Request"), args.len, &args)) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    }) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    try scope.set(pending.owner, "request", request);
    const view = try request_api.view(&scope, request);
    if (scope.truthy(try scope.get(view.signal, "aborted"))) {
        const reason = try scope.get(view.signal, "reason");
        if (view.payload) |payload| {
            const canceled = try scope.invoke(payload.stream, "cancel", &.{reason});
            if (c.JS_PromiseState(engine.context, canceled) >= 0) c.JS_PromiseMarkAsHandled(engine.context, canceled);
        }
        try reject(&scope, pending.owner, reason, false);
        return pending.promise;
    }
    const url_text = try engine.toString(view.url);
    defer engine.gpa.free(url_text);
    if (std.mem.startsWith(u8, url_text, "data:")) {
        const data = @import("native_web_data_url.zig").process(&scope, view.url) catch |err| {
            try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        };
        if (data) |decoded| {
            const pair = try scope.array();
            try scope.index(pair, 0, try scope.text("content-type"));
            try scope.index(pair, 1, decoded.mime_type);
            const headers = try scope.array();
            try scope.index(headers, 0, pair);
            const response = response_api.fromTransport(engine, .{ .body = decoded.bytes, .status = 200, .status_text = try scope.text("OK"), .headers = headers, .url = view.url }) catch |err| {
                try flow.rejectError(engine, pending.owner, err);
                return pending.promise;
            };
            defer engine.freeValue(response);
            try flow.settle(engine, pending.owner, false, response);
        } else {
            const reason = try scope.own(try js.builtin(engine, "Error", &.{try scope.text("failed to fetch the data URL")}));
            try reject(&scope, pending.owner, reason, true);
        }
        return pending.promise;
    }
    if (view.payload) |payload| {
        if (c.JS_IsNull(payload.source)) {
            try flow.rejectError(engine, pending.owner, error.NativeWebStreamingUploadUnavailable);
            return pending.promise;
        }
        const bytes = try scope.own(try body.consume(engine, payload, .bytes, c.pi_js_null()));
        try flow.wait(continued, engine, pending.owner, bytes, 0);
    } else {
        const empty = try scope.own(try engine.checked(c.JS_NewUint8ArrayCopy(engine.context, null, 0)));
        open(&scope, pending.owner, empty) catch |err| try flow.rejectError(engine, pending.owner, err);
    }
    return pending.promise;
}
fn callback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    return fetch(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined(), .{});
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(key)) return;
    try request_api.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try response_api.install(engine, try @import("native_web_platform.zig").prepare(&scope));
    const captured = try scope.object();
    try scope.set(captured, "Request", try scope.global("Request"));
    const function = try scope.own(try @import("native_node_function.zig").create(engine, "fetch", 1, callback, &.{}));
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    if (c.JS_DefinePropertyValueStr(engine.context, global, "fetch", c.JS_DupValue(engine.context, function), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    engine.native_module_values.putAssumeCapacity(key, c.JS_DupValue(engine.context, captured));
}
