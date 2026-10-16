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
    const namespace = try s.get(modules, "value/create/from_array.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_array.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_array.mjs", bindings);
    const v28456 = try s.own(try ordinary.create(e, "FromArray", 2, body28413, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28412", v28456);
    const v28457 = try o.lookup(&s, frame, "binding28412");
    try s.put(namespace, "FromArray", v28457);
    const v28458 = try o.lookup(&s, frame, "binding28412");
    try s.put(namespace, "FromArray", v28458);
    try s.put(bindings, "FromArray", try s.text("binding28412"));
}
fn body28446(e: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v28448 = try o.importValue(&s, graph, "value/create/from_type.mjs", "FromType");
    const v28449 = try o.lookup(&s, frame, "binding28414");
    const v28450 = try o.lookup(&s, frame, "binding28415");
    const v28451 = try s.text("items");
    const v28452 = try s.own(try js.getKey(e, v28450, v28451));
    const v28453 = try o.call(&s, @src(), v28448, c.pi_js_undefined(), &.{ v28449, v28452 });
    return c.JS_DupValue(e.context, v28453);
}
fn body28446C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body28446(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body28413(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28417 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28414", v28417);
    const v28418 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28415", v28418);
    const v28420 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsUniqueItems");
    const v28421 = try o.lookup(&s, frame, "binding28415");
    const v28422 = try o.call(&s, @src(), v28420, c.pi_js_undefined(), &.{v28421});
    const v28424 = logical28423: {
        if (!s.truthy(v28422)) break :logical28423 v28422;
        const v28425 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsDefault");
        const v28426 = try o.lookup(&s, frame, "binding28415");
        const v28427 = try o.call(&s, @src(), v28425, c.pi_js_undefined(), &.{v28426});
        break :logical28423 o.boolean(&s, !s.truthy(v28427));
    };
    if (s.truthy(v28424)) {
        const v28428 = try o.importValue(&s, graph, "value/create/error.mjs", "CreateError");
        const v28429 = try o.lookup(&s, frame, "binding28415");
        const v28430 = try s.text("Arrays with uniqueItems constraints must specify a default annotation");
        const v28431 = try o.construct(&s, v28428, &.{ v28429, v28430 });
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v28431));
        return js.capture(e);
    }
    const v28432 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsMinItems");
    const v28433 = try o.lookup(&s, frame, "binding28415");
    const v28434 = try o.call(&s, @src(), v28432, c.pi_js_undefined(), &.{v28433});
    const v28436 = conditional28435: {
        if (s.truthy(v28434)) {
            const v28437 = try o.lookup(&s, frame, "binding28415");
            const v28438 = try s.text("minItems");
            const v28439 = try s.own(try js.getKey(e, v28437, v28438));
            break :conditional28435 v28439;
        } else {
            break :conditional28435 c.JS_NewFloat64(e.context, 0);
        }
    };
    try o.assign(&s, frame, "binding28419", v28436);
    const v28440 = try s.global("Array");
    const v28441 = try s.text("from");
    const v28442 = try s.own(try js.getKey(e, v28440, v28441));
    const v28443 = try s.object();
    const v28444 = try s.text("length");
    const v28445 = try o.lookup(&s, frame, "binding28419");
    try o.defineKey(&s, v28443, v28444, v28445);
    const v28454 = try o.arrow(&s, "", 0, body28446C, &.{ graph, frame });
    const v28455 = try o.call(&s, @src(), v28442, v28440, &.{ v28443, v28454 });
    return c.JS_DupValue(e.context, v28455);
}
