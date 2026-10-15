//! Source5ab iterateSseMessages and iterateAnthropicEvents bodies on the real
//! QuickJS AsyncGenerator queue. Each parser consumes only up to its next
//! actual yield; provider hooks run after the outer generator yield.
const v = @import("native_ai_provider_values.zig");
const gen = @import("native_async_generator.zig");
const sse = @import("native_ai_anthropic_sse.zig");
const flow = @import("native_agent_async.zig");
const Scope = v.Scope;
const c = v.c;

fn private(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
}
fn phase(scope: *Scope, owner: c.JSValue) !i32 {
    var result: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &result, try scope.get(owner, "phase")) < 0) return v.js.capture(scope.engine);
    return result;
}
fn failure(scope: *Scope, err: anyerror) !c.JSValue {
    const value = try scope.own(flow.reason(scope.engine, err));
    if (scope.engine.captured_exception) |previous| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(previous);
    }
    return value;
}
fn freshAllocation(scope: *Scope, owner: c.JSValue, value: c.JSValue) !bool {
    const tagged = c.pi_js_native_allocation_error_generation(value);
    if (tagged == 0) return false;
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(scope.engine.context, &generation, try scope.get(owner, "generation")) < 0) return v.js.capture(scope.engine);
    const distance = tagged -% generation;
    return distance != 0 and distance <= scope.engine.native_allocation_generation -% generation;
}
fn captureGeneration(scope: *Scope, owner: c.JSValue) !void {
    try scope.put(owner, "generation", try scope.own(try scope.engine.checked(c.JS_NewBigUint64(scope.engine.context, scope.engine.native_allocation_generation))));
}
pub fn messageEvents(scope: *Scope) !c.JSValue {
    const names = try scope.array();
    inline for (.{ "message_start", "message_delta", "message_stop", "content_block_start", "content_block_delta", "content_block_stop" }, 0..) |name, index| try scope.index(names, index, try scope.text(name));
    return scope.own(try v.js.builtin(scope.engine, "Set", &.{names}));
}
pub fn create(engine: *v.em.Engine, response: c.JSValue, http: c.JSValue, signal: c.JSValue, json: c.JSValue, known: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try private(&scope);
    try scope.put(owner, "response", response);
    try scope.put(owner, "http", http);
    try scope.put(owner, "signal", signal);
    try scope.put(owner, "json", json);
    try scope.put(owner, "known", known);
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "entered", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "closing", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "sawStart", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "sawStop", c.pi_js_bool(engine.context, 0));
    try captureGeneration(&scope, owner);
    return gen.create(engine, owner, eventsAdvance, try scope.own(try gen.prototype(engine)));
}
fn messages(engine: *v.em.Engine, body: c.JSValue, http: c.JSValue, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try private(&scope);
    try scope.put(owner, "body", body);
    try scope.put(owner, "http", http);
    try scope.put(owner, "signal", signal);
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "cleanup", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "eof", c.pi_js_bool(engine.context, 0));
    try captureGeneration(&scope, owner);
    return gen.create(engine, owner, messagesAdvance, try scope.own(try gen.prototype(engine)));
}
fn readerFinish(scope: *Scope, owner: c.JSValue, value: c.JSValue, thrown: bool) !gen.Action {
    if (scope.truthy(try scope.get(owner, "cleanup"))) {
        try scope.put(owner, "cleanup", c.pi_js_bool(scope.engine.context, 0));
        const reader = try scope.get(owner, "reader");
        if (!v.nullish(reader)) {
            _ = scope.invoke(reader, "releaseLock", &.{}) catch |err| {
                const closing_error = try failure(scope, err);
                // Trusted host OOM cannot become an unrelated guest failure.
                if (thrown and try freshAllocation(scope, owner, value)) return .{ .thrown = c.JS_DupValue(scope.engine.context, value) };
                return .{ .thrown = c.JS_DupValue(scope.engine.context, closing_error) };
            };
        }
    }
    return if (thrown) .{ .thrown = c.JS_DupValue(scope.engine.context, value) } else .{ .complete = c.JS_DupValue(scope.engine.context, value) };
}
fn messagesAdvance(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .returned or completion == .thrown or completion == .rejected) return readerFinish(&scope, owner, input, completion != .returned);
    return messagesStep(engine, owner, completion, input) catch |err| readerFinish(&scope, owner, try failure(&scope, err), true);
}
fn messagesStep(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const http = try scope.get(owner, "http");
        if (v.nullish(http)) try scope.put(owner, "reader", try scope.invoke(try scope.get(owner, "body"), "getReader", &.{})) else try scope.put(owner, "raw", try scope.get(http, "events"));
        try scope.put(owner, "decoder", try scope.own(try v.js.builtin(engine, "TextDecoder", &.{})));
        try scope.put(owner, "state", try sse.create(&scope));
        // Source's try/finally starts after reader, decoder and state setup.
        try scope.put(owner, "cleanup", c.pi_js_bool(engine.context, 1));
    } else if (completion == .fulfilled and try phase(&scope, owner) == 1) {
        const bytes = try scope.get(input, "value");
        const done = scope.truthy(try scope.get(input, "done"));
        const decoder = try scope.get(owner, "decoder");
        const text = if (done) try scope.invoke(decoder, "decode", &.{}) else decoded: {
            const config = try scope.object();
            try scope.put(config, "stream", c.pi_js_bool(engine.context, 1));
            const data = if (v.nullish(try scope.get(owner, "http"))) bytes else try scope.get(bytes, "data");
            break :decoded try scope.invoke(decoder, "decode", &.{ data, config });
        };
        try sse.append(&scope, try scope.get(owner, "state"), text);
        try scope.put(owner, "eof", c.pi_js_bool(engine.context, @intFromBool(done)));
    }
    const eof = scope.truthy(try scope.get(owner, "eof"));
    if (try sse.take(engine, try scope.get(owner, "state"), eof)) |frame| {
        try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 2));
        return .{ .yielded = frame };
    }
    if (eof) return readerFinish(&scope, owner, c.pi_js_undefined(), false);
    if (scope.truthy(try v.optional(&scope, try scope.get(owner, "signal"), "aborted"))) return v.errorText(&scope, try scope.text("Request was aborted"));
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 1));
    const raw = try scope.get(owner, "raw");
    const pending = if (v.nullish(raw)) try scope.invoke(try scope.get(owner, "reader"), "read", &.{}) else try scope.invoke(raw, "next", &.{});
    return .{ .awaited = c.JS_DupValue(engine.context, pending) };
}
fn original(scope: *Scope, owner: c.JSValue) !gen.Action {
    const value = c.JS_DupValue(scope.engine.context, try scope.get(owner, "closeValue"));
    return if (scope.truthy(try scope.get(owner, "closeThrown"))) .{ .thrown = value } else .{ .complete = value };
}
fn closeInner(scope: *Scope, owner: c.JSValue, value: c.JSValue, thrown: bool) !gen.Action {
    try scope.put(owner, "closeValue", value);
    try scope.put(owner, "closeThrown", c.pi_js_bool(scope.engine.context, @intFromBool(thrown)));
    if (!scope.truthy(try scope.get(owner, "entered"))) return original(scope, owner);
    const iterator = try scope.get(owner, "iterator");
    const method = scope.get(iterator, "return") catch |err| {
        const close_error = try failure(scope, err);
        if (thrown and !try freshAllocation(scope, owner, close_error)) return original(scope, owner);
        return .{ .thrown = c.JS_DupValue(scope.engine.context, close_error) };
    };
    if (v.nullish(method)) return original(scope, owner);
    try scope.put(owner, "closing", c.pi_js_bool(scope.engine.context, 1));
    const pending = scope.call(method, iterator, &.{}) catch |err| {
        const close_error = try failure(scope, err);
        if (thrown and !try freshAllocation(scope, owner, close_error)) return original(scope, owner);
        return .{ .thrown = c.JS_DupValue(scope.engine.context, close_error) };
    };
    return .{ .awaited = c.JS_DupValue(scope.engine.context, pending) };
}
fn next(scope: *Scope, owner: c.JSValue) !gen.Action {
    try scope.put(owner, "phase", c.JS_NewInt32(scope.engine.context, 1));
    return .{ .awaited = c.JS_DupValue(scope.engine.context, try scope.call(try scope.get(owner, "next"), try scope.get(owner, "iterator"), &.{})) };
}
fn eventsAdvance(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(owner, "closing"))) {
        const thrown = scope.truthy(try scope.get(owner, "closeThrown"));
        if (completion == .rejected and (!thrown or try freshAllocation(&scope, owner, input))) return .{ .thrown = c.JS_DupValue(engine.context, input) };
        if (completion == .fulfilled and !thrown and !c.JS_IsObject(input)) return v.js.typeError(engine, "Iterator return result is not an object");
        return original(&scope, owner);
    }
    if (completion == .returned) return closeInner(&scope, owner, input, false);
    if (completion == .rejected and try phase(&scope, owner) == 1) return .{ .thrown = c.JS_DupValue(engine.context, input) };
    if (completion == .thrown or completion == .rejected) {
        const wrapped = if (try freshAllocation(&scope, owner, input)) input else try sse.parseFailure(&scope, try scope.get(owner, "frame"), input);
        return closeInner(&scope, owner, wrapped, true);
    }
    return eventsStep(engine, owner, completion, input) catch |err| closeInner(&scope, owner, try failure(&scope, err), true);
}
fn eventsStep(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const http = try scope.get(owner, "http");
        var body = c.pi_js_undefined();
        if (v.nullish(http)) {
            if (!scope.truthy(try scope.get(try scope.get(owner, "response"), "body"))) return v.errorText(&scope, try scope.text("Attempted to iterate over an Anthropic response with no body"));
            body = try scope.get(try scope.get(owner, "response"), "body");
        }
        const iterable = try scope.own(try messages(engine, body, http, try scope.get(owner, "signal")));
        const symbol = try scope.own(try engine.checked(c.JS_GetAsyncIteratorSymbol(engine.context)));
        const method = try scope.own(try v.js.getKey(engine, iterable, symbol));
        const iterator = try scope.call(method, iterable, &.{});
        if (!c.JS_IsObject(iterator)) return v.js.typeError(engine, "Async iterator is not an object");
        try scope.put(owner, "iterator", iterator);
        try scope.put(owner, "next", try scope.get(iterator, "next"));
        try scope.put(owner, "entered", c.pi_js_bool(engine.context, 1));
        return next(&scope, owner);
    }
    if (completion != .fulfilled) return next(&scope, owner);
    if (!c.JS_IsObject(input)) return v.js.typeError(engine, "Iterator result is not an object");
    if (scope.truthy(try scope.get(input, "done"))) {
        try scope.put(owner, "entered", c.pi_js_bool(engine.context, 0));
        if (scope.truthy(try scope.get(owner, "sawStart")) and !scope.truthy(try scope.get(owner, "sawStop"))) return v.errorText(&scope, try scope.text("Anthropic stream ended before message_stop"));
        return .{ .complete = c.pi_js_undefined() };
    }
    const frame = try scope.get(input, "value");
    const kind = try scope.get(frame, "event");
    if (try v.eq(&scope, kind, "error")) return v.errorText(&scope, try scope.get(frame, "data"));
    if (!scope.truthy(try scope.invoke(try scope.get(owner, "known"), "has", &.{if (v.nullish(kind)) try scope.text("") else kind}))) return next(&scope, owner);
    const parse_generation = engine.native_allocation_generation;
    const event = parseEvent(&scope, owner, frame) catch |err| {
        const classified = engine.nativeAllocationError(err, parse_generation);
        if (classified == error.OutOfMemory) return classified;
        const reason = try failure(&scope, err);
        const wrapped = try sse.parseFailure(&scope, frame, reason);
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, wrapped)));
        unreachable;
    };
    try scope.put(owner, "frame", frame);
    try scope.put(owner, "phase", c.JS_NewInt32(engine.context, 2));
    return .{ .yielded = c.JS_DupValue(engine.context, event) };
}
fn parseEvent(scope: *Scope, owner: c.JSValue, frame: c.JSValue) !c.JSValue {
    const event = try scope.invoke(try scope.get(owner, "json"), "parseJsonWithRepair", &.{try scope.get(frame, "data")});
    if (try v.eq(scope, try scope.get(event, "type"), "message_start")) try scope.put(owner, "sawStart", c.pi_js_bool(scope.engine.context, 1)) else if (try v.eq(scope, try scope.get(event, "type"), "message_stop")) try scope.put(owner, "sawStop", c.pi_js_bool(scope.engine.context, 1));
    return event;
}
