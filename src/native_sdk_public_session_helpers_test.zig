//! Actual public Session helper controls. Each observer runs the pinned Source
//! and native function in separate fresh realms over real C retirement holders.
const std = @import("std");
const x = @import("extensions/native_sdk_catalog_values.zig");
const c = x.c;
const helpers = @import("extensions/native_sdk_public_session_helpers.zig");
const uuid = @import("extensions/native_node_crypto_uuid_binding.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-public-session-helpers-observer.mjs");

fn publish(o: *x.Ops, name: [*:0]const u8, value: c.JSValue) !void {
    const root = try o.own(c.JS_GetGlobalObject(o.s.engine.context));
    try o.put(root, name, value);
}
fn prepare(engine: *x.em.Engine) !void {
    engine.native_io = std.testing.io;
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, prepareBody(&o));
}
fn prepareBody(o: *x.Ops) !void {
    const engine = o.s.engine;
    const actual = try o.own(try helpers.create(engine));
    const actual_uuid = try o.own(try uuid.create(engine));
    const source_factory = try o.own(try engine.eval(@embedFile("extensions/fixtures/sdk-public-session-helpers-c268-source.mjs"), "sdk-session-c268-source.js", c.JS_EVAL_TYPE_GLOBAL));
    const source = try o.call(source_factory, c.pi_js_undefined(), &.{actual_uuid});
    const hooks = try o.own(try retirement.createNativeRetirementHooks(engine));
    try publish(o, "actualSessionHelpers", actual);
    try publish(o, "sourceSessionHelpers", source);
    try publish(o, "sessionRetirement", hooks);
    try publish(o, "actualNodeRandomUUID", actual_uuid);
}
fn run(engine: *x.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-public-session-control.mjs");
    engine.freeValue(result);
}
fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const root = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(root);
    return engine.checked(c.JS_GetPropertyStr(engine.context, root, name));
}
fn clean(engine: *x.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn both(comptime name: []const u8) !void {
    inline for (.{ "sourceSessionHelpers", "actualSessionHelpers" }) |subject| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try run(engine, observer ++ "\n" ++ name ++ "(" ++ subject ++ ",sessionRetirement);\n");
        try clean(engine);
    }
}
fn record(engine: *x.em.Engine) !c.JSValue {
    const hooks = try read(engine, "sessionRetirement"); defer engine.freeValue(hooks);
    return engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
}
test "SDK public session actual namespace shapes cache and manager constructor identity" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try prepare(engine);
    const first = try helpers.create(engine); defer engine.freeValue(first);
    const second = try helpers.create(engine); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    try @import("extensions/native_stream.zig").install(engine);
    const sdk = @import("extensions/native_sdk.zig");
    const actual_sdk = try sdk.object(engine); defer engine.freeValue(actual_sdk);
    try sdk.install(engine, actual_sdk);
    const manager_before = try engine.checked(c.JS_GetPropertyStr(engine.context, actual_sdk, "SessionManager")); defer engine.freeValue(manager_before);
    try helpers.install(engine, actual_sdk);
    const manager_after = try engine.checked(c.JS_GetPropertyStr(engine.context, actual_sdk, "SessionManager")); defer engine.freeValue(manager_after);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, manager_before, manager_after));
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    try x.owned.finishVoid(&s, publish(&o, "actualSessionSDK", actual_sdk));
    try run(engine,
        \\const expected={buildContextEntries:3,buildSessionProjection:3,buildSessionContext:3,sessionEntryToContextMessages:1,getLatestCompactionEntry:1,parseSessionEntries:1,migrateSessionEntries:1};
        \\for(const api of[sourceSessionHelpers,actualSessionHelpers]){
        \\if(api.CURRENT_SESSION_VERSION!==3||Object.keys(api).length!==8)throw Error('actual eight-binding namespace');
        \\for(const[name,length]of Object.entries(expected)){const f=api[name];if(f.name!==name||f.length!==length||typeof f.prototype!=='object'||Object.getPrototypeOf(f)!==Function.prototype)throw Error('ordinary public shape '+name)}
        \\}
        \\for(const name of Object.keys(expected))if(actualSessionSDK[name]!==actualSessionHelpers[name])throw Error('installed helper identity');
        \\const manager=actualSessionSDK.SessionManager.inMemory('/actual-session-control');
        \\if(!(manager instanceof actualSessionSDK.SessionManager))throw Error('genuine manager instance');
        \\manager.appendMessage({role:'user',content:'actual message',timestamp:1});
        \\const entries=manager.getEntries();
        \\if(!Array.isArray(entries)||!entries.some(e=>e.type==='message'))throw Error('actual manager stored entry');
        \\if(actualSessionHelpers.buildSessionContext(entries).messages[0].content!=='actual message')throw Error('real manager and public helper integration');
    );
    try clean(engine);
}
test "SDK public session actual projections compactions edits and message identities" { try both("observeSessionProjection"); }
test "SDK public session actual path indexing precedes null leaf and preserves repeated parents" { try both("observeSessionPath"); }
test "SDK public session actual latest lookup retires temporaries and rereads return index" { try both("observeSessionLatest"); }
test "SDK public session actual parser live methods and ordinary push catch" { try both("observeSessionParse"); }
test "SDK public session actual parser head and try local survive blank rows and done" { try both("observeSessionParseLocals"); }
test "SDK public session actual compaction scan head survives following findIndex" { try both("observeSessionCompactionHead"); }
test "SDK public session actual context body local survives false condition and slice" { try both("observeSessionContextBody"); }
test "SDK public session actual body reset fatal preempts following index getter" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveSessionContextFatal(actualSessionHelpers,sessionRetirement);\n"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
}
test "SDK public session actual migration uses live version separate passes and repeated message reads" { try both("observeSessionMigration"); }
test "SDK public session actual migration checks 100 collisions then full secure UUID fallback" { try both("observeSessionMigrationCollisions"); }
test "SDK public session actual strict migration delete failure closes iterator" { try both("observeSessionMigrationDelete"); }
test "SDK public session actual computed migration key retires before target getter" { try both("observeSessionComputedMigration"); }
test "SDK public session actual parser catches same-operation private DATA" { try both("observeSessionParsePrivateData"); }
test "SDK public session actual parser current native fatal preempts ordinary catch" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveSessionParseCurrentFatal(actualSessionHelpers,sessionRetirement);\n"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
}
test "SDK public session actual iterator close keeps head and original throw identity" { try both("observeSessionIteratorClose"); }
test "SDK public session actual new head cancellation preempts body and guest close" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveSessionCancellation(actualSessionHelpers,sessionRetirement);\n"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
}
test "SDK public session actual named UUID binding shares secure primitive and preserves WebCrypto brand" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try @import("extensions/native_web_crypto.zig").install(engine);
    const first = try uuid.create(engine); defer engine.freeValue(first);
    const second = try uuid.create(engine); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    try run(engine,
        \\const pattern=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
        \\const web=crypto,method=web.randomUUID;
        \\if(!pattern.test(actualNodeRandomUUID())||!pattern.test(method.call(web)))throw Error('shared secure v4 UUID');
        \\let branded=false;try{method.call({})}catch(e){branded=e instanceof TypeError}if(!branded)throw Error('WebCrypto brand preserved');
        \\if(actualNodeRandomUUID.name!=='randomUUID'||actualNodeRandomUUID.length!==1||!Object.hasOwn(actualNodeRandomUUID,'prototype'))throw Error('actual ordinary Node binding');
        \\Object.defineProperty(globalThis,'crypto',{configurable:true,get(){throw Error('mutable global crypto must not satisfy Source import')}});
        \\for(const api of[sourceSessionHelpers,actualSessionHelpers]){
        \\const entries=[{type:'session',version:1},{type:'custom'}];api.migrateSessionEntries(entries);
        \\if(!/^[0-9a-f]{8}$/.test(entries[1].id)||entries[0].version!==3)throw Error('captured actual Node binding');
        \\}
    );
    try clean(engine);
}
