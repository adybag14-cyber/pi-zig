//! Actual websocket.ts authenticator and immediate bounded link wrapping.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
fn authenticated(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, rejected: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return finish(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), rejected != 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn finish(engine: *h.Engine, work: c.JSValue, principal: c.JSValue, rejected: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const link = try s.get(work, "link");
    if (rejected) return js.invoke(engine, link, "close", &.{try s.text("authentication failed")});
    if (c.JS_IsUndefined(principal)) {
        _ = try h.invoke(&s, link, "close", &.{try s.text("unauthorized")});
        return c.pi_js_undefined();
    }
    const host = try s.get(work, "host");
    // Source gets the method before evaluating the object-spread argument.
    const accept_method = try s.get(host, "accept");
    const options = try s.record();
    try js.spreadInto(engine, options, try s.get(work, "options"));
    try h.field(&s, options, "principal", principal);
    try h.field(&s, options, "kind", try s.text("client"));
    _ = try s.keep(try js.call(engine, accept_method, host, &.{ link, options }));
    return c.pi_js_undefined();
}
fn connected(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return connection(engine, captures[0], captures[1], captures[2], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn connection(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, options: c.JSValue, socket: c.JSValue, request: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const link_options = try s.record();
    try h.field(&s, link_options, "compress", c.pi_js_bool(engine.context, 1));
    try h.field(&s, link_options, "acceptPacked", c.pi_js_bool(engine.context, 0));
    const link = try s.keep(try js.call(engine, try s.get(bindings, "webSocketLink"), c.pi_js_undefined(), &.{ socket, link_options }));
    const promise = try s.keep(try js.global(engine, "Promise"));
    const resolve = try s.get(promise, "resolve");
    const principal = try h.invoke(&s, options, "principal", &.{request});
    const pending = try s.keep(try js.call(engine, resolve, promise, &.{principal}));
    const work = try s.record();
    inline for (.{ "host", "options", "link" }, .{ host, options, link }) |name, value| try h.field(&s, work, name, value);
    var captures = [_]c.JSValue{work};
    const fulfilled = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, authenticated, "", 1, 0, 1, &captures)));
    const rejected = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, authenticated, "", 0, 1, 1, &captures)));
    _ = try h.invoke(&s, pending, "then", &.{ fulfilled, rejected });
    return c.pi_js_undefined();
}
fn accept(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var values = [_]c.JSValue{ captures[0], h.arg(args, 1), h.arg(args, 2) };
    const listener = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, connected, "", 2, 0, 3, &values)));
    _ = try h.invoke(&s, h.arg(args, 0), "on", &.{ try s.text("connection"), listener });
    return c.pi_js_undefined();
}
pub fn install(engine: *h.Engine, api: c.JSValue, bindings: c.JSValue) !void {
    try js.define(engine, api, "acceptWebSockets", try @import("native_node_function.zig").create(engine, "acceptWebSockets", 3, accept, &.{bindings}));
}
