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
    const namespace = try s.get(modules, "value/codec/from_tuple.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "value/codec/from_tuple.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "value/codec/from_tuple.mjs", bindings);
    const v25318 = try s.own(try ordinary.create(e, "Decode", 4, body25261, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25258", v25318);
    const v25379 = try s.own(try ordinary.create(e, "Encode", 4, body25319, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25259", v25379);
    const v25409 = try s.own(try ordinary.create(e, "FromTuple", 4, body25380, &.{ graph, frame }));
    try o.assign(&s, frame, "binding25260", v25409);
    const v25410 = try o.lookup(&s, frame, "binding25260");
    try s.put(namespace, "FromTuple", v25410);
    const v25411 = try o.lookup(&s, frame, "binding25260");
    try s.put(namespace, "FromTuple", v25411);
    try s.put(bindings, "FromTuple", try s.text("binding25260"));
}
fn body25261(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25266 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25262", v25266);
    const v25267 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25263", v25267);
    const v25268 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25264", v25268);
    const v25269 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25265", v25269);
    const v25270 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25271 = try s.text("IsArray");
    const v25272 = try s.own(try js.getKey(e, v25270, v25271));
    const v25273 = try o.lookup(&s, frame, "binding25265");
    const v25274 = try o.call(&s, @src(), v25272, v25270, &.{v25273});
    if (s.truthy(o.boolean(&s, !s.truthy(v25274)))) {
        const v25275 = try o.lookup(&s, frame, "binding25265");
        return c.JS_DupValue(e.context, v25275);
    }
    try o.assign(&s, frame, "binding25276", c.JS_NewFloat64(e.context, 0));
    loop25277: while (true) {
        const v25279 = try o.lookup(&s, frame, "binding25276");
        const v25280 = try s.global("Math");
        const v25281 = try s.text("min");
        const v25282 = try s.own(try js.getKey(e, v25280, v25281));
        const v25283 = try o.lookup(&s, frame, "binding25264");
        const v25284 = try s.text("items");
        const v25285 = try s.own(try js.getKey(e, v25283, v25284));
        const v25286 = try s.text("length");
        const v25287 = try s.own(try js.getKey(e, v25285, v25286));
        const v25288 = try o.lookup(&s, frame, "binding25265");
        const v25289 = try s.text("length");
        const v25290 = try s.own(try js.getKey(e, v25288, v25289));
        const v25291 = try o.call(&s, @src(), v25282, v25280, &.{ v25287, v25290 });
        const v25292 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v25279, v25291)));
        if (!s.truthy(v25292)) break :loop25277;
        {
            const v25293 = try o.lookup(&s, frame, "binding25265");
            const v25294 = try o.lookup(&s, frame, "binding25276");
            const v25295 = try o.propertyKey(&s, v25294);
            const v25296 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
            const v25297 = try o.lookup(&s, frame, "binding25262");
            const v25298 = try o.lookup(&s, frame, "binding25263");
            const v25299 = try o.lookup(&s, frame, "binding25264");
            const v25300 = try s.text("items");
            const v25301 = try s.own(try js.getKey(e, v25299, v25300));
            const v25302 = try o.lookup(&s, frame, "binding25276");
            const v25303 = try o.propertyKey(&s, v25302);
            const v25304 = try s.own(try js.getKey(e, v25301, v25303));
            const v25305 = try o.lookup(&s, frame, "binding25265");
            const v25306 = try o.lookup(&s, frame, "binding25276");
            const v25307 = try o.propertyKey(&s, v25306);
            const v25308 = try s.own(try js.getKey(e, v25305, v25307));
            const v25309 = try o.call(&s, @src(), v25296, c.pi_js_undefined(), &.{ v25297, v25298, v25304, v25308 });
            try js.setKey(e, v25293, v25295, v25309);
        }
        const v25310 = try o.lookup(&s, frame, "binding25276");
        const v25311 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v25310)));
        try o.assign(&s, frame, "binding25276", v25311);
    }
    const v25312 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v25313 = try o.lookup(&s, frame, "binding25262");
    const v25314 = try o.lookup(&s, frame, "binding25263");
    const v25315 = try o.lookup(&s, frame, "binding25264");
    const v25316 = try o.lookup(&s, frame, "binding25265");
    const v25317 = try o.call(&s, @src(), v25312, c.pi_js_undefined(), &.{ v25313, v25314, v25315, v25316 });
    return c.JS_DupValue(e.context, v25317);
}
fn body25319(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25325 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25320", v25325);
    const v25326 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25321", v25326);
    const v25327 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25322", v25327);
    const v25328 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25323", v25328);
    const v25330 = try o.importValue(&s, graph, "value/codec/callback.mjs", "Callback");
    const v25331 = try o.lookup(&s, frame, "binding25320");
    const v25332 = try o.lookup(&s, frame, "binding25321");
    const v25333 = try o.lookup(&s, frame, "binding25322");
    const v25334 = try o.lookup(&s, frame, "binding25323");
    const v25335 = try o.call(&s, @src(), v25330, c.pi_js_undefined(), &.{ v25331, v25332, v25333, v25334 });
    try o.assign(&s, frame, "binding25329", v25335);
    const v25336 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25337 = try s.text("IsArray");
    const v25338 = try s.own(try js.getKey(e, v25336, v25337));
    const v25339 = try o.lookup(&s, frame, "binding25329");
    const v25340 = try o.call(&s, @src(), v25338, v25336, &.{v25339});
    if (s.truthy(o.boolean(&s, !s.truthy(v25340)))) {
        const v25341 = try o.lookup(&s, frame, "binding25323");
        return c.JS_DupValue(e.context, v25341);
    }
    try o.assign(&s, frame, "binding25342", c.JS_NewFloat64(e.context, 0));
    loop25343: while (true) {
        const v25345 = try o.lookup(&s, frame, "binding25342");
        const v25346 = try s.global("Math");
        const v25347 = try s.text("min");
        const v25348 = try s.own(try js.getKey(e, v25346, v25347));
        const v25349 = try o.lookup(&s, frame, "binding25322");
        const v25350 = try s.text("items");
        const v25351 = try s.own(try js.getKey(e, v25349, v25350));
        const v25352 = try s.text("length");
        const v25353 = try s.own(try js.getKey(e, v25351, v25352));
        const v25354 = try o.lookup(&s, frame, "binding25329");
        const v25355 = try s.text("length");
        const v25356 = try s.own(try js.getKey(e, v25354, v25355));
        const v25357 = try o.call(&s, @src(), v25348, v25346, &.{ v25353, v25356 });
        const v25358 = try s.own(try e.checked(c.JS_PiBinaryOperator(e.context, 4, v25345, v25357)));
        if (!s.truthy(v25358)) break :loop25343;
        {
            const v25359 = try o.lookup(&s, frame, "binding25329");
            const v25360 = try o.lookup(&s, frame, "binding25342");
            const v25361 = try o.propertyKey(&s, v25360);
            const v25362 = try o.importValue(&s, graph, "value/codec/from_type.mjs", "FromType");
            const v25363 = try o.lookup(&s, frame, "binding25320");
            const v25364 = try o.lookup(&s, frame, "binding25321");
            const v25365 = try o.lookup(&s, frame, "binding25322");
            const v25366 = try s.text("items");
            const v25367 = try s.own(try js.getKey(e, v25365, v25366));
            const v25368 = try o.lookup(&s, frame, "binding25342");
            const v25369 = try o.propertyKey(&s, v25368);
            const v25370 = try s.own(try js.getKey(e, v25367, v25369));
            const v25371 = try o.lookup(&s, frame, "binding25329");
            const v25372 = try o.lookup(&s, frame, "binding25342");
            const v25373 = try o.propertyKey(&s, v25372);
            const v25374 = try s.own(try js.getKey(e, v25371, v25373));
            const v25375 = try o.call(&s, @src(), v25362, c.pi_js_undefined(), &.{ v25363, v25364, v25370, v25374 });
            try js.setKey(e, v25359, v25361, v25375);
        }
        const v25376 = try o.lookup(&s, frame, "binding25342");
        const v25377 = try s.own(try e.checked(c.JS_PiIncrement(e.context, v25376)));
        try o.assign(&s, frame, "binding25342", v25377);
    }
    const v25378 = try o.lookup(&s, frame, "binding25329");
    return c.JS_DupValue(e.context, v25378);
}
fn body25380(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v25385 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25381", v25385);
    const v25386 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25382", v25386);
    const v25387 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25383", v25387);
    const v25388 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding25384", v25388);
    const v25389 = try o.importValue(&s, graph, "guard/index.mjs", "Guard");
    const v25390 = try s.text("IsEqual");
    const v25391 = try s.own(try js.getKey(e, v25389, v25390));
    const v25392 = try o.lookup(&s, frame, "binding25381");
    const v25393 = try s.text("Decode");
    const v25394 = try o.call(&s, @src(), v25391, v25389, &.{ v25392, v25393 });
    const v25396 = conditional25395: {
        if (s.truthy(v25394)) {
            const v25397 = try o.lookup(&s, frame, "binding25258");
            const v25398 = try o.lookup(&s, frame, "binding25381");
            const v25399 = try o.lookup(&s, frame, "binding25382");
            const v25400 = try o.lookup(&s, frame, "binding25383");
            const v25401 = try o.lookup(&s, frame, "binding25384");
            const v25402 = try o.call(&s, @src(), v25397, c.pi_js_undefined(), &.{ v25398, v25399, v25400, v25401 });
            break :conditional25395 v25402;
        } else {
            const v25403 = try o.lookup(&s, frame, "binding25259");
            const v25404 = try o.lookup(&s, frame, "binding25381");
            const v25405 = try o.lookup(&s, frame, "binding25382");
            const v25406 = try o.lookup(&s, frame, "binding25383");
            const v25407 = try o.lookup(&s, frame, "binding25384");
            const v25408 = try o.call(&s, @src(), v25403, c.pi_js_undefined(), &.{ v25404, v25405, v25406, v25407 });
            break :conditional25395 v25408;
        }
    };
    return c.JS_DupValue(e.context, v25396);
}
