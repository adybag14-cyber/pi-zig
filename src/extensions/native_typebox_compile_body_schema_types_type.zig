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
    const namespace = try s.get(modules, "schema/types/type.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/type.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/type.mjs", bindings);
    const v22478 = try s.own(try ordinary.create(e, "IsType", 1, body22433, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22432", v22478);
    const v22479 = try o.lookup(&s, frame, "binding22432");
    try s.put(namespace, "IsType", v22479);
    const v22480 = try o.lookup(&s, frame, "binding22432");
    try s.put(namespace, "IsType", v22480);
    try s.put(bindings, "IsType", try s.text("binding22432"));
}
fn body22467(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v22470 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22469", v22470);
    const v22471 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22472 = try s.text("IsString");
    const v22473 = try s.own(try js.getKey(e, v22471, v22472));
    const v22474 = try o.lookup(&s, frame, "binding22469");
    const v22475 = try s.call(v22473, v22471, &.{v22474});
    return c.JS_DupValue(e.context, v22475);
}
fn body22467C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body22467(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body22433(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22435 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22434", v22435);
    const v22436 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22437 = try s.text("HasPropertyKey");
    const v22438 = try s.own(try js.getKey(e, v22436, v22437));
    const v22439 = try o.lookup(&s, frame, "binding22434");
    const v22440 = try s.text("type");
    const v22441 = try s.call(v22438, v22436, &.{ v22439, v22440 });
    const v22443 = logical22442: {
        if (!s.truthy(v22441)) break :logical22442 v22441;
        const v22444 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22445 = try s.text("IsString");
        const v22446 = try s.own(try js.getKey(e, v22444, v22445));
        const v22447 = try o.lookup(&s, frame, "binding22434");
        const v22448 = try s.text("type");
        const v22449 = try s.own(try js.getKey(e, v22447, v22448));
        const v22450 = try s.call(v22446, v22444, &.{v22449});
        const v22452 = logical22451: {
            if (s.truthy(v22450)) break :logical22451 v22450;
            const v22453 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v22454 = try s.text("IsArray");
            const v22455 = try s.own(try js.getKey(e, v22453, v22454));
            const v22456 = try o.lookup(&s, frame, "binding22434");
            const v22457 = try s.text("type");
            const v22458 = try s.own(try js.getKey(e, v22456, v22457));
            const v22459 = try s.call(v22455, v22453, &.{v22458});
            const v22461 = logical22460: {
                if (!s.truthy(v22459)) break :logical22460 v22459;
                const v22462 = try o.lookup(&s, frame, "binding22434");
                const v22463 = try s.text("type");
                const v22464 = try s.own(try js.getKey(e, v22462, v22463));
                const v22465 = try s.text("every");
                const v22466 = try s.own(try js.getKey(e, v22464, v22465));
                const v22476 = try o.arrow(&s, "", 1, body22467C, &.{ graph, frame });
                const v22477 = try s.call(v22466, v22464, &.{v22476});
                break :logical22460 v22477;
            };
            break :logical22451 v22461;
        };
        break :logical22442 v22452;
    };
    return c.JS_DupValue(e.context, v22443);
}
