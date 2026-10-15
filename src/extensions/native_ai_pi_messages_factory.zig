//! Actual pi-messages provider functions. VM continuations retain owner graphs;
//! the common HTTP worker owns raw bytes and never receives a JS value.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const codec = @import("native_ai_pi_messages_decode.zig");
const request = @import("native_ai_pi_messages_request.zig");
const Stage = enum(c_int) { payload, fetched, ready, response, errorBody, read, providerEvent };

pub fn create(engine: *v.em.Engine) !c.JSValue {
    try @import("native_stream.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.object();
    try scope.put(dependencies, "json", try scope.own(try @import("native_ai_json_parse.zig").create(engine)));
    try scope.put(dependencies, "env", try scope.own(try @import("native_provider_env.zig").create(engine)));
    const result = try scope.object();
    inline for (.{ "stream", "streamSimple" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var values = [_]c.JSValue{c.pi_js_undefined()} ** 3;
                for (args[0..@min(args.len, values.len)], 0..) |value, i| values[i] = value;
                return stream(host, roots[0], &values, index == 1);
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").createArrow(engine, name, 3, Adapter.call, &.{dependencies})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn stream(engine: *v.em.Engine, dependencies: c.JSValue, args: []const c.JSValue, simple: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var options = args[2];
    if (simple) {
        options = try v.spread(&scope, args[2]);
        inline for (.{ "reasoning", "toolChoice", "debug" }) |key| try scope.put(options, key, try v.optional(&scope, args[2], key));
    }
    const module = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativePiMessagesStreamMissing;
    const outer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(module, "AssistantMessageEventStream"), 0, null)));
    const pending = try flow.create(engine, dependencies);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const owner = pending.owner;
    try scope.put(owner, "allocationGeneration", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
    try scope.put(owner, "model", args[0]);
    try scope.put(owner, "context", args[1]);
    try scope.put(owner, "options", options);
    try scope.put(owner, "stream", outer);
    inline for (.{ "http", "reader", "responseFailure" }) |key| try scope.put(owner, key, c.pi_js_undefined());
    try scope.put(owner, "buffer", try scope.text(""));
    try scope.put(owner, "eof", c.pi_js_bool(engine.context, 0));
    try codec.initialize(&scope, owner, args[0]);
    setup(&scope, owner) catch |err| try failError(&scope, owner, err);
    return c.JS_DupValue(engine.context, outer);
}
fn wait(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(continued, scope.engine, owner, value, @intFromEnum(stage));
}
fn hook(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const options = try scope.get(owner, "options");
    const callback = try v.optional(scope, options, name);
    return if (v.nullish(callback)) c.pi_js_undefined() else scope.call(callback, options, &.{ value, try scope.get(owner, "model") });
}
fn setup(scope: *Scope, owner: c.JSValue) !void {
    const options = try scope.get(owner, "options");
    const model = try scope.get(owner, "model");
    const key = try v.optional(scope, options, "apiKey");
    if (!scope.truthy(key)) return v.errorText(scope, try scope.concat(try scope.concat(try scope.text("No API key provided for provider \""), try scope.stringify(try scope.get(model, "provider"))), try scope.text("\"")));
    try scope.put(owner, "apiKey", key);
    const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text("/+$"), try scope.text("u") }));
    const base = try scope.invoke(try scope.get(model, "baseUrl"), "replace", &.{ regex, try scope.text("") });
    const url = try scope.own(try v.js.builtin(scope.engine, "URL", &.{try scope.concat(base, try scope.text("/messages"))}));
    if (scope.truthy(try v.optional(scope, options, "debug"))) _ = try scope.invoke(try scope.get(url, "searchParams"), "set", &.{ try scope.text("debug"), try scope.text("1") });
    try scope.put(owner, "url", url);
    const payload = try request.build(scope, model, try scope.get(owner, "context"), options, try scope.get(try scope.get(owner, "agent"), "env"));
    try scope.put(owner, "payload", payload);
    try wait(scope, owner, try hook(scope, owner, "onPayload", payload), .payload);
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) {
        if (try allocationFailure(&scope, owner, value)) {
            try @import("native_stream.zig").reject(engine, try scope.get(owner, "stream"), value);
            return flow.settle(engine, owner, false, c.pi_js_undefined());
        }
        const stage: Stage = @enumFromInt(raw);
        const reason = if ((stage == .ready or stage == .read) and !scope.truthy(try scope.get(owner, "customFetch"))) transportFailure(&scope, owner, value, stage) catch |err| return emergency(engine, owner, err) else value;
        fail(&scope, owner, reason) catch |err| return emergency(engine, owner, err);
        return;
    }
    advance(&scope, owner, value, @enumFromInt(raw)) catch |err| {
        failError(&scope, owner, err) catch |failure| return emergency(engine, owner, failure);
    };
}
fn transportFailure(scope: *Scope, owner: c.JSValue, raw: c.JSValue, stage: Stage) !c.JSValue {
    const code = try v.optional(scope, raw, "code");
    if (try v.eq(scope, code, "OutOfMemory")) return error.OutOfMemory;
    if (try v.eq(scope, code, "ProviderRequestAborted")) {
        const signal = try v.optional(scope, try scope.get(owner, "options"), "signal");
        const reason = try v.optional(scope, signal, "reason");
        if (!c.JS_IsUndefined(reason)) return reason;
        const fallback = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("This operation was aborted")}));
        try scope.set(fallback, "name", try scope.text("AbortError"));
        return fallback;
    }
    const failure = try scope.own(try v.js.builtin(scope.engine, "TypeError", &.{try scope.text(if (stage == .ready) "fetch failed" else "terminated")}));
    try scope.put(failure, "cause", raw);
    return failure;
}
fn emergency(engine: *v.em.Engine, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    if (engine.captured_exception) |captured| {
        engine.captured_exception = null;
        engine.freeValue(captured);
    }
    const stream_value = try @import("native_sdk.zig").get(engine, owner, "stream");
    defer engine.freeValue(stream_value);
    try @import("native_stream.zig").reject(engine, stream_value, reason);
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn release(scope: *Scope, owner: c.JSValue) !void {
    const reader = try scope.get(owner, "reader");
    if (!v.nullish(reader)) {
        try scope.put(owner, "reader", c.pi_js_undefined());
        _ = try scope.invoke(reader, "releaseLock", &.{});
    }
    const http = try scope.get(owner, "http");
    if (!v.nullish(http)) _ = try scope.invoke(http, "cancel", &.{});
}
fn failError(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    if (err == error.OutOfMemory) return emergency(scope.engine, owner, err);
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    if (try allocationFailure(scope, owner, reason)) {
        try @import("native_stream.zig").reject(scope.engine, try scope.get(owner, "stream"), reason);
        return flow.settle(scope.engine, owner, false, c.pi_js_undefined());
    }
    return fail(scope, owner, reason);
}
fn allocationFailure(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !bool {
    const tagged = c.pi_js_native_allocation_error_generation(reason);
    if (tagged == 0) return false;
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(scope.engine.context, &generation, try scope.get(owner, "allocationGeneration")) < 0) return v.js.capture(scope.engine);
    const distance = tagged -% generation;
    return distance != 0 and distance <= scope.engine.native_allocation_generation -% generation;
}
fn fail(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    var failure = reason;
    release(scope, owner) catch |err| {
        failure = try scope.own(flow.reason(scope.engine, err));
        if (scope.engine.captured_exception) |captured| {
            scope.engine.captured_exception = null;
            scope.engine.freeValue(captured);
        }
    };
    const signal = try v.optional(scope, try scope.get(owner, "options"), "signal");
    const aborted = scope.truthy(try v.optional(scope, signal, "aborted"));
    const why: []const u8 = if (aborted) "aborted" else "error";
    const output = try scope.object();
    const assistant = try codec.message(scope, try scope.get(owner, "model"), why);
    const instance = c.JS_IsInstanceOf(scope.engine.context, failure, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    try scope.put(assistant, "errorMessage", if (instance != 0) try scope.get(failure, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{failure}));
    // Only the private response-error instance constructed by this invocation
    // receives the HTTP diagnostic; guest name/code lookalikes do not.
    if (!aborted and scope.equal(failure, try scope.get(owner, "responseFailure"))) {
        const diagnostic = try scope.object();
        try scope.put(diagnostic, "type", try scope.text("pi_messages_response_failure"));
        try scope.put(diagnostic, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
        const error_info = try scope.object();
        const name = try scope.get(failure, "name");
        const message = try scope.get(failure, "message");
        try scope.put(error_info, "name", if (scope.truthy(name)) name else c.pi_js_undefined());
        try scope.put(error_info, "message", if (scope.truthy(message)) message else name);
        try scope.put(error_info, "stack", try scope.get(failure, "stack"));
        const code = try scope.get(failure, "code");
        try scope.put(error_info, "code", if (c.JS_IsString(code) or c.JS_IsNumber(code)) code else c.pi_js_undefined());
        try scope.put(diagnostic, "error", error_info);
        try scope.put(diagnostic, "details", try scope.get(failure, "diagnosticDetails"));
        try codec.appendDiagnostic(scope, assistant, diagnostic);
    }
    try scope.put(output, "type", try scope.text("error"));
    try scope.put(output, "reason", try scope.text(why));
    try scope.put(output, "error", assistant);
    _ = scope.invoke(try scope.get(owner, "stream"), "push", &.{output}) catch |err| {
        try @import("native_stream.zig").reject(scope.engine, try scope.get(owner, "stream"), failure);
        return flow.rejectError(scope.engine, owner, err);
    };
    try flow.settle(scope.engine, owner, false, c.pi_js_undefined());
}
fn open(scope: *Scope, owner: c.JSValue) !void {
    const options = try scope.get(owner, "options");
    const headers = try request.headers(scope, options, try scope.get(owner, "apiKey"));
    const body = try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(owner, "payload")});
    const fetch = try v.optional(scope, options, "fetch");
    try scope.put(owner, "customFetch", c.pi_js_bool(scope.engine.context, @intFromBool(!v.nullish(fetch))));
    if (!v.nullish(fetch)) {
        const init = try scope.object();
        try scope.put(init, "method", try scope.text("POST"));
        try scope.put(init, "headers", headers);
        try scope.put(init, "body", body);
        try scope.put(init, "signal", try v.optional(scope, options, "signal"));
        return wait(scope, owner, try scope.call(fetch, c.pi_js_undefined(), &.{ try scope.get(owner, "url"), init }), .fetched);
    }
    var fields: std.ArrayList(std.http.Header) = .empty;
    defer {
        for (fields.items) |field| {
            scope.engine.gpa.free(field.name);
            scope.engine.gpa.free(field.value);
        }
        fields.deinit(scope.engine.gpa);
    }
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{headers}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const name = try scope.engine.toString(try v.at(&row, entry, 0));
        errdefer scope.engine.gpa.free(name);
        for (name) |*byte| byte.* = std.ascii.toLower(byte.*);
        const untrimmed = try scope.engine.toString(try v.at(&row, entry, 1));
        defer scope.engine.gpa.free(untrimmed);
        const value = try scope.engine.gpa.dupe(u8, std.mem.trim(u8, untrimmed, " \t\r\n"));
        errdefer scope.engine.gpa.free(value);
        var existing: ?usize = null;
        for (fields.items, 0..) |field, i| if (std.mem.eql(u8, field.name, name)) {
            existing = i;
            break;
        };
        if (existing) |i| {
            const combined = try std.fmt.allocPrint(scope.engine.gpa, "{s}, {s}", .{ fields.items[i].value, value });
            scope.engine.gpa.free(fields.items[i].value);
            fields.items[i].value = combined;
            scope.engine.gpa.free(name);
            scope.engine.gpa.free(value);
            continue;
        }
        try fields.append(scope.engine.gpa, .{ .name = name, .value = value });
    }
    const url = try scope.engine.toString(try scope.invoke(try scope.get(owner, "url"), "toString", &.{}));
    defer scope.engine.gpa.free(url);
    const payload = try scope.engine.toString(body);
    defer scope.engine.gpa.free(payload);
    const http = try scope.own(try @import("native_ai_http.zig").open(scope.engine, .{ .url = url, .payload = payload, .headers = fields.items, .framing = .bytes }, try v.optional(scope, options, "signal")));
    try scope.put(owner, "http", http);
    try scope.put(owner, "iterator", try scope.get(http, "events"));
    try wait(scope, owner, try scope.get(http, "ready"), .ready);
}
fn next(scope: *Scope, owner: c.JSValue) !void {
    const custom = scope.truthy(try scope.get(owner, "customFetch"));
    try wait(scope, owner, try scope.invoke(try scope.get(owner, if (custom) "reader" else "iterator"), if (custom) "read" else "next", &.{}), .read);
}
fn responseFailure(scope: *Scope, owner: c.JSValue, body: c.JSValue) !void {
    const failure = try request.responseError(scope, try scope.get(owner, "model"), try scope.get(owner, "url"), try scope.get(owner, "response"), body);
    try scope.put(owner, "responseFailure", failure);
    try fail(scope, owner, failure);
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .payload => {
            if (!c.JS_IsUndefined(value)) try scope.put(owner, "payload", value);
            try open(scope, owner);
        },
        .fetched => {
            try scope.put(owner, "response", value);
            const metadata = try scope.object();
            try scope.put(metadata, "status", try scope.get(value, "status"));
            const headers = try scope.invoke(try scope.global("Object"), "fromEntries", &.{try scope.invoke(try scope.get(value, "headers"), "entries", &.{})});
            try scope.put(metadata, "headers", headers);
            try wait(scope, owner, try hook(scope, owner, "onResponse", metadata), .response);
        },
        .ready => {
            try scope.put(owner, "response", value);
            const metadata = try scope.object();
            try scope.put(metadata, "status", try scope.get(value, "status"));
            try scope.put(metadata, "headers", try scope.get(value, "headers"));
            try wait(scope, owner, try hook(scope, owner, "onResponse", metadata), .response);
        },
        .response => {
            const response = try scope.get(owner, "response");
            const custom = scope.truthy(try scope.get(owner, "customFetch"));
            var ok = false;
            if (custom) ok = scope.truthy(try scope.get(response, "ok")) else {
                var status: i32 = 0;
                if (c.JS_ToInt32(scope.engine.context, &status, try scope.get(response, "status")) < 0) return v.js.capture(scope.engine);
                ok = status >= 200 and status < 300;
            }
            try scope.put(owner, "ok", c.pi_js_bool(scope.engine.context, @intFromBool(ok)));
            if (!ok and custom) return wait(scope, owner, try scope.invoke(response, "text", &.{}), .errorBody);
            if (custom) {
                const body = try scope.get(response, "body");
                if (!scope.truthy(body)) return v.errorText(scope, try scope.concat(try scope.stringify(try scope.get(try scope.get(owner, "model"), "provider")), try scope.text(" response has no body")));
                try scope.put(owner, "reader", try scope.invoke(body, "getReader", &.{}));
            } else if (ok) {
                const status = try scope.get(response, "status");
                if (scope.equal(status, c.JS_NewInt32(scope.engine.context, 204)) or scope.equal(status, c.JS_NewInt32(scope.engine.context, 205))) return v.errorText(scope, try scope.concat(try scope.stringify(try scope.get(try scope.get(owner, "model"), "provider")), try scope.text(" response has no body")));
            }
            if (ok) try scope.put(owner, "decoder", try scope.own(try v.js.builtin(scope.engine, "TextDecoder", &.{})));
            try next(scope, owner);
        },
        .errorBody => try responseFailure(scope, owner, value),
        .read => {
            const done = scope.truthy(try scope.get(value, "done"));
            const custom = scope.truthy(try scope.get(owner, "customFetch"));
            const item = try scope.get(value, "value");
            if (!custom and !done and try v.eq(scope, try scope.get(item, "type"), "error_body")) return responseFailure(scope, owner, try scope.get(item, "body"));
            if (!scope.truthy(try scope.get(owner, "ok"))) {
                if (done) return responseFailure(scope, owner, try scope.text(""));
                return next(scope, owner);
            }
            const decoder = try scope.get(owner, "decoder");
            var decoded: c.JSValue = undefined;
            if (done) decoded = try scope.invoke(decoder, "decode", &.{}) else {
                const options = try scope.object();
                try scope.put(options, "stream", c.pi_js_bool(scope.engine.context, 1));
                decoded = try scope.invoke(decoder, "decode", &.{ if (custom) item else try scope.get(item, "data"), options });
            }
            const appended = try scope.concat(try scope.get(owner, "buffer"), decoded);
            const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{ try scope.text("\r\n"), try scope.text("g") }));
            try scope.put(owner, "buffer", try scope.invoke(appended, "replace", &.{ regex, try scope.text("\n") }));
            try scope.put(owner, "eof", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
            try drain(scope, owner);
        },
        .providerEvent => {
            const event = try codec.convert(scope, owner, try scope.get(owner, "event"));
            _ = try scope.invoke(try scope.get(owner, "stream"), "push", &.{event});
            const kind = try scope.get(event, "type");
            if (try v.eq(scope, kind, "done") or try v.eq(scope, kind, "error")) {
                try release(scope, owner);
                return flow.settle(scope.engine, owner, false, c.pi_js_undefined());
            }
            try drain(scope, owner);
        },
    }
}
fn drain(scope: *Scope, owner: c.JSValue) !void {
    while (true) {
        // Each frame scope is retired before the next frame; comments and empty
        // records cannot accumulate VM roots during one large HTTP chunk.
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const buffer = try row.get(owner, "buffer");
        var split: i64 = 0;
        if (c.JS_ToInt64(scope.engine.context, &split, try row.invoke(buffer, "indexOf", &.{try row.text("\n\n")})) < 0) return v.js.capture(scope.engine);
        const eof = row.truthy(try row.get(owner, "eof"));
        if (split < 0 and !eof) return next(scope, owner);
        const raw = if (split >= 0) try row.invoke(buffer, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt64(scope.engine.context, split) }) else buffer;
        try row.put(owner, "buffer", if (split >= 0) try row.invoke(buffer, "slice", &.{c.JS_NewInt64(scope.engine.context, split + 2)}) else try row.text(""));
        const lines = try row.invoke(raw, "split", &.{try row.text("\n")});
        var iterator = try v.iterator(&row, lines);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        var data = c.pi_js_undefined();
        while (try iterator.next()) |line| {
            defer scope.engine.freeValue(line);
            if (row.truthy(try row.invoke(line, "startsWith", &.{try row.text("data:")}))) {
                data = try row.invoke(try row.invoke(line, "slice", &.{c.JS_NewInt32(scope.engine.context, 5)}), "trim", &.{});
                break;
            }
        }
        if (row.truthy(data) and !try v.eq(&row, data, "[DONE]")) {
            const event = parsed: {
                var diagnostics = @import("native_ai_json_scope.zig").Guard.enter(scope.engine);
                defer diagnostics.deinit();
                break :parsed try row.invoke(try row.global("JSON"), "parse", &.{data});
            };
            try row.put(owner, "event", event);
            return wait(&row, owner, try hook(&row, owner, "onProviderStreamEvent", event), .providerEvent);
        }
        if (split < 0) return v.errorText(scope, try scope.concat(try scope.stringify(try scope.get(try scope.get(owner, "model"), "provider")), try scope.text(" stream ended without a terminal event")));
    }
}
