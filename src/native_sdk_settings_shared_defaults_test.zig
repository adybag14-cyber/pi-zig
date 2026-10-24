//! Source-only declared controls. The reference uses the retained original
//! getter bodies on the SAME genuine SettingsManager class/backing-data owner;
//! no replacement class, filesystem namespace, or production constructor.
//! Each subject runs in a fresh Engine. Native lifetime traces are compared
//! against the actual VM execution of the unchanged original getter bodies.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const sdk = @import("extensions/native_sdk.zig");
const accessors = @import("extensions/native_sdk_settings_default_accessors.zig");
const defaults_owner = @import("extensions/native_sdk_settings_defaults.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-settings-shared-defaults-observer.mjs");
const original = @embedFile("extensions/fixtures/sdk-settings-default-accessors-4954-source.mjs");
const attach_original =
    \\(function attachActualOriginalGetters(receiver, data, methods) {
    \\  Object.defineProperties(receiver, {
    \\    settings: { configurable:true, get() { return data.settings; } },
    \\    globalSettings: { configurable:true, get() { return data.global; } },
    \\  });
    \\  for (const name of Reflect.ownKeys(methods))
    \\    if (name !== "constructor")
    \\      Object.defineProperty(receiver, name, Object.getOwnPropertyDescriptor(methods, name));
    \\  return receiver;
    \\})
;
fn publish(s: *h.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn prepare(engine: *h.Engine, source: bool) !void {
    var environment: std.process.Environ.Map = .init(engine.gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"settings-default-control"});
    try @import("extensions/native_stream.zig").install(engine);
    return h.statement(engine, prepareBody, .{source});
}
fn prepareBody(s: *h.Scope, source: bool) !void {
    const engine = s.engine;
    const shared = try v.own(s, try defaults_owner.create(engine));
    const managers = try v.own(s, try sdk.managerImports(engine));
    const constructor = try v.get(s, managers, "SettingsManager");
    const manager = try v.invoke(s, constructor, "inMemory", &.{});
    const second = try v.invoke(s, constructor, "inMemory", &.{});
    const data = try v.own(s, v.duplicate(s, (try sdk.state(engine, manager)).data));
    const second_data = try v.own(s, v.duplicate(s, (try sdk.state(engine, second)).data));
    var modes = try v.own(s, try accessors.cacheWarmingModes(engine));
    if (source) {
        const factory = try v.own(s, try engine.eval(original, "original-settings-getter-definitions.js", c.JS_EVAL_TYPE_GLOBAL));
        const reference = try v.call(s, factory, c.pi_js_undefined(), &.{shared});
        modes = try v.get(s, reference, "CACHE_WARMING_MODES");
        const methods = try v.get(s, reference, "methods");
        const attach = try v.own(s, try engine.eval(attach_original, "attach-original-getters-to-actual-settings.js", c.JS_EVAL_TYPE_GLOBAL));
        _ = try v.call(s, attach, c.pi_js_undefined(), &.{ manager, data, methods });
        _ = try v.call(s, attach, c.pi_js_undefined(), &.{ second, second_data, methods });
    }
    const subject = try v.object(s);
    try v.put(s, subject, "manager", manager);
    try v.put(s, subject, "second", second);
    try v.put(s, subject, "data", data);
    try v.put(s, subject, "defaults", shared);
    try v.put(s, subject, "modes", modes);
    try v.put(s, subject, "SettingsManager", constructor);
    const names = try v.array(s);
    inline for (std.meta.tags(accessors.Kind), 0..) |kind, index|
        try v.index(s, names, @intCast(index), try v.text(s, @tagName(kind)));
    try v.put(s, subject, "names", names);
    try publish(s, "settingsSubject", subject);
    try publish(s, "settingsHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
}
fn run(engine: *h.Engine, source: []const u8) !void {
    const evaluation = try engine.evalModule(source, "actual-settings-defaults-control.mjs");
    defer engine.freeValue(evaluation);
    engine.freeValue(try engine.awaitValue(evaluation));
}
fn clean(engine: *h.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn observedBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.global(s, "settingsObserved"));
}
fn capture(comptime name: []const u8, source: bool) ![]u8 {
    const engine = try h.Engine.init(std.testing.allocator, .{ .interrupt_budget = 4_000_000 });
    defer engine.deinit();
    try prepare(engine, source);
    try run(engine, observer ++ "\nglobalThis.settingsObserved = JSON.stringify(await " ++ name ++ "(settingsSubject,settingsHooks));\n");
    const value = try h.expression(engine, observedBody, .{});
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsString(value));
    try clean(engine);
    return engine.toString(value);
}
fn both(comptime name: []const u8) !void {
    const expected = try capture(name, true);
    defer std.testing.allocator.free(expected);
    const actual = try capture(name, false);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}
