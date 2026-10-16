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
    const namespace = try s.get(modules, "value/shared/optional_undefined.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/shared/optional_undefined.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/shared/optional_undefined.mjs", bindings);
    const v31684 = try s.own(try ordinary.create(e, "IsOptionalUndefined", 3, body31664, &.{ graph, frame }));
    try o.assign(&s, frame, "binding31663", v31684);
    const v31685 = try o.lookup(&s, frame, "binding31663");
    try s.put(namespace, "IsOptionalUndefined", v31685);
    const v31686 = try o.lookup(&s, frame, "binding31663");
    try s.put(namespace, "IsOptionalUndefined", v31686);
    try s.put(bindings, "IsOptionalUndefined", try s.text("binding31663"));
}
fn body31664(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v31668 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31665", v31668);
    const v31669 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31666", v31669);
    const v31670 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding31667", v31670);
    const v31671 = try o.importValue(&s, graph, "type/index.mjs", "IsOptional");
    const v31672 = try o.lookup(&s, frame, "binding31665");
    const v31673 = try s.call(v31671, c.pi_js_undefined(), &.{v31672});
    const v31675 = logical31674: {
        if (!s.truthy(v31673)) break :logical31674 v31673;
        const v31676 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v31677 = try s.text("IsUndefined");
        const v31678 = try s.own(try js.getKey(e, v31676, v31677));
        const v31679 = try o.lookup(&s, frame, "binding31667");
        const v31680 = try o.lookup(&s, frame, "binding31666");
        const v31681 = try o.propertyKey(&s, v31680);
        const v31682 = try s.own(try js.getKey(e, v31679, v31681));
        const v31683 = try s.call(v31678, v31676, &.{v31682});
        break :logical31674 v31683;
    };
    return c.JS_DupValue(e.context, v31675);
}
