//! Actual Google Generative AI, Vertex and Mistral asynchronous stream facades.
//! Private qualification boundary: no automatic global registry installation.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const decoder = @import("native_ai_google_mistral_decode.zig");
const google = @import("native_ai_google_request.zig");
const mistral = @import("native_ai_mistral_request.zig");
const auth = @import("native_ai_google_auth.zig");
pub const Kind = enum { google, vertex, mistral };
const Stage = enum(c_int) { payload, ready, response, next, chunk, retried };
pub fn create(engine: *v.em.Engine, comptime kind: Kind) !c.JSValue {
    try @import("native_stream.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.own(try @import("native_ai_openai_dependencies.zig").create(engine));
    try scope.put(dependencies, "text", try scope.own(try @import("native_ai_text.zig").create(engine)));
    try scope.put(dependencies, "counter", c.JS_NewInt32(engine.context, 0));
    const result = try scope.object();
    inline for (.{ "stream", "streamSimple" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var input = [_]c.JSValue{c.pi_js_undefined()} ** 3;
                for (args[0..@min(args.len, input.len)], 0..) |value, i| input[i] = value;
                return stream(host, roots[0], &input, index == 1, kind);
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").create(engine, name, 3, Adapter.call, &.{dependencies})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn apiKey(scope: *Scope, model: c.JSValue, options: c.JSValue) !c.JSValue {
    const key = try v.optional(scope, options, "apiKey");
    if (scope.truthy(key)) return key;
    return v.errorText(scope, try scope.concat(try scope.text("No API key for provider: "), try scope.stringify(try scope.get(model, "provider"))));
}
fn stream(engine: *v.em.Engine, dependencies: c.JSValue, args: []const c.JSValue, simple: bool, comptime kind: Kind) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var options = args[2];
    if (simple) {
        if (kind != .vertex) _ = try apiKey(&scope, args[0], options);
        options = if (kind == .mistral) try mistral.simple(&scope, dependencies, args[0], args[1], options) else try google.simple(&scope, dependencies, args[0], args[1], options, kind == .vertex);
    }
    const module = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativeProviderStreamModuleMissing;
    const constructor = try scope.get(module, "AssistantMessageEventStream");
    const outer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    const compat = try scope.get(args[0], "compat");
    const context = try scope.own(try @import("native_ai_provider_transcript.zig").resolve(engine, args[1], kind == .mistral and scope.truthy(try v.optional(&scope, compat, "supportsMidConvoSystemMessages"))));
    const pending = try flow.create(engine, dependencies);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const owner = pending.owner;
    try scope.put(owner, "model", args[0]);
    try scope.put(owner, "context", context);
    try scope.put(owner, "options", options);
    try scope.put(owner, "stream", outer);
    try scope.put(owner, "http", c.pi_js_undefined());
    try scope.put(owner, "done", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "attempt", c.JS_NewInt32(engine.context, 0));
    const decoded = try scope.own(try decoder.create(engine, args[0], outer, try scope.get(dependencies, "json"), dependencies, if (kind == .mistral) .mistral else if (kind == .vertex) .vertex else .google));
    try scope.put(owner, "decoder", decoded);
    setup(&scope, owner, kind) catch |err| try failError(&scope, owner, err);
    return c.JS_DupValue(engine.context, outer);
}
fn setup(scope: *Scope, owner: c.JSValue, comptime kind: Kind) !void {
    const model = try scope.get(owner, "model");
    const options = try scope.get(owner, "options");
    const dependencies = try scope.get(owner, "agent");
    const custom_fetch = try v.optional(scope, options, "fetch");
    if (kind != .mistral and scope.truthy(custom_fetch) and !scope.equal(custom_fetch, try scope.global("fetch"))) return v.errorText(scope, try scope.text(if (kind == .google) "Custom fetch is not supported by the Google Generative AI adapter" else "Custom fetch is not supported by the Google Vertex AI adapter"));
    if (kind == .mistral) try scope.put(owner, "apiKey", try apiKey(scope, model, options)) else try scope.put(owner, "auth", try auth.resolve(scope, dependencies, model, options, kind == .vertex));
    const payload = try scope.own(if (kind == .mistral) try mistral.build(scope.engine, dependencies, model, try scope.get(owner, "context"), options) else try google.build(scope.engine, dependencies, model, try scope.get(owner, "context"), options));
    try scope.put(owner, "payload", payload);
    try wait(scope, owner, try hook(scope, owner, "onPayload", payload), .payload, kind);
}
fn hook(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const options = try scope.get(owner, "options");
    const callback = try v.optional(scope, options, name);
    return if (v.nullish(callback)) c.pi_js_undefined() else scope.call(callback, options, &.{ value, try scope.get(owner, "model") });
}
fn wait(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage, comptime kind: Kind) !void {
    const Adapter = struct {
        fn continued(engine: *v.em.Engine, state: c.JSValue, result: c.JSValue, rejected: bool, raw: c_int) !void {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            if (rejected) return fail(&row, state, result);
            advance(&row, state, result, @enumFromInt(raw), kind) catch |err| try failError(&row, state, err);
        }
    };
    try flow.wait(Adapter.continued, scope.engine, owner, value, @intFromEnum(stage));
}
fn aborted(scope: *Scope, owner: c.JSValue) !bool {
    return scope.truthy(try v.optional(scope, try v.optional(scope, try scope.get(owner, "options"), "signal"), "aborted"));
}
fn failError(scope: *Scope, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    try fail(scope, owner, reason);
}
fn fail(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const transport = try scope.get(owner, "http");
    if (!v.nullish(transport)) _ = try scope.invoke(transport, "cancel", &.{});
    _ = scope.invoke(try scope.get(owner, "decoder"), "fail", &.{ reason, c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner))) }) catch |err| {
        try @import("native_stream.zig").reject(scope.engine, try scope.get(owner, "stream"), reason);
        try flow.rejectError(scope.engine, owner, err);
        return;
    };
    try flow.settle(scope.engine, owner, false, c.pi_js_undefined());
}
fn headers(scope: *Scope, owner: c.JSValue, comptime kind: Kind) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "user-agent", try scope.text(@import("../ai/pi_user_agent.zig").value));
    try scope.put(result, "accept", try scope.text("text/event-stream"));
    try scope.put(result, "content-type", try scope.text("application/json"));
    if (kind == .mistral) try scope.put(result, "authorization", try scope.concat(try scope.text("Bearer "), try scope.stringify(try scope.get(owner, "apiKey")))) else {
        const credentials = try scope.get(owner, "auth");
        const bearer = try scope.get(credentials, "bearer");
        if (scope.truthy(bearer)) try scope.put(result, "authorization", try scope.concat(try scope.text("Bearer "), bearer));
        const quota = try scope.get(credentials, "quota");
        if (scope.truthy(quota)) try scope.put(result, "x-goog-user-project", quota);
        const key = try scope.get(credentials, "apiKey");
        if (scope.truthy(key)) try scope.put(result, "x-goog-api-key", key);
    }
    var affinity_override = false;
    inline for (.{ "model", "options" }) |source_key| {
        const source = try v.optional(scope, try scope.get(owner, source_key), "headers");
        if (!v.nullish(source)) {
            var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{source}));
            defer rows.deinit();
            errdefer rows.closePreserving();
            while (try rows.next()) |entry| {
                defer scope.engine.freeValue(entry);
                const name = try scope.invoke(try v.at(scope, entry, 0), "toLowerCase", &.{});
                const value = try v.at(scope, entry, 1);
                if (try v.eq(scope, name, "x-affinity")) affinity_override = true;
                try v.js.setKey(scope.engine, result, name, value);
            }
        }
    }
    const options = try scope.get(owner, "options");
    if (kind == .mistral and !affinity_override and try mistral.cache(scope, options)) try scope.put(result, "x-affinity", try scope.get(options, "sessionId"));
    return result;
}
fn url(scope: *Scope, owner: c.JSValue, comptime kind: Kind) !c.JSValue {
    const model = try scope.get(owner, "model");
    if (kind == .mistral) {
        const base = try scope.own(try v.js.builtin(scope.engine, "URL", &.{try scope.get(model, "baseUrl")}));
        const regex = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("/+$")}));
        try scope.set(base, "pathname", try scope.concat(try scope.invoke(try scope.get(base, "pathname"), "replace", &.{ regex, try scope.text("") }), try scope.text("/")));
        const target = try scope.own(try v.js.builtin(scope.engine, "URL", &.{ try scope.text("v1/chat/completions"), base }));
        return scope.get(target, "href");
    }
    const credentials = try scope.get(owner, "auth");
    var base = try scope.get(credentials, "base");
    if (scope.truthy(try scope.invoke(base, "endsWith", &.{try scope.text("/")}))) base = try scope.invoke(base, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, -1) });
    const id = try scope.get(try scope.get(owner, "payload"), "model");
    var path = id;
    if (kind == .vertex) {
        if (!(scope.truthy(try scope.invoke(id, "startsWith", &.{try scope.text("publishers/")})) or scope.truthy(try scope.invoke(id, "startsWith", &.{try scope.text("projects/")})) or scope.truthy(try scope.invoke(id, "startsWith", &.{try scope.text("models/")})))) {
            if (scope.truthy(try scope.invoke(id, "includes", &.{try scope.text("/")}))) {
                const parts = try scope.invoke(id, "split", &.{ try scope.text("/"), c.JS_NewInt32(scope.engine.context, 2) });
                path = try scope.concat(try scope.concat(try scope.text("publishers/"), try v.at(scope, parts, 0)), try scope.text("/models/"));
                path = try scope.concat(path, try v.at(scope, parts, 1));
            } else path = try scope.concat(try scope.text("publishers/google/models/"), id);
        }
    } else if (!(scope.truthy(try scope.invoke(id, "startsWith", &.{try scope.text("models/")})) or scope.truthy(try scope.invoke(id, "startsWith", &.{try scope.text("tunedModels/")})))) path = try scope.concat(try scope.text("models/"), id);
    return scope.concat(try scope.concat(base, try scope.text("/")), try scope.concat(path, try scope.text(":streamGenerateContent?alt=sse")));
}
fn open(scope: *Scope, owner: c.JSValue, comptime kind: Kind) !void {
    const engine = scope.engine;
    const options = try scope.get(owner, "options");
    if (kind == .vertex) {
        const credentials = try scope.get(owner, "auth");
        if (scope.truthy(try scope.get(credentials, "adc"))) try auth.adc(scope, try scope.get(owner, "agent"), options, credentials);
    }
    // The injectable fetch path requires its own live Response/reader adapter.
    // Keep this failure explicit until that path is implemented and qualified.
    if (kind == .mistral and !v.nullish(try v.optional(scope, options, "fetch")) and !scope.equal(try scope.get(options, "fetch"), try scope.global("fetch"))) return v.errorText(scope, try scope.text("Native Mistral custom fetch transport is not yet qualified"));
    const fields_object = try headers(scope, owner, kind);
    var fields: std.ArrayList(std.http.Header) = .empty;
    defer {
        for (fields.items) |field| {
            engine.gpa.free(field.name);
            engine.gpa.free(field.value);
        }
        fields.deinit(engine.gpa);
    }
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{fields_object}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer engine.freeValue(entry);
        const value = try v.at(scope, entry, 1);
        if (v.nullish(value)) continue;
        const name = try engine.toString(try v.at(scope, entry, 0));
        errdefer engine.gpa.free(name);
        const data = try engine.toString(value);
        errdefer engine.gpa.free(data);
        try fields.append(engine.gpa, .{ .name = name, .value = data });
    }
    const target = try engine.toString(try url(scope, owner, kind));
    defer engine.gpa.free(target);
    const body = if (kind == .mistral) try mistral.wire(scope, try scope.get(owner, "payload")) else try google.wire(scope, try scope.get(owner, "payload"));
    const payload = try engine.toString(try scope.invoke(try scope.global("JSON"), "stringify", &.{body}));
    defer engine.gpa.free(payload);
    const timeout = try v.optional(scope, options, "timeoutMs");
    var milliseconds: i64 = if (kind == .mistral) 60000 else 600000;
    if (!v.nullish(timeout) and c.JS_ToInt64(engine.context, &milliseconds, timeout) < 0) return v.js.capture(engine);
    const transport = try scope.own(try @import("native_ai_http.zig").open(engine, .{ .url = target, .payload = payload, .headers = fields.items, .timeout_ms = @intCast(@max(0, milliseconds)) }, try v.optional(scope, options, "signal")));
    try scope.put(owner, "http", transport);
    try scope.put(owner, "iterator", try scope.get(transport, "events"));
    try wait(scope, owner, try scope.get(transport, "ready"), .ready, kind);
}
fn next(scope: *Scope, owner: c.JSValue, comptime kind: Kind) !void {
    try wait(scope, owner, try scope.invoke(try scope.get(owner, "iterator"), "next", &.{}), .next, kind);
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage, comptime kind: Kind) !void {
    switch (stage) {
        .payload => {
            if (!c.JS_IsUndefined(value)) try scope.put(owner, "payload", value);
            try open(scope, owner, kind);
        },
        .ready => {
            try scope.put(owner, "response", value);
            try wait(scope, owner, if (kind == .mistral) try hook(scope, owner, "onResponse", value) else c.pi_js_undefined(), .response, kind);
        },
        .response => {
            const status = try scope.get(try scope.get(owner, "response"), "status");
            const arithmetic = @import("native_image_arithmetic.zig");
            const bad = try arithmetic.compare(scope.engine, .less, status, c.JS_NewInt32(scope.engine.context, 200)) or try arithmetic.compare(scope.engine, .greater_equal, status, c.JS_NewInt32(scope.engine.context, 300));
            if (!bad) _ = try scope.invoke(try scope.get(owner, "decoder"), "start", &.{});
            try next(scope, owner, kind);
        },
        .next => {
            if (scope.truthy(try scope.get(value, "done"))) {
                _ = try scope.invoke(try scope.get(owner, "decoder"), "finish", &.{c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner)))});
                return flow.settle(scope.engine, owner, false, c.pi_js_undefined());
            }
            const frame = try scope.get(value, "value");
            if (try v.eq(scope, try scope.get(frame, "type"), "error_body")) {
                const response = try scope.get(owner, "response");
                const reason = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("HTTP request failed")}));
                try scope.put(reason, if (kind == .mistral) "statusCode" else "status", try scope.get(response, "status"));
                try scope.put(reason, "headers", if (kind == .mistral) try scope.get(response, "headers") else c.pi_js_undefined());
                if (kind == .mistral) try scope.put(reason, "body", try scope.get(frame, "body")) else try scope.put(reason, "message", try scope.get(frame, "body"));
                return if (kind == .mistral) fail(scope, owner, reason) else retryOrFail(scope, owner, reason, kind);
            }
            if (scope.truthy(try scope.get(owner, "done"))) return next(scope, owner, kind);
            const data = try scope.get(frame, "data");
            if (try v.eq(scope, try scope.invoke(data, "trim", &.{}), "[DONE]")) {
                try scope.put(owner, "done", c.pi_js_bool(scope.engine.context, 1));
                return next(scope, owner, kind);
            }
            const chunk = try scope.invoke(try scope.global("JSON"), "parse", &.{data});
            try scope.put(owner, "chunk", chunk);
            try wait(scope, owner, try hook(scope, owner, "onProviderStreamEvent", chunk), .chunk, kind);
        },
        .chunk => {
            _ = try scope.invoke(try scope.get(owner, "decoder"), "push", &.{try scope.get(owner, "chunk")});
            try next(scope, owner, kind);
        },
        .retried => try open(scope, owner, kind),
    }
}

