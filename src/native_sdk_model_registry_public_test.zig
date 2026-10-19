//! Genuine c268 ModelRegistry class on the actual installed SDK actor.
//! Fresh Source/native Engines. Controlled ModelRuntime arguments are public
//! inputs; the native class, VM Await/spread/constructor and lease are real.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const h = @import("extensions/native_sdk_session_locals.zig");
const sdk = @import("extensions/native_sdk.zig");
const registry = @import("extensions/native_sdk_model_registry_public.zig");
const bridge = @import("extensions/native_sdk_model_bridge.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const c = v.c;
const observer = @embedFile("extensions/fixtures/sdk-model-registry-observer.mjs");
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn asyncBrand(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
fn prepare(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *v.Scope) !void {
    const engine = s.engine;
    engine.native_io = std.testing.io;
    try @import("extensions/native_stream.zig").install(engine);
    const exports = try v.object(s);
    try sdk.install(engine, exports);
    const actual = try v.get(s, exports, "ModelRegistry");
    try std.testing.expect(v.equal(s, actual, try v.own(s, try registry.constructor(engine))));
    const source_factory = try v.own(s, try engine.eval(
        @embedFile("extensions/fixtures/sdk-model-registry-c268-source.mjs"),
        "actual-model-registry-source-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, source_factory, c.pi_js_undefined(), &.{});
    try publish(s, "ModelRegistryNative", actual);
    try publish(s, "ModelRegistrySource", reference);
    try publish(s, "registrySdkExports", exports);
    try publish(s, "registryHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
    try publish(s, "registryIsAsync", try v.own(s, try engine.checked(
        c.JS_NewCFunction(engine.context, asyncBrand, "registryIsAsync", 1))));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-model-registry-control.mjs");
    engine.freeValue(result);
}
fn clean(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn both(comptime name: []const u8, comptime argument: []const u8) !void {
    inline for (.{ "ModelRegistrySource", "ModelRegistryNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\nawait " ++ name ++ "(" ++ subject ++ ",registryHooks" ++ argument ++ ");\n");
        try clean(engine);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    return h.expression(engine, recordBody, .{});
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "registryHooks"), "record"));
}
test "SDK public ModelRegistry actual class descriptors and both VM async brands" {
    try both("observeRegistryShapes", "");
}
test "SDK public ModelRegistry own field and actual newTarget construction" {
    try both("observeRegistryConstructor", "");
}
test "SDK public ModelRegistry unbranded runtime replacement retires its sole root" {
    try both("observeRegistryRuntimeRetirement", "");
}
test "SDK public ModelRegistry all ordinary delegation argument counts and result identity" {
    try both("observeRegistryDelegation", "");
}
test "SDK public ModelRegistry runtime callee selection precedes provider argument getter" {
    try both("observeRegistryProviderArguments", "");
}
test "SDK public ModelRegistry optional provider name reads primitives and preserves nullish fallback" {
    try both("observeRegistryDisplayName", "");
}
test "SDK public ModelRegistry snapshots use intrinsic literal and real iterator" {
    try both("observeRegistrySnapshots", "");
}
test "SDK public ModelRegistry call receiver and callee retire before snapshot iterator" {
    inline for (.{ "ModelRegistrySource", "ModelRegistryNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\nglobalThis.registryPrepared=observeRegistrySnapshotRetirement(" ++ subject ++ ",registryHooks);");
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        engine.finishJob();
        try run(engine, "registryPrepared();delete globalThis.registryPrepared;");
        try clean(engine);
    }
}
test "SDK public ModelRegistry void methods discard actual returned owners" {
    try both("observeRegistryVoids", "");
}
test "SDK public ModelRegistry missing registration config constructs live Error before runtime" {
    try both("observeRegistryRegistrationError", "");
}
test "SDK public ModelRegistry two actual async bodies suspend and use intrinsic promises" {
    try both("observeRegistryAwait", "");
}
test "SDK public ModelRegistry resolved auth rereads exact fields and retires predicate operands" {
    try both("observeRegistryResolved", "");
}
test "SDK public ModelRegistry compatibility path rereads runtime and consumes authHeader predicate" {
    try both("observeRegistryCompatibility", "");
}
test "SDK public ModelRegistry catch uses actual live repeated instanceof and cause selection" {
    try both("observeRegistryCatchSelection", "");
}
test "SDK public ModelRegistry global String result and catch abrupt identity remain actual" {
    try both("observeRegistryCatchStringAndAbrupt", "");
}
test "SDK public ModelRegistry missing key templates use intrinsic string hint conversion" {
    try both("observeRegistryMissingTemplate", "");
}
test "SDK public ModelRegistry key method optional access and ordinary empty catch" {
    try both("observeRegistryKey", "");
}
test "SDK public ModelRegistry private DATA stays ordinary before and after Await" {
    try both("observeRegistryData", ",\"headers:start\"");
    try both("observeRegistryData", ",\"headers:after\"");
    try both("observeRegistryData", ",\"key:start\"");
    try both("observeRegistryData", ",\"key:after\"");
}
test "SDK public ModelRegistry arguments and resolution survive actual Await and return adoption" {
    try both("observeRegistryAwaitLifetime", "");
}
test "SDK public ModelRegistry catch locals survive return adoption then retire" {
    try both("observeRegistryCatchLifetime", "");
}
test "SDK public ModelRegistry actual reaction input outlives key adoption until its job ends" {
    try both("observeRegistryKeyAdoption", "");
}
test "SDK public ModelRegistry current B bypasses both ordinary async catches" {
    inline for (.{ "", ",true" }) |key| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
        const original = try record(engine); defer engine.freeValue(original);
        try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
            "\nawait observeRegistryCurrentFatal(ModelRegistryNative,registryHooks" ++ key ++ ");"));
        try retirement.verifyRecordedActualNativeFatal(engine, original);
        try retirement.verifyNoVisits(original, .{ 1, 2, 3 });
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "SDK public ModelRegistry post Await predicate retirement B skips provider and catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeRegistryPredicateStop(ModelRegistryNative,registryHooks,false);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    try retirement.verifyNoVisits(original, .{ 1, 2, 3 });
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public ModelRegistry post Await cancellation skips later fields and catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeRegistryPredicateStop(ModelRegistryNative,registryHooks,true);"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
    try retirement.verifyNoVisits(original, .{3});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
fn foreignBody(s: *v.Scope, foreign: c.JSValue) !void { try publish(s, "registryForeign", foreign); }
test "SDK public ModelRegistry newTarget primitive prototype falls back to the actual foreign realm" {
    inline for (.{ "ModelRegistrySource", "ModelRegistryNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
        const context = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
        defer c.JS_FreeContext(context);
        const source =
            \\(function(){function ForeignTarget(){};ForeignTarget.prototype=0;return {target:ForeignTarget,objectPrototype:Object.prototype}})()
        ;
        const foreign = try engine.checked(c.JS_Eval(context, source, source.len, "actual-foreign-registry-realm.js", c.JS_EVAL_TYPE_GLOBAL));
        defer engine.freeValue(foreign);
        try h.statement(engine, foreignBody, .{foreign});
        try run(engine, observer ++ "\nobserveRegistryForeignTarget(" ++ subject ++ ",registryForeign);");
        try clean(engine);
    }
}
test "SDK public ModelRegistry uses the actual SDK state and completed constructor identity" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const actual = try registry.constructor(engine); defer engine.freeValue(actual);
    const again = try registry.constructor(engine); defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, again));
    const receiver = try engine.eval("new ModelRegistryNative({})", "actual-registry-sdk-state.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(receiver);
    const owner = try sdk.state(engine, receiver);
    try std.testing.expect(owner.kind == .model_registry);
    try std.testing.expectError(error.NativeSDKModelLeaseUnavailable, sdk.modelRegistryLease(engine, receiver));
    try clean(engine);
}
fn fixtureAuthPath(s: *v.Scope, path: []const u8) !void {
    try publish(s, "registryFixtureAuthPath", try v.text(s, path));
}
test "SDK public ModelRegistry real branded runtime retains its original independent lease" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    const auth_path = try std.fs.path.join(std.testing.allocator, &.{path[0..count], "absent-auth.json"});
    defer std.testing.allocator.free(auth_path);
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try h.statement(engine, fixtureAuthPath, .{auth_path});
    try run(engine,
        \\import "@earendil-works/pi-ai";
        \\globalThis.registryRealRuntime=new registrySdkExports.ModelRuntime({authPath:registryFixtureAuthPath});
        \\globalThis.registryRealFacade=new ModelRegistryNative(registryRealRuntime);
    );
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const runtime = try sdk.get(engine, global, "registryRealRuntime"); defer engine.freeValue(runtime);
    const facade = try sdk.get(engine, global, "registryRealFacade"); defer engine.freeValue(facade);
    const lease = try sdk.modelRegistryLease(engine, facade);
    const original = try bridge.borrowRuntime(engine, lease); defer engine.freeValue(original);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, runtime, original));
    try run(engine, "registryRealFacade.runtime={};delete globalThis.registryRealRuntime;");
    const retained = try bridge.borrowRuntime(engine, lease); defer engine.freeValue(retained);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, runtime, retained));
    const independent = try sdk.newModelRegistry(engine, runtime);
    const other_lease = try sdk.modelRegistryLease(engine, independent);
    try std.testing.expect(lease.generation != other_lease.generation);
    engine.freeValue(independent);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectError(error.RetiredNativeSDKModelLease, bridge.borrowRuntime(engine, other_lease));
    try clean(engine);
}
