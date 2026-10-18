//! Prepared source controls only; no compiler, metadata or runtime result.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const subject = @import("extensions/native_ai_auth_helpers.zig");
const c = v.c;
fn publish(engine: *v.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    try v.js.define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn prepare(engine: *v.em.Engine) !void {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try environment.put("PI_AUTH_HELPER_OWNED", "owned-env-value");
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"owned-auth-helper-controls"});
    const api = try subject.create(engine); defer engine.freeValue(api); try publish(engine, "actualAuthHelpers", api);
    const context = try subject.defaultProviderAuthContext(engine); defer engine.freeValue(context); try publish(engine, "actualAuthContext", context);
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-auth-helper-control.mjs"); defer engine.freeValue(namespace);
}
fn markedData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory(); const value = c.JS_GetException(context);
    c.JS_SetUncatchableError(context, value); return value; // Successful DATA.
}
fn rawFailure(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return v.em.Engine.fromContext(context.?).throwNativeOutOfMemory(); // Real pending producer.
}
test "AI auth helper genuine AF real factories preserve held Await getters and tail adoption" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const caller = try std.mem.concat(std.testing.allocator, u8, &.{ @embedFile("extensions/fixtures/ai-auth-helper-genuine-af-observer.mjs"), "\nexport const rows=await observeAuthHelpers(actualAuthHelpers,actualAuthContext);if(rows.length!==9)throw Error('all factory cases');" });
    defer std.testing.allocator.free(caller); try run(engine, caller);
}
test "AI auth helper genuine AF metadata and stored and context zero Await settle immediately" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    var scope: v.Scope = .{ .engine = engine }; defer scope.deinit();
    const auth = try scope.own(try engine.eval("actualAuthHelpers.envApiKeyAuth('Owned',[])", "actual-auth-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    inline for (.{ "login", "resolve" }) |name| {
        const function = try scope.get(auth, name);
        try std.testing.expect(c.JS_IsAsyncFunction(function)); try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
        try std.testing.expect(scope.equal(try scope.get(function, "length"), c.JS_NewInt32(engine.context, 1)));
        try std.testing.expect(scope.equal(try scope.get(function, "name"), try scope.text(name)));
    }
    const stored = try scope.own(try engine.eval("actualAuthHelpers.envApiKeyAuth('Owned',[]).resolve({credential:{key:'owned'},signal:{throwIfAborted(){}}})", "actual-auth-zero-await.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, stored));
    const env = try scope.own(try engine.eval("actualAuthContext.env('PI_AUTH_HELPER_OWNED')", "actual-context-zero-await.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, env));
    const lazy = try scope.own(try engine.eval("actualAuthHelpers.lazyOAuth({name:'Owned',load(){return Promise.resolve({})}})", "actual-lazy-metadata.js", c.JS_EVAL_TYPE_GLOBAL));
    inline for (.{ "login", "refresh", "toAuth" }, 0..) |name, index| {
        const function = try scope.get(lazy, name); try std.testing.expect(c.JS_IsAsyncFunction(function));
        try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
        try std.testing.expect(scope.equal(try scope.get(function, "length"), c.JS_NewInt32(engine.context, if (index == 2) 1 else 2)));
    }
}
test "AI auth helper genuine AF marked rejected and historical private getter DATA stays ordinary" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try engine.bindFunction("actualMarkedData", markedData, 0);
    try run(engine,
        \\const reason=actualMarkedData();let closed=0;
        \\const auth=actualAuthHelpers.envApiKeyAuth('Owned',{[Symbol.iterator](){return{next(){return{value:'ONLY',done:false}},return(){closed++;return{}}}}});
        \\let got;try{await auth.resolve({ctx:{env(){return Promise.reject(reason)}},signal:{throwIfAborted(){}}})}catch(error){got=error}
        \\if(got!==reason||closed!==1)throw Error('flagged Await DATA must close ordinarily');
        \\let history;got=undefined;
        \\try{await actualAuthHelpers.envApiKeyAuth('Owned',[]).resolve({get ctx(){history=actualMarkedData();return{}},get credential(){throw history},signal:{throwIfAborted(){}}})}catch(error){got=error}
        \\if(got!==history)throw Error('historical successful private DATA must stay ordinary');
    );
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "AI auth helper genuine AF fresh raw credential getter is current fatal before signal or catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try engine.bindFunction("actualRawFailure", rawFailure, 0);
    const result = engine.evalModule(
        \\globalThis.authAfterFatal=0;
        \\try{await actualAuthHelpers.envApiKeyAuth('Owned',[]).resolve({ctx:{},get credential(){return actualRawFailure()},get signal(){authAfterFatal++;return{throwIfAborted(){}}}})}catch(error){authAfterFatal++}
    , "actual-auth-current-fatal.mjs");
    if (result) |value| { engine.freeValue(value); return error.ActualRawGetterFatalWasSwallowed; } else |err| try std.testing.expect(err == error.JavaScriptException);
    const reason = engine.captured_exception orelse return error.RequiredActualRawGetterFailure;
    try std.testing.expect(c.JS_IsUncatchableError(reason)); try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    const count = c.JS_GetPropertyStr(engine.context, global, "authAfterFatal"); defer engine.freeValue(count);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0)));
}
test "AI auth helper genuine AF pending login and lazy values survive actual GC" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    try run(engine,
        \\globalThis.authCredential={owned:'credential'};
        \\globalThis.authLogin=actualAuthHelpers.envApiKeyAuth({toString(){return 'Owned GC'}},[]).login({signal:{throwIfAborted(){}},prompt(options){if(options.message!=='Enter Owned GC')throw Error('name identity');return new Promise(resolve=>{globalThis.authLoginRelease=resolve})}});
        \\globalThis.authLazy=actualAuthHelpers.lazyOAuth({name:'Owned',load(){return new Promise(resolve=>{globalThis.authRelease=resolve})}});
        \\globalThis.authPending=authLazy.toAuth(authCredential);
    );
    c.JS_RunGC(engine.runtime);
    try run(engine,
        \\authLoginRelease('owned-gc-key');if((await authLogin).key!=='owned-gc-key')throw Error('login GC roots');
        \\authRelease({toAuth(credential){if(credential!==authCredential)throw Error('GC identity');return credential}});
        \\if(await authPending!==authCredential)throw Error('GC lost return');
        \\delete globalThis.authPending;delete globalThis.authLazy;delete globalThis.authRelease;delete globalThis.authCredential;
        \\delete globalThis.authLogin;delete globalThis.authLoginRelease;
    );
    c.JS_RunGC(engine.runtime);
}

