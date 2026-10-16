//! Native fetch facade: actual Request/Response/Headers and shared HTTP worker.
//! Source-only. Redirect metadata, custom methods and duplex upload need the
//! transport owner's remaining seams; no second worker or substitute Response.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const request_api = @import("native_web_request.zig");
const response_api = @import("native_web_response.zig");
const header_api = @import("native_headers.zig");
const web = @import("native_headers_webidl.zig");
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
fn networkError(scope: *Scope, owner: c.JSValue, message: []const u8) !void {
    cleanupTransport(scope, owner);
    try reject(scope, owner, try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text(message)})), true);
}
fn cancelUpload(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try scope.invoke(roots[0], "cancel", &.{if (args.len > 0) args[0] else c.pi_js_undefined()}));
}
fn collectUpload(scope: *Scope, owner: c.JSValue, payload: body.Body, signal: c.JSValue) !void {
    const reader = try scope.invoke(payload.stream, "getReader", &.{});
    try scope.set(owner, "upload_reader", reader);
    const cancel = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, cancelUpload, &.{reader}));
    const bytes = try scope.own(try @import("native_body_collect.zig").collect(scope.engine, reader, .{ .mode = .bytes, .signal = signal, .cancel = cancel }));
    try flow.wait(continued, scope.engine, owner, bytes, 0);
}
fn addDefault(scope: *Scope, headers: c.JSValue, name: []const u8, value: c.JSValue) !void {
    const key_value = try scope.text(name);
    if (!scope.truthy(try scope.invoke(headers, "has", &.{key_value}))) _ = try scope.invoke(headers, "append", &.{ key_value, value });
}
fn open(scope: *Scope, owner: c.JSValue, upload: c.JSValue) !void {
    const view = try request_api.view(scope, try scope.get(owner, "request"));
    if (scope.truthy(try scope.get(view.signal, "aborted"))) return reject(scope, owner, try scope.get(view.signal, "reason"), false);
    if (!c.JS_IsNull(view.dispatcher) and !c.JS_IsUndefined(view.dispatcher)) return error.NativeWebDispatcherTransportUnavailable;
    const current_url = try scope.get(owner, "current_url");
    const current_method = try scope.get(owner, "current_method");
    const current_headers = try scope.get(owner, "current_headers");
    try scope.set(owner, "upload", upload);
    const url = try scope.engine.toString(current_url);
    defer scope.engine.gpa.free(url);
    const method = try scope.engine.toString(current_method);
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
    const wire_headers = try scope.own(try header_api.clone(scope.engine, current_headers, .none));
    try addDefault(scope, wire_headers, "accept", try scope.text("*/*"));
    try addDefault(scope, wire_headers, "accept-language", try scope.text("*"));
    _ = try scope.invoke(wire_headers, "set", &.{ try scope.text("sec-fetch-mode"), view.mode });
    var cache = view.cache;
    if (scope.equal(cache, try scope.text("default"))) inline for (.{ "if-modified-since", "if-none-match", "if-unmodified-since", "if-match", "if-range" }) |name| {
        if (scope.truthy(try scope.invoke(wire_headers, "has", &.{try scope.text(name)}))) cache = try scope.text("no-store");
    };
    if (scope.equal(cache, try scope.text("no-cache"))) try addDefault(scope, wire_headers, "cache-control", try scope.text("max-age=0"));
    if (scope.equal(cache, try scope.text("no-store")) or scope.equal(cache, try scope.text("reload"))) {
        try addDefault(scope, wire_headers, "pragma", try scope.text("no-cache"));
        try addDefault(scope, wire_headers, "cache-control", try scope.text("no-cache"));
    }
    _ = try scope.invoke(wire_headers, "delete", &.{try scope.text("host")});
    const pairs = try header_api.rawPairs(scope, wire_headers);
    for (0..try web.count(scope, pairs)) |index| {
        const pair = try web.index(scope, pairs, index);
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
    const transport = try scope.own(try http.openWithOptions(scope.engine, .{ .url = url, .payload = if (size == 0) &.{} else bytes[0..size], .headers = headers.items, .method = native_method, .framing = .bytes, .stream_error_bytes = true, .headers_timeout_only = true, .redirect_behavior = .unhandled, .timeout_ms = if (timeout < 0) null else @intCast(timeout) }, view.signal, .{ .raw_header_pairs = true }));
    try scope.set(owner, "transport", transport);
    try flow.wait(continued, scope.engine, owner, try scope.get(transport, "ready"), 1);
}
fn redirected(scope: *Scope, owner: c.JSValue, head: c.JSValue, status: u32) !bool {
    if (!(status == 301 or status == 302 or status == 303 or status == 307 or status == 308)) return false;
    const view = try request_api.view(scope, try scope.get(owner, "request"));
    if (scope.equal(view.redirect, try scope.text("manual"))) return false;
    if (scope.equal(view.redirect, try scope.text("error"))) {
        try networkError(scope, owner, "unexpected redirect");
        return true;
    }
    const response_headers = try scope.own(try header_api.fromRecord(scope.engine, try scope.get(head, "rawHeaders")));
    var location = try scope.invoke(response_headers, "get", &.{try scope.text("location")});
    if (c.JS_IsNull(location)) return false;
    const units = try @import("native_utf16.zig").unitsAlloc(scope.engine, location);
    defer scope.engine.gpa.free(units);
    for (units) |unit| if (unit > 126 or unit < 32) {
        const bytes = try latin1(scope, location);
        defer scope.engine.gpa.free(bytes);
        const decoded = try @import("binary_encoding.zig").decode(scope.engine.gpa, bytes, .utf8);
        defer scope.engine.gpa.free(decoded);
        location = try scope.text(decoded);
        break;
    };
    const current_url = try scope.get(owner, "current_url");
    const next = scope.own(js.builtin(scope.engine, "URL", &.{ location, current_url }) catch |err| {
        cleanupTransport(scope, owner);
        try reject(scope, owner, try scope.own(flow.reason(scope.engine, err)), true);
        return true;
    }) catch |err| {
        cleanupTransport(scope, owner);
        return err;
    };
    const previous = try scope.own(try js.builtin(scope.engine, "URL", &.{current_url}));
    if (!scope.truthy(try scope.get(next, "hash"))) try scope.set(next, "hash", try scope.get(previous, "hash"));
    const scheme = try scope.get(next, "protocol");
    if (!scope.equal(scheme, try scope.text("http:")) and !scope.equal(scheme, try scope.text("https:"))) {
        try networkError(scope, owner, "URL scheme must be a HTTP(S) scheme");
        return true;
    }
    var count: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &count, try scope.get(owner, "redirect_count")) < 0) return js.capture(scope.engine);
    if (count == 20) {
        try networkError(scope, owner, "redirect count exceeded");
        return true;
    }
    const same_origin = scope.equal(try scope.get(previous, "origin"), try scope.get(next, "origin"));
    if (scope.equal(view.mode, try scope.text("cors")) and (scope.truthy(try scope.get(next, "username")) or scope.truthy(try scope.get(next, "password"))) and !same_origin) {
        try networkError(scope, owner, "cross origin not allowed for request mode \"cors\"");
        return true;
    }
    const method = try scope.get(owner, "current_method");
    const headers = try scope.get(owner, "current_headers");
    if (status != 303 and scope.truthy(try scope.get(owner, "has_body")) and c.JS_IsNull(try scope.get(owner, "body_source"))) {
        cleanupTransport(scope, owner);
        try reject(scope, owner, try scope.own(try js.builtin(scope.engine, "Error", &.{c.pi_js_undefined()})), true);
        return true;
    }
    const drop_body = ((status == 301 or status == 302) and scope.equal(method, try scope.text("POST"))) or (status == 303 and !scope.equal(method, try scope.text("GET")) and !scope.equal(method, try scope.text("HEAD")));
    if (drop_body) {
        try scope.set(owner, "current_method", try scope.text("GET"));
        try scope.set(owner, "has_body", c.JS_NewBool(scope.engine.context, false));
        try scope.set(owner, "body_source", c.pi_js_null());
        inline for (.{ "content-encoding", "content-language", "content-location", "content-type", "content-length" }) |name| _ = try scope.invoke(headers, "delete", &.{try scope.text(name)});
    }
    if (!same_origin) inline for (.{ "authorization", "proxy-authorization", "cookie", "host" }) |name| {
        _ = try scope.invoke(headers, "delete", &.{try scope.text(name)});
    };
    cleanupTransport(scope, owner);
    try scope.set(owner, "current_url", try scope.get(next, "href"));
    try scope.set(owner, "redirect_count", c.JS_NewUint32(scope.engine.context, count + 1));
    const source = try scope.get(owner, "body_source");
    if (!c.JS_IsNull(source) and !c.JS_IsUndefined(source)) {
        const interfaces = try @import("native_web_platform.zig").prepare(scope);
        const payload = try body.extract(scope, &interfaces, source, false);
        try collectUpload(scope, owner, payload, view.signal);
    } else {
        const empty = try scope.own(try scope.engine.checked(c.JS_NewUint8ArrayCopy(scope.engine.context, null, 0)));
        try open(scope, owner, empty);
    }
    return true;
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
    if (try redirected(&scope, owner, value, status)) return;
    const transport = try scope.get(owner, "transport");
    const empty = status == 101 or status == 103 or status == 204 or status == 205 or status == 304 or scope.equal(try scope.get(owner, "current_method"), try scope.text("HEAD"));
    const stream = if (empty) c.pi_js_null() else try scope.own(try @import("native_web_byte_source.zig").fromEvents(engine, try scope.get(transport, "events"), .{ .cancel = try scope.get(transport, "cancel"), .signal = view.signal, .request = try scope.get(owner, "request") }));
    if (empty) cleanupTransport(&scope, owner);
    var redirects: u32 = 0;
    if (c.JS_ToUint32(engine.context, &redirects, try scope.get(owner, "redirect_count")) < 0) return js.capture(engine);
    const response = response_api.fromTransport(engine, .{ .body = stream, .status = @intCast(status), .status_text = try scope.get(value, "statusText"), .headers = try scope.get(value, "rawHeaders"), .url = try scope.get(owner, "current_url"), .redirected = redirects != 0 }) catch |err| {
        cleanupTransport(&scope, owner);
        return err;
    };
    defer engine.freeValue(response);
    try flow.settle(engine, owner, false, response);
}
/// Returns an owned Promise of an actual native Response. The internal owner
/// retains Request and worker handoff until the real response-head transition.
pub fn fetch(engine: *em.Engine, input: c.JSValue, init: c.JSValue, options: Options) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
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
    try scope.set(pending.owner, "current_url", view.url);
    try scope.set(pending.owner, "current_method", view.method);
    try scope.set(pending.owner, "current_headers", try scope.own(try header_api.clone(engine, view.headers, .none)));
    try scope.set(pending.owner, "redirect_count", c.JS_NewInt32(engine.context, 0));
    try scope.set(pending.owner, "body_source", if (view.payload) |payload| payload.source else c.pi_js_null());
    try scope.set(pending.owner, "has_body", c.JS_NewBool(engine.context, view.payload != null));
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
            const response = response_api.fromTransport(engine, .{ .body = if (scope.equal(view.method, try scope.text("HEAD"))) c.pi_js_null() else decoded.bytes, .status = 200, .status_text = try scope.text("OK"), .headers = headers, .url = view.url }) catch |err| {
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
        // The shared worker currently accepts owned upload bytes. Read the
        // genuine stream with actual disturbance/abort semantics; concurrent
        // network backpressure is a separate transport seam, not claimed here.
        collectUpload(&scope, pending.owner, payload, view.signal) catch |err| try flow.rejectError(engine, pending.owner, err);
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
