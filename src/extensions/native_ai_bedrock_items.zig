//! Actual SDK frame/codec/modeled/wrapper generator boundaries on real C queues.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const gen = @import("native_async_generator.zig");
const flow = @import("native_agent_async.zig");
const wire = @import("native_ai_bedrock_wire.zig");
const Layer = enum { frames, codec, modeled, wrapped };
pub fn create(engine: *v.em.Engine, http: c.JSValue, response: c.JSValue, request_id: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const frames_owner = try s.object();
    try s.put(frames_owner, "http", http);
    try s.put(frames_owner, "iterator", try s.get(http, "events"));
    try s.put(frames_owner, "response", response);
    try s.put(frames_owner, "requestId", request_id);
    const frames = try s.own(try gen.create(engine, frames_owner, Body(.frames).advance, c.pi_js_undefined()));
    const codec_owner = try s.object();
    try s.put(codec_owner, "iterator", frames);
    const codec = try s.own(try gen.create(engine, codec_owner, Body(.codec).advance, c.pi_js_undefined()));
    const modeled_owner = try s.object();
    try s.put(modeled_owner, "iterator", codec);
    const modeled = try s.own(try gen.create(engine, modeled_owner, Body(.modeled).advance, c.pi_js_undefined()));
    // SDK EventStreamSerde awaits firstEvent before client.send resolves.
    const pending = try flow.create(engine, modeled);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try flow.wait(prefetched, engine, pending.owner, try s.invoke(modeled, "next", &.{}), 0);
    return pending.promise;
}
fn prefetched(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const iterator = try s.get(owner, "agent");
    if (s.truthy(try s.get(value, "done"))) return flow.settle(engine, owner, false, iterator);
    const state = try s.object();
    try s.put(state, "iterator", iterator);
    try s.put(state, "firstEvent", value);
    const wrapped = try s.own(try gen.create(engine, state, Body(.wrapped).advance, c.pi_js_undefined()));
    return flow.settle(engine, owner, false, wrapped);
}
fn retire(s: *Scope, owner: c.JSValue) !void {
    inline for (.{ "http", "iterator", "response", "requestId", "pendingBytes", "chunk", "item", "message", "firstEvent", "closeValue", "stage" }) |key| try v.remove(s, owner, key);
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
fn pull(comptime layer: Layer, s: *Scope, owner: c.JSValue) !gen.Action {
    if (layer == .frames) {
        // Following frame length/CRC/error parsing happens only after next.
        const frame = try wire.take(s, owner);
        if (!c.JS_IsUndefined(frame)) {
            const item = try s.own(try v.js.builtin(s.engine, "Uint8Array", &.{frame}));
            try s.put(owner, "item", item);
            return .{ .yielded = c.JS_DupValue(s.engine.context, item) };
        }
    }
    if (layer == .frames) try v.remove(s, owner, "chunk");
    try s.put(owner, "stage", try s.text("pull"));
    return .{ .awaited = c.JS_DupValue(s.engine.context, try s.invoke(try s.get(owner, "iterator"), "next", &.{})) };
}
fn Body(comptime layer: Layer) type {
    return struct {
        fn advance(engine: *v.em.Engine, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !gen.Action {
            var s: Scope = .{ .engine = engine };
            defer s.deinit();
            return step(&s, owner, completion, input) catch |err| {
                const reason = try s.own(flow.reason(engine, err));
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
                .start => {
                    if (layer == .wrapped) {
                        const item = try s.get(try s.get(owner, "firstEvent"), "value");
                        try s.put(owner, "item", item);
                        return .{ .yielded = c.JS_DupValue(s.engine.context, item) };
                    }
                    return pull(layer, s, owner);
                },
                .next => {
                    try v.remove(s, owner, "item");
                    try v.remove(s, owner, "message");
                    // The SDK wrapper closes over const firstEvent throughout
                    // its while loop; retire it only when this generator ends.
                    return pull(layer, s, owner);
                },
                .returned => return close(s, owner, false, input),
                .thrown, .rejected => return close(s, owner, true, input),
                .fulfilled => {
                    if (layer == .modeled and try v.eq(s, stage, "deserialize")) {
                        if (c.JS_IsUndefined(input)) return pull(layer, s, owner);
                        try s.put(owner, "item", input);
                        return .{ .yielded = c.JS_DupValue(s.engine.context, input) };
                    }
                    if (s.truthy(try s.get(input, "done"))) {
                        if (layer == .frames) try wire.finish(s, owner);
                        return finish(s, owner, false, c.pi_js_undefined());
                    }
                    const value = try s.get(input, "value");
                    if (layer == .frames) {
                        if (try v.eq(s, try s.get(value, "type"), "error_body")) {
                            const reason = try @import("native_ai_bedrock_errors.zig").http(s, try s.get(owner, "response"), try s.get(owner, "requestId"), try s.get(value, "body"));
                            return close(s, owner, true, reason);
                        }
                        const chunk = try s.get(value, "data");
                        try s.put(owner, "chunk", chunk);
                        try wire.append(s, owner, chunk);
                        return pull(layer, s, owner);
                    }
                    if (layer == .codec) {
                        const message = try wire.codec(s, value);
                        try s.put(owner, "item", message);
                        return .{ .yielded = c.JS_DupValue(s.engine.context, message) };
                    }
                    if (layer == .modeled) {
                        try s.put(owner, "message", value);
                        try s.put(owner, "stage", try s.text("deserialize"));
                        return .{ .awaited = try @import("native_ai_bedrock_deserialize.zig").unmarshal(s.engine, value) };
                    }
                    try s.put(owner, "item", value);
                    return .{ .yielded = c.JS_DupValue(s.engine.context, value) };
                },
            }
        }
    };
}