fn abortError(scope: *Scope) !c.JSValue {
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("Request aborted")}));
    try scope.put(result, "name", try scope.text("AbortError"));
    return result;
}
fn binary(scope: *Scope, operation: @import("native_image_arithmetic.zig").Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, operation, left, right));
}
fn retryOrFail(scope: *Scope, owner: c.JSValue, reason: c.JSValue, comptime kind: Kind) !void {
    if (try aborted(scope, owner)) return fail(scope, owner, try abortError(scope));
    const options = try scope.get(owner, "options");
    const raw_max = try v.optional(scope, options, "maxRetries");
    const maximum = if (v.nullish(raw_max)) c.JS_NewInt32(scope.engine.context, 0) else raw_max;
    const attempt = try scope.get(owner, "attempt");
    const arithmetic = @import("native_image_arithmetic.zig");
    if (try arithmetic.compare(scope.engine, .greater_equal, attempt, maximum)) return fail(scope, owner, reason);
    const headers_value = try scope.get(reason, "headers");
    const hint = try v.optional(scope, headers_value, "x-should-retry");
    const status = try scope.get(reason, "status");
    const retryable = if (try v.eq(scope, hint, "true")) true else if (try v.eq(scope, hint, "false")) false else c.JS_IsUndefined(status) or scope.equal(status, c.JS_NewInt32(scope.engine.context, 408)) or scope.equal(status, c.JS_NewInt32(scope.engine.context, 409)) or scope.equal(status, c.JS_NewInt32(scope.engine.context, 429)) or (c.JS_IsNumber(status) and try arithmetic.compare(scope.engine, .greater_equal, status, c.JS_NewInt32(scope.engine.context, 500)));
    if (!retryable) return fail(scope, owner, reason);
    try scope.put(owner, "attempt", try binary(scope, .add, attempt, c.JS_NewInt32(scope.engine.context, 1)));
    var delay = c.pi_js_undefined();
    const number = try scope.global("Number");
    const after_ms = try v.optional(scope, headers_value, "retry-after-ms");
    if (scope.truthy(after_ms)) {
        const parsed = try scope.invoke(number, "parseFloat", &.{after_ms});
        if (scope.truthy(try scope.invoke(number, "isFinite", &.{parsed}))) delay = parsed;
    }
    if (c.JS_IsUndefined(delay)) {
        const after = try v.optional(scope, headers_value, "retry-after");
        if (scope.truthy(after)) {
            const seconds = try scope.invoke(number, "parseFloat", &.{after});
            const parsed = if (scope.truthy(try scope.invoke(number, "isNaN", &.{seconds}))) try binary(scope, .subtract, try scope.invoke(try scope.global("Date"), "parse", &.{after}), try scope.invoke(try scope.global("Date"), "now", &.{})) else try binary(scope, .multiply, seconds, c.JS_NewInt32(scope.engine.context, 1000));
            if (scope.truthy(try scope.invoke(number, "isFinite", &.{parsed}))) delay = parsed;
        }
    }
    if (!c.JS_IsUndefined(delay)) {
        const configured = try v.optional(scope, options, "maxRetryDelayMs");
        const cap = if (v.nullish(configured)) c.JS_NewInt32(scope.engine.context, 60000) else configured;
        if (try arithmetic.compare(scope.engine, .greater, cap, c.JS_NewInt32(scope.engine.context, 0)) and try arithmetic.compare(scope.engine, .greater, delay, cap)) {
            const seconds = try scope.invoke(try scope.global("Math"), "ceil", &.{try binary(scope, .divide, delay, c.JS_NewInt32(scope.engine.context, 1000))});
            const limit = try scope.invoke(try scope.global("Math"), "ceil", &.{try binary(scope, .divide, cap, c.JS_NewInt32(scope.engine.context, 1000))});
            var message = try scope.concat(try scope.concat(try scope.text("Server requested "), try scope.stringify(seconds)), try scope.text("s retry delay (max: "));
            message = try scope.concat(try scope.concat(message, try scope.stringify(limit)), try scope.text("s). "));
            return v.errorText(scope, try scope.concat(message, try scope.stringify(try scope.get(reason, "message"))));
        }
    } else {
        const exponential = try binary(scope, .multiply, try scope.invoke(try scope.global("Math"), "min", &.{ try binary(scope, .multiply, c.JS_NewFloat64(scope.engine.context, 0.5), try binary(scope, .power, c.JS_NewInt32(scope.engine.context, 2), attempt)), c.JS_NewInt32(scope.engine.context, 8) }), c.JS_NewInt32(scope.engine.context, 1000));
        delay = try binary(scope, .multiply, exponential, try binary(scope, .subtract, c.JS_NewInt32(scope.engine.context, 1), try binary(scope, .multiply, try scope.invoke(try scope.global("Math"), "random", &.{}), c.JS_NewFloat64(scope.engine.context, 0.25))));
    }
    try wait(scope, owner, try sleep(scope, delay, try v.optional(scope, options, "signal")), .retried, kind);
}
fn sleep(scope: *Scope, delay: c.JSValue, signal: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const pending = try flow.create(engine, signal);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    if (scope.truthy(try v.optional(scope, signal, "aborted"))) {
        try flow.settle(engine, pending.owner, true, try abortError(scope));
        return pending.promise;
    }
    const Adapter = struct {
        fn timer(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            const signal_value = try row.get(roots[0], "agent");
            if (!v.nullish(signal_value)) _ = try row.invoke(signal_value, "removeEventListener", &.{ try row.text("abort"), try row.get(roots[0], "onAbort") });
            try flow.settle(host, roots[0], false, c.pi_js_undefined());
            return c.pi_js_undefined();
        }
        fn abort(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            _ = try row.call(try row.global("clearTimeout"), c.pi_js_undefined(), &.{try row.get(roots[0], "timeout")});
            try flow.settle(host, roots[0], true, try abortError(&row));
            return c.pi_js_undefined();
        }
    };
    const on_abort = try scope.own(try @import("native_node_function.zig").create(engine, "onAbort", 0, Adapter.abort, &.{pending.owner}));
    try scope.put(pending.owner, "onAbort", on_abort);
    const timer = try scope.own(try @import("native_node_function.zig").create(engine, "", 0, Adapter.timer, &.{pending.owner}));
    const timeout = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ timer, try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(engine.context, 0), delay }) });
    try scope.put(pending.owner, "timeout", timeout);
    if (!v.nullish(signal)) {
        const once = try scope.object();
        try scope.put(once, "once", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), on_abort, once });
    }
    return pending.promise;
}
