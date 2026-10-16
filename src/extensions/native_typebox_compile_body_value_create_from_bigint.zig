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
    const namespace = try s.get(modules, "value/create/from_bigint.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_bigint.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_bigint.mjs", bindings);
    const v28490 = try s.own(try ordinary.create(e, "FromBigInt", 2, body28460, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28459", v28490);
    const v28491 = try o.lookup(&s, frame, "binding28459");
    try s.put(namespace, "FromBigInt", v28491);
    const v28492 = try o.lookup(&s, frame, "binding28459");
    try s.put(namespace, "FromBigInt", v28492);
    try s.put(bindings, "FromBigInt", try s.text("binding28459"));
}
fn body28460(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28463 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28461", v28463);
    const v28464 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28462", v28464);
    const v28465 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsExclusiveMinimum");
    const v28466 = try o.lookup(&s, frame, "binding28462");
    const v28467 = try o.call(&s, @src(), v28465, c.pi_js_undefined(), &.{v28466});
    const v28469 = conditional28468: {
        if (s.truthy(v28467)) {
            const v28470 = try s.global("BigInt");
            const v28471 = try o.lookup(&s, frame, "binding28462");
            const v28472 = try s.text("exclusiveMinimum");
            const v28473 = try s.own(try js.getKey(e, v28471, v28472));
            const v28474 = try o.call(&s, @src(), v28470, c.pi_js_undefined(), &.{v28473});
            const v28475 = try s.global("BigInt");
            const v28476 = try o.call(&s, @src(), v28475, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 1)});
            const v28477 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, v28474, v28476)));
            break :conditional28468 v28477;
        } else {
            const v28478 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsMinimum");
            const v28479 = try o.lookup(&s, frame, "binding28462");
            const v28480 = try o.call(&s, @src(), v28478, c.pi_js_undefined(), &.{v28479});
            const v28482 = conditional28481: {
                if (s.truthy(v28480)) {
                    const v28483 = try s.global("BigInt");
                    const v28484 = try o.lookup(&s, frame, "binding28462");
                    const v28485 = try s.text("minimum");
                    const v28486 = try s.own(try js.getKey(e, v28484, v28485));
                    const v28487 = try o.call(&s, @src(), v28483, c.pi_js_undefined(), &.{v28486});
                    break :conditional28481 v28487;
                } else {
                    const v28488 = try s.global("BigInt");
                    const v28489 = try o.call(&s, @src(), v28488, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
                    break :conditional28481 v28489;
                }
            };
            break :conditional28468 v28482;
        }
    };
    return c.JS_DupValue(e.context, v28469);
}
