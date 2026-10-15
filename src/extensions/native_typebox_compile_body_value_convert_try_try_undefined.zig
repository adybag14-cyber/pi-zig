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
    const namespace = try s.get(modules, "value/convert/try/try_undefined.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/convert/try/try_undefined.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/convert/try/try_undefined.mjs", bindings);
    const v28208 = try s.own(try ordinary.create(e, "FromBigInt", 1, body28192, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28187", v28208);
    const v28223 = try s.own(try ordinary.create(e, "FromBoolean", 1, body28209, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28188", v28223);
    const v28238 = try s.own(try ordinary.create(e, "FromNumber", 1, body28224, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28189", v28238);
    const v28287 = try s.own(try ordinary.create(e, "FromString", 1, body28239, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28190", v28287);
    const v28352 = try s.own(try ordinary.create(e, "TryUndefined", 1, body28288, &.{ graph, frame }));
    try o.assign(&s, frame, "binding28191", v28352);
    const v28353 = try o.lookup(&s, frame, "binding28191");
    try s.put(namespace, "TryUndefined", v28353);
    const v28354 = try o.lookup(&s, frame, "binding28191");
    try s.put(namespace, "TryUndefined", v28354);
    try s.put(bindings, "TryUndefined", try s.text("binding28191"));
}
fn body28192(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28194 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28193", v28194);
    const v28195 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28196 = try s.text("IsEqual");
    const v28197 = try s.own(try js.getKey(e, v28195, v28196));
    const v28198 = try o.lookup(&s, frame, "binding28193");
    const v28199 = try s.global("BigInt");
    const v28200 = try s.call(v28199, c.pi_js_undefined(), &.{c.JS_NewFloat64(e.context, 0)});
    const v28201 = try s.call(v28197, v28195, &.{ v28198, v28200 });
    const v28203 = conditional28202: {
        if (s.truthy(v28201)) {
            const v28204 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v28205 = try s.call(v28204, c.pi_js_undefined(), &.{c.pi_js_undefined()});
            break :conditional28202 v28205;
        } else {
            const v28206 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
            const v28207 = try s.call(v28206, c.pi_js_undefined(), &.{});
            break :conditional28202 v28207;
        }
    };
    return c.JS_DupValue(e.context, v28203);
}
fn body28209(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28211 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28210", v28211);
    const v28212 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28213 = try s.text("IsEqual");
    const v28214 = try s.own(try js.getKey(e, v28212, v28213));
    const v28215 = try o.lookup(&s, frame, "binding28210");
    const v28216 = try s.call(v28214, v28212, &.{ v28215, o.boolean(&s, false) });
    const v28218 = conditional28217: {
        if (s.truthy(v28216)) {
            const v28219 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v28220 = try s.call(v28219, c.pi_js_undefined(), &.{c.pi_js_undefined()});
            break :conditional28217 v28220;
        } else {
            const v28221 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
            const v28222 = try s.call(v28221, c.pi_js_undefined(), &.{});
            break :conditional28217 v28222;
        }
    };
    return c.JS_DupValue(e.context, v28218);
}
fn body28224(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28226 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28225", v28226);
    const v28227 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28228 = try s.text("IsEqual");
    const v28229 = try s.own(try js.getKey(e, v28227, v28228));
    const v28230 = try o.lookup(&s, frame, "binding28225");
    const v28231 = try s.call(v28229, v28227, &.{ v28230, c.JS_NewFloat64(e.context, 0) });
    const v28233 = conditional28232: {
        if (s.truthy(v28231)) {
            const v28234 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v28235 = try s.call(v28234, c.pi_js_undefined(), &.{c.pi_js_undefined()});
            break :conditional28232 v28235;
        } else {
            const v28236 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
            const v28237 = try s.call(v28236, c.pi_js_undefined(), &.{});
            break :conditional28232 v28237;
        }
    };
    return c.JS_DupValue(e.context, v28233);
}
fn body28239(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28243 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28240", v28243);
    const v28246 = try o.lookup(&s, frame, "binding28240");
    const v28247 = try s.text("toLowerCase");
    const v28248 = try s.own(try js.getKey(e, v28246, v28247));
    const v28249 = try s.call(v28248, v28246, &.{});
    try o.assign(&s, frame, "binding28244", v28249);
    const v28250 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28251 = try s.text("IsEqual");
    const v28252 = try s.own(try js.getKey(e, v28250, v28251));
    const v28253 = try o.lookup(&s, frame, "binding28244");
    const v28254 = try s.text("undefined");
    const v28255 = try s.call(v28252, v28250, &.{ v28253, v28254 });
    const v28257 = logical28256: {
        if (s.truthy(v28255)) break :logical28256 v28255;
        const v28258 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v28259 = try s.text("IsEqual");
        const v28260 = try s.own(try js.getKey(e, v28258, v28259));
        const v28261 = try o.lookup(&s, frame, "binding28244");
        const v28262 = try s.text("null");
        const v28263 = try s.call(v28260, v28258, &.{ v28261, v28262 });
        break :logical28256 v28263;
    };
    const v28265 = logical28264: {
        if (s.truthy(v28257)) break :logical28264 v28257;
        const v28266 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v28267 = try s.text("IsEqual");
        const v28268 = try s.own(try js.getKey(e, v28266, v28267));
        const v28269 = try o.lookup(&s, frame, "binding28240");
        const v28270 = try s.text("");
        const v28271 = try s.call(v28268, v28266, &.{ v28269, v28270 });
        break :logical28264 v28271;
    };
    const v28273 = logical28272: {
        if (s.truthy(v28265)) break :logical28272 v28265;
        const v28274 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v28275 = try s.text("IsEqual");
        const v28276 = try s.own(try js.getKey(e, v28274, v28275));
        const v28277 = try o.lookup(&s, frame, "binding28240");
        const v28278 = try s.text("0");
        const v28279 = try s.call(v28276, v28274, &.{ v28277, v28278 });
        break :logical28272 v28279;
    };
    try o.assign(&s, frame, "binding28245", v28273);
    const v28280 = try o.lookup(&s, frame, "binding28245");
    const v28282 = conditional28281: {
        if (s.truthy(v28280)) {
            const v28283 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
            const v28284 = try s.call(v28283, c.pi_js_undefined(), &.{c.pi_js_undefined()});
            break :conditional28281 v28284;
        } else {
            const v28285 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
            const v28286 = try s.call(v28285, c.pi_js_undefined(), &.{});
            break :conditional28281 v28286;
        }
    };
    return c.JS_DupValue(e.context, v28282);
}
fn body28288(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v28290 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding28289", v28290);
    const v28291 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v28292 = try s.text("IsBigInt");
    const v28293 = try s.own(try js.getKey(e, v28291, v28292));
    const v28294 = try o.lookup(&s, frame, "binding28289");
    const v28295 = try s.call(v28293, v28291, &.{v28294});
    const v28297 = conditional28296: {
        if (s.truthy(v28295)) {
            const v28298 = try o.lookup(&s, frame, "binding28187");
            const v28299 = try o.lookup(&s, frame, "binding28289");
            const v28300 = try s.call(v28298, c.pi_js_undefined(), &.{v28299});
            break :conditional28296 v28300;
        } else {
            const v28301 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
            const v28302 = try s.text("IsBoolean");
            const v28303 = try s.own(try js.getKey(e, v28301, v28302));
            const v28304 = try o.lookup(&s, frame, "binding28289");
            const v28305 = try s.call(v28303, v28301, &.{v28304});
            const v28307 = conditional28306: {
                if (s.truthy(v28305)) {
                    const v28308 = try o.lookup(&s, frame, "binding28188");
                    const v28309 = try o.lookup(&s, frame, "binding28289");
                    const v28310 = try s.call(v28308, c.pi_js_undefined(), &.{v28309});
                    break :conditional28306 v28310;
                } else {
                    const v28311 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                    const v28312 = try s.text("IsNumber");
                    const v28313 = try s.own(try js.getKey(e, v28311, v28312));
                    const v28314 = try o.lookup(&s, frame, "binding28289");
                    const v28315 = try s.call(v28313, v28311, &.{v28314});
                    const v28317 = conditional28316: {
                        if (s.truthy(v28315)) {
                            const v28318 = try o.lookup(&s, frame, "binding28189");
                            const v28319 = try o.lookup(&s, frame, "binding28289");
                            const v28320 = try s.call(v28318, c.pi_js_undefined(), &.{v28319});
                            break :conditional28316 v28320;
                        } else {
                            const v28321 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                            const v28322 = try s.text("IsNull");
                            const v28323 = try s.own(try js.getKey(e, v28321, v28322));
                            const v28324 = try o.lookup(&s, frame, "binding28289");
                            const v28325 = try s.call(v28323, v28321, &.{v28324});
                            const v28327 = conditional28326: {
                                if (s.truthy(v28325)) {
                                    const v28328 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                    const v28329 = try s.call(v28328, c.pi_js_undefined(), &.{c.pi_js_undefined()});
                                    break :conditional28326 v28329;
                                } else {
                                    const v28330 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                    const v28331 = try s.text("IsString");
                                    const v28332 = try s.own(try js.getKey(e, v28330, v28331));
                                    const v28333 = try o.lookup(&s, frame, "binding28289");
                                    const v28334 = try s.call(v28332, v28330, &.{v28333});
                                    const v28336 = conditional28335: {
                                        if (s.truthy(v28334)) {
                                            const v28337 = try o.lookup(&s, frame, "binding28190");
                                            const v28338 = try o.lookup(&s, frame, "binding28289");
                                            const v28339 = try s.call(v28337, c.pi_js_undefined(), &.{v28338});
                                            break :conditional28335 v28339;
                                        } else {
                                            const v28340 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
                                            const v28341 = try s.text("IsUndefined");
                                            const v28342 = try s.own(try js.getKey(e, v28340, v28341));
                                            const v28343 = try o.lookup(&s, frame, "binding28289");
                                            const v28344 = try s.call(v28342, v28340, &.{v28343});
                                            const v28346 = conditional28345: {
                                                if (s.truthy(v28344)) {
                                                    const v28347 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Ok");
                                                    const v28348 = try o.lookup(&s, frame, "binding28289");
                                                    const v28349 = try s.call(v28347, c.pi_js_undefined(), &.{v28348});
                                                    break :conditional28345 v28349;
                                                } else {
                                                    const v28350 = try o.importValue(&s, graph, "value/convert/try/try_result.mjs", "Fail");
                                                    const v28351 = try s.call(v28350, c.pi_js_undefined(), &.{});
                                                    break :conditional28345 v28351;
                                                }
                                            };
                                            break :conditional28335 v28346;
                                        }
                                    };
                                    break :conditional28326 v28336;
                                }
                            };
                            break :conditional28316 v28327;
                        }
                    };
                    break :conditional28306 v28317;
                }
            };
            break :conditional28296 v28307;
        }
    };
    return c.JS_DupValue(e.context, v28297);
}
