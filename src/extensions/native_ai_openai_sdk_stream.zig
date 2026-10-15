//! Pinned OpenAI6.40 streaming producer layers, over an actual byte iterable.
//! The chunk, SSE-message and JSON-item generators own separate real QuickJS
//! AsyncGenerator queues. Provider hooks run only after the JSON-item yield.
const v = @import("native_ai_provider_values.zig");
const gen = @import("native_async_generator.zig");
const record = @import("native_ai_openai_sdk_iterator.zig");
const chunks = @import("native_ai_openai_sdk_chunks.zig");
const line = @import("native_ai_openai_sdk_line.zig");
const flow = @import("native_agent_async.zig");
const Scope = v.Scope;
const c = v.c;
pub const Options = struct { codec: c.JSValue, controller: c.JSValue, error_factory: c.JSValue, logger: c.JSValue };
pub fn fromBodyIterator(engine: *v.em.Engine, iterable: c.JSValue, options: Options) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try record.state(&scope);
    try scope.put(owner, "body", iterable);
    try scope.put(owner, "codec", options.codec);
    try scope.put(owner, "controller", options.controller);
    try scope.put(owner, "errorFactory", options.error_factory);
    try scope.put(owner, "logger", options.logger);
    try scope.put(owner, "done", c.pi_js_bool(engine.context, 0));
    return gen.create(engine, owner, itemAdvance, try scope.own(try gen.prototype(engine)));
}
fn messages(engine: *v.em.Engine, iterable: c.JSValue, codec: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try record.state(&scope);
    try scope.put(owner, "body", iterable);
    try scope.put(owner, "codec", codec);
    return gen.create(engine, owner, messageAdvance, try scope.own(try gen.prototype(engine)));
}
fn captured(scope: *Scope, err: anyerror) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    const reason = try scope.own(flow.reason(scope.engine, err));
    if (scope.engine.captured_exception) |value| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(value);
    }
    return reason;
}
fn beginLines(scope: *Scope, owner: c.JSValue, lines: c.JSValue) !void {
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context)));
    const method = try scope.own(try v.js.getKey(scope.engine, lines, symbol));
    const iterator = try scope.call(method, lines, &.{});
    try record.validate(scope, iterator);
    try scope.put(owner, "lineIterator", iterator);
    try scope.put(owner, "lineNext", try scope.get(iterator, "next"));
    try scope.put(owner, "lineActive", c.pi_js_bool(scope.engine.context, 1));
}
fn closeLines(scope: *Scope, owner: c.JSValue, thrown: bool) !void {
    if (!scope.truthy(try scope.get(owner, "lineActive"))) return;
    const iterator = try scope.get(owner, "lineIterator");
    const method = try scope.get(iterator, "return");
    if (v.nullish(method)) return;
    const result = scope.call(method, iterator, &.{}) catch |err| {
        if (err != error.JavaScriptException or !thrown) return err;
        _ = try captured(scope, err);
        return;
    };
    if (!thrown) try record.validate(scope, result);
}
fn messageClose(scope: *Scope, owner: c.JSValue, input: c.JSValue, thrown: bool) !gen.Action {
    try closeLines(scope, owner, thrown);
    return record.close(scope, owner, input, thrown);
}
fn messageAdvance(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try record.closed(&scope, owner, completion, input)) |action| return action;
    if (completion == .returned or completion == .thrown) return messageClose(&scope, owner, input, completion == .thrown);
    if (completion == .rejected) return if (scope.truthy(try scope.get(owner, "awaitingNext"))) .{ .thrown = c.JS_DupValue(engine.context, input) } else messageClose(&scope, owner, input, true);
    return messageStep(engine, owner, completion, input) catch |err| messageClose(&scope, owner, try captured(&scope, err), true);
}
fn messageStep(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        try scope.put(owner, "lineDecoder", try line.create(&scope));
        const sse = try scope.object();
        try scope.set(sse, "event", c.pi_js_null());
        try scope.set(sse, "data", try scope.array());
        try scope.set(sse, "chunks", try scope.array());
        try scope.put(owner, "sseDecoder", sse);
        try record.begin(&scope, owner, try scope.own(try chunks.create(engine, try scope.get(owner, "body"), try scope.get(owner, "codec"))));
        return record.next(&scope, owner);
    }
    if (completion == .fulfilled) {
        try record.validate(&scope, input);
        const decoder = try scope.get(owner, "lineDecoder");
        const codec = try scope.get(owner, "codec");
        const done = scope.truthy(try scope.get(input, "done"));
        try scope.put(owner, "flushing", c.pi_js_bool(engine.context, @intFromBool(done)));
        const lines = if (done) try line.flush(&scope, decoder, codec) else try line.decode(&scope, decoder, codec, try scope.get(input, "value"));
        try beginLines(&scope, owner, lines);
    }
    while (scope.truthy(try scope.get(owner, "lineActive"))) {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const step = try row.call(try row.get(owner, "lineNext"), try row.get(owner, "lineIterator"), &.{});
        try record.validate(&row, step);
        if (row.truthy(try row.get(step, "done"))) {
            try row.put(owner, "lineActive", c.pi_js_bool(engine.context, 0));
            break;
        }
        const decoded = try line.sse(&row, try row.get(owner, "sseDecoder"), try row.get(step, "value"));
        if (row.truthy(decoded)) {
            try row.put(owner, "awaitingNext", c.pi_js_bool(engine.context, 0));
            return .{ .yielded = c.JS_DupValue(engine.context, decoded) };
        }
    }
    if (scope.truthy(try scope.get(owner, "flushing"))) return .{ .complete = c.pi_js_undefined() };
    return record.next(&scope, owner);
}
fn isAbortError(scope: *Scope, value: c.JSValue) !bool {
    // typeof function is deliberately excluded, matching the literal SDK test.
    if (!c.JS_IsObject(value) or c.JS_IsFunction(scope.engine.context, value)) return false;
    if (try v.js.hasKey(scope.engine, value, try scope.text("name")) and try v.eq(scope, try scope.get(value, "name"), "AbortError")) return true;
    if (!try v.js.hasKey(scope.engine, value, try scope.text("message"))) return false;
    const message = try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{try scope.get(value, "message")});
    return scope.truthy(try scope.invoke(message, "includes", &.{try scope.text("FetchRequestCanceledException")}));
}
fn finish(scope: *Scope, owner: c.JSValue, action: gen.Action) !gen.Action {
    if (action == .awaited) return action;
    var result = action;
    errdefer switch (result) {
        inline else => |value| scope.engine.freeValue(value),
    };
    if (action == .thrown and try isAbortError(scope, action.thrown)) {
        scope.engine.freeValue(action.thrown);
        result = .{ .complete = c.pi_js_undefined() };
    }
    if (!scope.truthy(try scope.get(owner, "done"))) _ = try scope.invoke(try scope.get(owner, "controller"), "abort", &.{});
    return result;
}
fn itemClose(scope: *Scope, owner: c.JSValue, input: c.JSValue, thrown: bool) !gen.Action {
    return finish(scope, owner, try record.close(scope, owner, input, thrown));
}
fn itemAdvance(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try record.closed(&scope, owner, completion, input)) |action| return finish(&scope, owner, action);
    if (completion == .returned or completion == .thrown) return itemClose(&scope, owner, input, completion == .thrown);
    if (completion == .rejected) return if (scope.truthy(try scope.get(owner, "awaitingNext"))) finish(&scope, owner, .{ .thrown = c.JS_DupValue(engine.context, input) }) else itemClose(&scope, owner, input, true);
    return itemStep(engine, owner, completion, input) catch |err| itemClose(&scope, owner, try captured(&scope, err), true);
}
fn parse(scope: *Scope, owner: c.JSValue, sse: c.JSValue, thread: bool) !c.JSValue {
    var diagnostics = @import("native_ai_json_scope.zig").Guard.enter(scope.engine);
    defer diagnostics.deinit();
    return scope.invoke(try scope.global("JSON"), "parse", &.{try scope.get(sse, "data")}) catch |err| {
        const reason = try captured(scope, err);
        const logger = if (thread) try scope.global("console") else try scope.get(owner, "logger");
        _ = try scope.invoke(logger, "error", &.{ try scope.text("Could not parse message into JSON:"), try scope.get(sse, "data") });
        _ = try scope.invoke(logger, "error", &.{ try scope.text("From chunk:"), try scope.get(sse, "raw") });
        return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason)));
    };
}
fn itemStep(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        try record.begin(&scope, owner, try scope.own(try messages(engine, try scope.get(owner, "body"), try scope.get(owner, "codec"))));
        return record.next(&scope, owner);
    }
    if (completion != .fulfilled) return record.next(&scope, owner);
    try record.validate(&scope, input);
    if (scope.truthy(try scope.get(input, "done"))) {
        try scope.put(owner, "done", c.pi_js_bool(engine.context, 1));
        return .{ .complete = c.pi_js_undefined() };
    }
    if (scope.truthy(try scope.get(owner, "done"))) return record.next(&scope, owner);
    const sse = try scope.get(input, "value");
    if (scope.truthy(try scope.invoke(try scope.get(sse, "data"), "startsWith", &.{try scope.text("[DONE]")}))) {
        try scope.put(owner, "done", c.pi_js_bool(engine.context, 1));
        return record.next(&scope, owner);
    }
    const event = try scope.get(sse, "event");
    const thread = !c.JS_IsNull(event) and scope.truthy(try scope.invoke(event, "startsWith", &.{try scope.text("thread.")}));
    const data = try parse(&scope, owner, sse, thread);
    if (!thread) {
        if (scope.truthy(data) and scope.truthy(try scope.get(data, "error"))) {
            const error_value = try scope.call(try scope.get(owner, "errorFactory"), c.pi_js_undefined(), &.{ c.pi_js_undefined(), try scope.get(data, "error"), c.pi_js_undefined() });
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, error_value)));
            unreachable;
        }
        try scope.put(owner, "awaitingNext", c.pi_js_bool(engine.context, 0));
        return .{ .yielded = c.JS_DupValue(engine.context, data) };
    }
    if (try v.eq(&scope, event, "error")) {
        const error_value = try scope.call(try scope.get(owner, "errorFactory"), c.pi_js_undefined(), &.{ c.pi_js_undefined(), try scope.get(data, "error"), try scope.get(data, "message") });
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, error_value)));
        unreachable;
    }
    const wrapped = try scope.object();
    try scope.put(wrapped, "event", event);
    try scope.put(wrapped, "data", data);
    try scope.put(owner, "awaitingNext", c.pi_js_bool(engine.context, 0));
    return .{ .yielded = c.JS_DupValue(engine.context, wrapped) };
}
