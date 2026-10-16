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
    const namespace = try s.get(modules, "schema/build.mjs");
    const frame = try o.frame(&s, c.pi_js_null());
    try s.put(frame, "@this", c.pi_js_undefined());
    try s.put(try s.get(graph, "frames"), "schema/build.mjs", frame);
    const bindings = try s.object();
    try s.put(try s.get(graph, "bindings"), "schema/build.mjs", bindings);
    const v3264 = try s.own(try ordinary.create(e, "CreateCode", 1, body3207, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3200", v3264);
    const v3266 = try s.own(try ordinary.create(e, "CreateEvaluatedCheck", 2, native_lower3265, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3201", v3266);
    const v3306 = try s.own(try ordinary.create(e, "CreateDynamicCheck", 1, body3267, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3202", v3306);
    const v3325 = try s.own(try ordinary.create(e, "CreateCheck", 2, body3307, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3203", v3325);
    const v3423 = try s.own(try ordinary.create(e, "Build", 0, body3326, &.{ graph, frame }));
    try o.assign(&s, frame, "binding3206", v3423);
    const v3424 = try o.lookup(&s, frame, "binding3206");
    try s.put(namespace, "Build", v3424);
    const v3425 = try s.object();
    const v3439 = try s.own(try class.constructor(e, "EvaluateResult", 3, v3425, constructor3426, &.{ graph, frame, c.pi_js_undefined() }));
    const v3443 = try o.arrow(&s, "IsAccelerated", 0, body3440C, &.{ graph, frame });
    try o.method(&s, v3425, "IsAccelerated", v3443);
    const v3447 = try o.arrow(&s, "Code", 0, body3444C, &.{ graph, frame });
    try o.method(&s, v3425, "Code", v3447);
    const v3455 = try o.arrow(&s, "Check", 1, body3448C, &.{ graph, frame });
    try o.method(&s, v3425, "Check", v3455);
    try o.assign(&s, frame, "binding3204", v3439);
    const v3456 = try s.object();
    const v3482 = try s.own(try class.constructor(e, "BuildResult", 6, v3456, constructor3457, &.{ graph, frame, c.pi_js_undefined() }));
    const v3486 = try o.arrow(&s, "Context", 0, body3483C, &.{ graph, frame });
    try o.method(&s, v3456, "Context", v3486);
    const v3490 = try o.arrow(&s, "Schema", 0, body3487C, &.{ graph, frame });
    try o.method(&s, v3456, "Schema", v3490);
    const v3494 = try o.arrow(&s, "UseUnevaluated", 0, body3491C, &.{ graph, frame });
    try o.method(&s, v3456, "UseUnevaluated", v3494);
    const v3498 = try o.arrow(&s, "External", 0, body3495C, &.{ graph, frame });
    try o.method(&s, v3456, "External", v3498);
    const v3502 = try o.arrow(&s, "Functions", 0, body3499C, &.{ graph, frame });
    try o.method(&s, v3456, "Functions", v3502);
    const v3506 = try o.arrow(&s, "Entry", 0, body3503C, &.{ graph, frame });
    try o.method(&s, v3456, "Entry", v3506);
    const v3525 = try o.arrow(&s, "Evaluate", 0, body3507C, &.{ graph, frame });
    try o.method(&s, v3456, "Evaluate", v3525);
    try o.assign(&s, frame, "binding3205", v3482);
    const v3526 = try o.lookup(&s, frame, "binding3206");
    try s.put(namespace, "Build", v3526);
    const v3527 = try o.lookup(&s, frame, "binding3204");
    try s.put(namespace, "EvaluateResult", v3527);
    const v3528 = try o.lookup(&s, frame, "binding3205");
    try s.put(namespace, "BuildResult", v3528);
    try s.put(bindings, "Build", try s.text("binding3206"));
    try s.put(bindings, "EvaluateResult", try s.text("binding3204"));
    try s.put(bindings, "BuildResult", try s.text("binding3205"));
}
fn body3207(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3211 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3208", v3211);
    const v3214 = try o.lookup(&s, frame, "binding3208");
    const v3215 = try s.text("Functions");
    const v3216 = try s.own(try js.getKey(e, v3214, v3215));
    const v3217 = try o.call(&s, @src(), v3216, v3214, &.{});
    const v3218 = try s.text("join");
    const v3219 = try s.own(try js.getKey(e, v3217, v3218));
    const v3220 = try s.text(";\n");
    const v3221 = try o.call(&s, @src(), v3219, v3217, &.{v3220});
    try o.assign(&s, frame, "binding3212", v3221);
    const v3222 = try o.lookup(&s, frame, "binding3208");
    const v3223 = try s.text("UseUnevaluated");
    const v3224 = try s.own(try js.getKey(e, v3222, v3223));
    const v3225 = try o.call(&s, @src(), v3224, v3222, &.{});
    const v3227 = conditional3226: {
        if (s.truthy(v3225)) {
            const v3228 = try s.array();
            const v3229 = try s.text("const context = new CheckContext({}, {})");
            try o.append(&s, v3228, v3229);
            const v3230 = try s.text("return ");
            const v3231 = try o.lookup(&s, frame, "binding3208");
            const v3232 = try s.text("Entry");
            const v3233 = try s.own(try js.getKey(e, v3231, v3232));
            const v3234 = try o.call(&s, @src(), v3233, v3231, &.{});
            const v3235 = try s.stringify(v3234);
            const v3236 = try s.concat(v3230, v3235);
            const v3237 = try s.text("");
            const v3238 = try s.concat(v3236, v3237);
            try o.append(&s, v3228, v3238);
            break :conditional3226 v3228;
        } else {
            const v3239 = try s.array();
            const v3240 = try s.text("return ");
            const v3241 = try o.lookup(&s, frame, "binding3208");
            const v3242 = try s.text("Entry");
            const v3243 = try s.own(try js.getKey(e, v3241, v3242));
            const v3244 = try o.call(&s, @src(), v3243, v3241, &.{});
            const v3245 = try s.stringify(v3244);
            const v3246 = try s.concat(v3240, v3245);
            const v3247 = try s.text("");
            const v3248 = try s.concat(v3246, v3247);
            try o.append(&s, v3239, v3248);
            break :conditional3226 v3239;
        }
    };
    try o.assign(&s, frame, "binding3213", v3227);
    const v3249 = try s.text("");
    const v3250 = try o.lookup(&s, frame, "binding3212");
    const v3251 = try s.stringify(v3250);
    const v3252 = try s.concat(v3249, v3251);
    const v3253 = try s.text("; return (value) => { ");
    const v3254 = try s.concat(v3252, v3253);
    const v3255 = try o.lookup(&s, frame, "binding3213");
    const v3256 = try s.text("join");
    const v3257 = try s.own(try js.getKey(e, v3255, v3256));
    const v3258 = try s.text("; ");
    const v3259 = try o.call(&s, @src(), v3257, v3255, &.{v3258});
    const v3260 = try s.stringify(v3259);
    const v3261 = try s.concat(v3254, v3260);
    const v3262 = try s.text(" }");
    const v3263 = try s.concat(v3261, v3262);
    return c.JS_DupValue(e.context, v3263);
}
fn native_lower3265(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    return @import("native_typebox_compile_ir.zig").createCheck(e, roots[0], args[0], args[1]);
}
fn body3290(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3293 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3292", v3293);
    const v3294 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3295 = try s.text("CheckSchema");
    const v3296 = try s.own(try js.getKey(e, v3294, v3295));
    const v3297 = try o.lookup(&s, frame, "binding3272");
    const v3298 = try o.lookup(&s, frame, "binding3273");
    const v3299 = try o.lookup(&s, frame, "binding3268");
    const v3300 = try s.text("Schema");
    const v3301 = try s.own(try js.getKey(e, v3299, v3300));
    const v3302 = try o.call(&s, @src(), v3301, v3299, &.{});
    const v3303 = try o.lookup(&s, frame, "binding3292");
    const v3304 = try o.call(&s, @src(), v3296, v3294, &.{ v3297, v3298, v3302, v3303 });
    return c.JS_DupValue(e.context, v3304);
}
fn body3290C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3290(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3267(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3271 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3268", v3271);
    const v3274 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3275 = try s.text("Stack");
    const v3276 = try s.own(try js.getKey(e, v3274, v3275));
    const v3277 = try o.lookup(&s, frame, "binding3268");
    const v3278 = try s.text("Context");
    const v3279 = try s.own(try js.getKey(e, v3277, v3278));
    const v3280 = try o.call(&s, @src(), v3279, v3277, &.{});
    const v3281 = try o.lookup(&s, frame, "binding3268");
    const v3282 = try s.text("Schema");
    const v3283 = try s.own(try js.getKey(e, v3281, v3282));
    const v3284 = try o.call(&s, @src(), v3283, v3281, &.{});
    const v3285 = try o.construct(&s, v3276, &.{ v3280, v3284 });
    try o.assign(&s, frame, "binding3272", v3285);
    const v3286 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3287 = try s.text("CheckContext");
    const v3288 = try s.own(try js.getKey(e, v3286, v3287));
    const v3289 = try o.construct(&s, v3288, &.{});
    try o.assign(&s, frame, "binding3273", v3289);
    const v3305 = try o.arrow(&s, "", 1, body3290C, &.{ graph, frame });
    return c.JS_DupValue(e.context, v3305);
}
fn body3307(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3310 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3308", v3310);
    const v3311 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3309", v3311);
    const v3312 = try o.importValue(&s, graph, "system/environment/index.mjs", "Environment");
    const v3313 = try s.text("CanEvaluate");
    const v3314 = try s.own(try js.getKey(e, v3312, v3313));
    const v3315 = try o.call(&s, @src(), v3314, v3312, &.{});
    const v3317 = conditional3316: {
        if (s.truthy(v3315)) {
            const v3318 = try o.lookup(&s, frame, "binding3201");
            const v3319 = try o.lookup(&s, frame, "binding3308");
            const v3320 = try o.lookup(&s, frame, "binding3309");
            const v3321 = try o.call(&s, @src(), v3318, c.pi_js_undefined(), &.{ v3319, v3320 });
            break :conditional3316 v3321;
        } else {
            const v3322 = try o.lookup(&s, frame, "binding3202");
            const v3323 = try o.lookup(&s, frame, "binding3308");
            const v3324 = try o.call(&s, @src(), v3322, c.pi_js_undefined(), &.{v3323});
            break :conditional3316 v3324;
        }
    };
    return c.JS_DupValue(e.context, v3317);
}
fn body3349(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3353 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3351", v3353);
    const v3354 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3352", v3354);
    const v3355 = try s.array();
    const v3356 = try o.lookup(&s, frame, "binding3351");
    try o.append(&s, v3355, v3356);
    const v3357 = try o.lookup(&s, frame, "binding3352");
    try o.append(&s, v3355, v3357);
    return c.JS_DupValue(e.context, v3355);
}
fn body3349C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3349(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3360(e: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    _ = try o.lookup(&s, frame, "@this");
    const v3363 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3362", v3363);
    const v3364 = try s.array();
    const v3365 = try s.object();
    try o.append(&s, v3364, v3365);
    const v3366 = try o.lookup(&s, frame, "binding3362");
    try o.append(&s, v3364, v3366);
    return c.JS_DupValue(e.context, v3364);
}
fn body3360C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3360(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3326(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3335 = try o.rest(&s, args, 0);
    try o.assign(&s, frame, "binding3327", v3335);
    const v3343 = try o.importValue(&s, graph, "system/arguments/index.mjs", "Arguments");
    const v3344 = try s.text("Match");
    const v3345 = try s.own(try js.getKey(e, v3343, v3344));
    const v3346 = try o.lookup(&s, frame, "binding3327");
    const v3347 = try s.object();
    const v3348 = try s.text("2");
    const v3358 = try o.arrow(&s, "2", 2, body3349C, &.{ graph, frame });
    try o.defineKey(&s, v3347, v3348, v3358);
    const v3359 = try s.text("1");
    const v3367 = try o.arrow(&s, "1", 1, body3360C, &.{ graph, frame });
    try o.defineKey(&s, v3347, v3359, v3367);
    const v3368 = try o.call(&s, @src(), v3345, v3343, &.{ v3346, v3347 });
    var destructure3369 = try o.iterator(e, v3368);
    defer destructure3369.deinit();
    errdefer destructure3369.closePreserving();
    const v3370 = try s.own(if (destructure3369.closed) c.pi_js_undefined() else (try destructure3369.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding3336", v3370);
    const v3371 = try s.own(if (destructure3369.closed) c.pi_js_undefined() else (try destructure3369.next()) orelse c.pi_js_undefined());
    try o.assign(&s, frame, "binding3337", v3371);
    try destructure3369.close();
    const v3372 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3373 = try s.text("ResetExternal");
    const v3374 = try s.own(try js.getKey(e, v3372, v3373));
    const v3375 = try o.call(&s, @src(), v3374, v3372, &.{});
    _ = v3375;
    const v3376 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3377 = try s.text("ResetFunctions");
    const v3378 = try s.own(try js.getKey(e, v3376, v3377));
    const v3379 = try o.call(&s, @src(), v3378, v3376, &.{});
    _ = v3379;
    const v3380 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3381 = try s.text("Stack");
    const v3382 = try s.own(try js.getKey(e, v3380, v3381));
    const v3383 = try o.lookup(&s, frame, "binding3336");
    const v3384 = try o.lookup(&s, frame, "binding3337");
    const v3385 = try o.construct(&s, v3382, &.{ v3383, v3384 });
    try o.assign(&s, frame, "binding3338", v3385);
    const v3386 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3387 = try s.text("BuildContext");
    const v3388 = try s.own(try js.getKey(e, v3386, v3387));
    const v3389 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3390 = try s.text("HasUnevaluated");
    const v3391 = try s.own(try js.getKey(e, v3389, v3390));
    const v3392 = try o.lookup(&s, frame, "binding3336");
    const v3393 = try o.lookup(&s, frame, "binding3337");
    const v3394 = try o.call(&s, @src(), v3391, v3389, &.{ v3392, v3393 });
    const v3395 = try o.construct(&s, v3388, &.{v3394});
    try o.assign(&s, frame, "binding3339", v3395);
    const v3396 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3397 = try s.text("CreateFunction");
    const v3398 = try s.own(try js.getKey(e, v3396, v3397));
    const v3399 = try o.lookup(&s, frame, "binding3338");
    const v3400 = try o.lookup(&s, frame, "binding3339");
    const v3401 = try o.lookup(&s, frame, "binding3337");
    const v3402 = try s.text("value");
    const v3403 = try o.call(&s, @src(), v3398, v3396, &.{ v3399, v3400, v3401, v3402 });
    try o.assign(&s, frame, "binding3340", v3403);
    const v3404 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3405 = try s.text("GetFunctions");
    const v3406 = try s.own(try js.getKey(e, v3404, v3405));
    const v3407 = try o.call(&s, @src(), v3406, v3404, &.{});
    try o.assign(&s, frame, "binding3341", v3407);
    const v3408 = try o.importValue(&s, graph, "schema/engine/index.mjs", "*");
    const v3409 = try s.text("GetExternal");
    const v3410 = try s.own(try js.getKey(e, v3408, v3409));
    const v3411 = try o.call(&s, @src(), v3410, v3408, &.{});
    try o.assign(&s, frame, "binding3342", v3411);
    const v3412 = try o.lookup(&s, frame, "binding3205");
    const v3413 = try o.lookup(&s, frame, "binding3336");
    const v3414 = try o.lookup(&s, frame, "binding3337");
    const v3415 = try o.lookup(&s, frame, "binding3342");
    const v3416 = try o.lookup(&s, frame, "binding3341");
    const v3417 = try o.lookup(&s, frame, "binding3340");
    const v3418 = try o.lookup(&s, frame, "binding3339");
    const v3419 = try s.text("UseUnevaluated");
    const v3420 = try s.own(try js.getKey(e, v3418, v3419));
    const v3421 = try o.call(&s, @src(), v3420, v3418, &.{});
    const v3422 = try o.construct(&s, v3412, &.{ v3413, v3414, v3415, v3416, v3417, v3421 });
    return c.JS_DupValue(e.context, v3422);
}
fn constructor3426(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v3430 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3427", v3430);
    const v3431 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3428", v3431);
    const v3432 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3429", v3432);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v3433 = try s.text("isAccelerated");
    const v3434 = try o.lookup(&s, frame, "binding3427");
    try js.setKey(e, receiver, v3433, v3434);
    const v3435 = try s.text("code");
    const v3436 = try o.lookup(&s, frame, "binding3428");
    try js.setKey(e, receiver, v3435, v3436);
    const v3437 = try s.text("check");
    const v3438 = try o.lookup(&s, frame, "binding3429");
    try js.setKey(e, receiver, v3437, v3438);
    return c.JS_DupValue(e.context, receiver);
}
fn body3440(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3441 = try s.text("isAccelerated");
    const v3442 = try s.own(try js.getKey(e, receiver, v3441));
    return c.JS_DupValue(e.context, v3442);
}
fn body3440C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3440(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3444(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3445 = try s.text("code");
    const v3446 = try s.own(try js.getKey(e, receiver, v3445));
    return c.JS_DupValue(e.context, v3446);
}
fn body3444C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3444(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3448(e: *Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3450 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3449", v3450);
    const v3451 = try s.text("check");
    const v3452 = try s.own(try js.getKey(e, receiver, v3451));
    const v3453 = try o.lookup(&s, frame, "binding3449");
    const v3454 = try o.call(&s, @src(), v3452, receiver, &.{v3453});
    return c.JS_DupValue(e.context, v3454);
}
fn body3448C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3448(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn constructor3457(e: *Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    const v3464 = if (args.len > 0) args[0] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3458", v3464);
    const v3465 = if (args.len > 1) args[1] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3459", v3465);
    const v3466 = if (args.len > 2) args[2] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3460", v3466);
    const v3467 = if (args.len > 3) args[3] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3461", v3467);
    const v3468 = if (args.len > 4) args[4] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3462", v3468);
    const v3469 = if (args.len > 5) args[5] else c.pi_js_undefined();
    try o.assign(&s, frame, "binding3463", v3469);
    const receiver = try s.own(try class.object(e, target));
    try s.put(frame, "@this", receiver);
    const v3470 = try s.text("context");
    const v3471 = try o.lookup(&s, frame, "binding3458");
    try js.setKey(e, receiver, v3470, v3471);
    const v3472 = try s.text("schema");
    const v3473 = try o.lookup(&s, frame, "binding3459");
    try js.setKey(e, receiver, v3472, v3473);
    const v3474 = try s.text("external");
    const v3475 = try o.lookup(&s, frame, "binding3460");
    try js.setKey(e, receiver, v3474, v3475);
    const v3476 = try s.text("functions");
    const v3477 = try o.lookup(&s, frame, "binding3461");
    try js.setKey(e, receiver, v3476, v3477);
    const v3478 = try s.text("entry");
    const v3479 = try o.lookup(&s, frame, "binding3462");
    try js.setKey(e, receiver, v3478, v3479);
    const v3480 = try s.text("useUnevaluated");
    const v3481 = try o.lookup(&s, frame, "binding3463");
    try js.setKey(e, receiver, v3480, v3481);
    return c.JS_DupValue(e.context, receiver);
}
fn body3483(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3484 = try s.text("context");
    const v3485 = try s.own(try js.getKey(e, receiver, v3484));
    return c.JS_DupValue(e.context, v3485);
}
fn body3483C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3483(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3487(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3488 = try s.text("schema");
    const v3489 = try s.own(try js.getKey(e, receiver, v3488));
    return c.JS_DupValue(e.context, v3489);
}
fn body3487C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3487(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3491(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3492 = try s.text("useUnevaluated");
    const v3493 = try s.own(try js.getKey(e, receiver, v3492));
    return c.JS_DupValue(e.context, v3493);
}
fn body3491C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3491(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3495(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3496 = try s.text("external");
    const v3497 = try s.own(try js.getKey(e, receiver, v3496));
    return c.JS_DupValue(e.context, v3497);
}
fn body3495C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3495(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3499(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3500 = try s.text("functions");
    const v3501 = try s.own(try js.getKey(e, receiver, v3500));
    return c.JS_DupValue(e.context, v3501);
}
fn body3499C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3499(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3503(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3504 = try s.text("entry");
    const v3505 = try s.own(try js.getKey(e, receiver, v3504));
    return c.JS_DupValue(e.context, v3505);
}
fn body3503C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3503(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
fn body3507(e: *Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = roots[0];
    const frame = try o.frame(&s, roots[1]);
    try s.put(frame, "@this", receiver);
    const v3512 = try o.lookup(&s, frame, "binding3200");
    const v3513 = try o.call(&s, @src(), v3512, c.pi_js_undefined(), &.{receiver});
    try o.assign(&s, frame, "binding3510", v3513);
    const v3514 = try o.lookup(&s, frame, "binding3203");
    const v3515 = try o.lookup(&s, frame, "binding3510");
    const v3516 = try o.call(&s, @src(), v3514, c.pi_js_undefined(), &.{ receiver, v3515 });
    try o.assign(&s, frame, "binding3511", v3516);
    const v3517 = try o.lookup(&s, frame, "binding3204");
    const v3518 = try o.importValue(&s, graph, "system/environment/index.mjs", "Environment");
    const v3519 = try s.text("CanEvaluate");
    const v3520 = try s.own(try js.getKey(e, v3518, v3519));
    const v3521 = try o.call(&s, @src(), v3520, v3518, &.{});
    const v3522 = try o.lookup(&s, frame, "binding3510");
    const v3523 = try o.lookup(&s, frame, "binding3511");
    const v3524 = try o.construct(&s, v3517, &.{ v3521, v3522, v3523 });
    return c.JS_DupValue(e.context, v3524);
}
fn body3507C(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(ctx.?);
    return body3507(e, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots[0..2]) catch |err| sdk.fail(e, err);
}
