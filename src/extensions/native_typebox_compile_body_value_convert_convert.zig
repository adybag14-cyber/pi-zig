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
    const namespace = try s.get(modules, "value/convert/convert.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/convert.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/convert.mjs", bindings);
    const v26055 = try s.own(try ordinary.create(e, "Convert", 0, body26005, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26004", v26055);
    const v26056 = try o.lookup(&s, frame, "binding26004");
    try s.put(namespace, "Convert", v26056);
    const v26057 = try o.lookup(&s, frame, "binding26004");
    try s.put(namespace, "Convert", v26057);
    try s.put(bindings, "Convert", try s.text("binding26004"));
}
fn body26020(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v26025 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26022", v26025);
    const v26026 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26023", v26026);
    const v26027 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26024", v26027);
    const v26028 = try s.array();
    const v26029 = try o.lookup(&s, frame, "binding26022");
    try o.append(&s, v26028, v26029);
    const v26030 = try o.lookup(&s, frame, "binding26023");
    try o.append(&s, v26028, v26030);
    const v26031 = try o.lookup(&s, frame, "binding26024");
    try o.append(&s, v26028, v26031);
    return c.JS_DupValue(e.context, v26028);
}
fn body26020C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body26020(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body26034(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v26038 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26036", v26038);
    const v26039 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26037", v26039);
    const v26040 = try s.array();
    const v26041 = try s.object();
    try o.append(&s, v26040, v26041);
    const v26042 = try o.lookup(&s, frame, "binding26036");
    try o.append(&s, v26040, v26042);
    const v26043 = try o.lookup(&s, frame, "binding26037");
    try o.append(&s, v26040, v26043);
    return c.JS_DupValue(e.context, v26040);
}
fn body26034C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body26034(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body26005(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26010 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding26006", v26010);
    const v26014 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v26015 = try s.text("Match");
    const v26016 = try s.own(try js.getKey(e, v26014, v26015));
    const v26017 = try o.lookup(&s, frame, "binding26006");
    const v26018 = try s.object();
    const v26019 = try s.text("3");
    const v26032 = try o.arrow(&s, "3", 3, body26020C, &.{ graph, frame });
    try o.defineKey(&s, v26018, v26019, v26032);
    const v26033 = try s.text("2");
    const v26044 = try o.arrow(&s, "2", 2, body26034C, &.{ graph, frame });
    try o.defineKey(&s, v26018, v26033, v26044);
    const v26045 = try s.call(v26016, v26014, &.{ v26017, v26018 });
    var destructure26046 = try o.iterator(e, v26045);
    defer destructure26046.deinit();
    errdefer destructure26046.closePreserving();
    const v26047 = try s.own(if (destructure26046.closed) c.pi_js_undefined() else (try destructure26046.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding26011", v26047);
    const v26048 = try s.own(if (destructure26046.closed) c.pi_js_undefined() else (try destructure26046.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding26012", v26048);
    const v26049 = try s.own(if (destructure26046.closed) c.pi_js_undefined() else (try destructure26046.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding26013", v26049);
    try destructure26046.close();
    const v26050 = try o.importValue(&s, graph, "value/convert/from_type.mjs", "FromType");
    const v26051 = try o.lookup(&s, frame, "binding26011");
    const v26052 = try o.lookup(&s, frame, "binding26012");
    const v26053 = try o.lookup(&s, frame, "binding26013");
    const v26054 = try s.call(v26050, c.pi_js_undefined(), &.{ v26051, v26052, v26053 });
    return c.JS_DupValue(e.context, v26054);
}
