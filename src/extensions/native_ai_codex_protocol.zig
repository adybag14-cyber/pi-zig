//! Codex WS request shapes and session diagnostics over live native VM values.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const errors = @import("native_ai_codex_errors.zig");
const math = @import("native_image_arithmetic.zig");
fn json(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.invoke(try scope.global("JSON"), "stringify", &.{value});
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    const cache_key = "native:openai-codex-responses-state";
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "stats", try scope.own(try v.js.builtin(engine, "Map", &.{})));
    try scope.put(state, "fallback", try scope.own(try v.js.builtin(engine, "Set", &.{})));
    try scope.put(state, "errors", try scope.own(try errors.create(engine)));
    try scope.put(state, "uuid", try scope.own(try @import("native_ai_uuid.zig").create(engine)));
    const exports = try scope.object();
    inline for (.{ "getOpenAICodexWebSocketDebugStats", "resetOpenAICodexWebSocketDebugStats", "closeOpenAICodexWebSocketSessions" }, 0..) |method, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                const session = if (args.len > 0) args[0] else c.pi_js_undefined();
                if (index == 0) {
                    const found = try row.invoke(try row.get(roots[0], "stats"), "get", &.{session});
                    return if (row.truthy(found)) c.JS_DupValue(host.context, try v.spread(&row, found)) else c.pi_js_undefined();
                }
                if (index == 1) {
                    inline for (.{ "stats", "fallback" }) |key| {
                        const values = try row.get(roots[0], key);
                        _ = try row.invoke(values, if (row.truthy(session)) "delete" else "clear", if (row.truthy(session)) &.{session} else &.{});
                    }
                } else try @import("native_ai_codex_socket.zig").closeSession(host, if (row.truthy(session)) session else c.pi_js_undefined());
                return c.pi_js_undefined();
            }
        };
        try scope.put(exports, method, try scope.own(try @import("native_node_function.zig").create(engine, method, 1, Adapter.call, &.{state})));
    }
    try scope.put(state, "exports", exports);
    const registry = try scope.own(try @import("native_ai_session_resources.zig").bindings(engine));
    _ = try scope.invoke(registry, "registerSessionResourceCleanup", &.{try scope.get(exports, "closeOpenAICodexWebSocketSessions")});
    const retained = c.JS_DupValue(engine.context, state);
    errdefer engine.freeValue(retained);
    try engine.native_module_values.put(engine.gpa, cache_key, retained);
    return c.JS_DupValue(engine.context, state);
}
pub fn url(scope: *Scope, supplied: c.JSValue, websocket: bool) !c.JSValue {
    const raw = if (scope.truthy(supplied) and try v.length(scope, try scope.invoke(supplied, "trim", &.{})) > 0) supplied else try scope.text("https://chatgpt.com/backend-api");
    const pattern = try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("/+$")}));
    const normalized = try scope.invoke(raw, "replace", &.{ pattern, try scope.text("") });
    const endpoint = if (scope.truthy(try scope.invoke(normalized, "endsWith", &.{try scope.text("/codex/responses")}))) normalized else try scope.concat(normalized, try scope.text(if (scope.truthy(try scope.invoke(normalized, "endsWith", &.{try scope.text("/codex")}))) "/responses" else "/codex/responses"));
    if (!websocket) return endpoint;
    const parsed = try scope.own(try v.js.builtin(scope.engine, "URL", &.{endpoint}));
    const protocol = try scope.get(parsed, "protocol");
    if (try v.eq(scope, protocol, "https:")) try scope.set(parsed, "protocol", try scope.text("wss:")) else if (try v.eq(scope, protocol, "http:")) try scope.set(parsed, "protocol", try scope.text("ws:"));
    return scope.invoke(parsed, "toString", &.{});
}
pub fn headers(scope: *Scope, initial: c.JSValue, additional: c.JSValue, account: c.JSValue, token: c.JSValue, user_agent: c.JSValue, request_id: c.JSValue, websocket: bool) !c.JSValue {
    const defaults = try scope.object();
    try scope.put(defaults, "originator", try scope.text("pi"));
    try scope.put(defaults, "User-Agent", user_agent);
    const result = try scope.own(try v.js.builtin(scope.engine, "Headers", &.{defaults}));
    inline for (.{ false, true }) |deletion| {
        const value = if (deletion) additional else initial;
        const source = if (scope.truthy(value)) value else try scope.object();
        var entries = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{source}));
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const key = try v.at(scope, entry, 0);
            const field = try v.at(scope, entry, 1);
            _ = try scope.invoke(result, if (deletion and c.JS_IsNull(field)) "delete" else "set", if (deletion and c.JS_IsNull(field)) &.{key} else &.{ key, field });
        }
    }
    _ = try scope.invoke(result, "set", &.{ try scope.text("Authorization"), try scope.concat(try scope.text("Bearer "), token) });
    _ = try scope.invoke(result, "set", &.{ try scope.text("chatgpt-account-id"), account });
    if (websocket) {
        inline for (.{ "accept", "content-type", "OpenAI-Beta", "openai-beta" }) |key| _ = try scope.invoke(result, "delete", &.{try scope.text(key)});
        _ = try scope.invoke(result, "set", &.{ try scope.text("OpenAI-Beta"), try scope.text("responses_websockets=2026-02-06") });
    } else {
        _ = try scope.invoke(result, "set", &.{ try scope.text("OpenAI-Beta"), try scope.text("responses=experimental") });
        _ = try scope.invoke(result, "set", &.{ try scope.text("accept"), try scope.text("text/event-stream") });
        _ = try scope.invoke(result, "set", &.{ try scope.text("content-type"), try scope.text("application/json") });
    }
    if (websocket or scope.truthy(request_id)) {
        _ = try scope.invoke(result, "set", &.{ try scope.text("session-id"), request_id });
        _ = try scope.invoke(result, "set", &.{ try scope.text("x-client-request-id"), request_id });
    }
    return result;
}
fn withoutInput(scope: *Scope, body: c.JSValue) !c.JSValue {
    // Destructuring reads the excluded fields before copying enumerable own
    // string/symbol keys, and does not evaluate excluded getters a second time.
    _ = try scope.get(body, "input");
    _ = try scope.get(body, "previous_response_id");
    const engine = scope.engine;
    const boxed = try scope.own(try engine.checked(c.JS_ToObject(engine.context, body)));
    const result = try scope.object();
    const input = c.JS_NewAtom(engine.context, "input");
    if (input == c.JS_ATOM_NULL) return v.js.capture(engine);
    defer c.JS_FreeAtom(engine.context, input);
    const previous = c.JS_NewAtom(engine.context, "previous_response_id");
    if (previous == c.JS_ATOM_NULL) return v.js.capture(engine);
    defer c.JS_FreeAtom(engine.context, previous);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return v.js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        if (entry.atom == input or entry.atom == previous) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return v.js.capture(engine);
        if (present == 0) continue;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, boxed, entry.atom));
        if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    }
    return result;
}
pub fn request(scope: *Scope, entry: c.JSValue, body: c.JSValue, use_cached: bool) !c.JSValue {
    if (!use_cached or v.nullish(entry)) return body;
    const continuation = try scope.get(entry, "continuation");
    if (!scope.truthy(continuation)) return body;
    const last = try scope.get(continuation, "lastRequestBody");
    if (scope.equal(try json(scope, try withoutInput(scope, body)), try json(scope, try withoutInput(scope, last)))) {
        const supplied = try scope.get(body, "input");
        const current = if (v.nullish(supplied)) try scope.array() else supplied;
        const prior = try scope.get(last, "input");
        const baseline = try scope.array();
        inline for (.{ false, true }) |response_items| {
            const source = if (response_items) try scope.get(continuation, "lastResponseItems") else if (v.nullish(prior)) try scope.array() else prior;
            var items = try v.iterator(scope, source);
            defer items.deinit();
            errdefer items.closePreserving();
            while (try items.next()) |item| {
                defer scope.engine.freeValue(item);
                _ = try scope.invoke(baseline, "push", &.{item});
            }
        }
        const length = try scope.get(baseline, "length");
        if (!try math.compare(scope.engine, .less, try scope.get(current, "length"), length)) {
            const prefix = try scope.invoke(current, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), length });
            if (scope.equal(try json(scope, prefix), try json(scope, baseline)) and scope.truthy(try scope.get(continuation, "lastResponseId"))) {
                const delta = try scope.invoke(current, "slice", &.{length});
                const result = try v.spread(scope, body);
                try scope.put(result, "previous_response_id", try scope.get(continuation, "lastResponseId"));
                try scope.put(result, "input", delta);
                return result;
            }
        }
    }
    try scope.put(entry, "continuation", c.pi_js_undefined());
    return body;
}
pub fn stats(scope: *Scope, state: c.JSValue, session: c.JSValue) !c.JSValue {
    if (!scope.truthy(session)) return c.pi_js_undefined();
    const map = try scope.get(state, "stats");
    var result = try scope.invoke(map, "get", &.{session});
    if (!scope.truthy(result)) {
        result = try scope.object();
        inline for (.{ "requests", "connectionsCreated", "connectionsReused", "cachedContextRequests", "storeTrueRequests", "fullContextRequests", "deltaRequests", "lastInputItems", "websocketFailures", "sseFallbacks" }) |key| try scope.put(result, key, c.JS_NewInt32(scope.engine.context, 0));
        _ = try scope.invoke(map, "set", &.{ session, result });
    }
    return result;
}
pub fn increment(scope: *Scope, object: c.JSValue, key: [*:0]const u8) !void {
    try scope.put(object, key, try scope.own(try math.binary(scope.engine, .add, try scope.get(object, key), c.JS_NewInt32(scope.engine.context, 1))));
}
pub fn fallbackActive(scope: *Scope, state: c.JSValue, session: c.JSValue) !bool {
    return scope.truthy(session) and scope.truthy(try scope.invoke(try scope.get(state, "fallback"), "has", &.{session}));
}
pub fn recordFallback(scope: *Scope, state: c.JSValue, session: c.JSValue) !void {
    const row = try stats(scope, state, session);
    if (v.nullish(row)) return;
    try increment(scope, row, "sseFallbacks");
    try scope.put(row, "websocketFallbackActive", c.pi_js_bool(scope.engine.context, @intFromBool(try fallbackActive(scope, state, session))));
}
pub fn recordFailure(scope: *Scope, state: c.JSValue, session: c.JSValue, reason: c.JSValue) !void {
    if (!scope.truthy(session)) return;
    _ = try scope.invoke(try scope.get(state, "fallback"), "add", &.{session});
    const row = try stats(scope, state, session);
    try increment(scope, row, "websocketFailures");
    try scope.put(row, "lastWebSocketError", try errors.thrownText(scope, reason));
    try scope.put(row, "websocketFallbackActive", c.pi_js_bool(scope.engine.context, 1));
}
pub fn diagnostic(scope: *Scope, output: c.JSValue, reason: c.JSValue, details: c.JSValue) !void {
    const record = try scope.object();
    try scope.put(record, "type", try scope.text("provider_transport_failure"));
    try scope.put(record, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    const error_info = try scope.object();
    if (try errors.instance(scope, reason, try scope.global("Error"))) {
        const name = try scope.get(reason, "name");
        const message = try scope.get(reason, "message");
        const code = try scope.get(reason, "code");
        try scope.put(error_info, "name", if (scope.truthy(name)) name else c.pi_js_undefined());
        try scope.put(error_info, "message", if (scope.truthy(message)) message else name);
        try scope.put(error_info, "stack", try scope.get(reason, "stack"));
        try scope.put(error_info, "code", if (c.JS_IsString(code) or c.JS_IsNumber(code)) code else c.pi_js_undefined());
    } else {
        try scope.put(error_info, "name", try scope.text("ThrownValue"));
        try scope.put(error_info, "message", try errors.thrownText(scope, reason));
    }
    try scope.put(record, "error", error_info);
    try scope.put(record, "details", details);
    const list = try scope.array();
    const prior = try scope.get(output, "diagnostics");
    var entries = try v.iterator(scope, if (v.nullish(prior)) try scope.array() else prior);
    defer entries.deinit();
    errdefer entries.closePreserving();
    while (try entries.next()) |entry| {
        defer scope.engine.freeValue(entry);
        _ = try scope.invoke(list, "push", &.{entry});
    }
    _ = try scope.invoke(list, "push", &.{record});
    try scope.put(output, "diagnostics", list);
}
