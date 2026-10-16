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
    const namespace = try s.get(modules, "value/create/from_tuple.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_tuple.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_tuple.mjs", bindings);
    const v28971 = try s.own(try ordinary.create(e, "FromTuple", 2, body28941, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28940", v28971);
    const v28972 = try o.lookup(&s, frame, "binding28940");
    try s.put(namespace, "FromTuple", v28972);
    const v28973 = try o.lookup(&s, frame, "binding28940");
    try s.put(namespace, "FromTuple", v28973);
    try s.put(bindings, "FromTuple", try s.text("binding28940"));
}
fn body28954(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v28958 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28956", v28958);
    const v28959 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28957", v28959);
    const v28960 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28961 = try o.lookup(&s, frame, "binding28942");
    const v28962 = try o.lookup(&s, frame, "binding28943");
    const v28963 = try s.text("items");
    const v28964 = try s.own(try js.getKey(e, v28962, v28963));
    const v28965 = try o.lookup(&s, frame, "binding28957");
    const v28966 = try o.propertyKey(&s, v28965);
    const v28967 = try s.own(try js.getKey(e, v28964, v28966));
    const v28968 = try s.call(v28960, c.pi_js_undefined(), &.{ v28961, v28967 });
    return c.JS_DupValue(e.context, v28968);
}
fn body28954C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body28954(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body28941(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28944 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28942", v28944);
    const v28945 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28943", v28945);
    const v28946 = try s.global("Array");
    const v28947 = try s.text("from");
    const v28948 = try s.own(try js.getKey(e, v28946, v28947));
    const v28949 = try s.object();
    const v28950 = try s.text("length");
    const v28951 = try o.lookup(&s, frame, "binding28943");
    const v28952 = try s.text("minItems");
    const v28953 = try s.own(try js.getKey(e, v28951, v28952));
    try o.defineKey(&s, v28949, v28950, v28953);
    const v28969 = try o.arrow(&s, "", 2, body28954C, &.{ graph, frame });
    const v28970 = try s.call(v28948, v28946, &.{ v28949, v28969 });
    return c.JS_DupValue(e.context, v28970);
}
