//! Real c268 Kimi async exports: Source comparisons, job boundaries and actual C holders.
const std = @import("std");
const support = @import("native_ai_oauth_kimi_test_support.zig");
const x = support.x;
const c = support.c;
fn observe(engine: *x.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/oauth-kimi-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    try support.run(engine, source);
}
test "native OAuth Kimi actual public declarations are genuine async functions" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try support.prepareKimi(engine);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "kimiSource", "kimiNative" }) |name| {
        const namespace = try scope.global(name);
        inline for (.{ "login", "refresh", "toAuth" }, .{ "loginKimiCoding", "refresh", "toAuth" }, .{ 1, 2, 1 }) |key, expected_name, length| {
            const callable = try scope.get(namespace, key);
            try std.testing.expect(c.JS_IsAsyncFunction(callable));
            try std.testing.expect(!c.JS_IsConstructor(engine.context, callable));
            try std.testing.expect(scope.equal(try scope.get(callable, "name"), try scope.text(expected_name)));
            try std.testing.expect(scope.equal(try scope.get(callable, "length"), c.JS_NewInt32(engine.context, length)));
        }
        try std.testing.expect(scope.equal(try scope.get(namespace, "name"), try scope.text("Kimi Code (subscription)")));
        try std.testing.expect(scope.equal(try scope.get(namespace, "loginLabel"), try scope.text("Sign in with Kimi Code")));
        try std.testing.expect(c.JS_ToBool(engine.context, try scope.get(namespace, "isSubscription")) == 1);
    }
}
test "native OAuth Kimi actual Source login polling validation cancellation and request traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
    defer engine.deinit();
    try support.prepareKimi(engine);
    try observe(engine,
        \\const routes=["login-complete","host-override","login-pending","login-slow","login-aborted","login-expired","login-denied","login-server","login-other","login-missing","device-http","device-text-reject","device-text-throw","device-invalid-fields","device-untrusted-url","device-json-reject","device-defaults"];
        \\export const rows=await compareKimi(kimiNative,kimiSource,routes);
        \\if(rows.length!==routes.length)throw Error("Every requested Source route must execute");
    );
}
test "native OAuth Kimi actual Source refresh retry backoff unauthorized and rejection traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
    defer engine.deinit();
    try support.prepareKimi(engine);
    try observe(engine,
        \\const routes=["refresh-complete","refresh-429","refresh-503","refresh-network-throw","refresh-network-reject","refresh-network-exhausted","refresh-retry-exhausted","refresh-unauthorized","refresh-invalid-grant","refresh-other","refresh-missing","refresh-json-reject","refresh-aborted","refresh-abort-backoff"];
        \\export const rows=await compareKimi(kimiNative,kimiSource,routes);
        \\if(rows.length!==routes.length)throw Error("Every requested Source route must execute");
    );
}
test "native OAuth Kimi zero Await toAuth fulfills immediately and uses intrinsic Promise and string hint" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareKimi(engine);
        try support.selectKimi(engine, native);
        try support.run(engine,
            \\globalThis.kimiTrace=[];
            \\globalThis.kimiCredential={get access(){kimiTrace.push("get");return {[Symbol.toPrimitive](hint){kimiTrace.push(hint);return "token"}}}};
            \\Object.defineProperty(globalThis,"Promise",{configurable:true,get(){throw Error("Ambient Promise consulted")}});
        );
        const promise = try engine.eval("selectedKimi.toAuth(kimiCredential)", "actual-kimi-zero-await.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(promise);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, promise));
        const result = c.JS_PromiseResult(engine.context, promise);
        defer engine.freeValue(result);
        try support.publish(engine, "kimiAuth", result);
        try support.run(engine,
            \\if(JSON.stringify(kimiTrace)!=='["get","string"]'||kimiAuth.headers.Authorization!=="Bearer token")throw Error("Actual toAuth coercion and result");
        );
    }
}
test "native OAuth Kimi same-operation private credential DATA remains ordinary async rejection" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareKimi(engine);
        try support.selectKimi(engine, native);
        try support.run(engine,
            \\globalThis.kimiData=undefined;globalThis.kimiCaught=undefined;
            \\try{await selectedKimi.toAuth({get access(){kimiData=oauthHooks.freshPrivateData();throw kimiData}})}catch(error){kimiCaught=error}
            \\if(!kimiData||kimiCaught!==kimiData||!oauthHooks.isUnmarkedPrivateData(kimiData))throw Error("Actual Kimi DATA identity");
        );
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
test "native OAuth Kimi actual credential fatal preempts Source catch and older private DATA" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try support.prepareKimi(engine);
    const hooks = try support.read(engine, "oauthHooks");
    defer engine.freeValue(hooks);
    const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
    defer engine.freeValue(record);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\try{await kimiNative.toAuth({get access(){const prior=oauthHooks.freshPrivateData();try{oauthHooks.raiseNativeFatal()}catch(error){}throw prior}})}catch(error){oauthHooks.visit(3)}
    , "actual-kimi-fatal.mjs"));
    try support.retirement.verifyRecordedActualNativeFatal(engine, record);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "native OAuth Kimi form constructor retires before the next toString getter" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareKimi(engine);
        try support.selectKimi(engine, native);
        try support.run(engine,
            \\globalThis.process={env:{},versions:{}};globalThis.fetch=()=>{throw Error("Unexpected fetch")};
            \\globalThis.formReached=false;
            \\let ctor=function(){return {get toString(){formReached=oauthHooks.count(0)===1;throw Error("controlled form stop")}}};
            \\ctor.prototype=null;ctor.holder=oauthHooks.make(0);
            \\Object.defineProperty(globalThis,"URLSearchParams",{configurable:true,get(){const result=ctor;ctor=undefined;return result}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedKimi.login({signal:{}})}catch(error){caught=error.message==="controlled form stop"}
            \\if(!caught||!formReached||oauthHooks.count(0)!==1)throw Error("Actual form constructor retirement");
        );
    }
}
test "native OAuth Kimi URL constructor retires before actual protocol and href getters" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareKimi(engine);
        try support.selectKimi(engine, native);
        try support.run(engine, support.refreshAmbient);
        try support.run(engine,
            \\globalThis.urlVisits=[];let calls=0;
            \\Object.defineProperty(globalThis,"URL",{configurable:true,get(){
            \\ const slot=calls++;const ctor=function(value){return {get protocol(){urlVisits.push([slot,oauthHooks.count(slot)]);return "https:"},get href(){return value}}};
            \\ ctor.prototype=null;ctor.holder=oauthHooks.make(slot);return ctor;
            \\}});
            \\globalThis.fetch=()=>Promise.resolve({ok:true,json(){return Promise.resolve({device_code:"d",user_code:"u",verification_uri:"https://verify/",verification_uri_complete:"https://verify/code",interval:1,expires_in:60})}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedKimi.login({signal:controlledSignal,notify(){throw Error("controlled notification stop")}})}catch(error){caught=error.message==="controlled notification stop"}
            \\if(!caught||JSON.stringify(urlVisits)!=='[[0,1],[1,1]]')throw Error("Actual URL constructor retirement");
        );
    }
}
test "native OAuth Kimi Date receiver and now callee retire before token expiry coercion" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareKimi(engine);
        try support.selectKimi(engine, native);
        try support.run(engine, support.refreshAmbient);
        try support.run(engine,
            \\globalThis.expiryReached=false;
            \\Object.defineProperty(globalThis,"Date",{configurable:true,get(){
            \\ const receiver={holder:oauthHooks.make(0),now(){return {valueOf(){expiryReached=oauthHooks.count(0)===1&&oauthHooks.count(1)===1;return 10000}}}};
            \\ receiver.now.holder=oauthHooks.make(1);return receiver;
            \\}});
            \\globalThis.fetch=()=>Promise.resolve({ok:true,json(){return Promise.resolve({access_token:"a",refresh_token:"r",expires_in:60})}});
        );
        try support.run(engine,
            \\const token=await selectedKimi.refresh({refresh:"old"},controlledSignal);
            \\if(!expiryReached||token.expires!==70000)throw Error("Actual Date call temporary retirement");
        );
    }
}
test "native OAuth Kimi caught fetch binding survives successful retries and retires at completion" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try support.prepareKimi(engine);
        try support.selectKimi(engine, native);
        try support.run(engine, support.refreshAmbient);
        try support.run(engine,
            \\globalThis.catchStillLive=false;let calls=0;
            \\globalThis.Date={now(){catchStillLive=oauthHooks.count(0)===0;return 10000}};
            \\globalThis.fetch=()=>{
            \\ if(++calls===1){const error=new Error("first network");error.holder=oauthHooks.make(0);return Promise.reject(error)}
            \\ if(calls===2)return Promise.resolve({ok:false,status:503,json(){return Promise.resolve({error:"temporary"})}});
            \\ return Promise.resolve({ok:true,json(){return Promise.resolve({access_token:"a",refresh_token:"r",expires_in:60})}});
            \\};
        );
        try support.run(engine,
            \\const token=await selectedKimi.refresh({refresh:"old"},controlledSignal);
            \\if(!catchStillLive||token.access!=="a")throw Error("Actual catch slot must survive successful retries");
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        c.JS_RunGC(engine.runtime);
        try support.run(engine,
            \\if(oauthHooks.count(0)!==1)throw Error("Actual catch slot must retire after function completion");
        );
    }
}

