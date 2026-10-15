//! Pinned SDK processStreamResponse and Models async-generator producer layers.
//! JSON is consumed by actual native Response/Body/ReadableStream promises.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const queue = @import("native_ai_google_sdk_generator.zig");
const framing = @import("native_ai_google_sse.zig");
const ProcessStage = enum(c_int) { initial, reading, await_yield, yielded, finished };
const ModelStage = enum(c_int) { initial, reading, json, await_yield, yielded, closing, finished };
fn getStage(comptime T: type, scope: *Scope, owner: c.JSValue) !T {
    var value: i32 = 0;
    if (c.JS_ToInt32(scope.engine.context, &value, try scope.get(owner, "stage")) < 0) return v.js.capture(scope.engine);
    return @enumFromInt(value);
}
fn setStage(scope: *Scope, owner: c.JSValue, value: anytype) !void {
    try scope.put(owner, "stage", c.JS_NewInt32(scope.engine.context, @intFromEnum(value)));
}
pub fn create(engine: *v.em.Engine, transport: c.JSValue, head: c.JSValue, url: c.JSValue, constructor: c.JSValue, vertex: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var status: u32 = 0;
    if (c.JS_ToUint32(engine.context, &status, try scope.get(head, "status")) < 0) return v.js.capture(engine);
    if (status > 65535) return error.NativeGoogleStatusLimit;
    const stream = try scope.own(try @import("native_web_byte_source.zig").fromEvents(engine, try scope.get(transport, "events"), .{ .cancel = try scope.get(transport, "cancel") }));
    const response = try scope.own(try @import("native_web_response.zig").fromTransport(engine, .{ .body = stream, .status = @intCast(status), .status_text = try scope.get(head, "statusText"), .headers = try scope.get(head, "rawHeaders"), .url = url }));
    const process_owner = try scope.object();
    try scope.put(process_owner, "response", response);
    try scope.put(process_owner, "reader", c.pi_js_undefined());
    try scope.put(process_owner, "entered", c.pi_js_bool(engine.context, 0));
    try scope.put(process_owner, "processed", c.pi_js_undefined());
    try setStage(&scope, process_owner, ProcessStage.initial);
    const process = try scope.own(try queue.create(engine, process_owner, processBody));
    const owner = try scope.object();
    try scope.put(owner, "process", process);
    try scope.put(owner, "iterator", c.pi_js_undefined());
    try scope.put(owner, "constructor", constructor);
    try scope.put(owner, "vertex", c.pi_js_bool(engine.context, @intFromBool(vertex)));
    try scope.put(owner, "chunk", c.pi_js_undefined());
    try scope.put(owner, "final", c.pi_js_undefined());
    try scope.put(owner, "throwing", c.pi_js_bool(engine.context, 0));
    try setStage(&scope, owner, ModelStage.initial);
    return queue.create(engine, owner, modelsBody);
}
fn release(scope: *Scope, owner: c.JSValue) !void {
    if (scope.truthy(try scope.get(owner, "entered"))) {
        try scope.put(owner, "entered", c.pi_js_bool(scope.engine.context, 0));
        _ = try scope.invoke(try scope.get(owner, "reader"), "releaseLock", &.{});
    }
    try setStage(scope, owner, ProcessStage.finished);
}
fn wrapped(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !c.JSValue {
    const prefix = try scope.concat(try scope.concat(try scope.text("exception parsing stream chunk "), try scope.get(owner, "processed")), try scope.text(". "));
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.concat(prefix, try scope.stringify(reason))}));
}
fn processBody(engine: *v.em.Engine, owner: c.JSValue, verb: queue.Verb, input: c.JSValue) !queue.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return processRun(&scope, owner, verb, input) catch |err| {
        var reason = try scope.own(@import("native_agent_async.zig").reason(engine, err));
        const current = try getStage(ProcessStage, &scope, owner);
        if (current == .await_yield or current == .yielded) reason = try wrapped(&scope, owner, reason);
        try release(&scope, owner);
        return .{ .thrown = c.JS_DupValue(engine.context, reason) };
    };
}
fn processRun(scope: *Scope, owner: c.JSValue, verb: queue.Verb, input: c.JSValue) !queue.Action {
    const current = try getStage(ProcessStage, scope, owner);
    if (verb == .returned) {
        try release(scope, owner);
        return .{ .complete = c.JS_DupValue(scope.engine.context, input) };
    }
    if (verb == .thrown) {
        const reason = if (current == .await_yield or current == .yielded) try wrapped(scope, owner, input) else input;
        try release(scope, owner);
        return .{ .thrown = c.JS_DupValue(scope.engine.context, reason) };
    }
    if (current == .initial) {
        const body = try v.optional(scope, try scope.get(owner, "response"), "body");
        const reader = if (v.nullish(body)) c.pi_js_undefined() else try scope.invoke(body, "getReader", &.{});
        try scope.put(owner, "reader", reader);
        try framing.init(scope, owner);
        if (!scope.truthy(reader)) return v.errorText(scope, try scope.text("Response body is empty"));
        try scope.put(owner, "entered", c.pi_js_bool(scope.engine.context, 1));
    } else if (current == .await_yield) {
        try setStage(scope, owner, ProcessStage.yielded);
        return .{ .yielded = c.JS_DupValue(scope.engine.context, input) };
    } else if (current == .reading) {
        const done = scope.truthy(try scope.get(input, "done"));
        const value = try scope.get(input, "value");
        if (done) {
            try framing.eof(scope, owner);
            try release(scope, owner);
            return .{ .complete = c.pi_js_undefined() };
        }
        try framing.feed(scope, owner, value);
    }
    if (try framing.pop(scope, owner)) |processed| {
        try scope.put(owner, "processed", processed);
        try setStage(scope, owner, ProcessStage.await_yield);
        const response = try scope.get(owner, "response");
        const init = try scope.object();
        inline for (.{ "headers", "status", "statusText" }) |key| try scope.put(init, key, try v.optional(scope, response, key));
        const partial = try scope.own(try v.js.builtin(scope.engine, "Response", &.{ processed, init }));
        const http = try @import("native_ai_google_http_response.zig").wrap(scope, partial);
        return .{ .awaited = c.JS_DupValue(scope.engine.context, http) };
    }
    try setStage(scope, owner, ProcessStage.reading);
    return .{ .awaited = c.JS_DupValue(scope.engine.context, try scope.invoke(try scope.get(owner, "reader"), "read", &.{})) };
}
fn closeModels(scope: *Scope, owner: c.JSValue, thrown: bool, value: c.JSValue) !queue.Action {
    const current = try getStage(ModelStage, scope, owner);
    try scope.put(owner, "throwing", c.pi_js_bool(scope.engine.context, @intFromBool(thrown)));
    try scope.put(owner, "final", value);
    // For-await does not call return when next itself rejects or reports done.
    if (current == .initial or current == .reading or current == .finished) {
        try setStage(scope, owner, ModelStage.finished);
        return if (thrown) .{ .thrown = c.JS_DupValue(scope.engine.context, value) } else .{ .complete = c.JS_DupValue(scope.engine.context, value) };
    }
    const iterator = try scope.get(owner, "iterator");
    const method = try scope.get(iterator, "return");
    if (!scope.truthy(method)) {
        try setStage(scope, owner, ModelStage.finished);
        return if (thrown) .{ .thrown = c.JS_DupValue(scope.engine.context, value) } else .{ .complete = c.JS_DupValue(scope.engine.context, value) };
    }
    try setStage(scope, owner, ModelStage.closing);
    return .{ .awaited = c.JS_DupValue(scope.engine.context, try scope.invoke(method, "call", &.{iterator})) };
}
fn modelsBody(engine: *v.em.Engine, owner: c.JSValue, verb: queue.Verb, input: c.JSValue) !queue.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return modelsRun(&scope, owner, verb, input) catch |err| {
        const reason = try scope.own(@import("native_agent_async.zig").reason(engine, err));
        if (try getStage(ModelStage, &scope, owner) == .closing and scope.truthy(try scope.get(owner, "throwing"))) return .{ .thrown = c.JS_DupValue(engine.context, try scope.get(owner, "final")) };
        return closeModels(&scope, owner, true, reason);
    };
}
fn modelsRun(scope: *Scope, owner: c.JSValue, verb: queue.Verb, input: c.JSValue) !queue.Action {
    const current = try getStage(ModelStage, scope, owner);
    if (current == .closing) {
        try setStage(scope, owner, ModelStage.finished);
        if (scope.truthy(try scope.get(owner, "throwing"))) return .{ .thrown = c.JS_DupValue(scope.engine.context, try scope.get(owner, "final")) };
        return if (verb == .thrown) .{ .thrown = c.JS_DupValue(scope.engine.context, input) } else .{ .complete = c.JS_DupValue(scope.engine.context, try scope.get(owner, "final")) };
    }
    if (verb == .returned) return closeModels(scope, owner, false, input);
    if (verb == .thrown) return closeModels(scope, owner, true, input);
    if (current == .initial) {
        const process = try scope.get(owner, "process");
        const symbol = try scope.get(try scope.global("Symbol"), "asyncIterator");
        const method = try scope.own(try v.js.getKey(scope.engine, process, symbol));
        try scope.put(owner, "iterator", try scope.invoke(method, "call", &.{process}));
    } else if (current == .reading) {
        if (scope.truthy(try scope.get(input, "done"))) {
            try setStage(scope, owner, ModelStage.finished);
            return .{ .complete = c.pi_js_undefined() };
        }
        const chunk = try scope.get(input, "value");
        try scope.put(owner, "chunk", chunk);
        try setStage(scope, owner, ModelStage.json);
        return .{ .awaited = c.JS_DupValue(scope.engine.context, try scope.invoke(chunk, "json", &.{})) };
    } else if (current == .json) {
        const typed = try @import("native_ai_google_response.zig").wrapSdk(scope, try scope.get(owner, "constructor"), input, try scope.get(try scope.get(owner, "chunk"), "headers"), scope.truthy(try scope.get(owner, "vertex")));
        try setStage(scope, owner, ModelStage.await_yield);
        return .{ .awaited = c.JS_DupValue(scope.engine.context, typed) };
    } else if (current == .await_yield) {
        try setStage(scope, owner, ModelStage.yielded);
        return .{ .yielded = c.JS_DupValue(scope.engine.context, input) };
    }
    try setStage(scope, owner, ModelStage.reading);
    return .{ .awaited = c.JS_DupValue(scope.engine.context, try scope.invoke(try scope.get(owner, "iterator"), "next", &.{})) };
}
