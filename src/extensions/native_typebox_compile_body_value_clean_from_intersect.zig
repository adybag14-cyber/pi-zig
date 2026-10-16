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
    const namespace = try s.get(modules, "value/clean/from_intersect.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/from_intersect.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/from_intersect.mjs", bindings);
    const v23472 = try s.own(try ordinary.create(e, "EvaluateIntersection", 2, body23430, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23428", v23472);
    const v23491 = try s.own(try ordinary.create(e, "FromIntersect", 3, body23473, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23429", v23491);
    const v23492 = try o.lookup(&s, frame, "binding23429");
    try s.put(namespace, "FromIntersect", v23492);
    const v23493 = try o.lookup(&s, frame, "binding23429");
    try s.put(namespace, "FromIntersect", v23493);
    try s.put(bindings, "FromIntersect", try s.text("binding23429"));
}
fn body23430(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23436 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23431", v23436);
    const v23437 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23432", v23437);
    const v23441 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v23442 = try s.text("HasPropertyKey");
    const v23443 = try s.own(try js.getKey(e, v23441, v23442));
    const v23444 = try o.lookup(&s, frame, "binding23432");
    const v23445 = try s.text("unevaluatedProperties");
    const v23446 = try o.call(&s, @src(), v23443, v23441, &.{ v23444, v23445 });
    const v23448 = conditional23447: {
        if (s.truthy(v23446)) {
            const v23449 = try s.object();
            const v23450 = try s.text("additionalProperties");
            const v23451 = try o.lookup(&s, frame, "binding23432");
            const v23452 = try s.text("unevaluatedProperties");
            const v23453 = try s.own(try js.getKey(e, v23451, v23452));
            try o.defineKey(&s, v23449, v23450, v23453);
            break :conditional23447 v23449;
        } else {
            const v23454 = try s.object();
            break :conditional23447 v23454;
        }
    };
    try o.assign(&s, frame, "binding23438", v23448);
    const v23455 = try o.importValue(&s, graph, "type/index.mjs", "Instantiate");
    const v23456 = try o.lookup(&s, frame, "binding23431");
    const v23457 = try o.lookup(&s, frame, "binding23432");
    const v23458 = try o.call(&s, @src(), v23455, c.pi_js_undefined(), &.{ v23456, v23457 });
    try o.assign(&s, frame, "binding23439", v23458);
    const v23459 = try o.importValue(&s, graph, "type/index.mjs", "Evaluate");
    const v23460 = try o.lookup(&s, frame, "binding23439");
    const v23461 = try o.call(&s, @src(), v23459, c.pi_js_undefined(), &.{v23460});
    try o.assign(&s, frame, "binding23440", v23461);
    const v23462 = try o.importValue(&s, graph, "type/index.mjs", "IsObject");
    const v23463 = try o.lookup(&s, frame, "binding23440");
    const v23464 = try o.call(&s, @src(), v23462, c.pi_js_undefined(), &.{v23463});
    const v23466 = conditional23465: {
        if (s.truthy(v23464)) {
            const v23467 = try o.importValue(&s, graph, "type/index.mjs", "With");
            const v23468 = try o.lookup(&s, frame, "binding23440");
            const v23469 = try o.lookup(&s, frame, "binding23438");
            const v23470 = try o.call(&s, @src(), v23467, c.pi_js_undefined(), &.{ v23468, v23469 });
            break :conditional23465 v23470;
        } else {
            const v23471 = try o.lookup(&s, frame, "binding23440");
            break :conditional23465 v23471;
        }
    };
    return c.JS_DupValue(e.context, v23466);
}
fn body23473(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23478 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23474", v23478);
    const v23479 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23475", v23479);
    const v23480 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23476", v23480);
    const v23482 = try o.lookup(&s, frame, "binding23428");
    const v23483 = try o.lookup(&s, frame, "binding23474");
    const v23484 = try o.lookup(&s, frame, "binding23475");
    const v23485 = try o.call(&s, @src(), v23482, c.pi_js_undefined(), &.{ v23483, v23484 });
    try o.assign(&s, frame, "binding23481", v23485);
    const v23486 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
    const v23487 = try o.lookup(&s, frame, "binding23474");
    const v23488 = try o.lookup(&s, frame, "binding23481");
    const v23489 = try o.lookup(&s, frame, "binding23476");
    const v23490 = try o.call(&s, @src(), v23486, c.pi_js_undefined(), &.{ v23487, v23488, v23489 });
    return c.JS_DupValue(e.context, v23490);
}
