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
    const namespace = try s.get(modules, "value/convert/from_string.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_string.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_string.mjs", bindings);
    const v26862 = try s.own(try ordinary.create(e, "FromString", 3, body26837, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26836", v26862);
    const v26863 = try o.lookup(&s, frame, "binding26836");
    try s.put(namespace, "FromString", v26863);
    const v26864 = try o.lookup(&s, frame, "binding26836");
    try s.put(namespace, "FromString", v26864);
    try s.put(bindings, "FromString", try s.text("binding26836"));
}
fn body26837(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26842 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26838", v26842);
    const v26843 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26839", v26843);
    const v26844 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26840", v26844);
    const v26846 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26847 = try s.text("TryString");
    const v26848 = try s.own(try js.getKey(e, v26846, v26847));
    const v26849 = try o.lookup(&s, frame, "binding26840");
    const v26850 = try s.call(v26848, v26846, &.{v26849});
    try o.assign(&s, frame, "binding26845", v26850);
    const v26851 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26852 = try s.text("IsOk");
    const v26853 = try s.own(try js.getKey(e, v26851, v26852));
    const v26854 = try o.lookup(&s, frame, "binding26845");
    const v26855 = try s.call(v26853, v26851, &.{v26854});
    const v26857 = conditional26856: {
        if (s.truthy(v26855)) {
            const v26858 = try o.lookup(&s, frame, "binding26845");
            const v26859 = try s.text("value");
            const v26860 = try s.own(try js.getKey(e, v26858, v26859));
            break :conditional26856 v26860;
        } else {
            const v26861 = try o.lookup(&s, frame, "binding26840");
            break :conditional26856 v26861;
        }
    };
    return c.JS_DupValue(e.context, v26857);
}
