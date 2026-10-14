//! Actual local/relayed provider holds, root admission, calls and state feeds from Source connection.ts.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const dispatch = @import("native_chord_connection_v2_dispatch.zig");
const consumer = @import("native_chord_connection_v2_consumer.zig");
const Callback = enum(c_int) { shape, gone, relay_error, run_local, run_relay, result, failed, settled, state };
pub const handlers: dispatch.Provider = .{ .hold = onHold, .call = onCall, .sub = onSub, .unsub = onUnsub, .drop = dropServed };
fn function(s: *Scope, work: c.JSValue, operation: Callback, name: [*:0]const u8, arity: c_int) !c.JSValue {
    var captures = [_]c.JSValue{work};
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, name, arity, @intFromEnum(operation), 1, &captures)));
}
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return execute(engine, captures[0], @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn toWire(s: *Scope, bindings: c.JSValue, value: c.JSValue) !c.JSValue {
    return h.invoke(s, try s.get(bindings, "Wire"), "toWireError", &.{value});
}
fn replyError(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, tag: []const u8, id: c.JSValue, failure: c.JSValue) !void {
    const message = try consumer.frame(s, tag, id);
    try h.field(s, message, "error", try toWire(s, bindings, failure));
    _ = try h.invoke(s, receiver, "send", &.{message});
}
fn principalOf(s: *Scope, receiver: c.JSValue, data: c.JSValue, frame: c.JSValue) !c.JSValue {
    if (try s.equal(try s.get(receiver, "role"), "downstream")) return s.get(receiver, "principal");
    const principal = try s.get(frame, "principal");
    if (!h.nullish(principal)) return principal;
    const value = try s.record();
    const parent = try s.get(data, "parentName");
    try h.field(s, value, "host", if (h.nullish(parent)) try s.text("parent") else parent);
    return value;
}
fn isClient(s: *Scope, receiver: c.JSValue, frame: c.JSValue) !bool {
    return if (try s.equal(try s.get(receiver, "role"), "downstream")) s.equal(try s.get(try s.get(receiver, "peer"), "kind"), "client") else c.JS_IsStrictEqual(s.engine.context, try s.get(frame, "client"), c.pi_js_bool(s.engine.context, 1));
}
fn clientError(s: *Scope, bindings: c.JSValue, failure: c.JSValue) !c.JSValue {
    const instance = c.JS_IsInstanceOf(s.engine.context, failure, try s.get(try s.get(bindings, "errors"), "ChordError"));
    if (instance < 0) return js.capture(s.engine);
    if (instance != 0 and try s.equal(try s.get(failure, "code"), "contract_mismatch")) {
        const options = try s.record();
        try h.field(s, options, "cause", failure);
        return h.errorValue(s, bindings, "upgrade_required", &.{try s.get(failure, "message")}, options);
    }
    return failure;
}
fn acquireLocal(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, frame: c.JSValue, principal: c.JSValue, client: bool) !c.JSValue {
    const token = try s.keep(try @import("native_chord_contract_from_description.zig").fromDescription(s.engine, bindings, try s.get(frame, "token")));
    if (!try s.equal(try s.get(token, "scope"), "remote")) return h.invalid(s, bindings, "token", &.{ try s.get(token, "name"), try s.text(" is local; only remote types cross links") });
    const options = try s.record();
    try h.field(s, options, "principal", principal);
    const acquired = try h.invoke(s, try s.get(receiver, "host"), "acquire", &.{ token, try s.get(frame, "input"), options, try s.text(if (client) "client" else "connection") });
    const local = c.JS_IsInstanceOf(s.engine.context, acquired, try s.get(bindings, "RefImpl"));
    if (local < 0) return js.capture(s.engine);
    if (local == 0) return h.throwValue(s, try h.errorValue(s, bindings, "unavailable", &.{try s.text("not a local reference")}, c.pi_js_undefined()));
    return acquired;
}
pub fn onHold(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, data: c.JSValue, frame: c.JSValue) anyerror!void {
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(receiver, "served"), "has", &.{try s.get(frame, "id")})) != 0) return dispatch.violation(s, bindings, receiver, try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("duplicate hold id "), try s.get(frame, "id") })));
    const principal = try principalOf(s, receiver, data, frame);
    const client = try isClient(s, receiver, frame);
    if (!c.JS_IsStrictEqual(s.engine.context, try s.get(frame, "at"), try s.get(try s.get(receiver, "host"), "name"))) {
        if (try s.equal(try s.get(receiver, "role"), "upstream")) return replyError(s, bindings, receiver, "gone", try s.get(frame, "id"), try h.errorValue(s, bindings, "unavailable", &.{ try s.get(try s.get(receiver, "host"), "name"), try s.text(" does not relay") }, c.pi_js_undefined()));
        const relay = try h.construct(s, bindings, "RelayRef", &.{ receiver, frame, principal, c.pi_js_bool(s.engine.context, @intFromBool(client)) });
        const served = try s.record();
        try h.field(s, served, "kind", try s.text("relay"));
        try h.field(s, served, "relay", relay);
        _ = try h.invoke(s, try s.get(receiver, "served"), "set", &.{ try s.get(frame, "id"), served });
        const pending = try h.invoke(s, try s.get(receiver, "host"), "relay", &.{relay});
        const work = try s.record();
        try h.field(s, work, "relay", relay);
        _ = try h.invoke(s, pending, "catch", &.{try function(s, work, .relay_error, "", 1)});
        return;
    }
    const generation = s.engine.native_allocation_generation;
    const handle = acquireLocal(s, bindings, receiver, frame, principal, client) catch |err| {
        const mapped = s.engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
        const failure = s.engine.captured_exception orelse return err;
        return replyError(s, bindings, receiver, "gone", try s.get(frame, "id"), if (client) try clientError(s, bindings, failure) else failure);
    };
    const served = try s.record();
    try h.field(s, served, "kind", try s.text("local"));
    try h.field(s, served, "ref", handle);
    try h.field(s, served, "principal", principal);
    try h.field(s, served, "feeds", try h.set(s));
    _ = try h.invoke(s, try s.get(receiver, "served"), "set", &.{ try s.get(frame, "id"), served });
    const work = try s.record();
    inline for (.{ "bindings", "connection", "frame", "served", "ref" }, .{ bindings, receiver, frame, served, handle }) |name, value| try h.field(s, work, name, value);
    const shape = try function(s, work, .shape, "shape", 0);
    _ = try h.invoke(s, handle, "onShape", &.{shape});
    _ = try h.invoke(s, try s.get(handle, "goneListeners"), "add", &.{try function(s, work, .gone, "", 1)});
    if (try s.equal(try s.get(handle, "status"), "live")) _ = try s.keep(try execute(s.engine, work, .shape, c.pi_js_undefined()));
}
pub fn dropServed(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, id: c.JSValue, release: bool) anyerror!void {
    const served = try h.invoke(s, try s.get(receiver, "served"), "get", &.{id});
    if (c.JS_IsUndefined(served)) return;
    _ = try h.invoke(s, try s.get(receiver, "served"), "delete", &.{id});
    if (try s.equal(try s.get(served, "kind"), "relay")) {
        const options = try s.record();
        try h.field(s, options, "releaseDown", c.pi_js_bool(s.engine.context, @intFromBool(release)));
        try h.field(s, options, "notify", c.pi_js_bool(s.engine.context, 0));
        _ = try h.invoke(s, try s.get(served, "relay"), "close", &.{ try h.errorValue(s, bindings, "released", &.{try s.text("relayed hold released")}, c.pi_js_undefined()), options });
        return;
    }
    var iterator = try js.Iterator.init(s.engine, try s.get(served, "feeds"), try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |feed| {
        defer s.engine.freeValue(feed);
        try onUnsub(s, bindings, receiver, c.pi_js_undefined(), feed);
    }
    if (release) _ = try h.invoke(s, try s.get(served, "ref"), "release", &.{});
}
fn admitRoot(s: *Scope, receiver: c.JSValue, data: c.JSValue, root: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(root) or !try s.equal(try s.get(receiver, "role"), "downstream") or c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(receiver, "fencedCodeVersions"), "has", &.{try s.get(root, "codeVersion")})) == 0) return root;
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(receiver, "host"), "hasCodeVersion", &.{try s.get(root, "codeVersion")})) != 0) return root;
    const admitted = try s.get(data, "admitted");
    var epoch = try h.invoke(s, admitted, "get", &.{try s.get(root, "rootId")});
    if (c.JS_IsUndefined(epoch)) {
        epoch = try s.get(try s.get(try s.get(receiver, "host"), "current"), "id");
        _ = try h.invoke(s, admitted, "set", &.{ try s.get(root, "rootId"), epoch });
    }
    const result = try s.record();
    try h.field(s, result, "rootId", try s.get(root, "rootId"));
    try h.field(s, result, "codeVersion", epoch);
    return result;
}
pub fn onCall(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, data: c.JSValue, frame: c.JSValue) anyerror!void {
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(receiver, "incoming"), "has", &.{try s.get(frame, "id")})) != 0) return dispatch.violation(s, bindings, receiver, try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("duplicate call id "), try s.get(frame, "id") })));
    const excess = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 7, try s.get(try s.get(receiver, "incoming"), "size"), try s.get(data, "maxCalls"))));
    if (c.JS_ToBool(s.engine.context, excess) != 0) {
        const options = try s.record();
        try h.field(s, options, "reason", try s.text("too_many_calls"));
        return replyError(s, bindings, receiver, "result", try s.get(frame, "id"), try h.errorValue(s, bindings, "unavailable", &.{ try s.text("Too many calls in progress on this connection ("), try s.get(data, "maxCalls"), try s.text("); wait for earlier ones to finish") }, options));
    }
    const served = try h.invoke(s, try s.get(receiver, "served"), "get", &.{try s.get(frame, "hold")});
    if (c.JS_IsUndefined(served)) return replyError(s, bindings, receiver, "result", try s.get(frame, "id"), try h.errorValue(s, bindings, "gone", &.{try s.text("unknown hold")}, c.pi_js_undefined()));
    const controller = try s.keep(try js.builtin(s.engine, "AbortController", &.{}));
    _ = try h.invoke(s, try s.get(receiver, "incoming"), "set", &.{ try s.get(frame, "id"), controller });
    const root = if (try s.equal(try s.get(try s.get(receiver, "peer"), "kind"), "host")) try admitRoot(s, receiver, data, try s.get(frame, "root")) else c.pi_js_undefined();
    const local = try s.equal(try s.get(served, "kind"), "local");
    const principal = if (local) try s.get(served, "principal") else try s.get(try s.get(served, "relay"), "principal");
    const options = try s.record();
    try h.field(s, options, "principal", principal);
    try h.field(s, options, "signal", try s.get(controller, "signal"));
    const work = try s.record();
    inline for (.{ "bindings", "connection", "frame", "served", "controller" }, .{ bindings, receiver, frame, served, controller }) |name, value| try h.field(s, work, name, value);
    const run = try function(s, work, if (try s.equal(try s.get(served, "kind"), "local")) .run_local else .run_relay, "", 1);
    const host = try s.get(receiver, "host");
    const result = if (c.JS_IsUndefined(root)) try h.invoke(s, host, "root", &.{ run, options }) else result: {
        const joined = try s.record();
        try js.spreadInto(s.engine, joined, options);
        try h.field(s, joined, "from", receiver);
        break :result try h.invoke(s, host, "joinRoot", &.{ try s.get(root, "rootId"), try s.get(root, "codeVersion"), run, joined });
    };
    const replied = try h.invoke(s, result, "then", &.{ try function(s, work, .result, "", 1), try function(s, work, .failed, "", 1) });
    _ = try h.invoke(s, replied, "finally", &.{try function(s, work, .settled, "", 0)});
}
fn kindOf(s: *Scope, behavior: c.JSValue) !c.JSValue {
    return if (c.JS_IsString(try s.get(behavior, "variant"))) s.get(behavior, "variant") else c.pi_js_undefined();
}
fn memberDescription(s: *Scope, contract: c.JSValue, kind: c.JSValue, member: c.JSValue) !c.JSValue {
    const variants = try s.get(try s.get(contract, "description"), "variants");
    const variant = try s.key(variants, if (h.nullish(kind)) try s.text("") else kind);
    return if (h.nullish(variant)) c.pi_js_undefined() else s.key(variant, member);
}
fn validateSnapshot(s: *Scope, bindings: c.JSValue, handle: c.JSValue, member: c.JSValue, value: c.JSValue) !void {
    if (c.JS_IsUndefined(value)) return;
    const installed = try h.invoke(s, try s.get(handle, "object"), "currentInstalled", &.{});
    if (c.JS_IsUndefined(installed)) return;
    const view = try h.invoke(s, handle, "currentView", &.{});
    const kind = try kindOf(s, if (c.JS_IsUndefined(view)) try s.get(installed, "implementation") else view);
    const description = if (!c.JS_IsUndefined(view) and !c.JS_IsStrictEqual(s.engine.context, view, try s.get(installed, "implementation"))) try memberDescription(s, try s.get(handle, "contract"), kind, member) else try memberDescription(s, try s.get(try s.get(installed, "service"), "contract"), try kindOf(s, try s.get(installed, "implementation")), member);
    if (!h.nullish(description) and try s.equal(try s.get(description, "kind"), "state")) {
        const what = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.get(handle, "address"), try s.text("."), member }));
        try @import("native_chord_object_schema.zig").assertValid(s, bindings, "state", what, try s.get(description, "schema"), value);
    }
}
pub fn onSub(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, _: c.JSValue, frame: c.JSValue) anyerror!void {
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(receiver, "feeds"), "has", &.{try s.get(frame, "id")})) != 0 or c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(receiver, "relaySubs"), "has", &.{try s.get(frame, "id")})) != 0) return dispatch.violation(s, bindings, receiver, try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("duplicate sub id "), try s.get(frame, "id") })));
    const served = try h.invoke(s, try s.get(receiver, "served"), "get", &.{try s.get(frame, "hold")});
    if (c.JS_IsUndefined(served)) return replyError(s, bindings, receiver, "state", try s.get(frame, "id"), try h.errorValue(s, bindings, "gone", &.{try s.text("unknown hold")}, c.pi_js_undefined()));
    if (try s.equal(try s.get(served, "kind"), "relay")) {
        _ = try h.invoke(s, try s.get(served, "relay"), "subscribe", &.{ try s.get(frame, "id"), try s.get(frame, "member") });
        return;
    }
    const readable = try h.invoke(s, try s.get(served, "ref"), "member", &.{try s.get(frame, "member")});
    if (c.JS_IsUndefined(readable) or !c.JS_IsFunction(s.engine.context, try s.get(readable, "events"))) return replyError(s, bindings, receiver, "state", try s.get(frame, "id"), try h.errorValue(s, bindings, "not_in_variant", &.{ try s.get(frame, "member"), try s.text(" is not state") }, c.pi_js_undefined()));
    const work = try s.record();
    inline for (.{ "bindings", "connection", "frame", "served" }, .{ bindings, receiver, frame, served }) |name, value| try h.field(s, work, name, value);
    try h.field(s, work, "stream", try h.invoke(s, try s.get(bindings, "DeltaCodec"), "encoder", &.{}));
    const unsubscribe = try h.invoke(s, readable, "events", &.{try function(s, work, .state, "send", 1)});
    _ = try h.invoke(s, try s.get(receiver, "feeds"), "set", &.{ try s.get(frame, "id"), unsubscribe });
    _ = try h.invoke(s, try s.get(served, "feeds"), "add", &.{try s.get(frame, "id")});
}
pub fn onUnsub(s: *Scope, _: c.JSValue, receiver: c.JSValue, _: c.JSValue, id: c.JSValue) anyerror!void {
    _ = try h.invoke(s, receiver, "dropState", &.{id});
    const unsubscribe = try h.invoke(s, try s.get(receiver, "feeds"), "get", &.{id});
    if (!c.JS_IsUndefined(unsubscribe)) {
        _ = try h.invoke(s, try s.get(receiver, "feeds"), "delete", &.{id});
        _ = try s.keep(try js.call(s.engine, unsubscribe, c.pi_js_undefined(), &.{}));
    }
    const relay = try h.invoke(s, try s.get(receiver, "relaySubs"), "get", &.{id});
    if (!h.nullish(relay)) _ = try h.invoke(s, relay, "unsubscribe", &.{id});
}
fn execute(engine: *h.Engine, work: c.JSValue, operation: Callback, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (operation == .relay_error) {
        const options = try s.record();
        try h.field(&s, options, "releaseDown", c.pi_js_bool(engine.context, 1));
        try h.field(&s, options, "notify", c.pi_js_bool(engine.context, 1));
        _ = try h.invoke(&s, try s.get(work, "relay"), "close", &.{ value, options });
        return c.pi_js_undefined();
    }
    const bindings = try s.get(work, "bindings");
    const receiver = try s.get(work, "connection");
    const incoming = try s.get(work, "frame");
    if (operation == .settled) return js.invoke(engine, try s.get(receiver, "incoming"), "delete", &.{try s.get(incoming, "id")});
    if (operation == .result or operation == .failed) {
        const message = try consumer.frame(&s, "result", try s.get(incoming, "id"));
        try h.field(&s, message, if (operation == .result) "value" else "error", if (operation == .result) value else try toWire(&s, bindings, value));
        _ = try h.invoke(&s, receiver, "send", &.{message});
        return c.pi_js_undefined();
    }
    const served = try s.get(work, "served");
    if (operation == .run_local) {
        const handle = try s.get(served, "ref");
        return js.invoke(engine, try s.get(handle, "object"), "call", &.{ try s.get(served, "ref"), try s.get(incoming, "member"), try @import("native_chord_packing.zig").unpack(&s, bindings, try s.get(incoming, "args")), value });
    }
    if (operation == .run_relay) {
        const root = try s.record();
        try h.field(&s, root, "rootId", try s.get(value, "rootId"));
        try h.field(&s, root, "codeVersion", try s.get(value, "codeVersion"));
        return @import("native_chord_relay_v2_call.zig").call(engine, bindings, try s.get(served, "relay"), incoming, root, try s.get(value, "signal"), try s.get(receiver, "host"));
    }
    if (operation == .shape) {
        const current = try s.get(try s.get(work, "ref"), "shape");
        if (c.JS_IsUndefined(current) or !c.JS_IsStrictEqual(engine.context, try h.invoke(&s, try s.get(receiver, "served"), "get", &.{try s.get(incoming, "id")}), served)) return c.pi_js_undefined();
        const message = try consumer.frame(&s, "shape", try s.get(incoming, "id"));
        inline for (.{ "variant", "members", "contract", "codeVersion" }) |name| try h.field(&s, message, name, try s.get(current, name));
        _ = try h.invoke(&s, receiver, "send", &.{message});
        return c.pi_js_undefined();
    }
    if (operation == .gone) {
        if (!c.JS_IsStrictEqual(engine.context, try h.invoke(&s, try s.get(receiver, "served"), "get", &.{try s.get(incoming, "id")}), served)) return c.pi_js_undefined();
        try dropServed(&s, bindings, receiver, try s.get(incoming, "id"), false);
        try replyError(&s, bindings, receiver, "gone", try s.get(incoming, "id"), value);
        return c.pi_js_undefined();
    }
    const message = try consumer.frame(&s, "state", try s.get(incoming, "id"));
    if (try s.equal(try s.get(value, "type"), "ops")) {
        try h.field(&s, message, "ops", try h.invoke(&s, try s.get(work, "stream"), "encode", &.{try s.get(value, "ops")}));
        if (c.JS_ToBool(engine.context, try h.invoke(&s, receiver, "sendState", &.{message})) != 0) return c.pi_js_undefined();
    }
    if (c.JS_IsUndefined(try s.get(value, "value"))) return c.pi_js_undefined();
    const generation = engine.native_allocation_generation;
    validateSnapshot(&s, bindings, try s.get(served, "ref"), try s.get(incoming, "member"), try s.get(value, "value")) catch |err| {
        const mapped = engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
        const failure = try consumer.frame(&s, "state", try s.get(incoming, "id"));
        try h.field(&s, failure, "error", try toWire(&s, bindings, engine.captured_exception orelse return err));
        _ = try h.invoke(&s, receiver, "sendState", &.{failure});
        return c.pi_js_undefined();
    };
    try h.field(&s, work, "stream", try h.invoke(&s, try s.get(bindings, "DeltaCodec"), "encoder", &.{}));
    const reset = try consumer.frame(&s, "state", try s.get(incoming, "id"));
    try h.field(&s, reset, if (try s.equal(try s.get(value, "type"), "snap")) "snap" else "reset", try s.get(value, "value"));
    _ = try h.invoke(&s, receiver, "sendState", &.{reset});
    return c.pi_js_undefined();
}
