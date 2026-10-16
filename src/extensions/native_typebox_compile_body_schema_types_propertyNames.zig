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
    const namespace = try s.get(modules, "schema/types/propertyNames.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/propertyNames.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/propertyNames.mjs", bindings);
    const v22238 = try s.own(try ordinary.create(e, "IsPropertyNames", 1, body22213, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22212", v22238);
    const v22239 = try o.lookup(&s, frame, "binding22212");
    try s.put(namespace, "IsPropertyNames", v22239);
    const v22240 = try o.lookup(&s, frame, "binding22212");
    try s.put(namespace, "IsPropertyNames", v22240);
    try s.put(bindings, "IsPropertyNames", try s.text("binding22212"));
}
fn body22213(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22215 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22214", v22215);
    const v22216 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22217 = try s.text("HasPropertyKey");
    const v22218 = try s.own(try js.getKey(e, v22216, v22217));
    const v22219 = try o.lookup(&s, frame, "binding22214");
    const v22220 = try s.text("propertyNames");
    const v22221 = try s.call(v22218, v22216, &.{ v22219, v22220 });
    const v22223 = logical22222: {
        if (!s.truthy(v22221)) break :logical22222 v22221;
        const v22224 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22225 = try s.text("IsObject");
        const v22226 = try s.own(try js.getKey(e, v22224, v22225));
        const v22227 = try o.lookup(&s, frame, "binding22214");
        const v22228 = try s.text("propertyNames");
        const v22229 = try s.own(try js.getKey(e, v22227, v22228));
        const v22230 = try s.call(v22226, v22224, &.{v22229});
        const v22232 = logical22231: {
            if (s.truthy(v22230)) break :logical22231 v22230;
            const v22233 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
            const v22234 = try o.lookup(&s, frame, "binding22214");
            const v22235 = try s.text("propertyNames");
            const v22236 = try s.own(try js.getKey(e, v22234, v22235));
            const v22237 = try s.call(v22233, c.pi_js_undefined(), &.{v22236});
            break :logical22231 v22237;
        };
        break :logical22222 v22232;
    };
    return c.JS_DupValue(e.context, v22223);
}
