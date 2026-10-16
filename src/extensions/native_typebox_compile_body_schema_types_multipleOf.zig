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
    const namespace = try s.get(modules, "schema/types/multipleOf.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/multipleOf.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/multipleOf.mjs", bindings);
    const v22000 = try s.own(try ordinary.create(e, "IsMultipleOf", 1, body21973, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21972", v22000);
    const v22001 = try o.lookup(&s, frame, "binding21972");
    try s.put(namespace, "IsMultipleOf", v22001);
    const v22002 = try o.lookup(&s, frame, "binding21972");
    try s.put(namespace, "IsMultipleOf", v22002);
    try s.put(bindings, "IsMultipleOf", try s.text("binding21972"));
}
fn body21973(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21975 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21974", v21975);
    const v21976 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21977 = try s.text("HasPropertyKey");
    const v21978 = try s.own(try js.getKey(e, v21976, v21977));
    const v21979 = try o.lookup(&s, frame, "binding21974");
    const v21980 = try s.text("multipleOf");
    const v21981 = try s.call(v21978, v21976, &.{ v21979, v21980 });
    const v21983 = logical21982: {
        if (!s.truthy(v21981)) break :logical21982 v21981;
        const v21984 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21985 = try s.text("IsNumber");
        const v21986 = try s.own(try js.getKey(e, v21984, v21985));
        const v21987 = try o.lookup(&s, frame, "binding21974");
        const v21988 = try s.text("multipleOf");
        const v21989 = try s.own(try js.getKey(e, v21987, v21988));
        const v21990 = try s.call(v21986, v21984, &.{v21989});
        const v21992 = logical21991: {
            if (s.truthy(v21990)) break :logical21991 v21990;
            const v21993 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v21994 = try s.text("IsBigInt");
            const v21995 = try s.own(try js.getKey(e, v21993, v21994));
            const v21996 = try o.lookup(&s, frame, "binding21974");
            const v21997 = try s.text("multipleOf");
            const v21998 = try s.own(try js.getKey(e, v21996, v21997));
            const v21999 = try s.call(v21995, v21993, &.{v21998});
            break :logical21991 v21999;
        };
        break :logical21982 v21992;
    };
    return c.JS_DupValue(e.context, v21983);
}
