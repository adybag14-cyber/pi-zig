//! Source Connection validation/dispatch. Provider operations must be real native handlers supplied by the owner.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
pub const Handler = *const fn (*h.Scope, c.JSValue, c.JSValue, c.JSValue, c.JSValue) anyerror!void;
pub const Drop = *const fn (*h.Scope, c.JSValue, c.JSValue, c.JSValue, bool) anyerror!void;
pub const Provider = struct { hold: Handler, call: Handler, sub: Handler, unsub: Handler, drop: Drop };
pub fn violation(s: *h.Scope, bindings: c.JSValue, receiver: c.JSValue, reason: c.JSValue) !void {
    const name = try s.get(receiver, "name");
    const options = try s.record();
    try h.field(s, options, "reason", try s.text("protocol"));
    const failure = try h.errorValue(s, bindings, "invalid", &.{ try s.text("link to "), if (h.nullish(name)) try s.text("peer") else name, try s.text(": "), reason }, options);
    _ = try h.invoke(s, try s.get(receiver, "host"), "report", &.{failure});
    const message = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("protocol error: "), reason }));
    _ = try h.invoke(s, try s.get(receiver, "link"), "close", &.{message});
}
fn report(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const host = s.get(captures[0], "host") catch |err| return @import("native_durable.zig").reject(engine, err);
    return js.invoke(engine, host, "report", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn onHello(s: *h.Scope, bindings: c.JSValue, receiver: c.JSValue, data: c.JSValue, frame: c.JSValue) !void {
    if (try s.equal(try s.get(receiver, "role"), "upstream")) {
        if (!try s.equal(try s.get(frame, "kind"), "host")) return violation(s, bindings, receiver, try s.text("parent is not a host"));
        if (h.nullish(try s.get(data, "parentName"))) try h.field(s, data, "parentName", try s.get(frame, "name"));
        return;
    }
    if (!c.JS_IsStrictEqual(s.engine.context, try s.get(frame, "kind"), try s.get(try s.get(receiver, "peer"), "kind")) or (!c.JS_IsUndefined(try s.get(try s.get(receiver, "peer"), "name")) and !c.JS_IsStrictEqual(s.engine.context, try s.get(frame, "name"), try s.get(try s.get(receiver, "peer"), "name")))) {
        const peer_name = try s.get(try s.get(receiver, "peer"), "name");
        const reason = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("hello "), try s.get(frame, "kind"), try s.text(" "), try s.get(frame, "name"), try s.text(" does not match the accepted "), try s.get(try s.get(receiver, "peer"), "kind"), try s.text(" "), if (h.nullish(peer_name)) try s.text("") else peer_name }));
        return violation(s, bindings, receiver, reason);
    }
    if (try s.equal(try s.get(try s.get(receiver, "peer"), "kind"), "host")) _ = try h.invoke(s, try s.get(receiver, "host"), "peerHello", &.{ receiver, try s.get(frame, "epoch") });
}
fn fromWire(s: *h.Scope, bindings: c.JSValue, error_value: c.JSValue) !c.JSValue {
    return h.invoke(s, try s.get(bindings, "Wire"), "fromWireError", &.{error_value});
}
fn onHoldReply(s: *h.Scope, bindings: c.JSValue, receiver: c.JSValue, frame: c.JSValue) !void {
    const relay = try h.invoke(s, try s.get(receiver, "relayedHolds"), "get", &.{try s.get(frame, "id")});
    if (!c.JS_IsUndefined(relay)) {
        if (try s.equal(try s.get(frame, "t"), "gone")) {
            const options = try s.record();
            try h.field(s, options, "releaseDown", c.pi_js_bool(s.engine.context, 0));
            try h.field(s, options, "notify", c.pi_js_bool(s.engine.context, 1));
            _ = try h.invoke(s, relay, "close", &.{ try fromWire(s, bindings, try s.get(frame, "error")), options });
        } else if (!try h.flag(s, relay, "closed")) {
            const outgoing = try s.record();
            try js.spreadInto(s.engine, outgoing, frame);
            try h.field(s, outgoing, "id", try s.get(relay, "originId"));
            _ = try h.invoke(s, try s.get(relay, "origin"), "send", &.{outgoing});
        }
        return;
    }
    const handle = try h.invoke(s, try s.get(receiver, "remotes"), "get", &.{try s.get(frame, "id")});
    if (c.JS_IsUndefined(handle)) return;
    if (try s.equal(try s.get(frame, "t"), "gone")) {
        _ = try h.invoke(s, try s.get(receiver, "remotes"), "delete", &.{try s.get(frame, "id")});
        _ = try h.invoke(s, handle, "gone", &.{try fromWire(s, bindings, try s.get(frame, "error"))});
        return;
    }
    const shape = try s.record();
    inline for (.{ "kind", "members", "contract", "epoch" }) |key| try h.field(s, shape, key, try s.get(frame, key));
    _ = try h.invoke(s, handle, "shaped", &.{shape});
}
fn onResult(s: *h.Scope, bindings: c.JSValue, receiver: c.JSValue, frame: c.JSValue) !void {
    const relayed = try h.invoke(s, try s.get(receiver, "relayedCalls"), "get", &.{try s.get(frame, "id")});
    if (!c.JS_IsUndefined(relayed)) {
        const error_value = try s.get(frame, "error");
        _ = try h.invoke(s, relayed, "finish", &.{ if (c.JS_IsUndefined(error_value)) c.pi_js_undefined() else try fromWire(s, bindings, try s.get(frame, "error")), try s.get(frame, "value") });
        return;
    }
    const pending = try h.invoke(s, try s.get(receiver, "calls"), "get", &.{try s.get(frame, "id")});
    _ = try h.invoke(s, try s.get(receiver, "calls"), "delete", &.{try s.get(frame, "id")});
    const failed = !c.JS_IsUndefined(try s.get(frame, "error"));
    if (h.nullish(pending)) return;
    _ = try h.invoke(s, pending, if (failed) "reject" else "resolve", &.{if (failed) try fromWire(s, bindings, try s.get(frame, "error")) else try s.get(frame, "value")});
}
fn onState(s: *h.Scope, receiver: c.JSValue, frame: c.JSValue) !void {
    const relayed = try h.invoke(s, try s.get(receiver, "relayedSubs"), "get", &.{try s.get(frame, "id")});
    if (!c.JS_IsUndefined(relayed)) {
        const outgoing = try s.record();
        try js.spreadInto(s.engine, outgoing, frame);
        try h.field(s, outgoing, "id", try s.get(relayed, "originSubId"));
        _ = try h.invoke(s, try s.get(try s.get(relayed, "relay"), "origin"), "send", &.{outgoing});
        return;
    }
    const sink = try h.invoke(s, try s.get(receiver, "subs"), "get", &.{try s.get(frame, "id")});
    if (!h.nullish(sink)) _ = try s.keep(try js.call(s.engine, sink, c.pi_js_undefined(), &.{frame}));
}
pub fn dispatch(s: *h.Scope, bindings: c.JSValue, receiver: c.JSValue, data: c.JSValue, frame: c.JSValue, provider: Provider) anyerror!void {
    const tag = try s.get(frame, "t");
    if (try s.equal(tag, "hello")) return onHello(s, bindings, receiver, data, frame);
    if (try s.equal(tag, "ping")) {
        const outgoing = try s.record();
        try h.field(s, outgoing, "t", try s.text("pong"));
        try h.field(s, outgoing, "n", try s.get(frame, "n"));
        _ = try h.invoke(s, receiver, "send", &.{outgoing});
        return;
    }
    if (try s.equal(tag, "pong") or try s.equal(tag, "bye")) return;
    if (try s.equal(tag, "hold")) return provider.hold(s, bindings, receiver, data, frame);
    if (try s.equal(tag, "release")) return provider.drop(s, bindings, receiver, try s.get(frame, "id"), true);
    if (try s.equal(tag, "call")) return provider.call(s, bindings, receiver, data, frame);
    if (try s.equal(tag, "cancel")) {
        const controller = try h.invoke(s, try s.get(receiver, "incoming"), "get", &.{try s.get(frame, "id")});
        if (!h.nullish(controller)) _ = try h.invoke(s, controller, "abort", &.{try h.errorValue(s, bindings, "aborted", &.{try s.text("cancelled by caller")}, c.pi_js_undefined())});
        return;
    }
    if (try s.equal(tag, "sub")) return provider.sub(s, bindings, receiver, data, frame);
    if (try s.equal(tag, "unsub")) return provider.unsub(s, bindings, receiver, data, try s.get(frame, "id"));
    if (try s.equal(tag, "shape") or try s.equal(tag, "gone")) return onHoldReply(s, bindings, receiver, frame);
    if (try s.equal(tag, "result")) return onResult(s, bindings, receiver, frame);
    if (try s.equal(tag, "state")) return onState(s, receiver, frame);
    if (try s.equal(tag, "root_end")) {
        _ = try h.invoke(s, try s.get(data, "admitted"), "delete", &.{try s.get(frame, "rootId")});
        _ = try h.invoke(s, try s.get(receiver, "host"), "foreignRootEnded", &.{ try s.get(frame, "rootId"), receiver });
        return;
    }
    if (try s.equal(tag, "invalidate") or try s.equal(tag, "prepare") or try s.equal(tag, "commit") or try s.equal(tag, "abort") or try s.equal(tag, "retire")) {
        if (!try s.equal(try s.get(receiver, "role"), "upstream")) return violation(s, bindings, receiver, try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ tag, try s.text(" from a child") })));
        const host = try s.get(receiver, "host");
        if (try s.equal(tag, "invalidate")) {
            const pending = try h.invoke(s, host, "invalidatePrincipal", &.{try s.get(frame, "pattern")});
            var captures = [_]c.JSValue{receiver};
            const rejected = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, report, "", 1, 0, 1, &captures)));
            _ = try h.invoke(s, pending, "catch", &.{rejected});
        } else if (try s.equal(tag, "retire")) {
            _ = try h.invoke(s, host, "allowRetire", &.{try s.get(frame, "epoch")});
        } else _ = try h.invoke(s, host, "onReloadFrame", &.{ receiver, frame });
        return;
    }
    if (try s.equal(tag, "vote")) {
        if (!try s.equal(try s.get(receiver, "role"), "downstream") or !try s.equal(try s.get(try s.get(receiver, "peer"), "kind"), "host")) return violation(s, bindings, receiver, try s.text("vote from a non-participant"));
        const pending = try h.invoke(s, try s.get(receiver, "votes"), "get", &.{try s.get(frame, "reload")});
        _ = try h.invoke(s, try s.get(receiver, "votes"), "delete", &.{try s.get(frame, "reload")});
        const failed = !c.JS_IsUndefined(try s.get(frame, "error"));
        if (!h.nullish(pending)) _ = try h.invoke(s, pending, if (failed) "reject" else "resolve", &.{if (failed) try fromWire(s, bindings, try s.get(frame, "error")) else try s.get(frame, "report")});
    }
}
pub fn receive(s: *h.Scope, bindings: c.JSValue, receiver: c.JSValue, data: c.JSValue, frame: c.JSValue, provider: Provider) anyerror!void {
    const now = try s.builtin("Date", "now", &.{});
    try h.field(s, data, "lastSeen", now);
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(bindings, "Wire"), "isFrame", &.{frame})) == 0) return violation(s, bindings, receiver, try s.text("malformed frame"));
    const generation = s.engine.native_allocation_generation;
    dispatch(s, bindings, receiver, data, frame, provider) catch |err| {
        const mapped = s.engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
        _ = try h.invoke(s, try s.get(receiver, "host"), "report", &.{s.engine.captured_exception orelse return err});
    };
}
