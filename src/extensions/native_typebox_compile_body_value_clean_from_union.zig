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
    const namespace = try s.get(modules, "value/clean/from_union.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/clean/from_union.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/clean/from_union.mjs", bindings);
    const v23953 = try s.own(try ordinary.create(e, "FromUnion", 3, body23923, &.{ graph, frame }));
    try o.assign(&s, frame, "binding23922", v23953);
    const v23954 = try o.lookup(&s, frame, "binding23922");
    try s.put(namespace, "FromUnion", v23954);
    const v23955 = try o.lookup(&s, frame, "binding23922");
    try s.put(namespace, "FromUnion", v23955);
    try s.put(bindings, "FromUnion", try s.text("binding23922"));
}
fn body23923(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v23927 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23924", v23927);
    const v23928 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23925", v23928);
    const v23929 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding23926", v23929);
    const v23930 = try o.lookup(&s, frame, "binding23925");
    const v23931 = try s.text("anyOf");
    const v23932 = try s.own(try js.getKey(e, v23930, v23931));
    var iterator23933 = try o.iterator(e, v23932);
    defer iterator23933.deinit();
    errdefer iterator23933.closePreserving();
    while (try iterator23933.next()) |next23934| {
        defer e.freeValue(next23934);
        const iteration23936 = try o.frame(&s, frame);
        try o.assign(&s, iteration23936, "binding23937", next23934);
        const v23939 = try o.importValue(&s, graph, "value/clean/from_type.mjs", "FromType");
        const v23940 = try o.lookup(&s, iteration23936, "binding23924");
        const v23941 = try o.lookup(&s, iteration23936, "binding23937");
        const v23942 = try o.importValue(&s, graph, "value/clone/index.mjs", "Clone");
        const v23943 = try o.lookup(&s, iteration23936, "binding23926");
        const v23944 = try o.call(&s, @src(), v23942, c.pi_js_undefined(), &.{v23943});
        const v23945 = try o.call(&s, @src(), v23939, c.pi_js_undefined(), &.{ v23940, v23941, v23944 });
        try o.assign(&s, iteration23936, "binding23938", v23945);
        const v23946 = try o.importValue(&s, graph, "value/check/index.mjs", "Check");
        const v23947 = try o.lookup(&s, iteration23936, "binding23924");
        const v23948 = try o.lookup(&s, iteration23936, "binding23937");
        const v23949 = try o.lookup(&s, iteration23936, "binding23938");
        const v23950 = try o.call(&s, @src(), v23946, c.pi_js_undefined(), &.{ v23947, v23948, v23949 });
        if (s.truthy(v23950)) {
            const v23951 = try o.lookup(&s, iteration23936, "binding23938");
            try iterator23933.close();
            return c.JS_DupValue(e.context, v23951);
        }
    }
    try iterator23933.close();
    const v23952 = try o.lookup(&s, frame, "binding23926");
    return c.JS_DupValue(e.context, v23952);
}
