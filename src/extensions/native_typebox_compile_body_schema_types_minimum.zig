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
    const namespace = try s.get(modules, "schema/types/minimum.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/minimum.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/minimum.mjs", bindings);
    const v21903 = try s.own(try ordinary.create(e, "IsMinimum", 1, body21876, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21875", v21903);
    const v21904 = try o.lookup(&s, frame, "binding21875");
    try s.put(namespace, "IsMinimum", v21904);
    const v21905 = try o.lookup(&s, frame, "binding21875");
    try s.put(namespace, "IsMinimum", v21905);
    try s.put(bindings, "IsMinimum", try s.text("binding21875"));
}
fn body21876(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21878 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21877", v21878);
    const v21879 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21880 = try s.text("HasPropertyKey");
    const v21881 = try s.own(try js.getKey(e, v21879, v21880));
    const v21882 = try o.lookup(&s, frame, "binding21877");
    const v21883 = try s.text("minimum");
    const v21884 = try s.call(v21881, v21879, &.{ v21882, v21883 });
    const v21886 = logical21885: {
        if (!s.truthy(v21884)) break :logical21885 v21884;
        const v21887 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21888 = try s.text("IsNumber");
        const v21889 = try s.own(try js.getKey(e, v21887, v21888));
        const v21890 = try o.lookup(&s, frame, "binding21877");
        const v21891 = try s.text("minimum");
        const v21892 = try s.own(try js.getKey(e, v21890, v21891));
        const v21893 = try s.call(v21889, v21887, &.{v21892});
        const v21895 = logical21894: {
            if (s.truthy(v21893)) break :logical21894 v21893;
            const v21896 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v21897 = try s.text("IsBigInt");
            const v21898 = try s.own(try js.getKey(e, v21896, v21897));
            const v21899 = try o.lookup(&s, frame, "binding21877");
            const v21900 = try s.text("minimum");
            const v21901 = try s.own(try js.getKey(e, v21899, v21900));
            const v21902 = try s.call(v21898, v21896, &.{v21901});
            break :logical21894 v21902;
        };
        break :logical21885 v21895;
    };
    return c.JS_DupValue(e.context, v21886);
}
