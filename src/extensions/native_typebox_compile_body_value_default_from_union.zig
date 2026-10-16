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
    const namespace = try s.get(modules, "value/default/from_union.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/default/from_union.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/default/from_union.mjs", bindings);
    const v29943 = try s.own(try ordinary.create(e, "FromUnion", 3, body29913, &.{ graph, frame }));
    try o.assign(&s, frame, "binding29912", v29943);
    const v29944 = try o.lookup(&s, frame, "binding29912");
    try s.put(namespace, "FromUnion", v29944);
    const v29945 = try o.lookup(&s, frame, "binding29912");
    try s.put(namespace, "FromUnion", v29945);
    try s.put(bindings, "FromUnion", try s.text("binding29912"));
}
fn body29913(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v29917 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29914", v29917);
    const v29918 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29915", v29918);
    const v29919 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding29916", v29919);
    const v29920 = try o.lookup(&s, frame, "binding29915");
    const v29921 = try s.text("anyOf");
    const v29922 = try s.own(try js.getKey(e, v29920, v29921));
    var iterator29923 = try o.iterator(e, v29922);
    defer iterator29923.deinit();
    errdefer iterator29923.closePreserving();
    while (try iterator29923.next()) |next29924| {
        defer e.freeValue(next29924);
        const iteration29926 = try o.frame(&s, frame);
        try o.assign(&s, iteration29926, "binding29927", next29924);
        const v29929 = try o.importValue(&s, graph, "value/default/from_type.mjs", "FromType");
        const v29930 = try o.lookup(&s, iteration29926, "binding29914");
        const v29931 = try o.lookup(&s, iteration29926, "binding29927");
        const v29932 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
        const v29933 = try o.lookup(&s, iteration29926, "binding29916");
        const v29934 = try o.call(&s, @src(), v29932, c.pi_js_undefined(), &.{v29933});
        const v29935 = try o.call(&s, @src(), v29929, c.pi_js_undefined(), &.{ v29930, v29931, v29934 });
        try o.assign(&s, iteration29926, "binding29928", v29935);
        const v29936 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
        const v29937 = try o.lookup(&s, iteration29926, "binding29914");
        const v29938 = try o.lookup(&s, iteration29926, "binding29927");
        const v29939 = try o.lookup(&s, iteration29926, "binding29928");
        const v29940 = try o.call(&s, @src(), v29936, c.pi_js_undefined(), &.{ v29937, v29938, v29939 });
        if (s.truthy(v29940)) {
            const v29941 = try o.lookup(&s, iteration29926, "binding29928");
            try iterator29923.close();
            return c.JS_DupValue(e.context, v29941);
        }
    }
    try iterator29923.close();
    const v29942 = try o.lookup(&s, frame, "binding29916");
    return c.JS_DupValue(e.context, v29942);
}
