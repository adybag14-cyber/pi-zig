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
    const namespace = try s.get(modules, "value/codec/from_ref.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/from_ref.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/from_ref.mjs", bindings);
    const v25215 = try s.own(try ordinary.create(e, "ResolveRef", 4, body25184, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25182", v25215);
    const v25255 = try s.own(try ordinary.create(e, "FromRef", 4, body25216, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25183", v25255);
    const v25256 = try o.lookup(&s, frame, "binding25183");
    try s.put(namespace, "FromRef", v25256);
    const v25257 = try o.lookup(&s, frame, "binding25183");
    try s.put(namespace, "FromRef", v25257);
    try s.put(bindings, "FromRef", try s.text("binding25183"));
}
fn body25184(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25189 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25185", v25189);
    const v25190 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25186", v25190);
    const v25191 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25187", v25191);
    const v25192 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25188", v25192);
    const v25193 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25194 = try s.text("HasPropertyKey");
    const v25195 = try s.own(try js.getKey(e, v25193, v25194));
    const v25196 = try o.lookup(&s, frame, "binding25186");
    const v25197 = try o.lookup(&s, frame, "binding25187");
    const v25198 = try s.text("$ref");
    const v25199 = try s.own(try js.getKey(e, v25197, v25198));
    const v25200 = try s.call(v25195, v25193, &.{ v25196, v25199 });
    const v25202 = conditional25201: {
        if (s.truthy(v25200)) {
            const v25203 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
            const v25204 = try o.lookup(&s, frame, "binding25185");
            const v25205 = try o.lookup(&s, frame, "binding25186");
            const v25206 = try o.lookup(&s, frame, "binding25186");
            const v25207 = try o.lookup(&s, frame, "binding25187");
            const v25208 = try s.text("$ref");
            const v25209 = try s.own(try js.getKey(e, v25207, v25208));
            const v25210 = try o.propertyKey(&s, v25209);
            const v25211 = try s.own(try js.getKey(e, v25206, v25210));
            const v25212 = try o.lookup(&s, frame, "binding25188");
            const v25213 = try s.call(v25203, c.pi_js_undefined(), &.{ v25204, v25205, v25211, v25212 });
            break :conditional25201 v25213;
        } else {
            const v25214 = try o.lookup(&s, frame, "binding25188");
            break :conditional25201 v25214;
        }
    };
    return c.JS_DupValue(e.context, v25202);
}
fn body25216(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25221 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25217", v25221);
    const v25222 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25218", v25222);
    const v25223 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25219", v25223);
    const v25224 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25220", v25224);
    const v25225 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25226 = try s.text("IsEqual");
    const v25227 = try s.own(try js.getKey(e, v25225, v25226));
    const v25228 = try o.lookup(&s, frame, "binding25217");
    const v25229 = try s.text("Decode");
    const v25230 = try s.call(v25227, v25225, &.{ v25228, v25229 });
    const v25232 = conditional25231: {
        if (s.truthy(v25230)) {
            const v25233 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
            const v25234 = try o.lookup(&s, frame, "binding25217");
            const v25235 = try o.lookup(&s, frame, "binding25218");
            const v25236 = try o.lookup(&s, frame, "binding25219");
            const v25237 = try o.lookup(&s, frame, "binding25182");
            const v25238 = try o.lookup(&s, frame, "binding25217");
            const v25239 = try o.lookup(&s, frame, "binding25218");
            const v25240 = try o.lookup(&s, frame, "binding25219");
            const v25241 = try o.lookup(&s, frame, "binding25220");
            const v25242 = try s.call(v25237, c.pi_js_undefined(), &.{ v25238, v25239, v25240, v25241 });
            const v25243 = try s.call(v25233, c.pi_js_undefined(), &.{ v25234, v25235, v25236, v25242 });
            break :conditional25231 v25243;
        } else {
            const v25244 = try o.lookup(&s, frame, "binding25182");
            const v25245 = try o.lookup(&s, frame, "binding25217");
            const v25246 = try o.lookup(&s, frame, "binding25218");
            const v25247 = try o.lookup(&s, frame, "binding25219");
            const v25248 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
            const v25249 = try o.lookup(&s, frame, "binding25217");
            const v25250 = try o.lookup(&s, frame, "binding25218");
            const v25251 = try o.lookup(&s, frame, "binding25219");
            const v25252 = try o.lookup(&s, frame, "binding25220");
            const v25253 = try s.call(v25248, c.pi_js_undefined(), &.{ v25249, v25250, v25251, v25252 });
            const v25254 = try s.call(v25244, c.pi_js_undefined(), &.{ v25245, v25246, v25247, v25253 });
            break :conditional25231 v25254;
        }
    };
    return c.JS_DupValue(e.context, v25232);
}
