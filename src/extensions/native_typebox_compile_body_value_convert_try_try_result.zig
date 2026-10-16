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
    const namespace = try s.get(modules, "value/convert/try/try_result.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/try/try_result.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/try/try_result.mjs", bindings);
    const v28093 = try s.own(try ordinary.create(e, "IsOk", 1, body28077, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28074", v28093);
    const v28100 = try s.own(try ordinary.create(e, "Ok", 1, body28094, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28075", v28100);
    const v28102 = try s.own(try ordinary.create(e, "Fail", 0, body28101, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28076", v28102);
    const v28103 = try o.lookup(&s, frame, "binding28074");
    try s.put(namespace, "IsOk", v28103);
    const v28104 = try o.lookup(&s, frame, "binding28075");
    try s.put(namespace, "Ok", v28104);
    const v28105 = try o.lookup(&s, frame, "binding28076");
    try s.put(namespace, "Fail", v28105);
    const v28106 = try o.lookup(&s, frame, "binding28074");
    try s.put(namespace, "IsOk", v28106);
    const v28107 = try o.lookup(&s, frame, "binding28075");
    try s.put(namespace, "Ok", v28107);
    const v28108 = try o.lookup(&s, frame, "binding28076");
    try s.put(namespace, "Fail", v28108);
    try s.put(bindings, "IsOk", try s.text("binding28074"));
    try s.put(bindings, "Ok", try s.text("binding28075"));
    try s.put(bindings, "Fail", try s.text("binding28076"));
}
fn body28077(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28079 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28078", v28079);
    const v28080 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28081 = try s.text("IsObject");
    const v28082 = try s.own(try js.getKey(e, v28080, v28081));
    const v28083 = try o.lookup(&s, frame, "binding28078");
    const v28084 = try s.call(v28082, v28080, &.{v28083});
    const v28086 = logical28085: {
        if (!s.truthy(v28084)) break :logical28085 v28084;
        const v28087 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v28088 = try s.text("HasPropertyKey");
        const v28089 = try s.own(try js.getKey(e, v28087, v28088));
        const v28090 = try o.lookup(&s, frame, "binding28078");
        const v28091 = try s.text("value");
        const v28092 = try s.call(v28089, v28087, &.{ v28090, v28091 });
        break :logical28085 v28092;
    };
    return c.JS_DupValue(e.context, v28086);
}
fn body28094(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28096 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28095", v28096);
    const v28097 = try s.object();
    const v28098 = try s.text("value");
    const v28099 = try o.lookup(&s, frame, "binding28095");
    try o.defineKey(&s, v28097, v28098, v28099);
    return c.JS_DupValue(e.context, v28097);
}
fn body28101(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    return c.JS_DupValue(e.context, c.pi_js_undefined());
}
