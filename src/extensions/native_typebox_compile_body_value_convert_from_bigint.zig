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
    const namespace = try s.get(modules, "value/convert/from_bigint.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/from_bigint.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/from_bigint.mjs", bindings);
    const v26173 = try s.own(try ordinary.create(e, "FromBigInt", 3, body26148, &.{ graph, frame }));
    try o.assign(&s, frame, "binding26147", v26173);
    const v26174 = try o.lookup(&s, frame, "binding26147");
    try s.put(namespace, "FromBigInt", v26174);
    const v26175 = try o.lookup(&s, frame, "binding26147");
    try s.put(namespace, "FromBigInt", v26175);
    try s.put(bindings, "FromBigInt", try s.text("binding26147"));
}
fn body26148(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v26153 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26149", v26153);
    const v26154 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26150", v26154);
    const v26155 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding26151", v26155);
    const v26157 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26158 = try s.text("TryBigInt");
    const v26159 = try s.own(try js.getKey(e, v26157, v26158));
    const v26160 = try o.lookup(&s, frame, "binding26151");
    const v26161 = try s.call(v26159, v26157, &.{v26160});
    try o.assign(&s, frame, "binding26156", v26161);
    const v26162 = try o.importValue(&s, graph, "value/convert/try/index.mjs", "Try");
    const v26163 = try s.text("IsOk");
    const v26164 = try s.own(try js.getKey(e, v26162, v26163));
    const v26165 = try o.lookup(&s, frame, "binding26156");
    const v26166 = try s.call(v26164, v26162, &.{v26165});
    const v26168 = conditional26167: {
        if (s.truthy(v26166)) {
            const v26169 = try o.lookup(&s, frame, "binding26156");
            const v26170 = try s.text("value");
            const v26171 = try s.own(try js.getKey(e, v26169, v26170));
            break :conditional26167 v26171;
        } else {
            const v26172 = try o.lookup(&s, frame, "binding26151");
            break :conditional26167 v26172;
        }
    };
    return c.JS_DupValue(e.context, v26168);
}
