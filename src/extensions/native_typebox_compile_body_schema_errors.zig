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
    const namespace = try s.get(modules, "schema/errors.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/errors.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/errors.mjs", bindings);
    const v18054 = try s.own(try ordinary.create(e, "Errors", 0, body17953, &.{ graph, frame }));
    try o.assign(&s, frame, "binding17952", v18054);
    const v18055 = try o.lookup(&s, frame, "binding17952");
    try s.put(namespace, "Errors", v18055);
    const v18056 = try o.lookup(&s, frame, "binding17952");
    try s.put(namespace, "Errors", v18056);
    try s.put(bindings, "Errors", try s.text("binding17952"));
}
fn body17980(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v17985 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17982", v17985);
    const v17986 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17983", v17986);
    const v17987 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17984", v17987);
    const v17988 = try s.array();
    const v17989 = try o.lookup(&s, frame, "binding17982");
    try o.append(&s, v17988, v17989);
    const v17990 = try o.lookup(&s, frame, "binding17983");
    try o.append(&s, v17988, v17990);
    const v17991 = try o.lookup(&s, frame, "binding17984");
    try o.append(&s, v17988, v17991);
    return c.JS_DupValue(e.context, v17988);
}
fn body17980C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body17980(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body17994(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v17998 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17996", v17998);
    const v17999 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding17997", v17999);
    const v18000 = try s.array();
    const v18001 = try s.object();
    try o.append(&s, v18000, v18001);
    const v18002 = try o.lookup(&s, frame, "binding17996");
    try o.append(&s, v18000, v18002);
    const v18003 = try o.lookup(&s, frame, "binding17997");
    try o.append(&s, v18000, v18003);
    return c.JS_DupValue(e.context, v18000);
}
fn body17994C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body17994(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body18039(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v18042 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding18041", v18042);
    const v18043 = try s.object();
    const v18044 = try o.lookup(&s, frame, "binding18041");
    try js.spreadInto(e, v18043, v18044);
    const v18045 = try s.text("message");
    const v18046 = try o.lookup(&s, frame, "binding17972");
    const v18047 = try o.lookup(&s, frame, "binding18041");
    const v18048 = try o.call(&s, @src(), v18046, c.pi_js_undefined(), &.{v18047});
    try o.defineKey(&s, v18043, v18045, v18048);
    return c.JS_DupValue(e.context, v18043);
}
fn body18039C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body18039(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body17953(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v17964 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding17954", v17964);
    const v17974 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v17975 = try s.text("Match");
    const v17976 = try s.own(try js.getKey(e, v17974, v17975));
    const v17977 = try o.lookup(&s, frame, "binding17954");
    const v17978 = try s.object();
    const v17979 = try s.text("3");
    const v17992 = try o.arrow(&s, "3", 3, body17980C, &.{ graph, frame });
    try o.defineKey(&s, v17978, v17979, v17992);
    const v17993 = try s.text("2");
    const v18004 = try o.arrow(&s, "2", 2, body17994C, &.{ graph, frame });
    try o.defineKey(&s, v17978, v17993, v18004);
    const v18005 = try o.call(&s, @src(), v17976, v17974, &.{ v17977, v17978 });
    var destructure18006 = try o.iterator(e, v18005);
    defer destructure18006.deinit();
    errdefer destructure18006.closePreserving();
    const v18007 = try s.own(if (destructure18006.closed) c.pi_js_undefined() else (try destructure18006.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding17965", v18007);
    const v18008 = try s.own(if (destructure18006.closed) c.pi_js_undefined() else (try destructure18006.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding17966", v18008);
    const v18009 = try s.own(if (destructure18006.closed) c.pi_js_undefined() else (try destructure18006.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding17967", v18009);
    try destructure18006.close();
    const v18010 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v18011 = try s.text("Stack");
    const v18012 = try s.own(try js.getKey(e, v18010, v18011));
    const v18013 = try o.lookup(&s, frame, "binding17965");
    const v18014 = try o.lookup(&s, frame, "binding17966");
    const v18015 = try o.construct(&s, v18012, &.{ v18013, v18014 });
    try o.assign(&s, frame, "binding17968", v18015);
    const v18016 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v18017 = try s.text("ErrorContext");
    const v18018 = try s.own(try js.getKey(e, v18016, v18017));
    const v18019 = try o.construct(&s, v18018, &.{});
    try o.assign(&s, frame, "binding17969", v18019);
    const v18020 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v18021 = try s.text("ErrorSchema");
    const v18022 = try s.own(try js.getKey(e, v18020, v18021));
    const v18023 = try o.lookup(&s, frame, "binding17968");
    const v18024 = try o.lookup(&s, frame, "binding17969");
    const v18025 = try s.text("#");
    const v18026 = try s.text("");
    const v18027 = try o.lookup(&s, frame, "binding17966");
    const v18028 = try o.lookup(&s, frame, "binding17967");
    const v18029 = try o.call(&s, @src(), v18022, v18020, &.{ v18023, v18024, v18025, v18026, v18027, v18028 });
    try o.assign(&s, frame, "binding17970", v18029);
    const v18030 = try o.lookup(&s, frame, "binding17969");
    const v18031 = try s.text("GetErrors");
    const v18032 = try s.own(try js.getKey(e, v18030, v18031));
    const v18033 = try o.call(&s, @src(), v18032, v18030, &.{});
    try o.assign(&s, frame, "binding17971", v18033);
    const v18034 = try o.importValue(&s, graph, "system/locale/_config.mjs", "Get");
    const v18035 = try o.call(&s, @src(), v18034, c.pi_js_undefined(), &.{});
    try o.assign(&s, frame, "binding17972", v18035);
    const v18036 = try o.lookup(&s, frame, "binding17971");
    const v18037 = try s.text("map");
    const v18038 = try s.own(try js.getKey(e, v18036, v18037));
    const v18049 = try o.arrow(&s, "", 1, body18039C, &.{ graph, frame });
    const v18050 = try o.call(&s, @src(), v18038, v18036, &.{v18049});
    try o.assign(&s, frame, "binding17973", v18050);
    const v18051 = try s.array();
    const v18052 = try o.lookup(&s, frame, "binding17970");
    try o.append(&s, v18051, v18052);
    const v18053 = try o.lookup(&s, frame, "binding17973");
    try o.append(&s, v18051, v18053);
    return c.JS_DupValue(e.context, v18051);
}
