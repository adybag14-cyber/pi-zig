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
    const namespace = try s.get(modules, "value/convert/from_array.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_array.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_array.mjs", bindings);
    const v26144 = try s.own(try ordinary.create(e, "FromArray", 3, body26112, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26111", v26144);
    const v26145 = try o.lookup(&s, frame, "binding26111");
    try s.put(namespace, "FromArray", v26145);
    const v26146 = try o.lookup(&s, frame, "binding26111");
    try s.put(namespace, "FromArray", v26146);
    try s.put(bindings, "FromArray", try s.text("binding26111"));
}
fn body26131(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v26134 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26133", v26134);
    const v26135 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
    const v26136 = try o.lookup(&s, frame, "binding26113");
    const v26137 = try o.lookup(&s, frame, "binding26114");
    const v26138 = try s.text("items");
    const v26139 = try s.own(try js.getKey(e, v26137, v26138));
    const v26140 = try o.lookup(&s, frame, "binding26133");
    const v26141 = try o.call(&s, @src(), v26135, c.pi_js_undefined(), &.{ v26136, v26139, v26140 });
    return c.JS_DupValue(e.context, v26141);
}
fn body26131C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body26131(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body26112(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26117 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26113", v26117);
    const v26118 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26114", v26118);
    const v26119 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26115", v26119);
    const v26121 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26122 = try s.text("TryArray");
    const v26123 = try s.own(try js.getKey(e, v26121, v26122));
    const v26124 = try o.lookup(&s, frame, "binding26115");
    const v26125 = try o.call(&s, @src(), v26123, v26121, &.{v26124});
    try o.assign(&s, frame, "binding26120", v26125);
    const v26126 = try o.lookup(&s, frame, "binding26120");
    const v26127 = try s.text("value");
    const v26128 = try s.own(try js.getKey(e, v26126, v26127));
    const v26129 = try s.text("map");
    const v26130 = try s.own(try js.getKey(e, v26128, v26129));
    const v26142 = try o.arrow(&s, "", 1, body26131C, &.{ graph, frame });
    const v26143 = try o.call(&s, @src(), v26130, v26128, &.{v26142});
    return c.JS_DupValue(e.context, v26143);
}
