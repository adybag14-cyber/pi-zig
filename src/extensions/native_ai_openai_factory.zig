//! Actual native OpenAI-completions stream API over owned HTTP/SSE transport.
//! Private binding until genuine full wire/request/event/callback qualification.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const asynchronous = @import("native_async_function.zig");
const async_body = @import("native_async_body.zig");
const sdk_request = @import("native_ai_openai_sdk_request.zig");
const request = @import("native_ai_openai_request.zig");
const Stage = enum(c_int) { payload, ready, response, next, chunk, closed };
pub fn create(engine: *v.em.Engine) !c.JSValue {
    try @import("native_ai_openai_client_options.zig").initialize(engine);
    try @import("native_stream.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.own(try @import("native_ai_openai_dependencies.zig").create(engine));
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
fn hasHeader(scope: *Scope, headers: c.JSValue, expected: []const u8) !bool {
    if (!scope.truthy(headers)) return false;
    var rows = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{headers}));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const key = try v.at(&row, entry, 0);
        const value = try v.at(&row, entry, 1);
        if (try v.eq(&row, try row.invoke(key, "toLowerCase", &.{}), expected) and !c.JS_IsNull(value) and try v.length(&row, try row.invoke(value, "trim", &.{})) > 0) return true;
    }
    return false;
}
fn apiKey(scope: *Scope, model: c.JSValue, options: c.JSValue) !c.JSValue {
    const key = try v.optional(scope, options, "apiKey");
    if (scope.truthy(key)) return key;
    const headers = try v.optional(scope, options, "headers");
    if (try hasHeader(scope, headers, "authorization") or try hasHeader(scope, headers, "cf-aig-authorization")) return scope.text("unused");
    return v.errorText(scope, try scope.concat(try scope.text("No API key for provider: "), try scope.stringify(try scope.get(model, "provider"))));
}
fn stream(engine: *v.em.Engine, dependencies: c.JSValue, args: []const c.JSValue, simple: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var options = args[2];
    if (simple) {
        _ = try apiKey(&scope, args[0], options);
        options = try @import("native_ai_openai_dependencies.zig").options(&scope, dependencies, args[0], args[1], options);
    }
    const module = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativeOpenAIStreamMissing;
    const constructor = try scope.get(module, "AssistantMessageEventStream");
    const outer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
    const compat = try scope.own(try @import("native_ai_openai_compat_options.zig").resolve(engine, args[0]));
    const context = try scope.own(try @import("native_ai_provider_transcript.zig").resolve(engine, args[1], scope.truthy(try scope.get(compat, "supportsMidConvoSystemMessages"))));
    const owner = try scope.object();
    try scope.put(owner, "agent", dependencies);
    try scope.put(owner, "model", args[0]);
    try scope.put(owner, "context", context);
    try scope.put(owner, "options", options);
    try scope.put(owner, "compat", compat);
    try scope.put(owner, "stream", outer);
    try scope.put(owner, "iteratorActive", c.pi_js_bool(engine.context, 0));
    const iife = try scope.own(try asynchronous.createResumableArrow(engine, "", 0, streamBody, &.{owner}, c.pi_js_undefined()));
    _ = try scope.call(iife, c.pi_js_undefined(), &.{});
    return c.JS_DupValue(engine.context, outer);
}
fn streamBody(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: asynchronous.Completion, input: c.JSValue) !asynchronous.Action {
    return streamBodyValue(engine, roots[0], slot, completion, input) catch |err| return async_body.failure(engine, err);
}
fn streamBodyValue(engine: *v.em.Engine, owner: c.JSValue, slot: *c.JSValue, completion: asynchronous.Completion, input: c.JSValue) !asynchronous.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        asynchronous.replaceState(engine, slot, c.JS_DupValue(engine.context, owner));
        try scope.put(owner, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
        // Source allocates output inside the IIFE, before its setup try/catch.
        const created = try @import("native_ai_openai_decode.zig").createDetailed(engine, try scope.get(owner, "model"), c.pi_js_undefined(), try scope.get(owner, "stream"), try scope.get(try scope.get(owner, "agent"), "json"), c.pi_js_undefined());
        defer engine.freeValue(created.namespace);
        defer engine.freeValue(created.owner);
        try scope.put(owner, "decoder", created.namespace);
        try scope.put(owner, "decoderState", created.owner);
        setup(&scope, owner) catch |err| try failError(&scope, owner, err);
    } else {
        if (completion == .rejected) {
            var generation: u64 = 0;
            if (c.JS_ToBigUint64(engine.context, &generation, try scope.get(owner, "generation")) < 0) return v.js.capture(engine);
            try async_body.rethrowRecognizedAllocation(engine, input, generation);
        }
        const stage: Stage = @enumFromInt(try async_body.stage(&scope, owner));
        if (completion == .rejected) {
            if (stage == .closed) try applyFailure(&scope, owner, try scope.get(owner, "closeReason")) else {
                if (stage == .next) try scope.put(owner, "iteratorActive", c.JS_NewBool(engine.context, false));
                fail(&scope, owner, input) catch |err| try failError(&scope, owner, err);
            }
        } else advance(&scope, owner, input, stage) catch |err| try failError(&scope, owner, err);
    }
    return async_body.action(&scope, owner);
}
fn setup(scope: *Scope, owner: c.JSValue) !void {
    const options = try scope.get(owner, "options");
    try scope.put(owner, "apiKey", try apiKey(scope, try scope.get(owner, "model"), options));
    const compat = try scope.own(try @import("native_ai_openai_compat_options.zig").resolve(scope.engine, try scope.get(owner, "model")));
    try scope.put(owner, "compat", compat);
    const declared = try scope.own(try @import("native_ai_provider_transcript.zig").declared(scope.engine, try scope.get(try scope.get(owner, "context"), "messages")));
    const properties = try scope.own(try @import("native_ai_openai_tools.zig").grammarProperties(scope.engine, declared, scope.truthy(try scope.get(compat, "supportsOpenAIGrammarTools"))));
    try @import("native_ai_openai_decode.zig").configure(scope.engine, try scope.get(owner, "decoderState"), compat, properties);
    const retention = try request.cacheRetention(scope, options);
    try scope.put(owner, "retention", retention);
    // Preserve createClient argument evaluation before its header object body.
    const session = if (try v.eq(scope, retention, "none")) c.pi_js_undefined() else try v.optional(scope, options, "sessionId");
    const option_headers = try v.optional(scope, options, "headers");
    const provided_fetch = try v.optional(scope, options, "fetch");
    const defaults = try prepareClientHeaders(scope, owner, option_headers, session);
    const client = try scope.own(try @import("native_ai_openai_client_options.zig").capture(scope.engine, .{
        .api_key = try scope.get(owner, "apiKey"),
        .base_url = try scope.get(try scope.get(owner, "model"), "baseUrl"),
        .fetch = provided_fetch,
        .default_headers = defaults,
    }));
    try scope.put(owner, "clientOptions", client);
    const params = try scope.own(try request.build(scope.engine, try scope.get(owner, "model"), try scope.get(owner, "context"), options, try scope.get(owner, "compat"), retention, properties, try scope.get(try scope.get(owner, "agent"), "simple")));
    try scope.put(owner, "payload", params);
    try wait(scope, owner, try hook(scope, owner, "onPayload", params), .payload);
}
fn hook(scope: *Scope, owner: c.JSValue, key: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const options = try scope.get(owner, "options");
    const callback = try v.optional(scope, options, key);
    return if (v.nullish(callback)) c.pi_js_undefined() else scope.call(callback, options, &.{ value, try scope.get(owner, "model") });
}
fn wait(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try async_body.wait(scope, owner, value, @intFromEnum(stage));
}

