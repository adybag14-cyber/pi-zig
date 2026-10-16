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
    const namespace = try s.get(modules, "schema/types/schema.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/schema.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/schema.mjs", bindings);
    const v22384 = try s.own(try ordinary.create(e, "IsSchemaObject", 1, body22369, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22366", v22384);
    const v22393 = try s.own(try ordinary.create(e, "IsSchemaBoolean", 1, body22385, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22367", v22393);
    const v22405 = try s.own(try ordinary.create(e, "IsSchema", 1, body22394, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22368", v22405);
    const v22406 = try o.lookup(&s, frame, "binding22366");
    try s.put(namespace, "IsSchemaObject", v22406);
    const v22407 = try o.lookup(&s, frame, "binding22367");
    try s.put(namespace, "IsSchemaBoolean", v22407);
    const v22408 = try o.lookup(&s, frame, "binding22368");
    try s.put(namespace, "IsSchema", v22408);
    const v22409 = try o.lookup(&s, frame, "binding22366");
    try s.put(namespace, "IsSchemaObject", v22409);
    const v22410 = try o.lookup(&s, frame, "binding22367");
    try s.put(namespace, "IsSchemaBoolean", v22410);
    const v22411 = try o.lookup(&s, frame, "binding22368");
    try s.put(namespace, "IsSchema", v22411);
    try s.put(bindings, "IsSchemaObject", try s.text("binding22366"));
    try s.put(bindings, "IsSchemaBoolean", try s.text("binding22367"));
    try s.put(bindings, "IsSchema", try s.text("binding22368"));
}
fn body22369(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22371 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22370", v22371);
    const v22372 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22373 = try s.text("IsObject");
    const v22374 = try s.own(try js.getKey(e, v22372, v22373));
    const v22375 = try o.lookup(&s, frame, "binding22370");
    const v22376 = try o.call(&s, @src(), v22374, v22372, &.{v22375});
    const v22378 = logical22377: {
        if (!s.truthy(v22376)) break :logical22377 v22376;
        const v22379 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22380 = try s.text("IsArray");
        const v22381 = try s.own(try js.getKey(e, v22379, v22380));
        const v22382 = try o.lookup(&s, frame, "binding22370");
        const v22383 = try o.call(&s, @src(), v22381, v22379, &.{v22382});
        break :logical22377 o.boolean(&s, !s.truthy(v22383));
    };
    return c.JS_DupValue(e.context, v22378);
}
fn body22385(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22387 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22386", v22387);
    const v22388 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22389 = try s.text("IsBoolean");
    const v22390 = try s.own(try js.getKey(e, v22388, v22389));
    const v22391 = try o.lookup(&s, frame, "binding22386");
    const v22392 = try o.call(&s, @src(), v22390, v22388, &.{v22391});
    return c.JS_DupValue(e.context, v22392);
}
fn body22394(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22396 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22395", v22396);
    const v22397 = try o.lookup(&s, frame, "binding22366");
    const v22398 = try o.lookup(&s, frame, "binding22395");
    const v22399 = try o.call(&s, @src(), v22397, c.pi_js_undefined(), &.{v22398});
    const v22401 = logical22400: {
        if (s.truthy(v22399)) break :logical22400 v22399;
        const v22402 = try o.lookup(&s, frame, "binding22367");
        const v22403 = try o.lookup(&s, frame, "binding22395");
        const v22404 = try o.call(&s, @src(), v22402, c.pi_js_undefined(), &.{v22403});
        break :logical22400 v22404;
    };
    return c.JS_DupValue(e.context, v22401);
}
