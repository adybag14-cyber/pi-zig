//! Source Connection consumer operations. The actual Connection owner/dispatcher supplies the receiver.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
pub fn open(s: *Scope, receiver: c.JSValue) !c.JSValue {
    return c.pi_js_bool(s.engine.context, @intFromBool(!try h.flag(s, try s.get(receiver, "link"), "closed")));
}
pub fn getName(s: *Scope, bindings: c.JSValue, receiver: c.JSValue) !c.JSValue {
    if (try s.equal(try s.get(receiver, "role"), "upstream")) return js.get(s.engine, (try h.actor(s, receiver, bindings, .Connection)).data, "parentName");
    return js.get(s.engine, try s.get(receiver, "peer"), "name");
}
fn waitExecutor(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return addSyncWaiter(engine, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn addSyncWaiter(engine: *h.Engine, bindings: c.JSValue, receiver: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .Connection)).data;
    const pending = try s.record();
    try h.field(&s, pending, "resolve", resolve);
    try h.field(&s, pending, "reject", reject);
    _ = try h.invoke(&s, try s.get(data, "syncWaiters"), "add", &.{pending});
    return c.pi_js_undefined();
}
pub fn whenSynced(s: *Scope, bindings: c.JSValue, receiver: c.JSValue) !c.JSValue {
    if (!try h.flag(s, receiver, "open")) {
        const promise_type = try s.keep(try js.global(s.engine, "Promise"));
        const receiver_name = try s.get(receiver, "name");
        const failure = try h.errorValue(s, bindings, "unavailable", &.{ try s.text("link to "), if (h.nullish(receiver_name)) try s.text("peer") else receiver_name, try s.text(" closed") }, c.pi_js_undefined());
        return js.invoke(s.engine, promise_type, "reject", &.{failure});
    }
    if (try h.flag(s, receiver, "synced")) return js.invoke(s.engine, try s.keep(try js.global(s.engine, "Promise")), "resolve", &.{});
    var captures = [_]c.JSValue{ bindings, receiver };
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, waitExecutor, "", 2, 0, 2, &captures)));
    return js.builtin(s.engine, "Promise", &.{callback});
}
pub fn markSynced(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, epoch: c.JSValue) !void {
    try js.setKey(s.engine, receiver, try s.text("peerCodeVersion"), epoch);
    try js.setKey(s.engine, receiver, try s.text("synced"), c.pi_js_bool(s.engine.context, 1));
    const data = (try h.actor(s, receiver, bindings, .Connection)).data;
    const waiters = try s.get(data, "syncWaiters");
    var iterator = try js.Iterator.init(s.engine, waiters, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |pending| {
        defer s.engine.freeValue(pending);
        _ = try h.invoke(s, pending, "resolve", &.{c.pi_js_undefined()});
    }
    _ = try h.invoke(s, waiters, "clear", &.{});
}
pub fn send(s: *Scope, receiver: c.JSValue, message: c.JSValue) !void {
    _ = try h.invoke(s, try s.get(receiver, "link"), "send", &.{message});
}
pub fn frame(s: *Scope, tag: []const u8, id: c.JSValue) !c.JSValue {
    const message = try s.record();
    try h.field(s, message, "t", try s.text(tag));
    try h.field(s, message, "id", id);
    return message;
}
pub fn nextId(s: *Scope, data: c.JSValue) !c.JSValue {
    const value = try s.keep(try s.engine.checked(c.JS_PiToNumeric(s.engine.context, try s.get(data, "nextId"))));
    try h.field(s, data, "nextId", try s.keep(try s.engine.checked(c.JS_PiIncrement(s.engine.context, value))));
    return s.result(value);
}
pub fn hold(s: *Scope, receiver: c.JSValue, handle: c.JSValue) !c.JSValue {
    const id = try h.invoke(s, receiver, "nextId", &.{});
    _ = try h.invoke(s, try s.get(receiver, "remotes"), "set", &.{ id, handle });
    _ = try h.invoke(s, handle, "bound", &.{ receiver, id });
    const principal = try s.get(handle, "principal");
    const message = try frame(s, "hold", id);
    try h.field(s, message, "at", try s.get(handle, "at"));
    try h.field(s, message, "token", try s.get(try s.get(handle, "contract"), "description"));
    try h.field(s, message, "input", try s.get(handle, "input"));
    if (!c.JS_IsUndefined(principal)) try h.field(s, message, "principal", principal);
    if (try s.equal(try s.get(handle, "owner"), "client")) try h.field(s, message, "client", c.pi_js_bool(s.engine.context, 1));
    _ = try h.invoke(s, receiver, "send", &.{message});
    return s.result(id);
}
pub fn release(s: *Scope, receiver: c.JSValue, id: c.JSValue) !void {
    _ = try h.invoke(s, try s.get(receiver, "remotes"), "delete", &.{id});
    _ = try h.invoke(s, receiver, "send", &.{try frame(s, "release", id)});
}
pub fn sub(s: *Scope, receiver: c.JSValue, hold_id: c.JSValue, member: c.JSValue, sink: c.JSValue) !c.JSValue {
    const id = try h.invoke(s, receiver, "nextId", &.{});
    _ = try h.invoke(s, try s.get(receiver, "subs"), "set", &.{ id, sink });
    const message = try frame(s, "sub", id);
    try h.field(s, message, "hold", hold_id);
    try h.field(s, message, "member", member);
    _ = try h.invoke(s, receiver, "send", &.{message});
    return s.result(id);
}
pub fn unsub(s: *Scope, receiver: c.JSValue, id: c.JSValue) !void {
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(receiver, "subs"), "delete", &.{id})) != 0) _ = try h.invoke(s, receiver, "send", &.{try frame(s, "unsub", id)});
}
fn completed(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, failed: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return complete(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), failed != 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn complete(engine: *h.Engine, work: c.JSValue, value: c.JSValue, failed: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, try s.get(work, "signal"), "removeEventListener", &.{ try s.text("abort"), try s.get(work, "onAbort") });
    _ = try s.keep(try js.call(engine, try s.get(work, if (failed) "reject" else "resolve"), c.pi_js_undefined(), &.{value}));
    return c.pi_js_undefined();
}
fn abort(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return aborted(engine, captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn aborted(engine: *h.Engine, work: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const receiver = try s.get(work, "connection");
    _ = try h.invoke(&s, try s.get(receiver, "calls"), "delete", &.{try s.get(work, "id")});
    _ = try h.invoke(&s, receiver, "send", &.{try frame(&s, "cancel", try s.get(work, "id"))});
    const options = try s.record();
    try h.field(&s, options, "cause", try s.get(try s.get(work, "signal"), "reason"));
    const failure = try h.errorValue(&s, try s.get(work, "bindings"), "aborted", &.{try s.text("call aborted")}, options);
    _ = try s.keep(try js.call(engine, try s.get(work, "reject"), c.pi_js_undefined(), &.{failure}));
    return c.pi_js_undefined();
}
fn executor(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return execute(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn execute(engine: *h.Engine, work: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const signal = try s.get(work, "signal");
    const bindings = try s.get(work, "bindings");
    if (try h.flag(&s, signal, "aborted")) {
        const failure = try h.errorValue(&s, bindings, "aborted", &.{try s.text("call aborted")}, c.pi_js_undefined());
        _ = try s.keep(try js.call(engine, reject, c.pi_js_undefined(), &.{failure}));
        return c.pi_js_undefined();
    }
    try h.field(&s, work, "resolve", resolve);
    try h.field(&s, work, "reject", reject);
    var captures = [_]c.JSValue{work};
    const on_abort = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, abort, "onAbort", 0, 0, 1, &captures)));
    try h.field(&s, work, "onAbort", on_abort);
    const options = try s.record();
    try h.field(&s, options, "once", c.pi_js_bool(engine.context, 1));
    _ = try h.invoke(&s, signal, "addEventListener", &.{ try s.text("abort"), on_abort, options });
    const pending = try s.record();
    inline for (.{ "resolve", "reject" }, 0..) |name, phase| try h.field(&s, pending, name, try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, completed, name, 1, @intCast(phase), 1, &captures))));
    const receiver = try s.get(work, "connection");
    const id = try s.get(work, "id");
    _ = try h.invoke(&s, try s.get(receiver, "calls"), "set", &.{ id, pending });
    const root = try s.get(work, "root");
    const carried = !c.JS_IsUndefined(root) and try s.equal(try s.get(try s.get(receiver, "host"), "kind"), "host");
    if (carried) _ = try h.invoke(&s, try s.get(receiver, "host"), "rootSent", &.{ try s.get(root, "rootId"), receiver });
    const message = try frame(&s, "call", id);
    inline for (.{ "hold", "member", "args" }) |name| try h.field(&s, message, name, try s.get(work, name));
    if (carried) try h.field(&s, message, "root", root);
    _ = try h.invoke(&s, receiver, "send", &.{message});
    return c.pi_js_undefined();
}
pub fn call(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, hold_id: c.JSValue, member: c.JSValue, args: c.JSValue, root: c.JSValue, signal: c.JSValue) !c.JSValue {
    const id = try h.invoke(s, receiver, "nextId", &.{});
    const work = try s.record();
    inline for (.{ "bindings", "connection", "id", "hold", "member", "args", "root", "signal" }, .{ bindings, receiver, id, hold_id, member, args, root, signal }) |name, value| try h.field(s, work, name, value);
    var captures = [_]c.JSValue{work};
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, executor, "", 2, 0, 1, &captures)));
    return js.builtin(s.engine, "Promise", &.{callback});
}
pub fn revoke(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, next: c.JSValue) !void {
    const value = try s.keep(try s.engine.checked(c.JS_PiIncrement(s.engine.context, try s.get(receiver, "generation"))));
    try js.setKey(s.engine, receiver, try s.text("generation"), value);
    const failure = try h.errorValue(s, bindings, "gone", &.{try s.text("principal invalidated")}, c.pi_js_undefined());
    const served = try h.values(s, try s.get(receiver, "served"));
    for (0..try h.length(s, served)) |index| {
        const entry = try s.at(served, index);
        if (try s.equal(try s.get(entry, "kind"), "relay")) {
            const options = try s.record();
            try h.field(s, options, "releaseDown", c.pi_js_bool(s.engine.context, 1));
            try h.field(s, options, "notify", c.pi_js_bool(s.engine.context, 1));
            _ = try h.invoke(s, try s.get(entry, "relay"), "close", &.{ failure, options });
        }
    }
    if (c.JS_IsUndefined(next)) _ = try h.invoke(s, try s.get(receiver, "link"), "close", &.{try s.text("principal invalidated")}) else try js.setKey(s.engine, receiver, try s.text("principal"), next);
}
