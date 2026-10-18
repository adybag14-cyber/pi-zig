//! Actual c268 public resolver caller controls. Imported CLI thinking, model
//! equality/default map and minimatch are real retained component owners.
//! The reference fixture isolates resolver semantics; it does not qualify the
//! matcher's known full-package/resource/prototype gaps.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const resolver = @import("extensions/native_sdk_public_model_resolver.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-public-model-resolver-observer.mjs");
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn prepare(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *v.Scope) !void {
    const cli = try v.own(s, try @import("extensions/native_public_cli_args.zig").create(s.engine));
    const thinking = try v.get(s, cli, "isValidThinkingLevel");
    const defaults = try v.own(s, try @import("extensions/native_sdk_factory_model.zig").defaultModelPerProvider(s.engine));
    const model_values = try v.own(s, try @import("extensions/native_ai_model_values.zig").bindings(s.engine));
    const matcher = try v.own(s, try @import("extensions/native_minimatch_namespace.zig").create(s.engine));
    const actual = try v.own(s, try resolver.create(s.engine, .{ .thinking = thinking }));
    const factory = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/sdk-public-model-resolver-c268-source.mjs"), "actual-model-resolver-source-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{thinking, try v.get(s, model_values, "modelsAreEqual"), try v.get(s, matcher, "minimatch"), defaults});
    try publish(s, "modelNative", actual); try publish(s, "modelSource", reference);
    try publish(s, "modelThinking", thinking); try publish(s, "modelDefaults", defaults);
    try publish(s, "modelHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-public-model-resolver-control.mjs");
    engine.freeValue(result);
}
fn clean(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn both(comptime name: []const u8, comptime argument: []const u8) !void {
    inline for (.{ "modelSource", "modelNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try run(engine, observer ++ "\nawait " ++ name ++ "(" ++ subject ++ ",modelHooks,modelDefaults" ++ argument ++ ");\n");
        try clean(engine);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "modelHooks"), "record"));
}
test "SDK public model resolver actual ordinary async shapes and cached owner identity" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try prepare(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const again = try v.own(&s, try resolver.create(engine, .{ .thinking = try v.global(&s, "modelThinking") }));
    try std.testing.expect(v.equal(&s, again, try v.global(&s, "modelNative")));
    try run(engine,
        \\for(const api of[modelSource,modelNative]){
        \\if(Object.keys(api).join()!=="resolveCliModel,resolveModelScopeWithDiagnostics")throw Error("actual public resolver exports");
        \\const ordinary=api.resolveCliModel,asyncBody=api.resolveModelScopeWithDiagnostics;
        \\if(ordinary.name!=="resolveCliModel"||ordinary.length!==1||!Object.hasOwn(ordinary,"prototype")||Object.getPrototypeOf(ordinary)!==Function.prototype)throw Error("ordinary resolver shape");
        \\if(asyncBody.name!=="resolveModelScopeWithDiagnostics"||asyncBody.length!==3||Object.prototype.toString.call(asyncBody)!=="[object AsyncFunction]"||Object.hasOwn(asyncBody,"prototype"))throw Error("genuine resolver AF shape");
        \\if(new ordinary({}).error!==undefined)throw Error("actual ordinary construction body");
        \\}
    );
    try clean(engine);
}
test "SDK public model resolver actual provider ties inline keys and alias preference" { try both("observeModelChoices", ""); }
test "SDK public model resolver actual colon ids and recursive thinking suffixes" { try both("observeModelThinking", ""); }
test "SDK public model resolver actual custom fallback and shared mutable defaults" { try both("observeModelFallback", ""); }
test "SDK public model resolver actual option getter order and optional name chain" { try both("observeModelInputOrder", ""); }
test "SDK public model resolver actual BindingPattern receiver identity and retirement" { try both("observeModelOptionsBinding", ""); }
test "SDK public model resolver actual one Await and live runtime call arguments" { try both("observeModelScopeAwait", ""); }
test "SDK public model resolver actual scoped caller matching warnings and deduplication" { try both("observeModelScopeResults", ""); }
test "SDK public model resolver actual ordinary private DATA from call and Await rejection" {
    try both("observeModelScopeData", ",false");
    try both("observeModelScopeData", ",true");
}
test "SDK public model resolver actual outer IteratorClose and next failure" {
    try both("observeModelScopeClose", ",false");
    try both("observeModelScopeClose", ",true");
}
test "SDK public model resolver actual pattern head survives next done and retires on return" { try both("observeModelScopeHeads", ""); }
test "SDK public model resolver actual nested id receiver retires before provider getter" { try both("observeModelReceiver", ""); }
test "SDK public model resolver actual Set receiver retires before size coercion" { try both("observeModelSetSize", ""); }
test "SDK public model resolver actual retirement B blocks the next provider getter" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try prepare(engine); const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveModelReceiverFatal(modelNative,modelHooks);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public model resolver actual current B bypasses Await handlers" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try prepare(engine); const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nawait observeModelCurrentFatal(modelNative,modelHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public model resolver actual cancellation after head assignment blocks guest progress" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 }); defer engine.deinit();
    try prepare(engine); const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nawait observeModelCancellation(modelNative,modelHooks);"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
