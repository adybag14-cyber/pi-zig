//! Actual private OpenRouter exchange/parser bodies and causal ownership controls.
//! Callback/public-login/HTTP composition is qualified separately.
const std = @import("std");
const support = @import("native_ai_oauth_openrouter_test_support.zig");
const x = support.x;
const c = support.c;
fn observe(engine: *x.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{@embedFile("extensions/fixtures/oauth-openrouter-observer.mjs"), "\n", tail});
    defer engine.gpa.free(source);
    try support.run(engine, source);
}
test "native OAuth OpenRouter actual private async and ordinary declarations" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try support.prepare(engine);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "openRouterSource", "openRouterNative" }) |name| {
        const namespace = try scope.global(name);
        inline for (.{ "exchangeAuthorizationCode", "parseAuthorizationInput", "errorDetail" }, .{ 3, 1, 1 }, .{ true, false, false }) |key, length, is_async| {
            const callable = try scope.get(namespace, key);
            try std.testing.expectEqual(is_async, c.JS_IsAsyncFunction(callable));
            try std.testing.expectEqual(!is_async, c.JS_IsConstructor(engine.context, callable));
            try std.testing.expect(scope.equal(try scope.get(callable, "name"), try scope.text(key)));
            try std.testing.expect(scope.equal(try scope.get(callable, "length"), c.JS_NewInt32(engine.context, length)));
        }
    }
    inline for (.{ "openRouterSourceMethods", "openRouterNative" }) |name| {
        const namespace = try scope.global(name);
        inline for (.{ "refresh", "toAuth" }, .{ 2, 1 }) |key, length| {
            const callable = try scope.get(namespace, key);
            try std.testing.expect(c.JS_IsAsyncFunction(callable));
            try std.testing.expect(!c.JS_IsConstructor(engine.context, callable));
            try std.testing.expect(scope.equal(try scope.get(callable, "length"), c.JS_NewInt32(engine.context, length)));
        }
    }
}
test "native OAuth OpenRouter actual Source exchange request response cancellation and cleanup traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
    defer engine.deinit();
    try support.prepare(engine);
    try observe(engine,
        \\const routes=["success","pre-aborted","pre-aborted-getter-throw","constructor-throw","add-throw","timeout-throw","stringify-throw","controller-signal-throw","fetch-throw","fetch-reject","fetch-abort","abort-listener","token-timeout","catch-aborted-throw","controller-aborted-throw","json-throw","json-reject","json-abort","json-http-failure","array-predicate-throw","inner-ok-throw","final-ok-throw","status-throw","key-empty","key-number","key-missing","key-changing","key-getter-throw","body-null","body-array","body-function","http-description","http-message","http-error","http-nested","http-array","http-empty","clear-throw","remove-throw","cleanup-replaces-fetch","expiry-value"];
        \\export const rows=await compareOpenRouterExchange(openRouterNative,openRouterSource,routes);
        \\if(rows.length!==routes.length)throw Error("Every actual OpenRouter exchange route must execute");
    );
}
test "native OAuth OpenRouter actual Source authorization parser coercion catch and fallback traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
    defer engine.deinit();
    try support.prepare(engine);
    try observe(engine,
        \\const routes=["empty","whitespace","raw","query","url","trim-getter-throw","trim-throw","url-getter-throw","search-throw","url-get-method-throw","url-get-call-throw","url-null","url-undefined","url-identity","includes-value","query-null","query-getter-throw","query-call-throw","params-constructor-throw"];
        \\export const rows=compareOpenRouterSync(openRouterNative,openRouterSource,routes,"parse");
        \\if(rows.length!==routes.length)throw Error("Every actual OpenRouter parser route must execute");
    );
}
test "native OAuth OpenRouter actual Source repeated error fields and Array call ordering" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
    defer engine.deinit();
    try support.prepare(engine);
    try observe(engine,
        \\const routes=["description","description-throw","message","message-throw","error-string","error-null","error-number","error-array","error-function","error-throw","nested","nested-number","nested-throw","changing-null-object","array-throw","array-truthy"];
        \\export const rows=compareOpenRouterSync(openRouterNative,openRouterSource,routes,"detail");
        \\if(rows.length!==routes.length)throw Error("Every actual OpenRouter detail route must execute");
    );
}
test "native OAuth OpenRouter zero Await refresh and toAuth use intrinsic Promise and retain identity" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine,
            \\globalThis.accessValue={toString(){throw Error("Access must not coerce")}};
            \\globalThis.accessGets=0;globalThis.credential={get access(){accessGets++;return accessValue}};
            \\Object.defineProperty(globalThis,"Promise",{configurable:true,get(){throw Error("Ambient Promise consulted")}});
        );
        const refreshed = try engine.eval("selectedOpenRouterMethods.refresh(credential,undefined)", "actual-openrouter-refresh-zero.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(refreshed);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, refreshed));
        const credential = try support.read(engine, "credential");
        defer engine.freeValue(credential);
        const refresh_result = c.JS_PromiseResult(engine.context, refreshed);
        defer engine.freeValue(refresh_result);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, credential, refresh_result));
        const promise = try engine.eval("selectedOpenRouterMethods.toAuth(credential)", "actual-openrouter-toauth-zero.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(promise);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, promise));
        const result = c.JS_PromiseResult(engine.context, promise);
        defer engine.freeValue(result);
        try support.publish(engine, "authResult", result);
        try support.run(engine,
            \\if(accessGets!==1||authResult.apiKey!==accessValue)throw Error("Actual OpenRouter zero Await identity");
        );
    }
}
test "native OAuth OpenRouter same operation private DATA remains ordinary" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine,
            \\let reason,caught;
            \\try{await selectedOpenRouterMethods.toAuth({get access(){reason=oauthHooks.freshPrivateData();throw reason}})}catch(error){caught=error}
            \\if(caught!==reason||!oauthHooks.isUnmarkedPrivateData(reason))throw Error("Actual OpenRouter DATA identity");
        );
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
test "native OAuth OpenRouter actual fatal preempts private DATA catch and cleanup" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine, support.exchangeAmbient);
        const hooks = try support.read(engine, "oauthHooks");
        defer engine.freeValue(hooks);
        const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
        defer engine.freeValue(record);
        try support.run(engine,
            \\globalThis.clearTimeout=()=>{oauthHooks.record.guestReached=true};
            \\controlledSignal.removeEventListener=()=>{oauthHooks.record.guestReached=true};
            \\globalThis.fetch=()=>{const old=oauthHooks.freshPrivateData();try{oauthHooks.raiseNativeFatal()}catch(error){}throw old};
        );
        try std.testing.expectError(error.JavaScriptException, engine.evalModule(
            \\try{await selectedOpenRouter.exchangeAuthorizationCode("c","v",controlledSignal)}catch(error){oauthHooks.visit(3)}
        , "actual-openrouter-fatal.mjs"));
        try support.retirement.verifyRecordedActualNativeFatal(engine, record);
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native OAuth OpenRouter completed fetch argument releases headers body and JSON operands" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine, support.exchangeAmbient);
        try support.run(engine,
            \\globalThis.jsonRetired=false;globalThis.initRetired=false;
            \\Object.defineProperty(globalThis,"JSON",{configurable:true,get(){return {holder:oauthHooks.make(2),get stringify(){const fn=()=>({holder:oauthHooks.make(1)});fn.holder=oauthHooks.make(3);return fn}}}});
            \\globalThis.AbortController=function(){return {get signal(){jsonRetired=oauthHooks.count(2)===1&&oauthHooks.count(3)===1;return {}},abort(){}}};
            \\globalThis.fetch=(url,init)=>{init.headers.holder=oauthHooks.make(0);delete init.headers;delete init.body;initRetired=oauthHooks.count(0)===1&&oauthHooks.count(1)===1;throw Error("controlled fetch stop")};
        );
        try support.run(engine,
            \\let caught=false;try{await selectedOpenRouter.exchangeAuthorizationCode("c","v",controlledSignal)}catch(error){caught=error.message==="controlled fetch stop"}
            \\if(!caught||!jsonRetired||!initRetired)throw Error("Actual completed OpenRouter request operands");
        );
    }
}
test "native OAuth OpenRouter empty JSON catch retires a synchronous reason before response ok" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine, support.exchangeAmbient);
        try support.run(engine,
            \\globalThis.okCounts=[];
            \\globalThis.fetch=()=>Promise.resolve({get ok(){okCounts.push(oauthHooks.count(0));return false},status:401,json(){throw {holder:oauthHooks.make(0)}}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedOpenRouter.exchangeAuthorizationCode("c","v",controlledSignal)}catch(error){caught=error.message==="OpenRouter OAuth key exchange failed (HTTP 401)"}
            \\if(!caught||JSON.stringify(okCounts)!=="[1,1]")throw Error("Actual OpenRouter empty JSON catch retirement");
        );
    }
}
test "native OAuth OpenRouter named fetch catch retains its reason through finally" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine, support.exchangeAmbient);
        try support.run(engine,
            \\globalThis.catchCounts=[];let reads=0;
            \\Object.defineProperty(controlledSignal,"aborted",{get(){if(++reads===2)catchCounts.push(oauthHooks.count(0));return false}});
            \\globalThis.clearTimeout=()=>{catchCounts.push(oauthHooks.count(0))};
            \\globalThis.fetch=()=>{throw {holder:oauthHooks.make(0)}};
        );
        try support.run(engine,
            \\let caught=false;try{await selectedOpenRouter.exchangeAuthorizationCode("c","v",controlledSignal)}catch{caught=true}
            \\if(!caught||JSON.stringify(catchCounts)!=="[0,0]")throw Error("Actual OpenRouter named catch lifetime");
        );
    }
}
test "native OAuth OpenRouter invalid parsed array survives cleanup and final response access" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine, support.exchangeAmbient);
        try support.run(engine,
            \\globalThis.parsedCounts=[];
            \\globalThis.clearTimeout=()=>{parsedCounts.push(oauthHooks.count(0))};
            \\globalThis.fetch=()=>Promise.resolve({get ok(){parsedCounts.push(oauthHooks.count(0));return true},json(){const value=[];value.holder=oauthHooks.make(0);return Promise.resolve(value)}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedOpenRouter.exchangeAuthorizationCode("c","v",controlledSignal)}catch(error){caught=error.message==='OpenRouter OAuth response carries no "key"'}
            \\if(!caught||JSON.stringify(parsedCounts)!=="[0,0]"||oauthHooks.count(0)!==1)throw Error("Actual OpenRouter parsed local lifetime");
        );
    }
}
test "native OAuth OpenRouter clearTimeout result retires before removeEventListener selection" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine, support.exchangeAmbient);
        try support.run(engine,
            \\globalThis.removeReached=false;globalThis.clearTimeout=()=>({holder:oauthHooks.make(0)});
            \\Object.defineProperty(controlledSignal,"removeEventListener",{get(){removeReached=oauthHooks.count(0)===1;return ()=>{}}});
            \\globalThis.fetch=()=>Promise.resolve({ok:true,json(){return Promise.resolve({key:"key"})}});
        );
        try support.run(engine,
            \\const result=await selectedOpenRouter.exchangeAuthorizationCode("c","v",controlledSignal);
            \\if(!removeReached||result.access!=="key")throw Error("Actual separate cleanup statements");
        );
    }
}
test "native OAuth OpenRouter ordinary finally failure replaces prior throw and stops later cleanup" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine, support.exchangeAmbient);
        try support.run(engine,
            \\globalThis.originalFailure={tag:"original"};globalThis.cleanupFailure=undefined;globalThis.removeCalls=0;
            \\globalThis.fetch=()=>{throw originalFailure};globalThis.clearTimeout=()=>{cleanupFailure=oauthHooks.freshPrivateData();throw cleanupFailure};
            \\Object.defineProperty(controlledSignal,"removeEventListener",{get(){removeCalls++;return ()=>{}}});
        );
        try support.run(engine,
            \\let caught;try{await selectedOpenRouter.exchangeAuthorizationCode("c","v",controlledSignal)}catch(error){caught=error}
            \\if(caught!==cleanupFailure||caught===originalFailure||removeCalls!==0||!oauthHooks.isUnmarkedPrivateData(caught))throw Error("Actual finally completion precedence");
        );
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native OAuth OpenRouter parser retires URL constructor and temporary receiver in Source order" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine,
            \\globalThis.urlCounts=[];
            \\Object.defineProperty(globalThis,"URL",{configurable:true,get(){const constructor=function(){return {holder:oauthHooks.make(1),get searchParams(){urlCounts.push(oauthHooks.count(0));return {get get(){urlCounts.push(oauthHooks.count(1));return ()=>"code"}}}}};constructor.prototype=null;constructor.holder=oauthHooks.make(0);return constructor}});
            \\const code=selectedOpenRouter.parseAuthorizationInput("value");
            \\if(code!=="code"||JSON.stringify(urlCounts)!=="[1,1]")throw Error("Actual OpenRouter URL expression retirement");
        );
    }
}
test "native OAuth OpenRouter live Array receiver and callee retire before nested error lookup" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine,
            \\globalThis.arrayRetired=false;let gets=0;
            \\const nested={message:"nested"};const body={get error(){if(++gets===5)arrayRetired=oauthHooks.count(0)===1&&oauthHooks.count(1)===1;return nested}};
            \\Object.defineProperty(globalThis,"Array",{configurable:true,get(){return {holder:oauthHooks.make(0),get isArray(){const fn=()=>false;fn.holder=oauthHooks.make(1);return fn}}}});
            \\const detail=selectedOpenRouter.errorDetail(body);
            \\if(detail!=="nested"||!arrayRetired||gets!==5)throw Error("Actual OpenRouter Array method lifetime");
        );
    }
}
test "native OAuth OpenRouter selects Error before status and retires status before construction" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepare(engine);
        try support.select(engine, native);
        try support.run(engine, support.exchangeAmbient);
        try support.run(engine,
            \\globalThis.statusReached=false;globalThis.errorReached=false;const OriginalError=Error;
            \\Object.defineProperty(globalThis,"Error",{configurable:true,get(){const constructor=function(message){errorReached=oauthHooks.count(0)===0&&oauthHooks.count(1)===1;return new OriginalError(message)};constructor.prototype=null;constructor.holder=oauthHooks.make(0);return constructor}});
            \\globalThis.fetch=()=>Promise.resolve({ok:false,get status(){statusReached=oauthHooks.count(0)===0;return {holder:oauthHooks.make(1),[Symbol.toPrimitive](hint){if(hint!=="string")throw new OriginalError("Status hint");return 418}}},json(){return Promise.resolve({error_description:"detail"})}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedOpenRouter.exchangeAuthorizationCode("c","v",controlledSignal)}catch(error){caught=error.message==="OpenRouter OAuth key exchange failed (HTTP 418): detail"}
            \\if(!caught||!statusReached||!errorReached||oauthHooks.count(0)!==1)throw Error("Actual OpenRouter Error/template evaluation and retirement");
        );
    }
}

