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
    const namespace = try s.get(modules, "value/create/from_integer.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_integer.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_integer.mjs", bindings);
    const v28656 = try s.own(try ordinary.create(e, "FromInteger", 2, body28625, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28624", v28656);
    const v28657 = try o.lookup(&s, frame, "binding28624");
    try s.put(namespace, "FromInteger", v28657);
    const v28658 = try o.lookup(&s, frame, "binding28624");
    try s.put(namespace, "FromInteger", v28658);
    try s.put(bindings, "FromInteger", try s.text("binding28624"));
}
fn body28625(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28628 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28626", v28628);
    const v28629 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28627", v28629);
    const v28630 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsExclusiveMinimum");
    const v28631 = try o.lookup(&s, frame, "binding28627");
    const v28632 = try s.call(v28630, c.pi_js_undefined(), &.{v28631});
    const v28634 = logical28633: {
        if (!s.truthy(v28632)) break :logical28633 v28632;
        const v28635 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v28636 = try s.text("IsNumber");
        const v28637 = try s.own(try js.getKey(e, v28635, v28636));
        const v28638 = try o.lookup(&s, frame, "binding28627");
        const v28639 = try s.text("exclusiveMinimum");
        const v28640 = try s.own(try js.getKey(e, v28638, v28639));
        const v28641 = try s.call(v28637, v28635, &.{v28640});
        break :logical28633 v28641;
    };
    const v28643 = conditional28642: {
        if (s.truthy(v28634)) {
            const v28644 = try o.lookup(&s, frame, "binding28627");
            const v28645 = try s.text("exclusiveMinimum");
            const v28646 = try s.own(try js.getKey(e, v28644, v28645));
            const v28647 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 0, v28646, c.JS_NewFloat64(e.context, 1))));
            break :conditional28642 v28647;
        } else {
            const v28648 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsMinimum");
            const v28649 = try o.lookup(&s, frame, "binding28627");
            const v28650 = try s.call(v28648, c.pi_js_undefined(), &.{v28649});
            const v28652 = conditional28651: {
                if (s.truthy(v28650)) {
                    const v28653 = try o.lookup(&s, frame, "binding28627");
                    const v28654 = try s.text("minimum");
                    const v28655 = try s.own(try js.getKey(e, v28653, v28654));
                    break :conditional28651 v28655;
                } else {
                    break :conditional28651 c.JS_NewFloat64(e.context, 0);
                }
            };
            break :conditional28642 v28652;
        }
    };
    return c.JS_DupValue(e.context, v28643);
}
