//! Converse SDK item layer on the reviewed real C AsyncGenerator substrate.
//! Wire buffers and the yielded local stay in GC-visible owner properties.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const gen = @import("native_async_generator.zig");
const wire = @import("native_ai_bedrock_wire.zig");
pub fn create(engine: *v.em.Engine, http: c.JSValue, response: c.JSValue, request_id: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owner = try s.object();
    try s.put(owner, "http", http);
    try s.put(owner, "iterator", try s.get(http, "events"));
    try s.put(owner, "response", response);
    try s.put(owner, "requestId", request_id);
    try s.put(owner, "queue", try s.array());
    try s.put(owner, "queueIndex", c.JS_NewInt32(engine.context, 0));
    return gen.create(engine, owner, advance, c.pi_js_undefined());
}
fn retire(s: *Scope, owner: c.JSValue) !void {
    inline for (.{ "http", "iterator", "response", "requestId", "queue", "queueIndex", "pendingBytes", "item", "closeValue", "stage" }) |key| try v.remove(s, owner, key);
}
fn finish(s: *Scope, owner: c.JSValue, thrown: bool, value: c.JSValue) !gen.Action {
    const retained = c.JS_DupValue(s.engine.context, value);
    errdefer s.engine.freeValue(retained);
    try retire(s, owner);
    return if (thrown) .{ .thrown = retained } else .{ .complete = retained };
}
fn close(s: *Scope, owner: c.JSValue, thrown: bool, value: c.JSValue) !gen.Action {
    try s.put(owner, "closeValue", value);
    try s.put(owner, "stage", try s.text(if (thrown) "closeThrow" else "closeReturn"));
    const http = try s.get(owner, "http");
    if (!v.nullish(http)) _ = try s.invoke(http, "cancel", &.{});
    const iterator = try s.get(owner, "iterator");
    const method = try v.optional(s, iterator, "return");
    if (v.nullish(method)) return finish(s, owner, thrown, value);
    return .{ .awaited = c.JS_DupValue(s.engine.context, try s.call(method, iterator, &.{})) };
}
fn pull(s: *Scope, owner: c.JSValue) !gen.Action {
    const queue = try s.get(owner, "queue");
    var index: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &index, try s.get(owner, "queueIndex")) < 0) return v.js.capture(s.engine);
    if (index < try v.length(s, queue)) {
        // Decode only the next item requested by the actual generator queue.
        // In particular, do not decode a later exception during an earlier yield.
        const item = try wire.decode(s, try v.at(s, queue, index));
        try s.put(owner, "queueIndex", c.JS_NewUint32(s.engine.context, index + 1));
        try s.put(owner, "item", item);
        return .{ .yielded = c.JS_DupValue(s.engine.context, item) };
    }
    try s.put(owner, "stage", try s.text("pull"));
    return .{ .awaited = c.JS_DupValue(s.engine.context, try s.invoke(try s.get(owner, "iterator"), "next", &.{})) };
}
fn advance(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return step(&s, owner, completion, input) catch |err| {
        const reason = try s.own(@import("native_agent_async.zig").reason(engine, err));
        if (engine.captured_exception) |captured| {
            engine.captured_exception = null;
            engine.freeValue(captured);
        }
        return close(&s, owner, true, reason);
    };
}
fn step(s: *Scope, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
    const stage = try s.get(owner, "stage");
    if (try v.eq(s, stage, "closeThrow") or try v.eq(s, stage, "closeReturn")) {
        const throwing = try v.eq(s, stage, "closeThrow");
        if (completion == .rejected and !throwing) return finish(s, owner, true, input);
        return finish(s, owner, throwing, try s.get(owner, "closeValue"));
    }
    switch (completion) {
        .start => return pull(s, owner),
        .next => {
            try v.remove(s, owner, "item");
            return pull(s, owner);
        },
        .returned => return close(s, owner, false, input),
        .thrown, .rejected => return close(s, owner, true, input),
        .fulfilled => {
            if (s.truthy(try s.get(input, "done"))) {
                try wire.finish(s, owner);
                return finish(s, owner, false, c.pi_js_undefined());
            }
            const event = try s.get(input, "value");
            if (try v.eq(s, try s.get(event, "type"), "error_body")) {
                const reason = try @import("native_ai_bedrock_errors.zig").http(s, try s.get(owner, "response"), try s.get(owner, "requestId"), try s.get(event, "body"));
                return close(s, owner, true, reason);
            }
            try s.put(owner, "queue", try wire.feed(s, owner, try s.get(event, "data")));
            try s.put(owner, "queueIndex", c.JS_NewInt32(s.engine.context, 0));
            return pull(s, owner);
        },
    }
}
