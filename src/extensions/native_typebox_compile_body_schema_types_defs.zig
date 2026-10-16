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
    const namespace = try s.get(modules, "schema/types/defs.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/defs.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/defs.mjs", bindings);
    const v21269 = try s.own(try ordinary.create(e, "IsDefs", 1, body21231, &.{ graph, frame }));
    try o.assign(&s, frame, "binding21230", v21269);
    const v21270 = try o.lookup(&s, frame, "binding21230");
    try s.put(namespace, "IsDefs", v21270);
    const v21271 = try o.lookup(&s, frame, "binding21230");
    try s.put(namespace, "IsDefs", v21271);
    try s.put(bindings, "IsDefs", try s.text("binding21230"));
}
fn body21260(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v21263 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21262", v21263);
    const v21264 = try o.importValue(&s, graph, "schema/types/schema.mjs", "IsSchema");
    const v21265 = try o.lookup(&s, frame, "binding21262");
    const v21266 = try s.call(v21264, c.pi_js_undefined(), &.{v21265});
    return c.JS_DupValue(e.context, v21266);
}
fn body21260C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body21260(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body21231(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v21233 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding21232", v21233);
    const v21234 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v21235 = try s.text("HasPropertyKey");
    const v21236 = try s.own(try js.getKey(e, v21234, v21235));
    const v21237 = try o.lookup(&s, frame, "binding21232");
    const v21238 = try s.text("$defs");
    const v21239 = try s.call(v21236, v21234, &.{ v21237, v21238 });
    const v21241 = logical21240: {
        if (!s.truthy(v21239)) break :logical21240 v21239;
        const v21242 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v21243 = try s.text("IsObject");
        const v21244 = try s.own(try js.getKey(e, v21242, v21243));
        const v21245 = try o.lookup(&s, frame, "binding21232");
        const v21246 = try s.text("$defs");
        const v21247 = try s.own(try js.getKey(e, v21245, v21246));
        const v21248 = try s.call(v21244, v21242, &.{v21247});
        break :logical21240 v21248;
    };
    const v21250 = logical21249: {
        if (!s.truthy(v21241)) break :logical21249 v21241;
        const v21251 = try s.global("Object");
        const v21252 = try s.text("values");
        const v21253 = try s.own(try js.getKey(e, v21251, v21252));
        const v21254 = try o.lookup(&s, frame, "binding21232");
        const v21255 = try s.text("$defs");
        const v21256 = try s.own(try js.getKey(e, v21254, v21255));
        const v21257 = try s.call(v21253, v21251, &.{v21256});
        const v21258 = try s.text("every");
        const v21259 = try s.own(try js.getKey(e, v21257, v21258));
        const v21267 = try o.arrow(&s, "", 1, body21260C, &.{ graph, frame });
        const v21268 = try s.call(v21259, v21257, &.{v21267});
        break :logical21249 v21268;
    };
    return c.JS_DupValue(e.context, v21250);
}
