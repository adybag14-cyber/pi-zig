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
    const namespace = try s.get(modules, "schema/types/recursiveAnchor.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/recursiveAnchor.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/recursiveAnchor.mjs", bindings);
    const v22261 = try s.own(try ordinary.create(e, "IsRecursiveAnchor", 1, body22243, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22241", v22261);
    const v22277 = try s.own(try ordinary.create(e, "IsRecursiveAnchorTrue", 1, body22262, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22242", v22277);
    const v22278 = try o.lookup(&s, frame, "binding22241");
    try s.put(namespace, "IsRecursiveAnchor", v22278);
    const v22279 = try o.lookup(&s, frame, "binding22242");
    try s.put(namespace, "IsRecursiveAnchorTrue", v22279);
    const v22280 = try o.lookup(&s, frame, "binding22241");
    try s.put(namespace, "IsRecursiveAnchor", v22280);
    const v22281 = try o.lookup(&s, frame, "binding22242");
    try s.put(namespace, "IsRecursiveAnchorTrue", v22281);
    try s.put(bindings, "IsRecursiveAnchor", try s.text("binding22241"));
    try s.put(bindings, "IsRecursiveAnchorTrue", try s.text("binding22242"));
}
fn body22243(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22245 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22244", v22245);
    const v22246 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22247 = try s.text("HasPropertyKey");
    const v22248 = try s.own(try js.getKey(e, v22246, v22247));
    const v22249 = try o.lookup(&s, frame, "binding22244");
    const v22250 = try s.text("$recursiveAnchor");
    const v22251 = try s.call(v22248, v22246, &.{ v22249, v22250 });
    const v22253 = logical22252: {
        if (!s.truthy(v22251)) break :logical22252 v22251;
        const v22254 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22255 = try s.text("IsBoolean");
        const v22256 = try s.own(try js.getKey(e, v22254, v22255));
        const v22257 = try o.lookup(&s, frame, "binding22244");
        const v22258 = try s.text("$recursiveAnchor");
        const v22259 = try s.own(try js.getKey(e, v22257, v22258));
        const v22260 = try s.call(v22256, v22254, &.{v22259});
        break :logical22252 v22260;
    };
    return c.JS_DupValue(e.context, v22253);
}
fn body22262(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22264 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22263", v22264);
    const v22265 = try o.lookup(&s, frame, "binding22241");
    const v22266 = try o.lookup(&s, frame, "binding22263");
    const v22267 = try s.call(v22265, c.pi_js_undefined(), &.{v22266});
    const v22269 = logical22268: {
        if (!s.truthy(v22267)) break :logical22268 v22267;
        const v22270 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22271 = try s.text("IsEqual");
        const v22272 = try s.own(try js.getKey(e, v22270, v22271));
        const v22273 = try o.lookup(&s, frame, "binding22263");
        const v22274 = try s.text("$recursiveAnchor");
        const v22275 = try s.own(try js.getKey(e, v22273, v22274));
        const v22276 = try s.call(v22272, v22270, &.{ v22275, o.boolean(&s, true) });
        break :logical22268 v22276;
    };
    return c.JS_DupValue(e.context, v22269);
}
