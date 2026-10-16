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
    const namespace = try s.get(modules, "schema/engine/if.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/engine/if.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/engine/if.mjs", bindings);
    const v9306 = try s.own(try ordinary.create(e, "BuildIf", 4, body9249, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9246", v9306);
    const v9362 = try s.own(try ordinary.create(e, "CheckIf", 4, body9307, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9247", v9362);
    const v9491 = try s.own(try ordinary.create(e, "ErrorIf", 6, body9363, &.{ graph, frame }));
    try o.assign(&s, frame, "binding9248", v9491);
    const v9492 = try o.lookup(&s, frame, "binding9246");
    try s.put(namespace, "BuildIf", v9492);
    const v9493 = try o.lookup(&s, frame, "binding9247");
    try s.put(namespace, "CheckIf", v9493);
    const v9494 = try o.lookup(&s, frame, "binding9248");
    try s.put(namespace, "ErrorIf", v9494);
    const v9495 = try o.lookup(&s, frame, "binding9246");
    try s.put(namespace, "BuildIf", v9495);
    const v9496 = try o.lookup(&s, frame, "binding9247");
    try s.put(namespace, "CheckIf", v9496);
    const v9497 = try o.lookup(&s, frame, "binding9248");
    try s.put(namespace, "ErrorIf", v9497);
    try s.put(bindings, "BuildIf", try s.text("binding9246"));
    try s.put(bindings, "CheckIf", try s.text("binding9247"));
    try s.put(bindings, "ErrorIf", try s.text("binding9248"));
}
fn body9249(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9256 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9250", v9256);
    const v9257 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9251", v9257);
    const v9258 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9252", v9258);
    const v9259 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9253", v9259);
    const v9262 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v9263 = try s.text("IsThen");
    const v9264 = try s.own(try js.getKey(e, v9262, v9263));
    const v9265 = try o.lookup(&s, frame, "binding9252");
    const v9266 = try o.call(&s, @src(), v9264, v9262, &.{v9265});
    const v9268 = conditional9267: {
        if (s.truthy(v9266)) {
            const v9269 = try o.lookup(&s, frame, "binding9252");
            const v9270 = try s.text("then");
            const v9271 = try s.own(try js.getKey(e, v9269, v9270));
            break :conditional9267 v9271;
        } else {
            break :conditional9267 o.boolean(&s, true);
        }
    };
    try o.assign(&s, frame, "binding9260", v9268);
    const v9272 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v9273 = try s.text("IsElse");
    const v9274 = try s.own(try js.getKey(e, v9272, v9273));
    const v9275 = try o.lookup(&s, frame, "binding9252");
    const v9276 = try o.call(&s, @src(), v9274, v9272, &.{v9275});
    const v9278 = conditional9277: {
        if (s.truthy(v9276)) {
            const v9279 = try o.lookup(&s, frame, "binding9252");
            const v9280 = try s.text("else");
            const v9281 = try s.own(try js.getKey(e, v9279, v9280));
            break :conditional9277 v9281;
        } else {
            break :conditional9277 o.boolean(&s, true);
        }
    };
    try o.assign(&s, frame, "binding9261", v9278);
    const v9282 = try o.importValue(&s, graph, "guard/index.mjs", "EmitGuard");
    const v9283 = try s.text("Ternary");
    const v9284 = try s.own(try js.getKey(e, v9282, v9283));
    const v9285 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchema");
    const v9286 = try o.lookup(&s, frame, "binding9250");
    const v9287 = try o.lookup(&s, frame, "binding9251");
    const v9288 = try o.lookup(&s, frame, "binding9252");
    const v9289 = try s.text("if");
    const v9290 = try s.own(try js.getKey(e, v9288, v9289));
    const v9291 = try o.lookup(&s, frame, "binding9253");
    const v9292 = try o.call(&s, @src(), v9285, c.pi_js_undefined(), &.{ v9286, v9287, v9290, v9291 });
    const v9293 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchema");
    const v9294 = try o.lookup(&s, frame, "binding9250");
    const v9295 = try o.lookup(&s, frame, "binding9251");
    const v9296 = try o.lookup(&s, frame, "binding9260");
    const v9297 = try o.lookup(&s, frame, "binding9253");
    const v9298 = try o.call(&s, @src(), v9293, c.pi_js_undefined(), &.{ v9294, v9295, v9296, v9297 });
    const v9299 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "BuildSchema");
    const v9300 = try o.lookup(&s, frame, "binding9250");
    const v9301 = try o.lookup(&s, frame, "binding9251");
    const v9302 = try o.lookup(&s, frame, "binding9261");
    const v9303 = try o.lookup(&s, frame, "binding9253");
    const v9304 = try o.call(&s, @src(), v9299, c.pi_js_undefined(), &.{ v9300, v9301, v9302, v9303 });
    const v9305 = try o.call(&s, @src(), v9284, v9282, &.{ v9292, v9298, v9304 });
    return c.JS_DupValue(e.context, v9305);
}
fn body9307(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9314 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9308", v9314);
    const v9315 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9309", v9315);
    const v9316 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9310", v9316);
    const v9317 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9311", v9317);
    const v9320 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v9321 = try s.text("IsThen");
    const v9322 = try s.own(try js.getKey(e, v9320, v9321));
    const v9323 = try o.lookup(&s, frame, "binding9310");
    const v9324 = try o.call(&s, @src(), v9322, v9320, &.{v9323});
    const v9326 = conditional9325: {
        if (s.truthy(v9324)) {
            const v9327 = try o.lookup(&s, frame, "binding9310");
            const v9328 = try s.text("then");
            const v9329 = try s.own(try js.getKey(e, v9327, v9328));
            break :conditional9325 v9329;
        } else {
            break :conditional9325 o.boolean(&s, true);
        }
    };
    try o.assign(&s, frame, "binding9318", v9326);
    const v9330 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v9331 = try s.text("IsElse");
    const v9332 = try s.own(try js.getKey(e, v9330, v9331));
    const v9333 = try o.lookup(&s, frame, "binding9310");
    const v9334 = try o.call(&s, @src(), v9332, v9330, &.{v9333});
    const v9336 = conditional9335: {
        if (s.truthy(v9334)) {
            const v9337 = try o.lookup(&s, frame, "binding9310");
            const v9338 = try s.text("else");
            const v9339 = try s.own(try js.getKey(e, v9337, v9338));
            break :conditional9335 v9339;
        } else {
            break :conditional9335 o.boolean(&s, true);
        }
    };
    try o.assign(&s, frame, "binding9319", v9336);
    const v9340 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchema");
    const v9341 = try o.lookup(&s, frame, "binding9308");
    const v9342 = try o.lookup(&s, frame, "binding9309");
    const v9343 = try o.lookup(&s, frame, "binding9310");
    const v9344 = try s.text("if");
    const v9345 = try s.own(try js.getKey(e, v9343, v9344));
    const v9346 = try o.lookup(&s, frame, "binding9311");
    const v9347 = try o.call(&s, @src(), v9340, c.pi_js_undefined(), &.{ v9341, v9342, v9345, v9346 });
    const v9349 = conditional9348: {
        if (s.truthy(v9347)) {
            const v9350 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchema");
            const v9351 = try o.lookup(&s, frame, "binding9308");
            const v9352 = try o.lookup(&s, frame, "binding9309");
            const v9353 = try o.lookup(&s, frame, "binding9318");
            const v9354 = try o.lookup(&s, frame, "binding9311");
            const v9355 = try o.call(&s, @src(), v9350, c.pi_js_undefined(), &.{ v9351, v9352, v9353, v9354 });
            break :conditional9348 v9355;
        } else {
            const v9356 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "CheckSchema");
            const v9357 = try o.lookup(&s, frame, "binding9308");
            const v9358 = try o.lookup(&s, frame, "binding9309");
            const v9359 = try o.lookup(&s, frame, "binding9319");
            const v9360 = try o.lookup(&s, frame, "binding9311");
            const v9361 = try o.call(&s, @src(), v9356, c.pi_js_undefined(), &.{ v9357, v9358, v9359, v9360 });
            break :conditional9348 v9361;
        }
    };
    return c.JS_DupValue(e.context, v9349);
}
fn body9363(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v9374 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9364", v9374);
    const v9375 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9365", v9375);
    const v9376 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9366", v9376);
    const v9377 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9367", v9377);
    const v9378 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9368", v9378);
    const v9379 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding9369", v9379);
    const v9384 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v9385 = try s.text("IsThen");
    const v9386 = try s.own(try js.getKey(e, v9384, v9385));
    const v9387 = try o.lookup(&s, frame, "binding9368");
    const v9388 = try o.call(&s, @src(), v9386, v9384, &.{v9387});
    const v9390 = conditional9389: {
        if (s.truthy(v9388)) {
            const v9391 = try o.lookup(&s, frame, "binding9368");
            const v9392 = try s.text("then");
            const v9393 = try s.own(try js.getKey(e, v9391, v9392));
            break :conditional9389 v9393;
        } else {
            break :conditional9389 o.boolean(&s, true);
        }
    };
    try o.assign(&s, frame, "binding9380", v9390);
    const v9394 = try o.importValue(&s, graph, "schema/types/index.mjs", "*");
    const v9395 = try s.text("IsElse");
    const v9396 = try s.own(try js.getKey(e, v9394, v9395));
    const v9397 = try o.lookup(&s, frame, "binding9368");
    const v9398 = try o.call(&s, @src(), v9396, v9394, &.{v9397});
    const v9400 = conditional9399: {
        if (s.truthy(v9398)) {
            const v9401 = try o.lookup(&s, frame, "binding9368");
            const v9402 = try s.text("else");
            const v9403 = try s.own(try js.getKey(e, v9401, v9402));
            break :conditional9399 v9403;
        } else {
            break :conditional9399 o.boolean(&s, true);
        }
    };
    try o.assign(&s, frame, "binding9381", v9400);
    const v9404 = try o.importValue(&s, graph, "schema/engine/_context.mjs", "ErrorContext");
    const v9405 = try o.construct(&s, v9404, &.{});
    try o.assign(&s, frame, "binding9382", v9405);
    const v9406 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchema");
    const v9407 = try o.lookup(&s, frame, "binding9364");
    const v9408 = try o.lookup(&s, frame, "binding9382");
    const v9409 = try s.text("");
    const v9410 = try o.lookup(&s, frame, "binding9366");
    const v9411 = try s.stringify(v9410);
    const v9412 = try s.concat(v9409, v9411);
    const v9413 = try s.text("/if");
    const v9414 = try s.concat(v9412, v9413);
    const v9415 = try o.lookup(&s, frame, "binding9367");
    const v9416 = try o.lookup(&s, frame, "binding9368");
    const v9417 = try s.text("if");
    const v9418 = try s.own(try js.getKey(e, v9416, v9417));
    const v9419 = try o.lookup(&s, frame, "binding9369");
    const v9420 = try o.call(&s, @src(), v9406, c.pi_js_undefined(), &.{ v9407, v9408, v9414, v9415, v9418, v9419 });
    const v9422 = conditional9421: {
        if (s.truthy(v9420)) {
            const v9423 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchema");
            const v9424 = try o.lookup(&s, frame, "binding9364");
            const v9425 = try o.lookup(&s, frame, "binding9382");
            const v9426 = try s.text("");
            const v9427 = try o.lookup(&s, frame, "binding9366");
            const v9428 = try s.stringify(v9427);
            const v9429 = try s.concat(v9426, v9428);
            const v9430 = try s.text("/then");
            const v9431 = try s.concat(v9429, v9430);
            const v9432 = try o.lookup(&s, frame, "binding9367");
            const v9433 = try o.lookup(&s, frame, "binding9380");
            const v9434 = try o.lookup(&s, frame, "binding9369");
            const v9435 = try o.call(&s, @src(), v9423, c.pi_js_undefined(), &.{ v9424, v9425, v9431, v9432, v9433, v9434 });
            const v9437 = logical9436: {
                if (s.truthy(v9435)) break :logical9436 v9435;
                const v9438 = try o.lookup(&s, frame, "binding9365");
                const v9439 = try s.text("AddError");
                const v9440 = try s.own(try js.getKey(e, v9438, v9439));
                const v9441 = try s.object();
                const v9442 = try s.text("keyword");
                const v9443 = try s.text("if");
                try o.defineKey(&s, v9441, v9442, v9443);
                const v9444 = try s.text("schemaPath");
                const v9445 = try o.lookup(&s, frame, "binding9366");
                try o.defineKey(&s, v9441, v9444, v9445);
                const v9446 = try s.text("instancePath");
                const v9447 = try o.lookup(&s, frame, "binding9367");
                try o.defineKey(&s, v9441, v9446, v9447);
                const v9448 = try s.text("params");
                const v9449 = try s.object();
                const v9450 = try s.text("failingKeyword");
                const v9451 = try s.text("then");
                try o.defineKey(&s, v9449, v9450, v9451);
                try o.defineKey(&s, v9441, v9448, v9449);
                const v9452 = try o.call(&s, @src(), v9440, v9438, &.{v9441});
                break :logical9436 v9452;
            };
            break :conditional9421 v9437;
        } else {
            const v9453 = try o.importValue(&s, graph, "schema/engine/schema.mjs", "ErrorSchema");
            const v9454 = try o.lookup(&s, frame, "binding9364");
            const v9455 = try o.lookup(&s, frame, "binding9365");
            const v9456 = try s.text("");
            const v9457 = try o.lookup(&s, frame, "binding9366");
            const v9458 = try s.stringify(v9457);
            const v9459 = try s.concat(v9456, v9458);
            const v9460 = try s.text("/else");
            const v9461 = try s.concat(v9459, v9460);
            const v9462 = try o.lookup(&s, frame, "binding9367");
            const v9463 = try o.lookup(&s, frame, "binding9381");
            const v9464 = try o.lookup(&s, frame, "binding9369");
            const v9465 = try o.call(&s, @src(), v9453, c.pi_js_undefined(), &.{ v9454, v9455, v9461, v9462, v9463, v9464 });
            const v9467 = logical9466: {
                if (s.truthy(v9465)) break :logical9466 v9465;
                const v9468 = try o.lookup(&s, frame, "binding9365");
                const v9469 = try s.text("AddError");
                const v9470 = try s.own(try js.getKey(e, v9468, v9469));
                const v9471 = try s.object();
                const v9472 = try s.text("keyword");
                const v9473 = try s.text("if");
                try o.defineKey(&s, v9471, v9472, v9473);
                const v9474 = try s.text("schemaPath");
                const v9475 = try o.lookup(&s, frame, "binding9366");
                try o.defineKey(&s, v9471, v9474, v9475);
                const v9476 = try s.text("instancePath");
                const v9477 = try o.lookup(&s, frame, "binding9367");
                try o.defineKey(&s, v9471, v9476, v9477);
                const v9478 = try s.text("params");
                const v9479 = try s.object();
                const v9480 = try s.text("failingKeyword");
                const v9481 = try s.text("else");
                try o.defineKey(&s, v9479, v9480, v9481);
                try o.defineKey(&s, v9471, v9478, v9479);
                const v9482 = try o.call(&s, @src(), v9470, v9468, &.{v9471});
                break :logical9466 v9482;
            };
            break :conditional9421 v9467;
        }
    };
    try o.assign(&s, frame, "binding9383", v9422);
    const v9483 = try o.lookup(&s, frame, "binding9383");
    if (s.truthy(v9483)) {
        const v9484 = try o.lookup(&s, frame, "binding9365");
        const v9485 = try s.text("Merge");
        const v9486 = try s.own(try js.getKey(e, v9484, v9485));
        const v9487 = try s.array();
        const v9488 = try o.lookup(&s, frame, "binding9382");
        try o.append(&s, v9487, v9488);
        const v9489 = try o.call(&s, @src(), v9486, v9484, &.{v9487});
        _ = v9489;
    }
    const v9490 = try o.lookup(&s, frame, "binding9383");
    return c.JS_DupValue(e.context, v9490);
}