/// Actual Graph0 and installed real fs/os namespace controls are parameterized
/// by the genuine Source module owner. No invented physical URL or import
/// callback can make this an automatically runnable stand-in integration test.
pub fn verifyActualQueuedContext(engine: *v.em.Engine, actual_context_url: c.JSValue, existing_path: c.JSValue, missing_path: c.JSValue) !c.JSValue {
    const context = try subject.defaultProviderAuthContextAt(engine, actual_context_url); defer engine.freeValue(context);
    try publish(engine, "actualQueuedAuthContext", context); try publish(engine, "actualAuthExistingPath", existing_path); try publish(engine, "actualAuthMissingPath", missing_path);
    var scope: v.Scope = .{ .engine = engine }; defer scope.deinit();
    inline for (.{ "env", "fileExists" }) |name| {
        const method = try scope.get(context, name); try std.testing.expect(c.JS_IsAsyncFunction(method));
        try std.testing.expect(!c.JS_IsConstructor(engine.context, method));
    }
    const caller = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/ai-auth-helper-genuine-af-observer.mjs"), "\nexport const rows=await observeAuthContext(actualQueuedAuthContext,actualAuthExistingPath,actualAuthMissingPath);" });
    defer engine.gpa.free(caller);
    return engine.evalModule(caller, "actual-auth-context-queued-caller.mjs");
}
// Instantiate the real parameterized producer route in an install-only target;
// it remains uncalled until Root's actual AI owner supplies its physical URL.
fn actualContextAnchor(engine: *v.em.Engine, url: c.JSValue, existing: c.JSValue, missing: c.JSValue) callconv(.c) c.JSValue {
    return verifyActualQueuedContext(engine, url, existing, missing) catch |err| @import("extensions/native_sdk.zig").fail(engine, err);
}
comptime { @export(&actualContextAnchor, .{ .name = "ai_auth_helper_actual_queued_context_control" }); }
