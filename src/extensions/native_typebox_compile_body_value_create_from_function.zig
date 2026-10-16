//! Direct native bodies from pinned typebox@1.3.27. Source-only pending qualification.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const o = @import("native_typebox_compile_ops.zig");
const ordinary = @import("native_legacy_function.zig");
const class = @import("native_class.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Engine = js.Engine;
pub fn prepare(e: *Engine, graph: c.JSValue) !void {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, "value/create/from_function.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_function.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_function.mjs", bindings);
    const v28621 = try s.own(try ordinary.create(e, "FromFunction", 2, body28604, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28603", v28621);
    const v28622 = try o.lookup(&s, frame, "binding28603");
    try s.put(namespace, "FromFunction", v28622);
    const v28623 = try o.lookup(&s, frame, "binding28603");
    try s.put(namespace, "FromFunction", v28623);
    try s.put(bindings, "FromFunction", try s.text("binding28603"));
}
fn body28617(e: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v28619 = try o.lookup(&s, frame, "binding28610");
    return c.JS_DupValue(e.context, v28619);
}
fn body28617C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body28617(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body28604(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28608 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28605", v28608);
    const v28609 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28606", v28609);
    const v28611 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28612 = try o.lookup(&s, frame, "binding28605");
    const v28613 = try o.lookup(&s, frame, "binding28606");
    const v28614 = try s.text("returnType");
    const v28615 = try s.own(try js.getKey(e, v28613, v28614));
    const v28616 = try s.call(v28611, c.pi_js_undefined(), &.{ v28612, v28615 });
    try o.assign(&s, frame, "binding28610", v28616);
    const v28620 = try o.arrow(&s, "", 0, body28617C, &.{ graph, frame });
    return c.JS_DupValue(e.context, v28620);
}
