//! Shared OAuth HTTP boundary. Guest fetch/Response identity remains untouched;
//! absent host fetch uses the existing owned byte worker and genuine Response.
//! The real native_web_response/body/stream graph is a required dependency.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const response = @import("native_web_response.zig");
pub fn captureFetch(scope: *Scope) !c.JSValue {
    const value = try scope.global("fetch");
    if (!c.JS_IsUndefined(value)) return value;
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return nativeRequest(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
        }
    };
    return scope.own(try helpers.asyncArrow(scope.engine, "fetch", 1, Adapter.call, &.{}));
}
pub fn request(engine: *v.em.Engine, url: c.JSValue, init: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return requestWithFetch(engine, try captureFetch(&scope), url, init);
}
pub fn requestWithFetch(engine: *v.em.Engine, fetch: c.JSValue, url: c.JSValue, init: c.JSValue) !c.JSValue {
    // The provider's native await performs PromiseResolve. Do not wrap a
    // caller-supplied Promise in an extra reaction or defer a synchronous throw.
    return v.js.call(engine, fetch, c.pi_js_undefined(), &.{ url, init });
}
pub fn requestJson(engine: *v.em.Engine, url: c.JSValue, init: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return requestJsonWithFetch(engine, try captureFetch(&scope), url, init);
}
pub fn requestJsonWithFetch(engine: *v.em.Engine, fetch: c.JSValue, url: c.JSValue, init: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const result = scope.call(fetch, c.pi_js_undefined(), &.{ url, init }) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    try flow.wait(jsonReady, engine, pending.owner, result, 0);
    return pending.promise;
}
fn jsonResult(scope: *Scope, owner: c.JSValue, json: c.JSValue) !void {
    const result = try scope.object();
    try scope.put(result, "response", try scope.get(owner, "response"));
    try scope.put(result, "json", json);
    return flow.settle(scope.engine, owner, false, result);
}
fn jsonReady(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected and stage == 0) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) return jsonResult(&scope, owner, if (rejected) c.pi_js_null() else value);
    try scope.put(owner, "response", value);
    const generation = engine.native_allocation_generation;
    const parsed = scope.invoke(value, "json", &.{}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(engine, err, generation);
        return jsonResult(&scope, owner, c.pi_js_null());
    };
    return flow.wait(jsonReady, engine, owner, parsed, 1);
}
fn nativeRequest(engine: *v.em.Engine, url: c.JSValue, init: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    open(&scope, pending.owner, url, init) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn open(scope: *Scope, owner: c.JSValue, url: c.JSValue, init: c.JSValue) !void {
    const engine = scope.engine;
    const address = try engine.toString(url);
    defer engine.gpa.free(address);
    const input_body = try v.optional(scope, init, "body");
    const body = if (v.nullish(input_body)) try scope.text("") else if (c.JS_IsString(input_body)) input_body else try scope.invoke(input_body, "toString", &.{});
    const bytes = try engine.toString(body);
    defer engine.gpa.free(bytes);
    const headers_init = try v.optional(scope, init, "headers");
    const headers = try scope.own(try v.js.builtin(engine, "Headers", &.{headers_init}));
    if (!v.nullish(input_body) and !c.JS_IsString(input_body) and !scope.truthy(try scope.invoke(headers, "has", &.{try scope.text("content-type")}))) _ = try scope.invoke(headers, "set", &.{ try scope.text("content-type"), try scope.text("application/x-www-form-urlencoded;charset=UTF-8") });
    var fields: std.ArrayList(std.http.Header) = .empty;
    defer {
        for (fields.items) |field| {
            engine.gpa.free(field.name);
            engine.gpa.free(field.value);
        }
        fields.deinit(engine.gpa);
    }
    var iterator = try v.iterator(scope, try scope.invoke(headers, "entries", &.{}));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const name = try engine.toString(try v.at(scope, entry, 0));
        errdefer engine.gpa.free(name);
        const value = try engine.toString(try v.at(scope, entry, 1));
        errdefer engine.gpa.free(value);
        try fields.append(engine.gpa, .{ .name = name, .value = value });
    }
    const method_value = try v.optional(scope, init, "method");
    const method_text = try engine.toString(if (c.JS_IsUndefined(method_value)) try scope.text("GET") else try scope.invoke(try scope.stringify(method_value), "toUpperCase", &.{}));
    defer engine.gpa.free(method_text);
    const method = std.meta.stringToEnum(std.http.Method, method_text) orelse return error.InvalidNativeOAuthHttpMethod;
    try scope.put(owner, "url", url);
    try scope.put(owner, "chunks", try scope.array());
    const http = try scope.own(try @import("native_ai_http.zig").openWithOptions(engine, .{ .url = address, .payload = bytes, .headers = fields.items, .method = method, .framing = .bytes, .stream_error_bytes = true }, try v.optional(scope, init, "signal"), .{ .raw_header_pairs = true }));
    try scope.put(owner, "http", http);
    try scope.put(owner, "iterator", try scope.get(http, "events"));
    return flow.wait(nativeReady, engine, owner, try scope.get(http, "ready"), 0);
}
fn nativeReady(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    advance(&scope, owner, value, stage) catch |err| try flow.rejectError(engine, owner, err);
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: c_int) !void {
    if (stage == 0) try scope.put(owner, "head", value) else {
        if (scope.truthy(try scope.get(value, "done"))) return completed(scope, owner);
        const frame = try scope.get(value, "value");
        if (!try v.eq(scope, try scope.get(frame, "type"), "bytes")) return error.NativeOAuthHttpByteFrameRequired;
        _ = try scope.invoke(try scope.get(owner, "chunks"), "push", &.{try scope.get(frame, "data")});
    }
    return flow.wait(nativeReady, scope.engine, owner, try scope.invoke(try scope.get(owner, "iterator"), "next", &.{}), 1);
}
fn completed(scope: *Scope, owner: c.JSValue) !void {
    const chunks = try scope.get(owner, "chunks");
    const count = try v.length(scope, chunks);
    var length: usize = 0;
    for (0..count) |index| length = try std.math.add(usize, length, try v.length(scope, try v.at(scope, chunks, @intCast(index))));
    const body = try scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{try scope.own(try scope.engine.checked(c.JS_NewFloat64(scope.engine.context, @floatFromInt(length))))}));
    var offset: usize = 0;
    for (0..count) |index| {
        const chunk = try v.at(scope, chunks, @intCast(index));
        _ = try scope.invoke(body, "set", &.{ chunk, c.JS_NewFloat64(scope.engine.context, @floatFromInt(offset)) });
        offset += try v.length(scope, chunk);
    }
    const head = try scope.get(owner, "head");
    var status: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &status, try scope.get(head, "status")) < 0) return v.js.capture(scope.engine);
    const result = try scope.own(try response.fromTransport(scope.engine, .{ .body = body, .status = @intCast(status), .status_text = try scope.get(head, "statusText"), .headers = try scope.get(head, "rawHeaders"), .url = try scope.get(owner, "url") }));
    return flow.settle(scope.engine, owner, false, result);
}
