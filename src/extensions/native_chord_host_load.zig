//! Source Host.load/resolve: resolve once, install every facet before awaiting eager records.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
fn isFacet(s: *Scope, value: c.JSValue) !bool {
    if ((!c.JS_IsObject(value) or c.JS_IsFunction(s.engine.context, value)) and !c.JS_IsNull(value)) return false;
    const match = c.JS_IsInstanceOf(s.engine.context, value, try s.keep(try js.global(s.engine, "URL")));
    if (match < 0) return js.capture(s.engine);
    return match == 0;
}
fn selectModule(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const facet = isFacet(&s, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(!facet));
}
fn selected(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return selectFacet(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn selectFacet(engine: *h.Engine, reference: c.JSValue, loaded: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return if (try isFacet(&s, reference)) s.result(reference) else js.invoke(engine, loaded, "shift", &.{});
}
pub fn resolve(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, plugins: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const filter = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, selectModule, "", 1, 0, 0, null)));
    const modules = try h.invoke(&s, plugins, "filter", &.{filter});
    const loader = try s.get((try h.actor(&s, host, bindings, .HostImpl)).data, "loader");
    if (try h.length(&s, modules) > 0 and c.JS_IsUndefined(loader)) return h.ordinaryError(&s, &.{try s.text("loading modules needs createHost({ loader }), e.g. nodeLoader from @earendil-works/chord/node")});
    const work = try s.record();
    try h.field(&s, work, "plugins", plugins);
    if (try h.length(&s, modules) > 0 and !c.JS_IsUndefined(loader)) {
        const loaded = try s.keep(try js.call(engine, loader, host, &.{modules}));
        return h.wait(resolved, engine, work, loaded, 0);
    }
    // No await in this branch: Source's conditional expression selects [] synchronously.
    return resolved(engine, work, try s.list(), false, 0);
}
fn resolved(engine: *h.Engine, work: c.JSValue, loaded: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, loaded);
    var captures = [_]c.JSValue{loaded};
    const mapper = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, selected, "", 1, 0, 1, &captures)));
    return js.invoke(engine, try s.get(work, "plugins"), "map", &.{mapper});
}
pub fn load(engine: *h.Engine, host: c.JSValue, plugins: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try s.record();
    try h.field(&s, work, "host", host);
    try h.field(&s, work, "options", options);
    return h.wait(install, engine, work, try h.invoke(&s, host, "resolve", &.{plugins}), 0);
}
fn installOne(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "install", &.{ if (argc > 0) argv[0] else c.pi_js_undefined(), captures[1] }) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn nothing(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn install(engine: *h.Engine, work: c.JSValue, facets: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, facets);
    var captures = [_]c.JSValue{ try s.get(work, "host"), try s.get(work, "options") };
    const mapper = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, installOne, "", 1, 0, 2, &captures)));
    const pending = try h.invoke(&s, facets, "map", &.{mapper});
    const all = try h.invoke(&s, try s.keep(try js.global(engine, "Promise")), "all", &.{pending});
    const done = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, nothing, "", 0, 0, 0, null)));
    return js.invoke(engine, all, "then", &.{done});
}
