//! Actual SDK modeled-member, union and unmarshaller async operations.
//! Locals cross real Promise awaits in GC-visible owner graphs.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const wire = @import("native_ai_bedrock_wire.zig");
fn header(s: *Scope, message: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return s.get(try s.get(try s.get(message, "headers"), name), "value");
}
fn reject(engine: *v.em.Engine, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    if (engine.captured_exception) |value| {
        engine.captured_exception = null;
        engine.freeValue(value);
    }
    return flow.settle(engine, owner, true, reason);
}
pub fn unmarshal(engine: *v.em.Engine, message: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, message);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    beginUnmarshal(&s, pending.owner, message) catch |err| try reject(engine, pending.owner, err);
    return pending.promise;
}
fn beginUnmarshal(s: *Scope, owner: c.JSValue, message: c.JSValue) !void {
    const kind = try header(s, message, ":message-type");
    try s.put(owner, "kind", kind);
    if (try v.eq(s, kind, "error")) {
        const text = try header(s, message, ":error-message");
        const error_value = try s.own(try v.js.builtin(s.engine, "Error", &.{if (s.truthy(text)) text else try s.text("UnknownError")}));
        try s.set(error_value, "name", try header(s, message, ":error-code"));
        return flow.settle(s.engine, owner, true, error_value);
    }
    const exception = try v.eq(s, kind, "exception");
    if (!exception and !try v.eq(s, kind, "event")) {
        const event = try header(s, message, ":event-type");
        const text = try s.invoke(try s.text("Unrecognizable event type: "), "concat", &.{event});
        return flow.settle(s.engine, owner, true, try s.own(try v.js.builtin(s.engine, "Error", &.{text})));
    }
    const typ = try header(s, message, if (exception) ":exception-type" else ":event-type");
    try s.put(owner, "type", typ);
    const promise = try s.own(try schema(s.engine, message, typ));
    return flow.wait(unmarshalled, s.engine, owner, promise, 0);
}
fn unmarshalled(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const exception = try v.eq(&s, try s.get(owner, "kind"), "exception");
    if (s.truthy(try s.get(value, "$unknown"))) {
        if (!exception) return flow.settle(engine, owner, false, c.pi_js_undefined());
        const body = try wire.bytes(&s, try s.get(try s.get(owner, "agent"), "body"));
        const error_value = try s.own(try v.js.builtin(engine, "Error", &.{try s.text(body)}));
        try s.set(error_value, "name", try s.get(owner, "type"));
        return flow.settle(engine, owner, true, error_value);
    }
    if (exception) return flow.settle(engine, owner, true, try s.own(try v.js.getKey(engine, value, try s.get(owner, "type"))));
    return flow.settle(engine, owner, false, value);
}
fn schema(engine: *v.em.Engine, message: c.JSValue, typ: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, message);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try s.put(pending.owner, "type", typ);
    const text = try engine.toString(typ);
    defer engine.gpa.free(text);
    if (!wire.modeledType(text)) {
        const event = try s.object();
        try v.js.setKey(engine, event, typ, message);
        const result = try s.object();
        try s.put(result, "$unknown", event);
        try flow.settle(engine, pending.owner, false, result);
    } else {
        const promise = try s.own(try readEventMember(engine, message, typ));
        try flow.wait(schemaRead, engine, pending.owner, promise, 0);
    }
    return pending.promise;
}
fn schemaRead(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.object();
    try v.js.setKey(engine, result, try s.get(owner, "type"), value);
    return flow.settle(engine, owner, false, result);
}
fn readEventMember(engine: *v.em.Engine, message: c.JSValue, typ: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, message);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try s.put(pending.owner, "type", typ);
    const body = try s.get(message, "body");
    if ((try wire.bytes(&s, body)).len == 0) {
        try memberRead(engine, pending.owner, try s.object(), false, 0);
    } else {
        const promise = try s.own(try jsonRead(engine, body, typ));
        try flow.wait(memberRead, engine, pending.owner, promise, 0);
    }
    return pending.promise;
}
fn memberRead(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const typ = try engine.toString(try s.get(owner, "type"));
    defer engine.gpa.free(typ);
    // The real schema creates the service Error value here; the async
    // unmarshaller throws it only after awaiting the completed union.
    const result = if (std.mem.endsWith(u8, typ, "Exception")) try wire.serviceError(&s, typ, value) else value;
    return flow.settle(engine, owner, false, result);
}
fn jsonRead(engine: *v.em.Engine, body: c.JSValue, typ: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, body);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const text = try engine.toString(typ);
    defer engine.gpa.free(text);
    const result = wire.readBody(&s, text, body) catch |err| {
        try reject(engine, pending.owner, err);
        return pending.promise;
    };
    try flow.settle(engine, pending.owner, false, result);
    return pending.promise;
}
