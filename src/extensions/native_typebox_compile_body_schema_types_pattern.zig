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
    const namespace = try s.get(modules, "schema/types/pattern.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/types/pattern.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/types/pattern.mjs", bindings);
    const v22087 = try s.own(try ordinary.create(e, "IsPattern", 1, body22062, &.{ graph, frame }));
    try o.assign(&s, frame, "binding22061", v22087);
    const v22088 = try o.lookup(&s, frame, "binding22061");
    try s.put(namespace, "IsPattern", v22088);
    const v22089 = try o.lookup(&s, frame, "binding22061");
    try s.put(namespace, "IsPattern", v22089);
    try s.put(bindings, "IsPattern", try s.text("binding22061"));
}
fn body22062(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v22064 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding22063", v22064);
    const v22065 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v22066 = try s.text("HasPropertyKey");
    const v22067 = try s.own(try js.getKey(e, v22065, v22066));
    const v22068 = try o.lookup(&s, frame, "binding22063");
    const v22069 = try s.text("pattern");
    const v22070 = try s.call(v22067, v22065, &.{ v22068, v22069 });
    const v22072 = logical22071: {
        if (!s.truthy(v22070)) break :logical22071 v22070;
        const v22073 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v22074 = try s.text("IsString");
        const v22075 = try s.own(try js.getKey(e, v22073, v22074));
        const v22076 = try o.lookup(&s, frame, "binding22063");
        const v22077 = try s.text("pattern");
        const v22078 = try s.own(try js.getKey(e, v22076, v22077));
        const v22079 = try s.call(v22075, v22073, &.{v22078});
        const v22081 = logical22080: {
            if (s.truthy(v22079)) break :logical22080 v22079;
            const v22082 = try o.lookup(&s, frame, "binding22063");
            const v22083 = try s.text("pattern");
            const v22084 = try s.own(try js.getKey(e, v22082, v22083));
            const v22085 = try s.global("RegExp");
            const v22086 = try o.instanceOf(&s, v22084, v22085);
            break :logical22080 v22086;
        };
        break :logical22071 v22081;
    };
    return c.JS_DupValue(e.context, v22072);
}
