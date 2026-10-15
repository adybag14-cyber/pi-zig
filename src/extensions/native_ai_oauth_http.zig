//! Shared OAuth HTTP boundary. Guest fetch/Response identity remains untouched;
//! absent host fetch uses the existing owned byte worker and genuine Response.
//! The real native_web_response/body/stream graph is a required dependency.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const response = @import("native_web_response.zig");
const streams = @import("native_readable_stream.zig");
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
    if (!scope.truthy(try scope.invoke(headers, "has", &.{try scope.text("user-agent")}))) {
        const diagnostic = try std.fmt.allocPrint(engine.gpa, "pi-zig/Zig-{s} QuickJS-{s} ({s}; {s})", .{ builtin.zig_version_string, std.mem.span(c.JS_GetVersion()), @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) });
        defer engine.gpa.free(diagnostic);
        _ = try scope.invoke(headers, "set", &.{ try scope.text("user-agent"), try scope.text(diagnostic) });
    }
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
    const signal = try v.optional(scope, init, "signal");
    try scope.put(owner, "signal", signal);
    try scope.put(owner, "headOnly", c.pi_js_bool(engine.context, @intFromBool(method == .HEAD)));
    const http = try scope.own(try @import("native_ai_http.zig").openWithOptions(engine, .{ .url = address, .payload = bytes, .headers = fields.items, .method = method, .framing = .bytes, .stream_error_bytes = true }, signal, .{ .raw_header_pairs = true }));
    try scope.put(owner, "http", http);
    try scope.put(owner, "iterator", try scope.get(http, "events"));
    return flow.wait(nativeReady, engine, owner, try scope.get(http, "ready"), 0);
}
fn abortReason(scope: *Scope, owner: c.JSValue, original: c.JSValue) !c.JSValue {
    const signal = try scope.get(owner, "signal");
    if (!v.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return scope.get(signal, "reason");
    return original;
}
fn nativeReady(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return flow.settle(engine, owner, true, try abortReason(&scope, owner, value));
    readyResponse(&scope, owner, value) catch |err| {
        const original = try scope.own(flow.reason(engine, err));
        const generation = engine.native_allocation_generation;
        _ = scope.invoke(try scope.get(owner, "iterator"), "return", &.{}) catch |close_error| discarded: {
            try @import("native_ai_partial_json.zig").discard(engine, close_error, generation);
            break :discarded c.pi_js_undefined();
        };
        return flow.settle(engine, owner, true, original);
    };
}
fn mappedIterator(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const result = try scope.object();
    const Adapter = struct {
        fn next(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            const pending = try flow.create(engine, roots[0]);
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            const value = local.invoke(try local.get(roots[0], "iterator"), "next", &.{}) catch |err| {
                try flow.rejectError(engine, pending.owner, err);
                return pending.promise;
            };
            try flow.wait(mappedReady, engine, pending.owner, value, 0);
            return pending.promise;
        }
        fn close(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            return v.js.invoke(engine, try local.get(roots[0], "iterator"), "return", &.{});
        }
    };
    try scope.put(result, "next", try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "next", 0, Adapter.next, &.{owner})));
    try scope.put(result, "return", try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "return", 0, Adapter.close, &.{owner})));
    return result;
}
fn mappedReady(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return flow.settle(engine, pending, true, try abortReason(&scope, try scope.get(pending, "agent"), value));
    const done = scope.truthy(try scope.get(value, "done"));
    const result = try scope.object();
    try scope.put(result, "done", c.pi_js_bool(engine.context, @intFromBool(done)));
    if (done) try scope.put(result, "value", c.pi_js_undefined()) else {
        const frame = try scope.get(value, "value");
        if (!try v.eq(&scope, try scope.get(frame, "type"), "bytes")) return flow.rejectError(engine, pending, error.NativeOAuthHttpByteFrameRequired);
        try scope.put(result, "value", try scope.get(frame, "data"));
    }
    return flow.settle(engine, pending, false, result);
}
fn readyResponse(scope: *Scope, owner: c.JSValue, head: c.JSValue) !void {
    var status: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &status, try scope.get(head, "status")) < 0) return v.js.capture(scope.engine);
    const null_body = scope.truthy(try scope.get(owner, "headOnly")) or status == 204 or status == 205 or status == 304;
    const body = if (null_body) c.pi_js_null() else try scope.own(try streams.fromAsyncIterator(scope.engine, try mappedIterator(scope, owner)));
    if (null_body) _ = try scope.invoke(try scope.get(owner, "iterator"), "return", &.{});
    const result = try scope.own(try response.fromTransport(scope.engine, .{ .body = body, .status = @intCast(status), .status_text = try scope.get(head, "statusText"), .headers = try scope.get(head, "rawHeaders"), .url = try scope.get(owner, "url") }));
    return flow.settle(scope.engine, owner, false, result);
}