test "native OAuth Kimi completed fetch argument releases nested headers and body roots" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareKimi(engine);
        try support.selectKimi(engine, native);
        try support.run(engine, support.refreshAmbient);
        try support.run(engine,
            \\globalThis.requestChildrenRetired=false;
            \\globalThis.URLSearchParams=function(){return {toString(){return {holder:oauthHooks.make(1)}}}};
            \\globalThis.fetch=(url,init)=>{
            \\ init.headers.holder=oauthHooks.make(0);delete init.headers;delete init.body;
            \\ requestChildrenRetired=oauthHooks.count(0)===1&&oauthHooks.count(1)===1;
            \\ throw Error("controlled request stop");
            \\};
        );
        try support.run(engine,
            \\let caught=false;try{await selectedKimi.login({signal:controlledSignal,notify(){}})}catch(error){caught=error.message==="controlled request stop"}
            \\if(!caught||!requestChildrenRetired)throw Error("Actual completed request retains no extra child roots");
        );
    }
}
test "native OAuth Kimi finite predicate return retires before following validation call" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareKimi(engine);
        try support.selectKimi(engine, native);
        try support.run(engine, support.refreshAmbient);
        try support.run(engine,
            \\globalThis.firstFiniteRetired=false;let calls=0;
            \\globalThis.Number={isFinite(){if(++calls===1)return {holder:oauthHooks.make(0)};firstFiniteRetired=oauthHooks.count(0)===1;return true}};
            \\globalThis.URL=function(input){return {protocol:"https:",href:input}};
            \\globalThis.fetch=()=>Promise.resolve({ok:true,status:200,json(){return Promise.resolve({device_code:"d",user_code:"u",verification_uri_complete:"https://verify/complete",verification_uri:"https://verify/",interval:1,expires_in:60})}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedKimi.login({signal:controlledSignal,notify(){throw Error("controlled notify stop")}})}catch(error){caught=error.message==="controlled notify stop"}
            \\if(!caught||!firstFiniteRetired||oauthHooks.count(0)!==1)throw Error("Actual finite return is consumed at its condition");
        );
    }
}