test "native OAuth OpenRouter parser retires temporary params before selected get callee" {
    inline for (.{ false, true }) |native| {
        inline for (.{ false, true }) |query| {
            const engine = try x.em.Engine.init(std.testing.allocator, .{});
            var order: support.OrderProbe = .{ .engine = engine };
            defer engine.deinit();
            try support.prepare(engine);
            try support.select(engine, native);
            try support.installOrderProbe(engine, &order);
            try support.run(engine,
                \\globalThis.makeParams=()=>({holder:makeOpenRouterOrderHolder(0),get get(){const method=()=>"code";method.holder=makeOpenRouterOrderHolder(1);return method}});
            );
            try support.run(engine, if (query)
                \\globalThis.URL=function(){throw Error("Expected URL fallback")};
                \\globalThis.URLSearchParams=function(){return makeParams()};
                \\if(selectedOpenRouter.parseAuthorizationInput("code=value")!=="code")throw Error("Actual query parser result");
            else
                \\globalThis.URL=function(){return {get searchParams(){return makeParams()}}};
                \\if(selectedOpenRouter.parseAuthorizationInput("url")!=="code")throw Error("Actual URL parser result");
            );
            try std.testing.expect(!order.overflow);
            try std.testing.expectEqual(@as(usize, 2), order.length);
            try std.testing.expectEqualSlices(u8, &.{ 0, 1 }, order.order[0..order.length]);
        }
    }
}
