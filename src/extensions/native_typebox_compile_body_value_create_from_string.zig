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
    const namespace = try s.get(modules, "value/create/from_string.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/create/from_string.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/create/from_string.mjs", bindings);
    const v28899 = try s.own(try ordinary.create(e, "FromString", 2, body28860, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28859", v28899);
    const v28900 = try o.lookup(&s, frame, "binding28859");
    try s.put(namespace, "FromString", v28900);
    const v28901 = try o.lookup(&s, frame, "binding28859");
    try s.put(namespace, "FromString", v28901);
    try s.put(bindings, "FromString", try s.text("binding28859"));
}
fn body28860(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28865 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28861", v28865);
    const v28866 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28862", v28866);
    const v28869 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsPattern");
    const v28870 = try o.lookup(&s, frame, "binding28862");
    const v28871 = try s.call(v28869, c.pi_js_undefined(), &.{v28870});
    const v28873 = logical28872: {
        if (s.truthy(v28871)) break :logical28872 v28871;
        const v28874 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsFormat");
        const v28875 = try o.lookup(&s, frame, "binding28862");
        const v28876 = try s.call(v28874, c.pi_js_undefined(), &.{v28875});
        break :logical28872 v28876;
    };
    const v28878 = logical28877: {
        if (!s.truthy(v28873)) break :logical28877 v28873;
        const v28879 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsDefault");
        const v28880 = try o.lookup(&s, frame, "binding28862");
        const v28881 = try s.call(v28879, c.pi_js_undefined(), &.{v28880});
        break :logical28877 o.boolean(&s, !s.truthy(v28881));
    };
    try o.assign(&s, frame, "binding28867", v28878);
    const v28882 = try o.lookup(&s, frame, "binding28867");
    if (s.truthy(v28882)) {
        const v28883 = try s.global("Error");
        const v28884 = try s.text("Strings with format or pattern constraints must specify default");
        const v28885 = try s.call(v28883, c.pi_js_undefined(), &.{v28884});
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v28885));
        return js.capture(e);
    }
    const v28886 = try o.importValue(&s, graph, "schema/types/index.mjs", "IsMinLength");
    const v28887 = try o.lookup(&s, frame, "binding28862");
    const v28888 = try s.call(v28886, c.pi_js_undefined(), &.{v28887});
    const v28890 = conditional28889: {
        if (s.truthy(v28888)) {
            const v28891 = try o.lookup(&s, frame, "binding28862");
            const v28892 = try s.text("minLength");
            const v28893 = try s.own(try js.getKey(e, v28891, v28892));
            break :conditional28889 v28893;
        } else {
            break :conditional28889 c.JS_NewFloat64(e.context, 0);
        }
    };
    try o.assign(&s, frame, "binding28868", v28890);
    const v28894 = try s.text("");
    const v28895 = try s.text("padEnd");
    const v28896 = try s.own(try js.getKey(e, v28894, v28895));
    const v28897 = try o.lookup(&s, frame, "binding28868");
    const v28898 = try s.call(v28896, v28894, &.{v28897});
    return c.JS_DupValue(e.context, v28898);
}
