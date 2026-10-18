//! Actual provider-env Source, ordinary lookup, fallback cache and operation lifetimes.
const std = @import("std");
const support = @import("native_ai_oauth_kimi_test_support.zig");
const x = support.x;
const c = support.c;
test "native provider env actual ordinary declaration and completed owner identity" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try support.prepareEnv(engine);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "envSource", "envNative" }) |name| {
        const callable = try scope.global(name);
        try std.testing.expect(!c.JS_IsAsyncFunction(callable));
        try std.testing.expect(c.JS_IsConstructor(engine.context, callable));
        try std.testing.expect(scope.equal(try scope.get(callable, "name"), try scope.text("getProviderEnvValue")));
        try std.testing.expect(scope.equal(try scope.get(callable, "length"), c.JS_NewInt32(engine.context, 2)));
    }
    const again = try @import("extensions/native_provider_env.zig").create(engine);
    defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, again, try scope.global("envNative")));
}
test "native provider env actual Source overrides live process fallback cache and catch traces" {
    inline for (.{ "override", "empty-override", "normal", "missing-process", "no-bun", "cache", "require-throws", "read-throws", "map-throws", "get-throws" }) |route| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try support.prepareEnv(engine);
        const source = try std.mem.concat(engine.gpa, u8, &.{
            @embedFile("extensions/fixtures/provider-env-observer.mjs"),
            "\nexport const observation=compareProviderEnv(envNative,envSource,'", route, "');",
        });
        defer engine.gpa.free(source);
        try support.run(engine, source);
    }
}
test "native provider env process receiver retires before computed property key coercion" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareEnv(engine);
        try support.selectEnv(engine, native);
        try support.run(engine,
            \\globalThis.envKeyObserved=false;
            \\Object.defineProperty(globalThis,"process",{configurable:true,get(){return {holder:oauthHooks.make(0),env:{KEY:"value"}}}});
            \\globalThis.envKey={[Symbol.toPrimitive](){envKeyObserved=oauthHooks.count(0)===2;return "KEY"}};
        );
        try support.run(engine,
            \\const value=selectedEnv(envKey);if(value!=="value"||!envKeyObserved)throw Error("Actual process receiver before computed key");
        );
    }
}
test "native provider env versions receiver retires before bun getter" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareEnv(engine);
        try support.selectEnv(engine, native);
        try support.run(engine,
            \\globalThis.envBunObserved=false;
            \\Object.defineProperty(globalThis,"process",{configurable:true,get(){return {holder:oauthHooks.make(0),env:{},versions:{get bun(){envBunObserved=oauthHooks.count(0)===4;return false}}}}});
        );
        try support.run(engine,
            \\const value=selectedEnv("MISSING");if(value!==undefined||!envBunObserved)throw Error("Actual versions receiver before bun");
        );
    }
}
test "native provider env Object keys call roots and names receiver retire at Source boundaries" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareEnv(engine);
        try support.selectEnv(engine, native);
        try support.run(engine,
            \\const ActualObject=Object;let envReads=0;globalThis.envLengthObserved=false;globalThis.envCompareObserved=false;
            \\globalThis.process={versions:{bun:true},get env(){return ++envReads===2?{holder:oauthHooks.make(2)}:{}}};
            \\ActualObject.defineProperty(globalThis,"Object",{configurable:true,get(){
            \\ const receiver={holder:oauthHooks.make(0),keys(){return {holder:oauthHooks.make(3),get length(){
            \\  envLengthObserved=[0,1,2].every(slot=>oauthHooks.count(slot)===1);
            \\  return {valueOf(){envCompareObserved=oauthHooks.count(3)===1;return 1}};
            \\ }}}};
            \\ receiver.keys.holder=oauthHooks.make(1);return receiver;
            \\}});
        );
        try support.run(engine,
            \\const value=selectedEnv("MISSING");
            \\if(value!==undefined||!envLengthObserved||!envCompareObserved)throw Error("Actual Object.keys temporary boundaries");
        );
    }
}
test "native provider env empty catch preserves ordinary private DATA and caches the failed read" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareEnv(engine);
        try support.selectEnv(engine, native);
        try support.run(engine,
            \\globalThis.process={env:{},versions:{bun:true}};globalThis.envData=undefined;let reads=0;
            \\globalThis.require=()=>({readFileSync(){reads++;envData=oauthHooks.freshPrivateData();throw envData}});
            \\if(selectedEnv("KEY")!==undefined||selectedEnv("OTHER")!==undefined||reads!==1||!oauthHooks.isUnmarkedPrivateData(envData))throw Error("Actual empty catch DATA and failed-read cache");
        );
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native provider env actual read fatal bypasses the ordinary fallback catch" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try support.prepareEnv(engine);
    const hooks = try support.read(engine, "oauthHooks");
    defer engine.freeValue(hooks);
    const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
    defer engine.freeValue(record);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\globalThis.process={env:{},versions:{bun:true}};
        \\globalThis.require=()=>({readFileSync(){const prior=oauthHooks.freshPrivateData();try{oauthHooks.raiseNativeFatal()}catch(error){}throw prior}});
        \\try{envNative("KEY")}catch(error){oauthHooks.visit(3)}
    , "actual-provider-env-fatal.mjs"));
    try support.retirement.verifyRecordedActualNativeFatal(engine, record);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
