//! Source1692 retained-version retirement, watcher notifications and dependency-ordered implementation cleanup.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub fn changed(s: *Scope, bindings: c.JSValue, host: c.JSValue) !void {
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    const watchers = try h.snapshot(s, try s.get(data, "retirementWatchers"));
    for (0..try h.length(s, watchers)) |index| _ = try s.keep(try js.call(s.engine, try s.at(watchers, index), c.pi_js_undefined(), &.{}));
}
pub fn retirable(s: *Scope, bindings: c.JSValue, host: c.JSValue) !bool {
    const previous = try s.get(host, "previous");
    if (c.JS_IsUndefined(previous) or try r.index(s, try s.get(previous, "roots"), "size") > 0) return false;
    if (try s.equal(try s.get(host, "kind"), "client") or c.JS_IsUndefined(try s.get(host, "upstream"))) return true;
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    const permitted = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 5, try s.get(previous, "id"), try s.get(data, "retireAllowed"))));
    return c.JS_ToBool(s.engine.context, permitted) != 0;
}
pub fn allow(s: *Scope, bindings: c.JSValue, host: c.JSValue, version: c.JSValue) !void {
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    try h.field(s, data, "retireAllowed", try s.builtin("Math", "max", &.{ try s.get(data, "retireAllowed"), version }));
    _ = try h.invoke(s, host, "maybeRetire", &.{});
    try changed(s, bindings, host);
}
fn unwatch(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "delete", &.{captures[1]}) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn watch(s: *Scope, bindings: c.JSValue, host: c.JSValue, watcher: c.JSValue) !c.JSValue {
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    const watchers = try s.get(data, "retirementWatchers");
    _ = try h.invoke(s, watchers, "add", &.{watcher});
    var captures = [_]c.JSValue{ watchers, watcher };
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, unwatch, "", 0, 0, 2, &captures)));
}
pub fn announce(s: *Scope, host: c.JSValue, connection: c.JSValue) !void {
    const oldest = r.default(s, try s.get(host, "previous"), try s.get(host, "current"));
    const retired = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 1, try s.get(oldest, "id"), c.JS_NewInt32(s.engine.context, 1))));
    if (!try r.greater(s, retired, c.JS_NewInt32(s.engine.context, 0))) return;
    const frame = try s.record();
    try h.field(s, frame, "t", try s.text("retire"));
    try h.field(s, frame, "codeVersion", retired);
    _ = try h.invoke(s, connection, "send", &.{frame});
}
pub fn retire(s: *Scope, bindings: c.JSValue, host: c.JSValue) !void {
    const previous = try s.get(host, "previous");
    if (c.JS_IsUndefined(previous)) return;
    try r.put(s, host, "previous", c.pi_js_undefined());
    _ = try h.invoke(s, try s.get(host, "codeVersions"), "delete", &.{try s.get(previous, "id")});
    const objects = try h.values(s, try s.get(host, "objects"));
    for (0..try h.length(s, objects)) |index| _ = try h.invoke(s, host, "retireImplementation", &.{ try s.at(objects, index), try s.get(previous, "id") });
    var connections = try r.iterate(s, try s.get(host, "connections"));
    defer connections.deinit();
    errdefer connections.closePreserving();
    while (try connections.next()) |connection| {
        defer s.engine.freeValue(connection);
        if (!try s.equal(try s.get(connection, "role"), "downstream") or !try s.equal(try r.optional(s, try s.get(connection, "peer"), "kind"), "host")) continue;
        const message = try s.record();
        try h.field(s, message, "t", try s.text("retire"));
        try h.field(s, message, "codeVersion", try s.get(previous, "id"));
        _ = try h.invoke(s, connection, "send", &.{message});
    }
    try changed(s, bindings, host);
}
fn keep(s: *Scope, declarations: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const values = try s.list();
    for (0..try h.length(s, declarations)) |index| {
        const current = try h.values(s, try s.get(try s.at(declarations, index), name));
        for (0..try h.length(s, current)) |slot| try js.push(s.engine, values, try s.at(current, slot));
    }
    return r.copySet(s, values);
}
fn comparator(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return compare(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn compare(engine: *h.Engine, order: c.JSValue, a: c.JSValue, b: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 1, try h.invoke(&s, order, "indexOf", &.{b}), try h.invoke(&s, order, "indexOf", &.{a})));
}
fn action(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, release: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], if (release == 0) "close" else "release", if (release == 0) &.{captures[1]} else &.{}) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn retireImplementation(s: *Scope, host: c.JSValue, object: c.JSValue, version: c.JSValue) anyerror!void {
    const implementations = try s.get(object, "implementations");
    const installed = try h.invoke(s, implementations, "get", &.{version});
    _ = try h.invoke(s, implementations, "delete", &.{version});
    if (c.JS_IsUndefined(installed) or c.JS_IsStrictEqual(s.engine.context, try s.get(installed, "decls"), try s.get(object, "decls"))) return;
    const declarations = try h.snapshot(s, try h.invoke(s, object, "allDecls", &.{}));
    const refs = try keep(s, declarations, "refs");
    const resources = try keep(s, declarations, "resources");
    const derives = try keep(s, declarations, "derives");
    const retired = try s.get(installed, "decls");
    var old_derives = try r.mapIterator(s, try s.get(retired, "derives"), "values");
    defer old_derives.deinit();
    errdefer old_derives.closePreserving();
    while (try old_derives.next()) |derived| {
        defer s.engine.freeValue(derived);
        if (!try r.has(s, derives, derived)) _ = try h.invoke(s, derived, "detach", &.{});
    }
    const closing = try s.list();
    const old_resources = try h.values(s, try s.get(retired, "resources"));
    for (0..try h.length(s, old_resources)) |index| {
        const resource = try s.at(old_resources, index);
        if (!try r.has(s, resources, resource)) try js.push(s.engine, closing, resource);
    }
    var captures = [_]c.JSValue{try s.get(object, "openOrder")};
    const sort = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, comparator, "", 2, 0, 1, &captures)));
    _ = try h.invoke(s, closing, "sort", &.{sort});
    const releasing = try s.list();
    const old_refs = try h.values(s, try s.get(retired, "refs"));
    for (0..try h.length(s, old_refs)) |index| {
        const ref = try s.at(old_refs, index);
        if (!try r.has(s, refs, ref)) try js.push(s.engine, releasing, ref);
    }
    _ = try h.invoke(s, object, "refreshSchemas", &.{});
    const steps = try s.list();
    inline for (.{ closing, releasing }, 0..) |actions, mode| {
        for (0..try h.length(s, actions)) |index| {
            var data = [_]c.JSValue{ try s.at(actions, index), try s.get(object, "openOrder") };
            const function = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, action, "", 0, @intCast(mode), 2, &data)));
            try js.push(s.engine, steps, function);
        }
    }
    const message = try r.concat(s, &.{ try s.get(object, "address"), try s.text(": retiring code version "), version, try s.text(" failed") });
    const pending = try s.keep(try @import("native_chord_run_all.zig").run(s, steps, message));
    _ = try r.reportPending(s, host, pending);
}
