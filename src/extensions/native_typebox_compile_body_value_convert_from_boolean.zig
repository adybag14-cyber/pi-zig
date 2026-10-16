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
    const namespace = try s.get(modules, "value/convert/from_boolean.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_boolean.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_boolean.mjs", bindings);
    const v26202 = try s.own(try ordinary.create(e, "FromBoolean", 3, body26177, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26176", v26202);
    const v26203 = try o.lookup(&s, frame, "binding26176");
    try s.put(namespace, "FromBoolean", v26203);
    const v26204 = try o.lookup(&s, frame, "binding26176");
    try s.put(namespace, "FromBoolean", v26204);
    try s.put(bindings, "FromBoolean", try s.text("binding26176"));
}
fn body26177(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26182 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26178", v26182);
    const v26183 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26179", v26183);
    const v26184 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26180", v26184);
    const v26186 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26187 = try s.text("TryBoolean");
    const v26188 = try s.own(try js.getKey(e, v26186, v26187));
    const v26189 = try o.lookup(&s, frame, "binding26180");
    const v26190 = try o.call(&s, @src(), v26188, v26186, &.{v26189});
    try o.assign(&s, frame, "binding26185", v26190);
    const v26191 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26192 = try s.text("IsOk");
    const v26193 = try s.own(try js.getKey(e, v26191, v26192));
    const v26194 = try o.lookup(&s, frame, "binding26185");
    const v26195 = try o.call(&s, @src(), v26193, v26191, &.{v26194});
    const v26197 = conditional26196: {
        if (s.truthy(v26195)) {
            const v26198 = try o.lookup(&s, frame, "binding26185");
            const v26199 = try s.text("value");
            const v26200 = try s.own(try js.getKey(e, v26198, v26199));
            break :conditional26196 v26200;
        } else {
            const v26201 = try o.lookup(&s, frame, "binding26180");
            break :conditional26196 v26201;
        }
    };
    return c.JS_DupValue(e.context, v26197);
}
