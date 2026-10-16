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
    const namespace = try s.get(modules, "schema/types/dependencies.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/dependencies.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/dependencies.mjs", bindings);
    const v21334 = try s.own(try ordinary.create(e, "IsDependencies", 1, body21273, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21272", v21334);
    const v21335 = try o.lookup(&s, frame, "binding21272");
    try s.put(namespace, "IsDependencies", v21335);
    const v21336 = try o.lookup(&s, frame, "binding21272");
    try s.put(namespace, "IsDependencies", v21336);
    try s.put(bindings, "IsDependencies", try s.text("binding21272"));
}
fn body21321(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21324 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21323", v21324);
    const v21325 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21326 = try s.text("IsString");
    const v21327 = try s.own(try js.getKey(e, v21325, v21326));
    const v21328 = try o.lookup(&s, frame, "binding21323");
    const v21329 = try s.call(v21327, v21325, &.{v21328});
    return c.JS_DupValue(e.context, v21329);
}
fn body21321C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body21321(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body21302(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21305 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21304", v21305);
    const v21306 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v21307 = try o.lookup(&s, frame, "binding21304");
    const v21308 = try s.call(v21306, c.pi_js_undefined(), &.{v21307});
    const v21310 = logical21309: {
        if (s.truthy(v21308)) break :logical21309 v21308;
        const v21311 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21312 = try s.text("IsArray");
        const v21313 = try s.own(try js.getKey(e, v21311, v21312));
        const v21314 = try o.lookup(&s, frame, "binding21304");
        const v21315 = try s.call(v21313, v21311, &.{v21314});
        const v21317 = logical21316: {
            if (!s.truthy(v21315)) break :logical21316 v21315;
            const v21318 = try o.lookup(&s, frame, "binding21304");
            const v21319 = try s.text("every");
            const v21320 = try s.own(try js.getKey(e, v21318, v21319));
            const v21330 = try o.arrow(&s, "", 1, body21321C, &.{ graph, frame });
            const v21331 = try s.call(v21320, v21318, &.{v21330});
            break :logical21316 v21331;
        };
        break :logical21309 v21317;
    };
    return c.JS_DupValue(e.context, v21310);
}
fn body21302C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body21302(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body21273(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21275 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21274", v21275);
    const v21276 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21277 = try s.text("HasPropertyKey");
    const v21278 = try s.own(try js.getKey(e, v21276, v21277));
    const v21279 = try o.lookup(&s, frame, "binding21274");
    const v21280 = try s.text("dependencies");
    const v21281 = try s.call(v21278, v21276, &.{ v21279, v21280 });
    const v21283 = logical21282: {
        if (!s.truthy(v21281)) break :logical21282 v21281;
        const v21284 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21285 = try s.text("IsObject");
        const v21286 = try s.own(try js.getKey(e, v21284, v21285));
        const v21287 = try o.lookup(&s, frame, "binding21274");
        const v21288 = try s.text("dependencies");
        const v21289 = try s.own(try js.getKey(e, v21287, v21288));
        const v21290 = try s.call(v21286, v21284, &.{v21289});
        break :logical21282 v21290;
    };
    const v21292 = logical21291: {
        if (!s.truthy(v21283)) break :logical21291 v21283;
        const v21293 = try s.global("Object");
        const v21294 = try s.text("values");
        const v21295 = try s.own(try js.getKey(e, v21293, v21294));
        const v21296 = try o.lookup(&s, frame, "binding21274");
        const v21297 = try s.text("dependencies");
        const v21298 = try s.own(try js.getKey(e, v21296, v21297));
        const v21299 = try s.call(v21295, v21293, &.{v21298});
        const v21300 = try s.text("every");
        const v21301 = try s.own(try js.getKey(e, v21299, v21300));
        const v21332 = try o.arrow(&s, "", 1, body21302C, &.{ graph, frame });
        const v21333 = try s.call(v21301, v21299, &.{v21332});
        break :logical21291 v21333;
    };
    return c.JS_DupValue(e.context, v21292);
}
