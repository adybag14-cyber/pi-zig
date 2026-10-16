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
    const namespace = try s.get(modules, "value/convert/try/try_string.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/try/try_string.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/try/try_string.mjs", bindings);
    const v28184 = try s.own(try ordinary.create(e, "TryString", 1, body28110, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28109", v28184);
    const v28185 = try o.lookup(&s, frame, "binding28109");
    try s.put(namespace, "TryString", v28185);
    const v28186 = try o.lookup(&s, frame, "binding28109");
    try s.put(namespace, "TryString", v28186);
    try s.put(bindings, "TryString", try s.text("binding28109"));
}
fn body28110(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28112 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28111", v28112);
    const v28113 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28114 = try s.text("IsBigInt");
    const v28115 = try s.own(try js.getKey(e, v28113, v28114));
    const v28116 = try o.lookup(&s, frame, "binding28111");
    const v28117 = try s.call(v28115, v28113, &.{v28116});
    const v28119 = conditional28118: {
        if (s.truthy(v28117)) {
            const v28120 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v28121 = try o.lookup(&s, frame, "binding28111");
            const v28122 = try s.text("toString");
            const v28123 = try s.own(try js.getKey(e, v28121, v28122));
            const v28124 = try s.call(v28123, v28121, &.{});
            const v28125 = try s.call(v28120, c.pi_js_undefined(), &.{v28124});
            break :conditional28118 v28125;
        } else {
            const v28126 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v28127 = try s.text("IsBoolean");
            const v28128 = try s.own(try js.getKey(e, v28126, v28127));
            const v28129 = try o.lookup(&s, frame, "binding28111");
            const v28130 = try s.call(v28128, v28126, &.{v28129});
            const v28132 = conditional28131: {
                if (s.truthy(v28130)) {
                    const v28133 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                    const v28134 = try o.lookup(&s, frame, "binding28111");
                    const v28135 = try s.text("toString");
                    const v28136 = try s.own(try js.getKey(e, v28134, v28135));
                    const v28137 = try s.call(v28136, v28134, &.{});
                    const v28138 = try s.call(v28133, c.pi_js_undefined(), &.{v28137});
                    break :conditional28131 v28138;
                } else {
                    const v28139 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v28140 = try s.text("IsNumber");
                    const v28141 = try s.own(try js.getKey(e, v28139, v28140));
                    const v28142 = try o.lookup(&s, frame, "binding28111");
                    const v28143 = try s.call(v28141, v28139, &.{v28142});
                    const v28145 = conditional28144: {
                        if (s.truthy(v28143)) {
                            const v28146 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                            const v28147 = try o.lookup(&s, frame, "binding28111");
                            const v28148 = try s.text("toString");
                            const v28149 = try s.own(try js.getKey(e, v28147, v28148));
                            const v28150 = try s.call(v28149, v28147, &.{});
                            const v28151 = try s.call(v28146, c.pi_js_undefined(), &.{v28150});
                            break :conditional28144 v28151;
                        } else {
                            const v28152 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v28153 = try s.text("IsNull");
                            const v28154 = try s.own(try js.getKey(e, v28152, v28153));
                            const v28155 = try o.lookup(&s, frame, "binding28111");
                            const v28156 = try s.call(v28154, v28152, &.{v28155});
                            const v28158 = conditional28157: {
                                if (s.truthy(v28156)) {
                                    const v28159 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                    const v28160 = try s.text("null");
                                    const v28161 = try s.call(v28159, c.pi_js_undefined(), &.{v28160});
                                    break :conditional28157 v28161;
                                } else {
                                    const v28162 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v28163 = try s.text("IsString");
                                    const v28164 = try s.own(try js.getKey(e, v28162, v28163));
                                    const v28165 = try o.lookup(&s, frame, "binding28111");
                                    const v28166 = try s.call(v28164, v28162, &.{v28165});
                                    const v28168 = conditional28167: {
                                        if (s.truthy(v28166)) {
                                            const v28169 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                            const v28170 = try o.lookup(&s, frame, "binding28111");
                                            const v28171 = try s.call(v28169, c.pi_js_undefined(), &.{v28170});
                                            break :conditional28167 v28171;
                                        } else {
                                            const v28172 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                            const v28173 = try s.text("IsUndefined");
                                            const v28174 = try s.own(try js.getKey(e, v28172, v28173));
                                            const v28175 = try o.lookup(&s, frame, "binding28111");
                                            const v28176 = try s.call(v28174, v28172, &.{v28175});
                                            const v28178 = conditional28177: {
                                                if (s.truthy(v28176)) {
                                                    const v28179 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                                    const v28180 = try s.text("");
                                                    const v28181 = try s.call(v28179, c.pi_js_undefined(), &.{v28180});
                                                    break :conditional28177 v28181;
                                                } else {
                                                    const v28182 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                                                    const v28183 = try s.call(v28182, c.pi_js_undefined(), &.{});
                                                    break :conditional28177 v28183;
                                                }
                                            };
                                            break :conditional28167 v28178;
                                        }
                                    };
                                    break :conditional28157 v28168;
                                }
                            };
                            break :conditional28144 v28158;
                        }
                    };
                    break :conditional28131 v28145;
                }
            };
            break :conditional28118 v28132;
        }
    };
    return c.JS_DupValue(e.context, v28119);
}
