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
    const namespace = try s.get(modules, "schema/pointer/pointer.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/pointer/pointer.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/pointer/pointer.mjs", bindings);
    const v19255 = try s.own(try ordinary.create(e, "AssertNotRoot", 1, body19246, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19232", v19255);
    const v19267 = try s.own(try ordinary.create(e, "AssertCanSet", 1, body19256, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19233", v19267);
    const v19279 = try s.own(try ordinary.create(e, "AssertIndex", 1, body19268, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19234", v19279);
    const v19292 = try s.own(try ordinary.create(e, "AssertIndices", 1, body19280, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19235", v19292);
    const v19304 = try s.own(try ordinary.create(e, "IsNumericIndex", 1, body19293, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19236", v19304);
    const v19327 = try s.own(try ordinary.create(e, "TakeIndexRight", 1, body19305, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19237", v19327);
    const v19346 = try s.own(try ordinary.create(e, "HasIndex", 2, body19328, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19238", v19346);
    const v19370 = try s.own(try ordinary.create(e, "GetIndex", 2, body19347, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19239", v19370);
    const v19392 = try s.own(try ordinary.create(e, "GetIndices", 2, body19371, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19240", v19392);
    const v19453 = try s.own(try ordinary.create(e, "Indices", 1, body19393, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19241", v19453);
    const v19481 = try s.own(try ordinary.create(e, "Has", 2, body19454, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19242", v19481);
    const v19496 = try s.own(try ordinary.create(e, "Get", 2, body19482, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19243", v19496);
    const v19539 = try s.own(try ordinary.create(e, "Set", 3, body19497, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19244", v19539);
    const v19596 = try s.own(try ordinary.create(e, "Delete", 2, body19540, &.{ graph, frame }));
    try o.assign(&s, frame, "binding19245", v19596);
    const v19597 = try o.lookup(&s, frame, "binding19241");
    try s.put(namespace, "Indices", v19597);
    const v19598 = try o.lookup(&s, frame, "binding19242");
    try s.put(namespace, "Has", v19598);
    const v19599 = try o.lookup(&s, frame, "binding19243");
    try s.put(namespace, "Get", v19599);
    const v19600 = try o.lookup(&s, frame, "binding19244");
    try s.put(namespace, "Set", v19600);
    const v19601 = try o.lookup(&s, frame, "binding19245");
    try s.put(namespace, "Delete", v19601);
    const v19602 = try o.lookup(&s, frame, "binding19241");
    try s.put(namespace, "Indices", v19602);
    const v19603 = try o.lookup(&s, frame, "binding19242");
    try s.put(namespace, "Has", v19603);
    const v19604 = try o.lookup(&s, frame, "binding19243");
    try s.put(namespace, "Get", v19604);
    const v19605 = try o.lookup(&s, frame, "binding19244");
    try s.put(namespace, "Set", v19605);
    const v19606 = try o.lookup(&s, frame, "binding19245");
    try s.put(namespace, "Delete", v19606);
    try s.put(bindings, "Indices", try s.text("binding19241"));
    try s.put(bindings, "Has", try s.text("binding19242"));
    try s.put(bindings, "Get", try s.text("binding19243"));
    try s.put(bindings, "Set", try s.text("binding19244"));
    try s.put(bindings, "Delete", try s.text("binding19245"));
}
fn body19246(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19248 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19247", v19248);
    const v19249 = try o.lookup(&s, frame, "binding19247");
    const v19250 = try s.text("length");
    const v19251 = try s.own(try js.getKey(e, v19249, v19250));
    if (s.truthy(o.boolean(&s, s.equal(v19251, c.JS_NewFloat64(e.context, 0))))) {
        const v19252 = try s.global("Error");
        const v19253 = try s.text("Cannot set root");
        const v19254 = try s.call(v19252, c.pi_js_undefined(), &.{v19253});
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v19254));
        return js.capture(e);
    }
    return c.pi_js_undefined();
}
fn body19256(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19258 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19257", v19258);
    const v19259 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19260 = try s.text("IsObject");
    const v19261 = try s.own(try js.getKey(e, v19259, v19260));
    const v19262 = try o.lookup(&s, frame, "binding19257");
    const v19263 = try s.call(v19261, v19259, &.{v19262});
    if (s.truthy(o.boolean(&s, !s.truthy(v19263)))) {
        const v19264 = try s.global("Error");
        const v19265 = try s.text("Cannot set value");
        const v19266 = try s.call(v19264, c.pi_js_undefined(), &.{v19265});
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v19266));
        return js.capture(e);
    }
    return c.pi_js_undefined();
}
fn body19268(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19270 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19269", v19270);
    const v19271 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19272 = try s.text("IsUnsafePropertyKey");
    const v19273 = try s.own(try js.getKey(e, v19271, v19272));
    const v19274 = try o.lookup(&s, frame, "binding19269");
    const v19275 = try s.call(v19273, v19271, &.{v19274});
    if (s.truthy(v19275)) {
        const v19276 = try s.global("Error");
        const v19277 = try s.text("Pointer contains unsafe property key");
        const v19278 = try s.call(v19276, c.pi_js_undefined(), &.{v19277});
        _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, v19278));
        return js.capture(e);
    }
    return c.pi_js_undefined();
}
fn body19280(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19282 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19281", v19282);
    const v19283 = try o.lookup(&s, frame, "binding19281");
    var iterator19284 = try o.iterator(e, v19283);
    defer iterator19284.deinit();
    errdefer iterator19284.closePreserving();
    while (try iterator19284.next()) |next19285| {
        defer e.freeValue(next19285);
        const iteration19287 = try o.frame(&s, frame);
        try o.assign(&s, iteration19287, "binding19288", next19285);
        const v19289 = try o.lookup(&s, iteration19287, "binding19234");
        const v19290 = try o.lookup(&s, iteration19287, "binding19288");
        const v19291 = try s.call(v19289, c.pi_js_undefined(), &.{v19290});
        _ = v19291;
    }
    try iterator19284.close();
    return c.pi_js_undefined();
}
fn body19293(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19295 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19294", v19295);
    const v19296 = try s.text("^(0|[1-9]\\d*)$");
    const v19297 = try s.text("");
    const v19298 = try s.global("RegExp");
    const v19299 = try o.construct(&s, v19298, &.{ v19296, v19297 });
    const v19300 = try s.text("test");
    const v19301 = try s.own(try js.getKey(e, v19299, v19300));
    const v19302 = try o.lookup(&s, frame, "binding19294");
    const v19303 = try s.call(v19301, v19299, &.{v19302});
    return c.JS_DupValue(e.context, v19303);
}
fn body19305(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19307 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19306", v19307);
    const v19308 = try s.array();
    const v19309 = try o.lookup(&s, frame, "binding19306");
    const v19310 = try s.text("slice");
    const v19311 = try s.own(try js.getKey(e, v19309, v19310));
    const v19312 = try o.lookup(&s, frame, "binding19306");
    const v19313 = try s.text("length");
    const v19314 = try s.own(try js.getKey(e, v19312, v19313));
    const v19315 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v19314, c.JS_NewFloat64(e.context, 1))));
    const v19316 = try s.call(v19311, v19309, &.{ c.JS_NewFloat64(e.context, 0), v19315 });
    try o.append(&s, v19308, v19316);
    const v19317 = try o.lookup(&s, frame, "binding19306");
    const v19318 = try s.text("slice");
    const v19319 = try s.own(try js.getKey(e, v19317, v19318));
    const v19320 = try o.lookup(&s, frame, "binding19306");
    const v19321 = try s.text("length");
    const v19322 = try s.own(try js.getKey(e, v19320, v19321));
    const v19323 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 1, v19322, c.JS_NewFloat64(e.context, 1))));
    const v19324 = try s.call(v19319, v19317, &.{v19323});
    const v19325 = try o.propertyKey(&s, c.JS_NewFloat64(e.context, 0));
    const v19326 = try s.own(try js.getKey(e, v19324, v19325));
    try o.append(&s, v19308, v19326);
    return c.JS_DupValue(e.context, v19308);
}
fn body19328(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19331 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19329", v19331);
    const v19332 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19330", v19332);
    const v19333 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19334 = try s.text("IsObject");
    const v19335 = try s.own(try js.getKey(e, v19333, v19334));
    const v19336 = try o.lookup(&s, frame, "binding19330");
    const v19337 = try s.call(v19335, v19333, &.{v19336});
    const v19339 = logical19338: {
        if (!s.truthy(v19337)) break :logical19338 v19337;
        const v19340 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v19341 = try s.text("HasPropertyKey");
        const v19342 = try s.own(try js.getKey(e, v19340, v19341));
        const v19343 = try o.lookup(&s, frame, "binding19330");
        const v19344 = try o.lookup(&s, frame, "binding19329");
        const v19345 = try s.call(v19342, v19340, &.{ v19343, v19344 });
        break :logical19338 v19345;
    };
    return c.JS_DupValue(e.context, v19339);
}
fn body19347(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19350 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19348", v19350);
    const v19351 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19349", v19351);
    const v19352 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19353 = try s.text("IsObject");
    const v19354 = try s.own(try js.getKey(e, v19352, v19353));
    const v19355 = try o.lookup(&s, frame, "binding19349");
    const v19356 = try s.call(v19354, v19352, &.{v19355});
    const v19358 = logical19357: {
        if (!s.truthy(v19356)) break :logical19357 v19356;
        const v19359 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
        const v19360 = try s.text("IsUnsafePropertyKey");
        const v19361 = try s.own(try js.getKey(e, v19359, v19360));
        const v19362 = try o.lookup(&s, frame, "binding19348");
        const v19363 = try s.call(v19361, v19359, &.{v19362});
        break :logical19357 o.boolean(&s, !s.truthy(v19363));
    };
    const v19365 = conditional19364: {
        if (s.truthy(v19358)) {
            const v19366 = try o.lookup(&s, frame, "binding19349");
            const v19367 = try o.lookup(&s, frame, "binding19348");
            const v19368 = try o.propertyKey(&s, v19367);
            const v19369 = try s.own(try js.getKey(e, v19366, v19368));
            break :conditional19364 v19369;
        } else {
            break :conditional19364 c.pi_js_undefined();
        }
    };
    return c.JS_DupValue(e.context, v19365);
}
fn body19379(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v19383 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19381", v19383);
    const v19384 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19382", v19384);
    const v19385 = try o.lookup(&s, frame, "binding19239");
    const v19386 = try o.lookup(&s, frame, "binding19382");
    const v19387 = try o.lookup(&s, frame, "binding19381");
    const v19388 = try s.call(v19385, c.pi_js_undefined(), &.{ v19386, v19387 });
    return c.JS_DupValue(e.context, v19388);
}
fn body19379C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body19379(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body19371(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19374 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19372", v19374);
    const v19375 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19373", v19375);
    const v19376 = try o.lookup(&s, frame, "binding19372");
    const v19377 = try s.text("reduce");
    const v19378 = try s.own(try js.getKey(e, v19376, v19377));
    const v19389 = try o.arrow(&s, "", 2, body19379C, &.{ graph, frame });
    const v19390 = try o.lookup(&s, frame, "binding19373");
    const v19391 = try s.call(v19378, v19376, &.{ v19389, v19390 });
    return c.JS_DupValue(e.context, v19391);
}
fn body19413(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v19416 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19415", v19416);
    const v19417 = try o.lookup(&s, frame, "binding19415");
    const v19418 = try s.text("replace");
    const v19419 = try s.own(try js.getKey(e, v19417, v19418));
    const v19420 = try s.text("~1");
    const v19421 = try s.text("g");
    const v19422 = try s.global("RegExp");
    const v19423 = try o.construct(&s, v19422, &.{ v19420, v19421 });
    const v19424 = try s.text("/");
    const v19425 = try s.call(v19419, v19417, &.{ v19423, v19424 });
    const v19426 = try s.text("replace");
    const v19427 = try s.own(try js.getKey(e, v19425, v19426));
    const v19428 = try s.text("~0");
    const v19429 = try s.text("g");
    const v19430 = try s.global("RegExp");
    const v19431 = try o.construct(&s, v19430, &.{ v19428, v19429 });
    const v19432 = try s.text("~");
    const v19433 = try s.call(v19427, v19425, &.{ v19431, v19432 });
    return c.JS_DupValue(e.context, v19433);
}
fn body19413C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body19413(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body19393(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19396 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19394", v19396);
    const v19398 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19399 = try s.text("IsEqual");
    const v19400 = try s.own(try js.getKey(e, v19398, v19399));
    const v19401 = try o.lookup(&s, frame, "binding19394");
    const v19402 = try s.text("length");
    const v19403 = try s.own(try js.getKey(e, v19401, v19402));
    const v19404 = try s.call(v19400, v19398, &.{ v19403, c.JS_NewFloat64(e.context, 0) });
    if (s.truthy(v19404)) {
        const v19405 = try s.array();
        return c.JS_DupValue(e.context, v19405);
    }
    const v19406 = try o.lookup(&s, frame, "binding19394");
    const v19407 = try s.text("split");
    const v19408 = try s.own(try js.getKey(e, v19406, v19407));
    const v19409 = try s.text("/");
    const v19410 = try s.call(v19408, v19406, &.{v19409});
    const v19411 = try s.text("map");
    const v19412 = try s.own(try js.getKey(e, v19410, v19411));
    const v19434 = try o.arrow(&s, "", 1, body19413C, &.{ graph, frame });
    const v19435 = try s.call(v19412, v19410, &.{v19434});
    try o.assign(&s, frame, "binding19397", v19435);
    const v19436 = try o.lookup(&s, frame, "binding19397");
    const v19437 = try s.text("length");
    const v19438 = try s.own(try js.getKey(e, v19436, v19437));
    const v19439 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 6, v19438, c.JS_NewFloat64(e.context, 0))));
    const v19441 = logical19440: {
        if (!s.truthy(v19439)) break :logical19440 v19439;
        const v19442 = try o.lookup(&s, frame, "binding19397");
        const v19443 = try o.propertyKey(&s, c.JS_NewFloat64(e.context, 0));
        const v19444 = try s.own(try js.getKey(e, v19442, v19443));
        const v19445 = try s.text("");
        break :logical19440 o.boolean(&s, s.equal(v19444, v19445));
    };
    const v19447 = conditional19446: {
        if (s.truthy(v19441)) {
            const v19448 = try o.lookup(&s, frame, "binding19397");
            const v19449 = try s.text("slice");
            const v19450 = try s.own(try js.getKey(e, v19448, v19449));
            const v19451 = try s.call(v19450, v19448, &.{c.JS_NewFloat64(e.context, 1)});
            break :conditional19446 v19451;
        } else {
            const v19452 = try o.lookup(&s, frame, "binding19397");
            break :conditional19446 v19452;
        }
    };
    return c.JS_DupValue(e.context, v19447);
}
fn body19467(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v19470 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19469", v19470);
    const v19471 = try o.lookup(&s, frame, "binding19238");
    const v19472 = try o.lookup(&s, frame, "binding19469");
    const v19473 = try o.lookup(&s, frame, "binding19460");
    const v19474 = try s.call(v19471, c.pi_js_undefined(), &.{ v19472, v19473 });
    if (s.truthy(o.boolean(&s, !s.truthy(v19474)))) {
        return c.JS_DupValue(e.context, o.boolean(&s, false));
    }
    const v19475 = try o.lookup(&s, frame, "binding19460");
    const v19476 = try o.lookup(&s, frame, "binding19469");
    const v19477 = try o.propertyKey(&s, v19476);
    const v19478 = try s.own(try js.getKey(e, v19475, v19477));
    try o.assign(&s, frame, "binding19460", v19478);
    return c.JS_DupValue(e.context, o.boolean(&s, true));
}
fn body19467C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body19467(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body19454(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19458 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19455", v19458);
    const v19459 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19456", v19459);
    const v19461 = try o.lookup(&s, frame, "binding19455");
    try o.assign(&s, frame, "binding19460", v19461);
    const v19462 = try o.lookup(&s, frame, "binding19241");
    const v19463 = try o.lookup(&s, frame, "binding19456");
    const v19464 = try s.call(v19462, c.pi_js_undefined(), &.{v19463});
    const v19465 = try s.text("every");
    const v19466 = try s.own(try js.getKey(e, v19464, v19465));
    const v19479 = try o.arrow(&s, "", 1, body19467C, &.{ graph, frame });
    const v19480 = try s.call(v19466, v19464, &.{v19479});
    return c.JS_DupValue(e.context, v19480);
}
fn body19482(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19486 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19483", v19486);
    const v19487 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19484", v19487);
    const v19489 = try o.lookup(&s, frame, "binding19241");
    const v19490 = try o.lookup(&s, frame, "binding19484");
    const v19491 = try s.call(v19489, c.pi_js_undefined(), &.{v19490});
    try o.assign(&s, frame, "binding19488", v19491);
    const v19492 = try o.lookup(&s, frame, "binding19240");
    const v19493 = try o.lookup(&s, frame, "binding19488");
    const v19494 = try o.lookup(&s, frame, "binding19483");
    const v19495 = try s.call(v19492, c.pi_js_undefined(), &.{ v19493, v19494 });
    return c.JS_DupValue(e.context, v19495);
}
fn body19497(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19505 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19498", v19505);
    const v19506 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19499", v19506);
    const v19507 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19500", v19507);
    const v19512 = try o.lookup(&s, frame, "binding19241");
    const v19513 = try o.lookup(&s, frame, "binding19499");
    const v19514 = try s.call(v19512, c.pi_js_undefined(), &.{v19513});
    try o.assign(&s, frame, "binding19508", v19514);
    const v19515 = try o.lookup(&s, frame, "binding19232");
    const v19516 = try o.lookup(&s, frame, "binding19508");
    const v19517 = try s.call(v19515, c.pi_js_undefined(), &.{v19516});
    _ = v19517;
    const v19518 = try o.lookup(&s, frame, "binding19235");
    const v19519 = try o.lookup(&s, frame, "binding19508");
    const v19520 = try s.call(v19518, c.pi_js_undefined(), &.{v19519});
    _ = v19520;
    const v19521 = try o.lookup(&s, frame, "binding19237");
    const v19522 = try o.lookup(&s, frame, "binding19508");
    const v19523 = try s.call(v19521, c.pi_js_undefined(), &.{v19522});
    var destructure19524 = try o.iterator(e, v19523);
    defer destructure19524.deinit();
    errdefer destructure19524.closePreserving();
    const v19525 = try s.own(if (destructure19524.closed) c.pi_js_undefined() else (try destructure19524.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding19509", v19525);
    const v19526 = try s.own(if (destructure19524.closed) c.pi_js_undefined() else (try destructure19524.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding19510", v19526);
    try destructure19524.close();
    const v19527 = try o.lookup(&s, frame, "binding19240");
    const v19528 = try o.lookup(&s, frame, "binding19509");
    const v19529 = try o.lookup(&s, frame, "binding19498");
    const v19530 = try s.call(v19527, c.pi_js_undefined(), &.{ v19528, v19529 });
    try o.assign(&s, frame, "binding19511", v19530);
    const v19531 = try o.lookup(&s, frame, "binding19233");
    const v19532 = try o.lookup(&s, frame, "binding19511");
    const v19533 = try s.call(v19531, c.pi_js_undefined(), &.{v19532});
    _ = v19533;
    const v19534 = try o.lookup(&s, frame, "binding19511");
    const v19535 = try o.lookup(&s, frame, "binding19510");
    const v19536 = try o.propertyKey(&s, v19535);
    const v19537 = try o.lookup(&s, frame, "binding19500");
    try js.setKey(e, v19534, v19536, v19537);
    const v19538 = try o.lookup(&s, frame, "binding19498");
    return c.JS_DupValue(e.context, v19538);
}
fn body19540(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v19547 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19541", v19547);
    const v19548 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding19542", v19548);
    const v19553 = try o.lookup(&s, frame, "binding19241");
    const v19554 = try o.lookup(&s, frame, "binding19542");
    const v19555 = try s.call(v19553, c.pi_js_undefined(), &.{v19554});
    try o.assign(&s, frame, "binding19549", v19555);
    const v19556 = try o.lookup(&s, frame, "binding19232");
    const v19557 = try o.lookup(&s, frame, "binding19549");
    const v19558 = try s.call(v19556, c.pi_js_undefined(), &.{v19557});
    _ = v19558;
    const v19559 = try o.lookup(&s, frame, "binding19235");
    const v19560 = try o.lookup(&s, frame, "binding19549");
    const v19561 = try s.call(v19559, c.pi_js_undefined(), &.{v19560});
    _ = v19561;
    const v19562 = try o.lookup(&s, frame, "binding19237");
    const v19563 = try o.lookup(&s, frame, "binding19549");
    const v19564 = try s.call(v19562, c.pi_js_undefined(), &.{v19563});
    var destructure19565 = try o.iterator(e, v19564);
    defer destructure19565.deinit();
    errdefer destructure19565.closePreserving();
    const v19566 = try s.own(if (destructure19565.closed) c.pi_js_undefined() else (try destructure19565.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding19550", v19566);
    const v19567 = try s.own(if (destructure19565.closed) c.pi_js_undefined() else (try destructure19565.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding19551", v19567);
    try destructure19565.close();
    const v19568 = try o.lookup(&s, frame, "binding19240");
    const v19569 = try o.lookup(&s, frame, "binding19550");
    const v19570 = try o.lookup(&s, frame, "binding19541");
    const v19571 = try s.call(v19568, c.pi_js_undefined(), &.{ v19569, v19570 });
    try o.assign(&s, frame, "binding19552", v19571);
    const v19572 = try o.lookup(&s, frame, "binding19233");
    const v19573 = try o.lookup(&s, frame, "binding19552");
    const v19574 = try s.call(v19572, c.pi_js_undefined(), &.{v19573});
    _ = v19574;
    const v19575 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v19576 = try s.text("IsArray");
    const v19577 = try s.own(try js.getKey(e, v19575, v19576));
    const v19578 = try o.lookup(&s, frame, "binding19552");
    const v19579 = try s.call(v19577, v19575, &.{v19578});
    const v19581 = logical19580: {
        if (!s.truthy(v19579)) break :logical19580 v19579;
        const v19582 = try o.lookup(&s, frame, "binding19236");
        const v19583 = try o.lookup(&s, frame, "binding19551");
        const v19584 = try s.call(v19582, c.pi_js_undefined(), &.{v19583});
        break :logical19580 v19584;
    };
    if (s.truthy(v19581)) {
        const v19585 = try o.lookup(&s, frame, "binding19552");
        const v19586 = try s.text("splice");
        const v19587 = try s.own(try js.getKey(e, v19585, v19586));
        const v19588 = try o.lookup(&s, frame, "binding19551");
        const v19589 = try o.toNumber(&s, v19588);
        const v19590 = try s.call(v19587, v19585, &.{ v19589, c.JS_NewFloat64(e.context, 1) });
        _ = v19590;
    } else {
        const v19591 = try o.lookup(&s, frame, "binding19552");
        const v19592 = try o.lookup(&s, frame, "binding19551");
        const v19593 = try o.propertyKey(&s, v19592);
        const v19594 = try o.deleteKey(&s, v19591, v19593);
        _ = v19594;
    }
    const v19595 = try o.lookup(&s, frame, "binding19541");
    return c.JS_DupValue(e.context, v19595);
}
