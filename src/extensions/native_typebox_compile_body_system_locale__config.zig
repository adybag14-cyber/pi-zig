//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_node_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "system/locale/_config.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "system/locale/_config.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "system/locale/_config.mjs", bindings);
    const v22551 = try s.own(try ordinary.create(e, "Set", 1, body22547, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22544", v22551);
    const v22554 = try s.own(try ordinary.create(e, "Get", 0, body22552, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22545", v22554);
    const v22559 = try s.own(try ordinary.create(e, "Reset", 0, body22555, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22546", v22559);
    const v22560 = try o.lookup(&s, frame, "binding22544");
    try s.put(namespace, "Set", v22560);
    const v22561 = try o.lookup(&s, frame, "binding22545");
    try s.put(namespace, "Get", v22561);
    const v22562 = try o.lookup(&s, frame, "binding22546");
    try s.put(namespace, "Reset", v22562);
    const v22563 = try o.importValue(&s, graph, "system/locale/en_US.mjs", "en_US");
    try o.assign(&s, frame, "binding22543", v22563);
    const v22564 = try o.lookup(&s, frame, "binding22544");
    try s.put(namespace, "Set", v22564);
    const v22565 = try o.lookup(&s, frame, "binding22545");
    try s.put(namespace, "Get", v22565);
    const v22566 = try o.lookup(&s, frame, "binding22546");
    try s.put(namespace, "Reset", v22566);
    try s.put(bindings, "Set", try s.text("binding22544"));
    try s.put(bindings, "Get", try s.text("binding22545"));
    try s.put(bindings, "Reset", try s.text("binding22546"));
}
fn body22547(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22549 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22548", v22549);
    const v22550 = try o.lookup(&s, frame, "binding22548");
    try o.assign(&s, frame, "binding22543", v22550);
    return c.pi_js_undefined();
}
fn body22552(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22553 = try o.lookup(&s, frame, "binding22543");
    return c.JS_DupValue(e.context, v22553);
}
fn body22555(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22556 = try o.lookup(&s, frame, "binding22544");
    const v22557 = try o.importValue(&s, graph, "system/locale/en_US.mjs", "en_US");
    const v22558 = try o.call(&s, @src(), v22556, c.pi_js_undefined(), &.{v22557});
    _ = v22558;
    return c.pi_js_undefined();
}