fn recordBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "settingsHooks"), "record"));
}
const Fatal = enum { current, retirement, cancelled };
fn fatal(comptime name: []const u8, comptime kind: Fatal) !void {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine, false);
    const record = try h.expression(engine, recordBody, .{});
    defer engine.freeValue(record);
    try std.testing.expectError(error.JavaScriptException, run(engine,
        observer ++ "\n" ++ name ++ "(settingsSubject,settingsHooks);\n"));
    switch (kind) {
        .current => try retirement.verifyRecordedActualNativeFatal(engine, record),
        .retirement => try retirement.verifyActualRetirementFatal(engine, record, 0),
        .cancelled => try retirement.verifyActualCancellationNoGuestClose(engine, record),
    }
    try retirement.verifyNoVisits(record, .{1,2,3});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
fn acquireCall(engine: *h.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return accessors.acquire(engine);
}
fn coldPrepareBody(s: *h.Scope) !void {
    try publish(s, "settingsColdDefaults", try v.own(s, try defaults_owner.create(s.engine)));
    try publish(s, "settingsActualAcquire", try v.ordinary(s, "settingsActualAcquire", 0, acquireCall, &.{}));
}
fn cold(source: []const u8) !void {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try h.statement(engine, coldPrepareBody, .{});
    try run(engine, observer ++ "\n" ++ source);
    try clean(engine);
}
test "native settings shared defaults complete actual getter shapes and original arities" { try both("observeSettingsShapes"); }
test "native settings shared defaults all twenty-one explicit paths suppress fallback" { try both("observeSettingsDefinedSuppression"); }
test "native settings shared defaults all twenty-one nullish paths read current object" { try both("observeSettingsLiveFallbacks"); }
test "native settings shared defaults original nullish and truthy distinctions" { try both("observeSettingsNullishAndTruthy"); }
test "native settings shared defaults genuine managers share one mutable import" { try both("observeSettingsSharedIdentity"); }
test "native settings shared defaults trust reads global and ask falls back live" { try both("observeSettingsGlobalTrust"); }
test "native settings shared defaults session-share original accepted and fallback choices" { try both("observeSettingsShare"); }
test "native settings shared defaults strict selectors do not eagerly accept default enum values" { try both("observeSettingsStrictChoices"); }
test "native settings shared defaults session-share setter uses actual storage and queue" { try both("observeSettingsShareSetter"); }
test "native settings shared defaults unrelated raw and special methods never consult defaults" { try both("observeSettingsUnrelated"); }
test "native settings shared defaults optional settings parents and required defaults parents" { try both("observeSettingsNestedParents"); }
test "native settings shared defaults global cache mode uses mutable retained includes owner" { try both("observeSettingsCacheModes"); }
test "native settings shared defaults tree modes allocate fresh array before predicate" { try both("observeSettingsTreeModes"); }
test "native settings shared defaults branch compound repeats original parent lookups" { try both("observeSettingsBranchOrder"); }
test "native settings shared defaults retry compound preserves live getter and field order" { try both("observeSettingsRetryOrder"); }
test "native settings shared defaults provider compound only defaults final field" { try both("observeSettingsProviderOrder"); }
test "native settings shared defaults compaction compound preserves actual live collaborators" { try both("observeSettingsCompactionCalls"); }
test "native settings shared defaults token wrappers capture live method before arguments" { try both("observeSettingsTokenWrappers"); }
test "native settings shared defaults private token constants capture once while enabled stays live" { try both("observeSettingsCapturedTokens"); }
test "native settings shared defaults token ordinary validation and exact errors" { try both("observeSettingsTokenValidation"); }
test "native settings shared defaults ordinary validation precedes model and override precedence" { try both("observeSettingsTokenPrecedence"); }
test "native settings shared defaults dynamic keys and provider coercion precede id lookup" { try both("observeSettingsTokenKeyOrder"); }
test "native settings shared defaults false model suppresses override and optional field work" { try both("observeSettingsTokenModelSuppression"); }
test "native settings shared defaults mergeable entry uses original live Array predicate" { try both("observeSettingsEntryValidation"); }
test "native settings shared defaults Error callee and String template evaluation order" { try both("observeSettingsErrorOrder"); }
test "native settings shared defaults thrown safe-integer predicate suppresses later model" { try both("observeSettingsThrownPredicates"); }
test "native settings shared defaults width resolves max callee before floor argument" { try both("observeSettingsWidthOrder"); }
test "native settings shared defaults wheel max min floor live receiver order" { try both("observeSettingsWheelOrder"); }
test "native settings shared defaults numeric type guards suppress Number lookup" { try both("observeSettingsNumericFallback"); }
test "native settings shared defaults clear-on-shrink rereads defined value and exact environment" { try both("observeSettingsClearOrder"); }
test "native settings shared defaults original getter exception retains identity" { try both("observeSettingsGetterFailure"); }
test "native settings shared defaults successful native private Error remains ordinary data" { try both("observeSettingsPrivateData"); }
test "native settings shared defaults temporary parent lifetime matches actual original VM" { try both("observeSettingsTemporaryOrder"); }
test "native settings shared defaults validated local lifetime matches actual original VM" { try both("observeSettingsLocalOrder"); }
test "native settings shared defaults comparison temporary lifetime matches actual original VM" { try both("observeSettingsComparisonOrder"); }
test "native settings shared defaults numeric predicate result retires before next lookup" { try both("observeSettingsPredicateOrder"); }
test "native settings shared defaults token locals and extra argument backing match original VM" { try both("observeSettingsTokenLocalOrder"); }
test "native settings shared defaults current fatal preempts guest catch and return" { try fatal("observeSettingsCurrentFatal", .current); }
test "native settings shared defaults actual parent retirement fatal prevents fallback" { try fatal("observeSettingsRetirementFatal", .retirement); }
test "native settings shared defaults actual parent retirement cancellation prevents fallback" { try fatal("observeSettingsRetirementCancel", .cancelled); }
test "native settings shared defaults module captures two separate original parent reads once" {
    try cold(
        \\const order=[];let n=0;
        \\Object.defineProperty(settingsColdDefaults,"compaction",{configurable:true,get(){order.push("compaction");return {get reserveTokens(){order.push("reserve");return 41;},get keepRecentTokens(){order.push("keep");return 43;}};}});
        \\const first=settingsActualAcquire(),second=settingsActualAcquire();
        \\expectSettings(first===second&&first.defaults===settingsColdDefaults,"one actual cached import capsule");
        \\sameSettings(order,["compaction","reserve","compaction","keep"],"original once-only capture order");
        \\sameSettings(first.compactionDefaults,{reserveTokens:41,keepRecentTokens:43},"captured original values");
        \\sameSettings(first.cacheWarmingModes,["off","streaming","idle"],"actual exported array");
        \\expectSettings(Object.getPrototypeOf(first)===null,"private capsule is not a public namespace");
    );
}
test "native settings shared defaults failed capture publishes no partial cache and can repair" {
    try cold(
        \\const sentinel={same:true},order=[];
        \\Object.defineProperty(settingsColdDefaults,"compaction",{configurable:true,get(){order.push("failed");throw sentinel;}});
        \\let caught;try{settingsActualAcquire();}catch(e){caught=e;}
        \\expectSettings(caught===sentinel,"actual first pending reason");
        \\Object.defineProperty(settingsColdDefaults,"compaction",{configurable:true,value:{reserveTokens:47,keepRecentTokens:53},writable:true});
        \\const repaired=settingsActualAcquire();
        \\expectSettings(repaired.compactionDefaults.reserveTokens===47&&repaired.compactionDefaults.keepRecentTokens===53,"no partial captured constants");
        \\settingsColdDefaults.compaction={reserveTokens:0,keepRecentTokens:0};
        \\expectSettings(settingsActualAcquire()===repaired,"warm import stable after repair");
        \\sameSettings(order,["failed"],"failed getter exactly once");
    );
}
test "native settings shared defaults host pending entry precedes cold or warm cache" {
    inline for (.{ false, true }) |warm| {
        const engine = try h.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        if (warm) engine.freeValue(try accessors.acquire(engine));
        const reason = try sdk.object(engine);
        defer engine.freeValue(reason);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        try std.testing.expectError(error.JavaScriptException, accessors.acquire(engine));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.MissingOriginalPending));
        try std.testing.expectEqual(warm, engine.native_module_values.contains("pi-private:actual-sdk-settings-accessor-imports"));
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
