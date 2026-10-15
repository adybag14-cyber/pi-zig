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
    const namespace = try s.get(modules, "value/default/from_ref.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_ref.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_ref.mjs", bindings);
    const v29721 = try s.own(try ordinary.create(e, "FromRef", 3, body29693, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29692", v29721);
    const v29722 = try o.lookup(&s, frame, "binding29692");
    try s.put(namespace, "FromRef", v29722);
    const v29723 = try o.lookup(&s, frame, "binding29692");
    try s.put(namespace, "FromRef", v29723);
    try s.put(bindings, "FromRef", try s.text("binding29692"));
}
fn body29693(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29697 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29694", v29697);
    const v29698 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29695", v29698);
    const v29699 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29696", v29699);
    const v29700 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v29701 = try s.text("HasPropertyKey");
    const v29702 = try s.own(try js.getKey(e, v29700, v29701));
    const v29703 = try o.lookup(&s, frame, "binding29694");
    const v29704 = try o.lookup(&s, frame, "binding29695");
    const v29705 = try s.text("$ref");
    const v29706 = try s.own(try js.getKey(e, v29704, v29705));
    const v29707 = try s.call(v29702, v29700, &.{ v29703, v29706 });
    const v29709 = conditional29708: {
        if (s.truthy(v29707)) {
            const v29710 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
            const v29711 = try o.lookup(&s, frame, "binding29694");
            const v29712 = try o.lookup(&s, frame, "binding29694");
            const v29713 = try o.lookup(&s, frame, "binding29695");
            const v29714 = try s.text("$ref");
            const v29715 = try s.own(try js.getKey(e, v29713, v29714));
            const v29716 = try o.propertyKey(&s, v29715);
            const v29717 = try s.own(try js.getKey(e, v29712, v29716));
            const v29718 = try o.lookup(&s, frame, "binding29696");
            const v29719 = try s.call(v29710, c.pi_js_undefined(), &.{ v29711, v29717, v29718 });
            break :conditional29708 v29719;
        } else {
            const v29720 = try o.lookup(&s, frame, "binding29696");
            break :conditional29708 v29720;
        }
    };
    return c.JS_DupValue(e.context, v29709);
}
