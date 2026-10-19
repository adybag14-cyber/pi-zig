//! Radius provider Source comparisons through the linked C runtime.
//! Controlled imports exercise the actual declaration, closures and genuine Awaits.
const std = @import("std");
const x = @import("extensions/native_ai_auth_helper_values.zig");
const c = x.c;
const subject = @import("extensions/native_ai_provider_radius.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/radius-provider-observer.mjs");

fn publish(engine: *x.em.Engine, name: [*:0]const u8, input: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, input));
}
fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
fn asyncBrand(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(ctx, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
fn makeNative(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return subject.createTestFactory(engine, if (argc > 0) argv[0] else c.pi_js_undefined())
        catch |err| @import("extensions/native_sdk.zig").fail(engine, err);
}
fn prepare(engine: *x.em.Engine, native: bool) !void {
    engine.native_io = std.testing.io;
    const hooks = try retirement.createNativeRetirementHooks(engine);
    defer engine.freeValue(hooks);
    try publish(engine, "radiusProviderHooks", hooks);
    const source = try engine.eval(@embedFile("extensions/fixtures/radius-provider-c268-source.mjs"),
        "actual-radius-provider-source-factory.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(source);
    const selected = if (native) try engine.checked(c.JS_NewCFunction(engine.context, makeNative, "radiusProviderMake", 1))
        else c.JS_DupValue(engine.context, source);
    defer engine.freeValue(selected);
    try publish(engine, "radiusProviderMake", selected);
    const brand = try engine.checked(c.JS_NewCFunction(engine.context, asyncBrand, "radiusProviderIsAsync", 1));
    defer engine.freeValue(brand);
    try publish(engine, "radiusProviderIsAsync", brand);
}
fn run(engine: *x.em.Engine, tail: []const u8) !void {
    const script = try std.mem.concat(engine.gpa, u8, &.{observer, "\n", tail});
    defer engine.gpa.free(script);
    const namespace = try engine.evalModule(script, "actual-radius-provider-observation.mjs");
    engine.freeValue(namespace);
}
fn clean(engine: *x.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn observe(native: bool, call: []const u8) ![]u8 {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
    defer engine.deinit();
    try prepare(engine, native);
    const tail = try std.fmt.allocPrint(engine.gpa, "globalThis.radiusProviderObservation=JSON.stringify(await {s});", .{call});
    defer engine.gpa.free(tail);
    try run(engine, tail);
    const result = try read(engine, "radiusProviderObservation");
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try clean(engine);
    return std.testing.allocator.dupe(u8, text);
}
fn compare(comptime observer_name: []const u8, comptime routes: anytype) !void {
    inline for (routes) |route| {
        const call = observer_name ++ "(\"" ++ route ++ "\")";
        const expected = try observe(false, call);
        defer std.testing.allocator.free(expected);
        const actual = try observe(true, call);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    }
}
fn both(comptime tail: []const u8) !void {
    inline for (.{false, true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        try run(engine, tail);
        try clean(engine);
    }
}

fn bothGc(comptime setup: []const u8, comptime retained: []const u8, comptime released: []const u8) !void {
    inline for (.{false,true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        try run(engine, setup);
        c.JS_RunGC(engine.runtime);
        try run(engine, retained);
        c.JS_RunGC(engine.runtime);
        try run(engine, released);
        try clean(engine);
    }
}
test "native Radius provider exact declaration defaults raw values and null failure" {
    try compare("observeRadiusProviderOrdinary", .{"default","undefined","null","nullish","raw"});
}
test "native Radius provider ordinary declaration has actual name length and constructability" {
    try both(
        \\const f=radiusProviderMake(radiusProviderMinimalImports());
        \\radiusProviderCheck(f.name==="radiusProvider"&&f.length===0&&!radiusProviderIsAsync(f)&&Object.hasOwn(f,"prototype"),"actual ordinary declaration");
        \\const p=new f({id:"constructed"});
        \\radiusProviderCheck(p.id==="constructed","ordinary constructor returns actual provider object");
    );
}
test "native Radius provider option getters and gateway normalization retain Source order" {
    try compare("observeRadiusProviderOrdinary", .{"option-ordered","option-id-throw","option-name-throw","option-gateway-throw","normalize-first-throw","normalize-second-throw"});
}
test "native Radius provider catalog selection shallow spread and escaped arrow identity" {
    try compare("observeRadiusProviderOrdinary", .{"custom-gateway","escaped-map"});
}
test "native Radius provider live Object values and map failures stop at exact operand" {
    try compare("observeRadiusProviderOrdinary", .{"values-get-throw","values-call-throw","map-get-throw","map-call-throw"});
}
test "native Radius provider imported streams and auth constructors retain selected call order" {
    try compare("observeRadiusProviderOrdinary", .{"api-throw","auth-key-throw","auth-lazy-throw"});
}
test "native Radius provider stream arrows forward exact receiver arguments and result" {
    try compare("observeRadiusProviderStreams", .{"stream","simple","stream-get-throw","stream-call-throw","simple-get-throw","simple-call-throw"});
}
test "native Radius provider lazy OAuth load arrow keeps captured name gateway and raw return" {
    try compare("observeRadiusProviderStreams", .{"oauth-load","oauth-load-throw"});
}
test "native Radius provider refresh is genuine async including zero Await offline exits" {
    try compare("observeRadiusProviderRefresh", .{"offline","already-aborted","missing-credential","null-credential","final-false"});
}
test "native Radius provider stored catalog filters without an invented map and shares updates" {
    try compare("observeRadiusProviderRefresh", .{"stored","stored-no-map","stored-offline","stored-false"});
}
test "native Radius provider stored and filter failures preserve exact callback boundary" {
    try compare("observeRadiusProviderRefresh", .{"stored-get-throw","stored-models-throw","filter-get-throw","filter-call-throw"});
}
test "native Radius provider legacy catalog preserves real length coercion and early publication" {
    try compare("observeRadiusProviderRefresh", .{"legacy","legacy-empty","legacy-length-coercion","legacy-offline","legacy-false"});
}
test "native Radius provider legacy call and length failures stop before network access" {
    try compare("observeRadiusProviderRefresh", .{"legacy-get-throw","legacy-length-throw"});
}
test "native Radius provider credential optional access retains repeated changing getter reads" {
    try compare("observeRadiusProviderRefresh", .{"changing-credential","oauth-access","credential-get-throw","credential-type-throw","credential-key-throw","credential-access-throw"});
}
test "native Radius provider network and signal gates preserve truthiness and abrupt completion" {
    try compare("observeRadiusProviderRefresh", .{"allow-throw","signal-get-throw","aborted-get-throw","signal-aborted-order","late-abort"});
}
test "native Radius provider config call and genuine Await retain exact rejection values" {
    try compare("observeRadiusProviderRefresh", .{"config-load-throw","config-then-throw","config-reject","config-map-throw"});
}
test "native Radius provider publication lookup call and Await stop at the exact operation" {
    try compare("observeRadiusProviderRefresh", .{"publish-get-throw","publish-call-throw","publish-then-throw","publish-reject"});
}
test "native Radius provider persisted publication retains Date now expression order" {
    try compare("observeRadiusProviderRefresh", .{"date-get-throw","date-call-throw","legacy"});
}
test "native Radius provider delayed update arrows retain distinct shared lexical bindings" {
    try compare("observeRadiusProviderRefresh", .{"delayed-update"});
}
test "native Radius provider Object values callee retires before following map lookup" {
    try both(
        \\const h=radiusProviderHooks,imports=radiusProviderMinimalImports(),f=radiusProviderMake(imports);
        \\const original=Object.getOwnPropertyDescriptor(Object,"values");let retired=false;
        \\Object.defineProperty(Object,"values",{configurable:true,get(){const call=function(){return {get map(){retired=h.count(0)===1;return function(){return [];};}};};call.holder=h.make(0);return call;}});
        \\try{f();radiusProviderCheck(retired&&h.count(0)===1,"values callable retires before map");}
        \\finally{Object.defineProperty(Object,"values",original);}
    );
}
test "native Radius provider getModels closure releases unrelated options names and streams" {
    try both(
        \\const h=radiusProviderHooks;let getModels;
        \\(function(){const imports=radiusProviderMinimalImports();imports.piMessagesApi=()=>({holder:h.make(3),stream(){},streamSimple(){}});
        \\ const f=radiusProviderMake(imports),p=f({id:{holder:h.make(0)},name:{holder:h.make(1)},gateway:"custom",extra:h.make(2)});getModels=p.getModels;})();
        \\radiusProviderCheck(getModels().length===0,"custom gateway has actual empty baseline");
        \\for(let i=0;i<4;i++)radiusProviderCheck(h.count(i)===1,"unrelated sole holder retired "+i);
        \\getModels=null;
    );
}
test "native Radius provider actual baseline stays alive through its sole getModels cell" {
    try both(
        \\const h=radiusProviderHooks;let getModels;
        \\(function(){const imports=radiusProviderMinimalImports();imports.RADIUS_MODELS.one.holder=h.make(0);getModels=radiusProviderMake(imports)().getModels;})();
        \\radiusProviderCheck(h.count(0)===0&&getModels().length===1,"actual baseline holder retained");
        \\getModels=null;radiusProviderCheck(h.count(0)===1,"sole baseline cell released once");
    );
}
test "native Radius provider restored block closure detaches before abandoned config Await" {
    try bothGc(
        \\radiusProviderPrepareAbandonedBlock("stored");await Promise.resolve();await Promise.resolve();
        \\radiusProviderCheck(globalThis.radiusProviderLoadReached===true,"actual later config Await reached");
        ,
        \\const h=radiusProviderHooks;radiusProviderCheck(h.count(0)===1&&h.count(2)===1&&h.count(1)===0,"closed restored cell releases unrelated actual coroutine roots");
        \\globalThis.radiusProviderRetainedUpdate();globalThis.radiusProviderRetainedUpdate=null;
        ,
        \\radiusProviderCheck(radiusProviderHooks.count(1)===1,"restored sole captured value retires after update removal");
    );
}
test "native Radius provider legacy block closure detaches before abandoned config Await" {
    try bothGc(
        \\radiusProviderPrepareAbandonedBlock("legacy");await Promise.resolve();await Promise.resolve();
        \\radiusProviderCheck(globalThis.radiusProviderLoadReached===true,"actual later config Await reached");
        ,
        \\const h=radiusProviderHooks;radiusProviderCheck(h.count(0)===1&&h.count(2)===1&&h.count(1)===0,"closed legacy cell releases unrelated actual coroutine roots");
        \\globalThis.radiusProviderRetainedUpdate();globalThis.radiusProviderRetainedUpdate=null;
        ,
        \\radiusProviderCheck(radiusProviderHooks.count(1)===1,"legacy sole captured value retires after update removal");
    );
}
test "native Radius provider open refreshed cell retains real abandoned final publication" {
    try bothGc(
        \\radiusProviderPrepareAbandonedFinalPublish();await Promise.resolve();await Promise.resolve();
        \\radiusProviderCheck(globalThis.radiusProviderPublishReached===true,"actual final publication Await reached");
        ,
        \\const h=radiusProviderHooks;for(let i=0;i<3;i++)radiusProviderCheck(h.count(i)===0,"actual open cell retains coroutine root "+i);
        \\globalThis.radiusProviderRetainedUpdate=null;
        ,
        \\const h=radiusProviderHooks;for(let i=0;i<3;i++)radiusProviderCheck(h.count(i)===1,"removed open cell permits actual coroutine retirement "+i);
    );
}
test "native Radius provider same-operation private DATA remains an ordinary rejection" {
    try both(
        \\const h=radiusProviderHooks,imports=radiusProviderMinimalImports();let reason,caught;
        \\imports.loadRadiusGatewayConfig=()=>{reason=h.freshPrivateData();throw reason;};
        \\try{await radiusProviderMake(imports)().refreshModels({allowNetwork:true,signal:{aborted:false}});}catch(error){caught=error;}
        \\radiusProviderCheck(caught===reason&&h.isUnmarkedPrivateData(caught),"same-operation private DATA preserves ordinary rejection");
    );
}
test "native Radius provider actual native fatal preempts continuation and guest catch" {
    inline for (.{false,true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        const hooks = try read(engine, "radiusProviderHooks");
        defer engine.freeValue(hooks);
        const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
        defer engine.freeValue(record);
        try std.testing.expectError(error.JavaScriptException, run(engine, "await observeRadiusProviderActualFatal();"));
        try retirement.verifyRecordedActualNativeFatal(engine, record);
        try retirement.verifyNoVisits(record, .{3});
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
