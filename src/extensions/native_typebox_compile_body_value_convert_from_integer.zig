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
    const namespace = try s.get(modules, "value/convert/from_integer.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_integer.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_integer.mjs", bindings);
    const v26277 = try s.own(try ordinary.create(e, "FromInteger", 3, body26248, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26247", v26277);
    const v26278 = try o.lookup(&s, frame, "binding26247");
    try s.put(namespace, "FromInteger", v26278);
    const v26279 = try o.lookup(&s, frame, "binding26247");
    try s.put(namespace, "FromInteger", v26279);
    try s.put(bindings, "FromInteger", try s.text("binding26247"));
}
fn body26248(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26253 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26249", v26253);
    const v26254 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26250", v26254);
    const v26255 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26251", v26255);
    const v26257 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26258 = try s.text("TryNumber");
    const v26259 = try s.own(try js.getKey(e, v26257, v26258));
    const v26260 = try o.lookup(&s, frame, "binding26251");
    const v26261 = try s.call(v26259, v26257, &.{v26260});
    try o.assign(&s, frame, "binding26256", v26261);
    const v26262 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26263 = try s.text("IsOk");
    const v26264 = try s.own(try js.getKey(e, v26262, v26263));
    const v26265 = try o.lookup(&s, frame, "binding26256");
    const v26266 = try s.call(v26264, v26262, &.{v26265});
    const v26268 = conditional26267: {
        if (s.truthy(v26266)) {
            const v26269 = try s.global("Math");
            const v26270 = try s.text("trunc");
            const v26271 = try s.own(try js.getKey(e, v26269, v26270));
            const v26272 = try o.lookup(&s, frame, "binding26256");
            const v26273 = try s.text("value");
            const v26274 = try s.own(try js.getKey(e, v26272, v26273));
            const v26275 = try s.call(v26271, v26269, &.{v26274});
            break :conditional26267 v26275;
        } else {
            const v26276 = try o.lookup(&s, frame, "binding26251");
            break :conditional26267 v26276;
        }
    };
    return c.JS_DupValue(e.context, v26268);
}
