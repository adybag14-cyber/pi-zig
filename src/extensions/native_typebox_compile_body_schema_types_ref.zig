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
    const namespace = try s.get(modules, "schema/types/ref.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/ref.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/ref.mjs", bindings);
    const v22323 = try s.own(try ordinary.create(e, "IsRef", 1, body22305, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22304", v22323);
    const v22324 = try o.lookup(&s, frame, "binding22304");
    try s.put(namespace, "IsRef", v22324);
    const v22325 = try o.lookup(&s, frame, "binding22304");
    try s.put(namespace, "IsRef", v22325);
    try s.put(bindings, "IsRef", try s.text("binding22304"));
}
fn body22305(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22307 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22306", v22307);
    const v22308 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22309 = try s.text("HasPropertyKey");
    const v22310 = try s.own(try js.getKey(e, v22308, v22309));
    const v22311 = try o.lookup(&s, frame, "binding22306");
    const v22312 = try s.text("$ref");
    const v22313 = try s.call(v22310, v22308, &.{ v22311, v22312 });
    const v22315 = logical22314: {
        if (!s.truthy(v22313)) break :logical22314 v22313;
        const v22316 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22317 = try s.text("IsString");
        const v22318 = try s.own(try js.getKey(e, v22316, v22317));
        const v22319 = try o.lookup(&s, frame, "binding22306");
        const v22320 = try s.text("$ref");
        const v22321 = try s.own(try js.getKey(e, v22319, v22320));
        const v22322 = try s.call(v22318, v22316, &.{v22321});
        break :logical22314 v22322;
    };
    return c.JS_DupValue(e.context, v22315);
}