fn aborted(scope: *Scope, owner: c.JSValue) !bool {
    return scope.truthy(try v.optional(scope, try v.optional(scope, try scope.get(owner, "options"), "signal"), "aborted"));
}
fn failError(scope: *Scope, owner: c.JSValue, err: anyerror) anyerror!void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (scope.engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return err;
    };
    const reason = flow.reason(scope.engine, err);
    defer scope.engine.freeValue(reason);
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    return fail(scope, owner, reason);
}
fn fail(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    if (scope.truthy(try scope.get(owner, "iteratorActive"))) {
        try scope.put(owner, "iteratorActive", c.pi_js_bool(scope.engine.context, 0));
        try scope.put(owner, "closeReason", reason);
        const iterator = try scope.get(owner, "iterator");
        const close = scope.get(iterator, "return") catch |err| {
            // GetMethod errors replace the original throw; invocation errors
            // are suppressed by AsyncIteratorClose's original throw.
            return failError(scope, owner, err);
        };
        if (!v.nullish(close)) {
            const result = scope.call(close, iterator, &.{}) catch |err| {
                if (err == error.OutOfMemory) return err;
                if (err == error.JavaScriptException) if (scope.engine.captured_exception) |value| {
                    if (c.JS_IsUncatchableError(value)) return err;
                };
                if (scope.engine.captured_exception) |value| {
                    scope.engine.captured_exception = null;
                    scope.engine.freeValue(value);
                }
                return applyFailure(scope, owner, reason);
            };
            return wait(scope, owner, result, .closed);
        }
    }
    return applyFailure(scope, owner, reason);
}
fn applyFailure(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const generation = scope.engine.native_allocation_generation;
    _ = scope.invoke(try scope.get(owner, "decoder"), "fail", &.{ reason, c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner))) }) catch |raw_err| {
        const err = scope.engine.nativeAllocationError(raw_err, generation);
        if (err == error.OutOfMemory) return err;
        const failure = flow.reason(scope.engine, err);
        defer scope.engine.freeValue(failure);
        try @import("native_stream.zig").reject(scope.engine, try scope.get(owner, "stream"), failure);
        try async_body.reject(scope, owner, failure);
        return;
    };
    try async_body.resolve(scope, owner, c.pi_js_undefined());
}
fn prepareClientHeaders(scope: *Scope, owner: c.JSValue, option_headers: c.JSValue, session: c.JSValue) !c.JSValue {
    const defaults = try scope.object();
    try scope.put(defaults, "User-Agent", try @import("native_ai_user_agent.zig").runtime(scope));
    const model = try scope.get(owner, "model");
    try v.js.spreadInto(scope.engine, defaults, try scope.get(model, "headers"));
    if (try v.eq(scope, try scope.get(model, "provider"), "github-copilot")) {
        const messages = try scope.get(try scope.get(owner, "context"), "messages");
        const count = try v.length(scope, messages);
        const last = if (count > 0) try v.at(scope, messages, count - 1) else c.pi_js_undefined();
        try scope.put(defaults, "X-Initiator", try scope.text(if (scope.truthy(last) and !try v.eq(scope, try scope.get(last, "role"), "user")) "agent" else "user"));
        try scope.put(defaults, "Openai-Intent", try scope.text("conversation-edits"));
        var rows = try v.iterator(scope, messages);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |message| {
            defer scope.engine.freeValue(message);
            const role = try scope.get(message, "role");
            const content = try scope.get(message, "content");
            if (!(try v.eq(scope, role, "user") or try v.eq(scope, role, "toolResult")) or !try v.array(scope, content)) continue;
            var blocks = try v.iterator(scope, content);
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            var found = false;
            while (try blocks.next()) |block| {
                defer scope.engine.freeValue(block);
                if (try v.eq(scope, try scope.get(block, "type"), "image")) {
                    found = true;
                    break;
                }
            }
            if (found) {
                try scope.put(defaults, "Copilot-Vision-Request", try scope.text("true"));
                break;
            }
        }
    }
    const compat = try scope.get(owner, "compat");
    if (scope.truthy(session) and scope.truthy(try scope.get(compat, "sendSessionAffinityHeaders"))) {
        if (try v.eq(scope, try scope.get(compat, "sessionAffinityFormat"), "openrouter")) try scope.put(defaults, "x-session-id", session) else {
            if (try v.eq(scope, try scope.get(compat, "sessionAffinityFormat"), "openai")) try scope.put(defaults, "session_id", session);
            try scope.put(defaults, "x-client-request-id", session);
            try scope.put(defaults, "x-session-affinity", session);
        }
    }
    try v.js.spreadInto(scope.engine, defaults, option_headers);
    return defaults;
}
fn open(scope: *Scope, owner: c.JSValue) !void {
    const Request = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            return c.JS_DupValue(engine.context, try sdk_request.withResponse(&row, try row.get(roots[0], "clientOptions"), try row.get(roots[0], "payload"), try row.get(roots[0], "requestOptions")));
        }
    };
    const options = try scope.get(owner, "options");
    const retry_options = try scope.object();
    try scope.put(retry_options, "maxRetries", try v.optional(scope, options, "maxRetries"));
    try scope.put(retry_options, "maxRetryDelayMs", try v.optional(scope, options, "maxRetryDelayMs"));
    try scope.put(retry_options, "signal", try v.optional(scope, options, "signal"));
    const request_callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 0, Request.call, &.{owner}));
    const retry = try scope.own(try @import("native_ai_provider_retry_request.zig").create(scope.engine));
    try wait(scope, owner, try scope.call(retry, c.pi_js_undefined(), &.{ request_callback, retry_options }), .ready);
}
fn next(scope: *Scope, owner: c.JSValue) !void {
    try wait(scope, owner, try scope.call(try scope.get(owner, "nextMethod"), try scope.get(owner, "iterator"), &.{}), .next);
}
fn advance(scope: *Scope, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    switch (stage) {
        .payload => {
            if (!c.JS_IsUndefined(value)) try scope.put(owner, "payload", value);
            const options = try scope.get(owner, "options");
            const request_options = try scope.object();
            if (scope.truthy(try v.optional(scope, options, "signal"))) try scope.put(request_options, "signal", try v.optional(scope, options, "signal"));
            const configured = try v.optional(scope, options, "timeoutMs");
            // Source captures requestOptions once after the payload hook. Its
            // conditional property spread observes a present timeout twice.
            if (!c.JS_IsUndefined(configured)) try scope.put(request_options, "timeout", try v.optional(scope, options, "timeoutMs"));
            try scope.put(request_options, "maxRetries", c.JS_NewInt32(scope.engine.context, 0));
            try scope.put(owner, "requestOptions", request_options);
            try open(scope, owner);
        },
        .ready => {
            try scope.put(owner, "sdkStream", try scope.get(value, "data"));
            const response = try scope.get(value, "response");
            try scope.put(owner, "response", response);
            const options = try scope.get(owner, "options");
            const callback = try v.optional(scope, options, "onResponse");
            const observed = if (v.nullish(callback)) c.pi_js_undefined() else observed: {
                const public_response = try scope.object();
                try scope.put(public_response, "status", try scope.get(response, "status"));
                try scope.put(public_response, "headers", try scope.own(try @import("native_ai_headers.zig").toRecord(scope.engine, try scope.get(response, "headers"))));
                break :observed try scope.call(callback, options, &.{ public_response, try scope.get(owner, "model") });
            };
            try wait(scope, owner, observed, .response);
        },
        .response => {
            _ = try scope.invoke(try scope.get(owner, "decoder"), "start", &.{});
            const iterable = try scope.get(owner, "sdkStream");
            const symbol = try scope.own(try scope.engine.checked(c.JS_GetAsyncIteratorSymbol(scope.engine.context)));
            const iterator = try scope.call(try scope.own(try v.js.getKey(scope.engine, iterable, symbol)), iterable, &.{});
            if (!c.JS_IsObject(iterator)) return v.js.typeError(scope.engine, "Async iterator is not an object");
            try scope.put(owner, "iterator", iterator);
            try scope.put(owner, "nextMethod", try scope.get(iterator, "next"));
            try scope.put(owner, "iteratorActive", c.pi_js_bool(scope.engine.context, 1));
            try next(scope, owner);
        },
        .next => {
            if (!c.JS_IsObject(value)) return v.js.typeError(scope.engine, "Iterator result is not an object");
            if (scope.truthy(try scope.get(value, "done"))) {
                try scope.put(owner, "iteratorActive", c.pi_js_bool(scope.engine.context, 0));
                _ = try scope.invoke(try scope.get(owner, "decoder"), "finish", &.{c.pi_js_bool(scope.engine.context, @intFromBool(try aborted(scope, owner)))});
                return async_body.resolve(scope, owner, c.pi_js_undefined());
            }
            const frame = try scope.get(value, "value");
            try scope.put(owner, "chunk", frame);
            try wait(scope, owner, try hook(scope, owner, "onProviderStreamEvent", frame), .chunk);
        },
        .chunk => {
            _ = try scope.invoke(try scope.get(owner, "decoder"), "push", &.{try scope.get(owner, "chunk")});
            try next(scope, owner);
        },
        .closed => try applyFailure(scope, owner, try scope.get(owner, "closeReason")),
    }
}
