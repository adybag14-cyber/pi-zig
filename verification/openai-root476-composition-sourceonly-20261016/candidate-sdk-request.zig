//! Selected pinned SDK6.40 chat request route. Every async source function
//! below is a genuine AF body; the private client record is not a public SDK
//! class. JSON chat payloads and maxRetries0 are the accessed Pi58 route.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const af = @import("native_async_function.zig");
const body = @import("native_async_body.zig");
const headers = @import("native_ai_openai_sdk_headers.zig");
const log = @import("native_ai_openai_client_log.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const Kind = enum { callApiKey, prepareOptions, bearerAuth, authHeaders, buildHeaders, buildRequest, prepareRequest, fetchWithTimeout, fetchWithAuth, makeRequest, shouldRetry, parseBody, defaultParseResponse, withResponse };
fn owned(scope: *Scope, value: c.JSValue) af.Action {
    return .{ .returned = c.JS_DupValue(scope.engine.context, value) };
}
fn addRequestID(scope: *Scope, value: c.JSValue, response: c.JSValue) !c.JSValue {
    if (!scope.truthy(value) or !c.JS_IsObject(value) or c.JS_IsFunction(scope.engine.context, value)) return value;
    if (scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{value}))) return value;
    const object = try scope.global("Object");
    const define = try scope.get(object, "defineProperty");
    const descriptor = try scope.object();
    try scope.put(descriptor, "value", try scope.invoke(try scope.get(response, "headers"), "get", &.{try scope.text("x-request-id")}));
    try scope.put(descriptor, "enumerable", c.JS_NewBool(scope.engine.context, false));
    return scope.call(define, object, &.{ value, try scope.text("_request_id"), descriptor });
}
/// The actual private defaultParseResponse route, also exposed to native
/// controls without fabricating a public SDK instance or parsing implementation.
pub fn parseResponse(scope: *Scope, client: c.JSValue, props: c.JSValue) !c.JSValue {
    return invoke(scope, client, .defaultParseResponse, &.{props});
}
fn wait(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: c_int) !af.Action {
    try body.wait(scope, job, value, stage);
    return body.action(scope, job);
}
fn escapeFatal(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror!void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        try body.rethrowRecognizedAllocation(engine, reason, generation);
        if (c.JS_IsUncatchableError(reason)) return err;
    };
}
fn invoke(scope: *Scope, client: c.JSValue, comptime kind: Kind, args: []const c.JSValue) anyerror!c.JSValue {
    const Adapter = struct {
        fn run(engine: *v.em.Engine, _: c.JSValue, values: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
            const generation_start = engine.native_allocation_generation;
            return dispatch(engine, roots[0], kind, values, slot, completion, input) catch |err| {
                try escapeFatal(engine, err, generation_start);
                return body.failure(engine, err);
            };
        }
    };
    const length: c_int = switch (kind) { .callApiKey, .parseBody, .withResponse => 0, .prepareRequest, .defaultParseResponse => 2, .makeRequest => 3, .fetchWithTimeout, .fetchWithAuth => 4, else => 1 };
    const name: [*:0]const u8 = if (kind == .callApiKey) "_callApiKey" else @tagName(kind);
    const function = try scope.own(if (kind == .parseBody) try af.createResumableArrow(scope.engine, "", 0, Adapter.run, &.{client}, c.pi_js_undefined()) else try af.createResumable(scope.engine, name, length, Adapter.run, &.{client}));
    return scope.call(function, client, args);
}
fn generation(scope: *Scope, job: c.JSValue, completion: af.Completion, input: c.JSValue) !void {
    if (completion == .start) {
        try scope.put(job, "generation", try scope.own(try scope.engine.checked(c.JS_NewBigUint64(scope.engine.context, scope.engine.native_allocation_generation))));
    } else if (completion == .rejected) {
        var start: u64 = 0;
        if (c.JS_ToBigUint64(scope.engine.context, &start, try scope.get(job, "generation")) < 0) return v.js.capture(scope.engine);
        try body.rethrowRecognizedAllocation(scope.engine, input, start);
    }
}
fn rest(scope: *Scope, input: c.JSValue) !c.JSValue {
    const excluded = [_][*:0]const u8{ "signal", "method" };
    const boxed = try scope.own(try scope.engine.checked(c.JS_ToObject(scope.engine.context, input)));
    const result = try scope.object();
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(scope.engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return v.js.capture(scope.engine);
    defer c.JS_FreePropertyEnum(scope.engine.context, names, count);
    var atoms: [excluded.len]c.JSAtom = undefined;
    var initialized: usize = 0;
    defer for (atoms[0..initialized]) |atom| c.JS_FreeAtom(scope.engine.context, atom);
    inline for (excluded) |key| {
        const atom = c.JS_NewAtom(scope.engine.context, key);
        if (atom == c.JS_ATOM_NULL) return v.js.capture(scope.engine);
        atoms[initialized] = atom;
        initialized += 1;
    }
    for (names[0..count]) |entry| {
        var skip = false;
        for (atoms) |atom| if (atom == entry.atom) {
            skip = true;
            break;
        };
        if (skip) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const found = c.JS_GetOwnProperty(scope.engine.context, &descriptor, boxed, entry.atom);
        if (found < 0) return v.js.capture(scope.engine);
        if (found == 0) continue;
        defer scope.engine.freeValue(descriptor.value);
        defer scope.engine.freeValue(descriptor.getter);
        defer scope.engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try scope.engine.checked(c.JS_GetProperty(scope.engine.context, boxed, entry.atom));
        if (c.JS_DefinePropertyValue(scope.engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return v.js.capture(scope.engine);
    }
    return result;
}

fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn packed(scope: *Scope, built: headers.Built) !c.JSValue {
    defer scope.engine.freeValue(built.values);
    defer scope.engine.freeValue(built.nulls);
    const result = try scope.object();
    try scope.put(result, "values", built.values);
    try scope.put(result, "nulls", built.nulls);
    return result;
}
fn nullable(scope: *Scope, value: c.JSValue) !headers.Layer {
    return .{ .nullable = .{ .values = try scope.get(value, "values"), .nulls = try scope.get(value, "nulls") } };
}
fn has(scope: *Scope, object: c.JSValue, name: [*:0]const u8) !bool {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(scope.engine);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    const result = c.JS_HasProperty(scope.engine.context, object, atom);
    if (result < 0) return v.js.capture(scope.engine);
    return result != 0;
}
fn abortError(scope: *Scope) !c.JSValue {
    return @import("native_ai_openai_sdk_error.zig").create(scope, c.pi_js_undefined(), c.pi_js_undefined(), try scope.text("Request was aborted."), c.pi_js_undefined());
}
fn keyFailure(scope: *Scope, reason: c.JSValue) !af.Action {
    const message = try scope.concat(try scope.text("Failed to get token from 'apiKey' function: "), try scope.get(reason, "message"));
    const options = try scope.object();
    try scope.put(options, "cause", reason);
    return ownedThrown(scope, try scope.own(try v.js.builtin(scope.engine, "Error", &.{ message, options })));
}
fn ownedThrown(scope: *Scope, reason: c.JSValue) af.Action {
    return .{ .thrown = c.JS_DupValue(scope.engine.context, reason) };
}
fn connectionFailure(scope: *Scope, reason: c.JSValue) !c.JSValue {
    const string = try scope.global("String");
    const is_abort = c.JS_IsObject(reason) and ((try has(scope, reason, "name") and try v.eq(scope, try scope.get(reason, "name"), "AbortError")) or (try has(scope, reason, "message") and scope.truthy(try scope.invoke(try scope.call(string, c.pi_js_undefined(), &.{try scope.get(reason, "message")}), "includes", &.{try scope.text("FetchRequestCanceledException")}))));
    var timeout = is_abort;
    if (!timeout) {
        const message = try scope.concat(try scope.call(string, c.pi_js_undefined(), &.{reason}), if (try has(scope, reason, "cause")) try scope.call(string, c.pi_js_undefined(), &.{try scope.get(reason, "cause")}) else try scope.text(""));
        var regex_args = [_]c.JSValue{ try scope.text("timed? ?out"), try scope.text("i") };
        const pattern = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, regex_args.len, &regex_args)));
        timeout = scope.truthy(try scope.invoke(pattern, "test", &.{message}));
    }
    const errors = @import("native_ai_openai_sdk_error.zig");
    if (timeout) return errors.create(scope, c.pi_js_undefined(), c.pi_js_undefined(), try scope.text("Request timed out."), c.pi_js_undefined());
    var current = reason;
    var message = try scope.text("Connection error.");
    var index: usize = 0;
    while (index < 8 and scope.truthy(current) and c.JS_IsObject(current)) : (index += 1) {
        if (try v.eq(scope, try scope.get(current, "code"), "UND_ERR_INVALID_ARG") and c.JS_IsString(try scope.get(current, "message")) and scope.truthy(try scope.invoke(try scope.get(current, "message"), "includes", &.{try scope.text("invalid onRequestStart method")}))) {
            message = try scope.text("Connection error. This may be caused by passing an undici dispatcher, such as ProxyAgent, that is incompatible with the fetch implementation. If you are using undici's ProxyAgent, pass the fetch implementation from the same undici package: import { fetch, ProxyAgent } from 'undici'; new OpenAI({ fetch, fetchOptions: { dispatcher: new ProxyAgent(...) } });");
            break;
        }
        current = try scope.get(current, "cause");
    }
    const result = try errors.create(scope, c.pi_js_undefined(), c.pi_js_undefined(), message, c.pi_js_undefined());
    if (scope.truthy(reason)) try scope.put(result, "cause", reason);
    return result;
}
fn cast(scope: *Scope, value: c.JSValue) !c.JSValue {
    const instance = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    if (instance != 0) return value;
    if (c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value)) {
        const foreign_start = scope.engine.native_allocation_generation;
        const foreign = castForeign(scope, value) catch |err| missing: {
            try escapeFatal(scope.engine, err, foreign_start);
            try @import("native_ai_partial_json.zig").discard(scope.engine, err, foreign_start);
            break :missing null;
        };
        if (foreign) |error_value| return error_value;
        const start = scope.engine.native_allocation_generation;
        const text = scope.invoke(try scope.global("JSON"), "stringify", &.{value}) catch |err| {
            try escapeFatal(scope.engine, err, start);
            try @import("native_ai_partial_json.zig").discard(scope.engine, err, start);
            return scope.own(try v.js.builtin(scope.engine, "Error", &.{value}));
        };
        return scope.own(try v.js.builtin(scope.engine, "Error", &.{text}));
    }
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{value}));
}
fn castForeign(scope: *Scope, value: c.JSValue) !?c.JSValue {
    const to_string = try scope.get(try scope.get(try scope.global("Object"), "prototype"), "toString");
    if (!try v.eq(scope, try scope.invoke(to_string, "call", &.{value}), "[object Error]")) return null;
    const message = try scope.get(value, "message");
    const options = try scope.object();
    if (scope.truthy(try scope.get(value, "cause"))) try scope.put(options, "cause", try scope.get(value, "cause"));
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{ message, options }));
    if (scope.truthy(try scope.get(value, "stack"))) try scope.put(result, "stack", try scope.get(value, "stack"));
    if (scope.truthy(try scope.get(value, "cause")) and !scope.truthy(try scope.get(result, "cause"))) try scope.put(result, "cause", try scope.get(value, "cause"));
    if (scope.truthy(try scope.get(value, "name"))) try scope.put(result, "name", try scope.get(value, "name"));
    return result;
}
fn caught(scope: *Scope, promise: c.JSValue, text_only: bool, boundary: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            var generation_start: u64 = 0;
            if (c.JS_ToBigUint64(engine.context, &generation_start, roots[1]) < 0) return v.js.capture(engine);
            try body.rethrowRecognizedAllocation(engine, argument(args, 0), generation_start);
            const reason = try cast(&row, argument(args, 0));
            return c.JS_DupValue(engine.context, if (row.truthy(roots[0])) try row.get(reason, "message") else reason);
        }
    };
    return scope.invoke(promise, "catch", &.{try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Adapter.call, &.{ c.JS_NewBool(scope.engine.context, text_only), boundary }))});
}
fn dispatch(engine: *v.em.Engine, client: c.JSValue, comptime kind: Kind, args: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const job = if (completion == .start) try body.init(&scope, slot) else slot.*;
    try generation(&scope, job, completion, input);
    const stage = if (completion == .start) @as(c_int, 0) else try body.stage(&scope, job);
    if (completion == .rejected and kind != .fetchWithTimeout and kind != .callApiKey) return .{ .thrown = c.JS_DupValue(engine.context, input) };
    switch (kind) {
        .callApiKey => {
            if (stage == 0) {
                const key = try scope.get(client, "constructorApiKey");
                if (!c.JS_IsFunction(engine.context, key)) return owned(&scope, c.JS_NewBool(engine.context, false));
                const key_generation = engine.native_allocation_generation;
                const token = scope.call(key, c.pi_js_undefined(), &.{}) catch |err| {
                    try escapeFatal(engine, err, key_generation);
                    const failure = try body.failure(engine, err);
                    const reason = switch (failure) { .thrown => |value| value, else => unreachable };
                    defer engine.freeValue(reason);
                    return keyFailure(&scope, reason);
                };
                return wait(&scope, job, token, 1);
            }
            if (completion == .rejected) return keyFailure(&scope, input);
            if (!c.JS_IsString(input) or !scope.truthy(input)) return v.errorText(&scope, try scope.concat(try scope.text("Expected 'apiKey' function argument to return a string but it returned "), input));
            try scope.put(client, "apiKey", input);
            return owned(&scope, c.JS_NewBool(engine.context, true));
        },
        .prepareOptions => {
            if (stage == 0) return wait(&scope, job, try invoke(&scope, client, .callApiKey, &.{}), 1);
            return owned(&scope, c.pi_js_undefined());
        },
        .prepareRequest => return owned(&scope, c.pi_js_undefined()),
        .bearerAuth => {
            const values = try scope.object();
            const key = try scope.get(client, "apiKey");
            if (v.nullish(key)) return owned(&scope, c.pi_js_undefined());
            try scope.put(values, "Authorization", try scope.concat(try scope.text("Bearer "), key));
            return owned(&scope, try packed(&scope, try headers.build(engine, &.{values})));
        },
        .authHeaders => {
            if (stage == 0) return wait(&scope, job, try invoke(&scope, client, .bearerAuth, &.{argument(args, 0)}), 1);
            const source: headers.Layer = if (v.nullish(input)) .{ .plain = input } else try nullable(&scope, input);
            return owned(&scope, try packed(&scope, try headers.buildMixed(engine, &.{ source, .{ .plain = c.pi_js_null() } })));
        },
        .buildHeaders => {
            if (stage == 0) {
                try scope.put(job, "idempotency", try scope.object());
                try scope.put(job, "options", argument(args, 0));
                try scope.put(job, "bodyHeaders", argument(args, 1));
                const base = try scope.object();
                try scope.put(base, "Accept", try scope.text("application/json"));
                try scope.put(base, "User-Agent", try @import("native_ai_user_agent.zig").runtime(&scope));
                try scope.put(base, "X-Stainless-Retry-Count", try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{c.JS_NewInt32(engine.context, 0)}));
                const timeout = try scope.get(argument(args, 0), "timeout");
                if (scope.truthy(timeout)) {
                    const string = try scope.global("String");
                    const math = try scope.global("Math");
                    const trunc = try scope.get(math, "trunc");
                    const seconds = try scope.own(try arithmetic.binary(engine, .divide, try scope.get(argument(args, 0), "timeout"), c.JS_NewInt32(engine.context, 1000)));
                    try scope.put(base, "X-Stainless-Timeout", try scope.call(string, c.pi_js_undefined(), &.{try scope.call(trunc, math, &.{seconds})}));
                }
                try scope.put(base, "OpenAI-Organization", try scope.get(client, "organization"));
                try scope.put(base, "OpenAI-Project", try scope.get(client, "project"));
                try scope.put(job, "base", base);
                return wait(&scope, job, try invoke(&scope, client, .authHeaders, &.{argument(args, 0)}), 1);
            }
            const defaults: headers.Layer = if (scope.truthy(try scope.get(client, "headersPrepared"))) .{ .nullable = .{ .values = try scope.get(client, "defaultHeaders"), .nulls = try scope.get(client, "headerNulls") } } else .{ .plain = try scope.get(client, "defaultHeaders") };
            const built = try headers.buildMixed(engine, &.{ .{ .plain = try scope.get(job, "idempotency") }, .{ .plain = try scope.get(job, "base") }, try nullable(&scope, input), defaults, .{ .plain = try scope.get(job, "bodyHeaders") }, .{ .plain = try scope.get(try scope.get(job, "options"), "headers") } });
            defer engine.freeValue(built.values);
            defer engine.freeValue(built.nulls);
            if (!scope.truthy(try scope.invoke(built.values, "get", &.{try scope.text("authorization")})) and !scope.truthy(try scope.invoke(built.values, "get", &.{try scope.text("api-key")})) and !scope.truthy(try scope.invoke(built.nulls, "has", &.{try scope.text("authorization")})) and !scope.truthy(try scope.invoke(built.nulls, "has", &.{try scope.text("api-key")}))) return v.errorText(&scope, try scope.text("Could not resolve authentication method. Expected either apiKey or adminAPIKey to be set. Or for one of the \"Authorization\" or \"api-key\" headers to be explicitly omitted"));
            return owned(&scope, built.values);
        },
        .buildRequest => {
            if (stage == 0) {
                const options = try v.spread(&scope, argument(args, 0));
                const base = try scope.get(client, "baseURL");
                const path = try scope.text("/chat/completions");
                const suffix = if (scope.truthy(try scope.invoke(base, "endsWith", &.{try scope.text("/")}))) try scope.invoke(path, "slice", &.{c.JS_NewInt32(engine.context, 1)}) else path;
                const url = try scope.invoke(try scope.own(try v.js.builtin(engine, "URL", &.{try scope.concat(base, suffix)})), "toString", &.{});
                if (try has(&scope, options, "timeout")) {
                    const timeout = try scope.get(options, "timeout");
                    if (!c.JS_IsNumber(timeout) or !scope.truthy(try scope.invoke(try scope.global("Number"), "isInteger", &.{timeout}))) return v.errorText(&scope, try scope.text("timeout must be an integer"));
                    if (try arithmetic.compare(engine, .less, timeout, c.JS_NewInt32(engine.context, 0))) return v.errorText(&scope, try scope.text("timeout must be a positive integer"));
                }
                const raw_timeout = try scope.get(options, "timeout");
                try scope.put(options, "timeout", if (v.nullish(raw_timeout)) c.JS_NewInt32(engine.context, 600000) else raw_timeout);
                try scope.put(job, "options", options);
                try scope.put(job, "url", url);
                // Pi58 supplies a JSON body and no request-level raw headers.
                const body_headers = try scope.object();
                const payload = try scope.get(options, "body");
                if (scope.truthy(payload)) {
                    const raw = try headers.build(engine, &.{try scope.get(options, "headers")});
                    defer engine.freeValue(raw.values);
                    defer engine.freeValue(raw.nulls);
                    try scope.put(body_headers, "content-type", try scope.text("application/json"));
                    try scope.put(job, "body", try scope.invoke(try scope.global("JSON"), "stringify", &.{payload}));
                }
                return wait(&scope, job, try invoke(&scope, client, .buildHeaders, &.{ argument(args, 0), if (scope.truthy(payload)) body_headers else c.pi_js_undefined() }), 1);
            }
            const options = try scope.get(job, "options");
            const req = try scope.object();
            try scope.put(req, "method", try scope.get(options, "method"));
            try scope.put(req, "headers", input);
            if (scope.truthy(try scope.get(options, "signal"))) try scope.put(req, "signal", try scope.get(options, "signal"));
            const payload = try scope.get(job, "body");
            if (scope.truthy(payload)) try scope.put(req, "body", payload);
            const result = try scope.object();
            try scope.put(result, "req", req);
            try scope.put(result, "url", try scope.get(job, "url"));
            try scope.put(result, "timeout", try scope.get(options, "timeout"));
            return owned(&scope, result);
        },
        .fetchWithTimeout => {
            if (stage == 0) {
                const init = argument(args, 1);
                const controller = argument(args, 3);
                const Abort = struct {
                    fn call(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                        return v.js.invoke(host, roots[0], "abort", &.{});
                    }
                };
                const abort = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 0, Abort.call, &.{controller}));
                const signal = try scope.get(init, "signal");
                const method = try scope.get(init, "method");
                const options = try rest(&scope, init);
                if (scope.truthy(signal)) {
                    const once = try scope.object();
                    try scope.put(once, "once", c.JS_NewBool(engine.context, true));
                    _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), abort, once });
                }
                const timeout = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ abort, argument(args, 2) });
                try scope.put(job, "timeout", timeout);
                const stream = try scope.global("ReadableStream");
                const payload = try scope.get(options, "body");
                var readable = false;
                if (scope.truthy(stream)) {
                    const instance = c.JS_IsInstanceOf(engine.context, payload, stream);
                    if (instance < 0) return v.js.capture(engine);
                    readable = instance != 0;
                }
                if (!readable and c.JS_IsObject(payload)) {
                    const symbol = try scope.own(try engine.checked(c.JS_GetAsyncIteratorSymbol(engine.context)));
                    const atom = c.JS_ValueToAtom(engine.context, symbol);
                    if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
                    defer c.JS_FreeAtom(engine.context, atom);
                    const present = c.JS_HasProperty(engine.context, payload, atom);
                    if (present < 0) return v.js.capture(engine);
                    readable = present != 0;
                }
                const fetch_options = try scope.object();
                try scope.put(fetch_options, "signal", try scope.get(controller, "signal"));
                if (readable) try scope.put(fetch_options, "duplex", try scope.text("half"));
                try scope.put(fetch_options, "method", try scope.text("GET"));
                try v.js.spreadInto(engine, fetch_options, options);
                if (scope.truthy(method)) try scope.put(fetch_options, "method", try scope.invoke(method, "toUpperCase", &.{}));
                // Deliberately use the captured function's live .call property,
                // with undefined as thisArg, exactly as primary fetchWithTimeout.
                const fetch_generation = engine.native_allocation_generation;
                const fetched = scope.invoke(try scope.get(client, "fetch"), "call", &.{ c.pi_js_undefined(), argument(args, 0), fetch_options }) catch |err| {
                    try escapeFatal(engine, err, fetch_generation);
                    const action = try body.failure(engine, err);
                    errdefer switch (action) { inline else => |value| engine.freeValue(value) };
                    _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timeout});
                    return action;
                };
                return wait(&scope, job, fetched, 1);
            }
            _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{try scope.get(job, "timeout")});
            return if (completion == .rejected) .{ .thrown = c.JS_DupValue(engine.context, input) } else owned(&scope, input);
        },
        .fetchWithAuth => {
            if (stage == 0) return wait(&scope, job, try invoke(&scope, client, .fetchWithTimeout, args), 1);
            return owned(&scope, input);
        },
        .shouldRetry => {
            const response = argument(args, 0);
            const hint = try scope.invoke(try scope.get(response, "headers"), "get", &.{try scope.text("x-should-retry")});
            if (try v.eq(&scope, hint, "true")) return owned(&scope, c.JS_NewBool(engine.context, true));
            if (try v.eq(&scope, hint, "false")) return owned(&scope, c.JS_NewBool(engine.context, false));
            inline for (.{ 408, 409, 429 }) |status| if (scope.equal(try scope.get(response, "status"), c.JS_NewInt32(engine.context, status))) return owned(&scope, c.JS_NewBool(engine.context, true));
            return owned(&scope, c.JS_NewBool(engine.context, try arithmetic.compare(engine, .greater_equal, try scope.get(response, "status"), c.JS_NewInt32(engine.context, 500))));
        },
        .makeRequest => return make(&scope, client, job, stage, args, input),
        .parseBody => {
            if (stage == 1) return owned(&scope, try addRequestID(&scope, input, try scope.get(job, "response")));
            if (stage == 2) return owned(&scope, input);
            const props = argument(args, 0);
            const response = argument(args, 1);
            if (scope.truthy(try scope.get(try scope.get(props, "options"), "stream"))) {
                const controller = try scope.get(props, "controller");
                return owned(&scope, try scope.own(try @import("native_ai_openai_sdk_stream.zig").fromBodyIterator(engine, try @import("native_ai_openai_sdk_readable.zig").deferred(&scope, response, controller), .{ .codec = try scope.own(try @import("native_ai_openai_sdk_chunks.zig").codec(engine)), .controller = controller, .error_factory = try scope.own(try @import("native_ai_openai_sdk_error.zig").factory(engine, try scope.get(response, "headers"))), .logger = try log.loggerFor(&scope, client) })));
            }
            if (scope.equal(try scope.get(response, "status"), c.JS_NewInt32(engine.context, 204))) return owned(&scope, c.pi_js_null());
            if (scope.truthy(try scope.get(try scope.get(props, "options"), "__binaryResponse"))) return owned(&scope, response);
            const content_type = try scope.invoke(try scope.get(response, "headers"), "get", &.{try scope.text("content-type")});
            const media = if (v.nullish(content_type)) c.pi_js_undefined() else media_value: {
                const first = try v.at(&scope, try scope.invoke(content_type, "split", &.{try scope.text(";")}), 0);
                break :media_value if (v.nullish(first)) c.pi_js_undefined() else try scope.invoke(first, "trim", &.{});
            };
            var is_json = false;
            if (!v.nullish(media)) {
                is_json = scope.truthy(try scope.invoke(media, "includes", &.{try scope.text("application/json")}));
                if (!is_json) is_json = scope.truthy(try scope.invoke(media, "endsWith", &.{try scope.text("+json")}));
            }
            if (is_json) {
                if (try v.eq(&scope, try scope.invoke(try scope.get(response, "headers"), "get", &.{try scope.text("content-length")}), "0")) return owned(&scope, c.pi_js_undefined());
                try scope.put(job, "response", response);
                return wait(&scope, job, try scope.invoke(response, "json", &.{}), 1);
            }
            return wait(&scope, job, try scope.invoke(response, "text", &.{}), 2);
        },
        .defaultParseResponse => {
            if (stage == 0) {
                const props = argument(args, 0);
                const response = try scope.get(props, "response");
                try scope.put(job, "response", response);
                // Actual outer destructuring precedes the parse IIFE. Keep
                // these live reads even while detailed diagnostics stay pending.
                inline for (.{ "requestLogID", "retryOfRequestLogID", "startTime" }) |name| try scope.put(job, name, try scope.get(props, name));
                return wait(&scope, job, try invoke(&scope, client, .parseBody, &.{ props, response }), 1);
            }
            const logger = try log.loggerFor(&scope, client);
            const debug = try scope.get(logger, "debug");
            const message = try scope.concat(try scope.concat(try scope.text("["), try scope.stringify(try scope.get(job, "requestLogID"))), try scope.text("] response parsed"));
            const details = try scope.object();
            try scope.put(details, "retryOfRequestLogID", try scope.get(job, "retryOfRequestLogID"));
            const response = try scope.get(job, "response");
            try scope.put(details, "url", try scope.get(response, "url"));
            try scope.put(details, "status", try scope.get(response, "status"));
            try scope.put(details, "body", input);
            try scope.put(details, "durationMs", try scope.own(try arithmetic.binary(engine, .subtract, try scope.invoke(try scope.global("Date"), "now", &.{}), try scope.get(job, "startTime"))));
            _ = try scope.call(debug, logger, &.{ message, try log.formatDetails(&scope, details) });
            return owned(&scope, input);
        },
        .withResponse => {
            if (stage == 0) {
                const promise = argument(args, 0);
                const Select = struct {
                    fn parse(host: *v.em.Engine, _: c.JSValue, values: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                        var row: Scope = .{ .engine = host };
                        defer row.deinit();
                        return c.JS_DupValue(host.context, try invoke(&row, roots[0], .defaultParseResponse, &.{argument(values, 0)}));
                    }
                    fn response(host: *v.em.Engine, _: c.JSValue, values: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                        return v.js.get(host, argument(values, 0), "response");
                    }
                };
                const parses = try scope.invoke(promise, "then", &.{try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, Select.parse, &.{client}))});
                const responses = try scope.invoke(promise, "then", &.{try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, Select.response, &.{}))});
                const pairs = try scope.array();
                try scope.index(pairs, 0, parses);
                try scope.index(pairs, 1, responses);
                return wait(&scope, job, try scope.invoke(try scope.global("Promise"), "all", &.{pairs}), 1);
            }
            const result = try scope.object();
            try scope.put(result, "data", try v.at(&scope, input, 0));
            const response = try v.at(&scope, input, 1);
            try scope.put(result, "response", response);
            try scope.put(result, "request_id", try scope.invoke(try scope.get(response, "headers"), "get", &.{try scope.text("x-request-id")}));
            return owned(&scope, result);
        },
    }
}
fn make(scope: *Scope, client: c.JSValue, job: c.JSValue, stage: c_int, args: []const c.JSValue, input: c.JSValue) anyerror!af.Action {
    const engine = scope.engine;
    switch (stage) {
        0 => return wait(scope, job, argument(args, 0), 1),
        1 => {
            try scope.put(job, "options", input);
            return wait(scope, job, try invoke(scope, client, .prepareOptions, &.{input}), 2);
        },
        2 => return wait(scope, job, try invoke(scope, client, .buildRequest, &.{try scope.get(job, "options")}), 3),
        3 => {
            try scope.put(job, "built", input);
            return wait(scope, job, try invoke(scope, client, .prepareRequest, &.{ try scope.get(input, "req"), input }), 4);
        },
        4 => {
            const options = try scope.get(job, "options");
            if (scope.truthy(try v.optional(scope, try scope.get(options, "signal"), "aborted"))) return .{ .thrown = c.JS_DupValue(engine.context, try abortError(scope)) };
            const controller = try scope.own(try v.js.builtin(engine, "AbortController", &.{}));
            try scope.put(job, "controller", controller);
            const built = try scope.get(job, "built");
            return wait(scope, job, try caught(scope, try invoke(scope, client, .fetchWithAuth, &.{ try scope.get(built, "url"), try scope.get(built, "req"), try scope.get(built, "timeout"), controller }), false, try scope.get(job, "generation")), 5);
        },
        5 => {
            const error_instance = c.JS_IsInstanceOf(engine.context, input, try scope.global("Error"));
            if (error_instance < 0) return v.js.capture(engine);
            if (error_instance != 0) {
                if (scope.truthy(try v.optional(scope, try scope.get(try scope.get(job, "options"), "signal"), "aborted"))) return .{ .thrown = c.JS_DupValue(engine.context, try abortError(scope)) };
                const failure = try connectionFailure(scope, input);
                return .{ .thrown = c.JS_DupValue(engine.context, failure) };
            }
            try scope.put(job, "response", input);
            if (!scope.truthy(try scope.get(input, "ok"))) return wait(scope, job, try invoke(scope, client, .shouldRetry, &.{input}), 6);
            const props = try scope.object();
            try scope.put(props, "response", input);
            try scope.put(props, "controller", try scope.get(job, "controller"));
            try scope.put(props, "options", try scope.get(job, "options"));
            return owned(scope, props);
        },
        6 => return wait(scope, job, try caught(scope, try scope.invoke(try scope.get(job, "response"), "text", &.{}), true, try scope.get(job, "generation")), 7),
        7 => {
            const response = try scope.get(job, "response");
            const start = engine.native_allocation_generation;
            const parsed = scope.invoke(try scope.global("JSON"), "parse", &.{input}) catch |err| missing: {
                try escapeFatal(engine, err, start);
                try @import("native_ai_partial_json.zig").discard(engine, err, start);
                break :missing c.pi_js_undefined();
            };
            const failure = try @import("native_ai_openai_sdk_error.zig").create(scope, try scope.get(response, "status"), try v.optional(scope, parsed, "error"), if (scope.truthy(parsed)) c.pi_js_undefined() else input, try scope.get(response, "headers"));
            return .{ .thrown = c.JS_DupValue(engine.context, failure) };
        },
        else => unreachable,
    }
}
/// Real synchronous methodRequest construction followed by actual withResponse
/// AF. No public APIPromise subclass is fabricated for this private route.
pub fn withResponse(scope: *Scope, client: c.JSValue, payload: c.JSValue, request_options: c.JSValue) !c.JSValue {
    const options = try scope.object();
    try scope.put(options, "body", payload);
    try v.js.spreadInto(scope.engine, options, request_options);
    const streamed = try scope.get(payload, "stream");
    try scope.put(options, "stream", if (v.nullish(streamed)) c.JS_NewBool(scope.engine.context, false) else streamed);
    const security = try scope.object();
    try scope.put(security, "bearerAuth", c.JS_NewBool(scope.engine.context, true));
    try scope.put(options, "__security", security);
    const Mapper = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            const result = try row.object();
            try row.put(result, "method", try row.text("post"));
            try row.put(result, "path", try row.text("/chat/completions"));
            try v.js.spreadInto(engine, result, argument(args, 0));
            return c.JS_DupValue(engine.context, result);
        }
    };
    const mapped = try scope.invoke(try scope.invoke(try scope.global("Promise"), "resolve", &.{options}), "then", &.{try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Mapper.call, &.{}))});
    const response = try invoke(scope, client, .makeRequest, &.{mapped});
    return invoke(scope, client, .withResponse, &.{response});
}
