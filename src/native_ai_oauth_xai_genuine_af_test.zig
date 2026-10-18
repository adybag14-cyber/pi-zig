//! Actual Xai provider Source comparisons and causal C retirement controls.
const std = @import("std");
const support = @import("native_ai_oauth_xai_test_support.zig");
const x = support.x;
const c = support.c;
fn observe(engine: *x.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/oauth-xai-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    try support.run(engine, source);
}
test "native OAuth Xai actual public async and ordinary function declarations" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try support.prepareXai(engine);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "xaiSource", "xaiNative" }) |name| {
        const namespace = try scope.global(name);
        inline for (.{ "login", "refresh", "toAuth" }, .{ "loginXai", "refresh", "toAuth" }, .{ 1, 2, 1 }, .{ true, false, true }) |key, expected_name, length, is_async| {
            const callable = try scope.get(namespace, key);
            try std.testing.expectEqual(is_async, c.JS_IsAsyncFunction(callable));
            try std.testing.expect(!c.JS_IsConstructor(engine.context, callable));
            try std.testing.expect(scope.equal(try scope.get(callable, "name"), try scope.text(expected_name)));
            try std.testing.expect(scope.equal(try scope.get(callable, "length"), c.JS_NewInt32(engine.context, length)));
        }
        try std.testing.expect(scope.equal(try scope.get(namespace, "name"), try scope.text("xAI (Grok/X subscription)")));
        try std.testing.expect(scope.equal(try scope.get(namespace, "loginLabel"), try scope.text("Sign in with SuperGrok or X Premium")));
        try std.testing.expect(c.JS_ToBool(engine.context, try scope.get(namespace, "isSubscription")) == 1);
    }
}
test "native OAuth Xai actual Source device polling cancellation and login traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
    defer engine.deinit();
    try support.prepareXai(engine);
    try observe(engine,
        \\const routes=["login-complete","login-pending","login-slow","login-slow-zero","login-denied","login-authorization-denied","login-expired","login-token-http","login-token-empty-access","login-token-empty-refresh","login-token-default-expiry","login-token-zero-expiry","login-token-json","login-aborted","login-abort-poll","login-fetch-throw","login-fetch-reject","login-fetch-abort","login-catch-signal-throw","login-notify-throw","device-http","device-http-empty-detail","device-array-body","device-null-body","device-function-body","device-empty-code","device-nonstring-user","device-no-complete","device-empty-complete","device-http-url","device-untrusted-url","device-malformed-url","device-default-interval","device-infinite-interval","device-zero-expiry","device-json-reject","device-json-throw","device-json-abort","device-protocol-throw","device-href-throw","device-ok-throw"];
        \\export const rows=await compareXai(xaiNative,xaiSource,routes);
        \\if(rows.length!==routes.length)throw Error("Every requested Xai Source login route must execute");
    );
}
test "native OAuth Xai actual Source token refresh validation and error traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
    defer engine.deinit();
    try support.prepareXai(engine);
    try observe(engine,
        \\const routes=["refresh-complete","refresh-http","refresh-array-body","refresh-empty-access","refresh-empty-refresh","refresh-omitted-token","refresh-previous-object","refresh-default-expiry","refresh-zero-expiry","refresh-infinite-expiry","refresh-nonstring-access","refresh-json-reject","refresh-json-throw","refresh-json-abort","refresh-fetch-throw","refresh-fetch-reject","refresh-fetch-abort","refresh-status-throw"];
        \\export const rows=await compareXai(xaiNative,xaiSource,routes);
        \\if(rows.length!==routes.length)throw Error("Every requested Xai Source refresh route must execute");
    );
}
test "native OAuth Xai zero Await toAuth preserves value identity and intrinsic Promise" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine,
            \\globalThis.xaiAccess={toString(){throw Error("Access must not coerce")}};
            \\globalThis.xaiGets=0;globalThis.xaiCredential={get access(){xaiGets++;return xaiAccess}};
            \\Object.defineProperty(globalThis,"Promise",{configurable:true,get(){throw Error("Ambient Promise consulted")}});
        );
        const promise = try engine.eval("selectedXai.toAuth(xaiCredential)", "actual-xai-zero-await.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(promise);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, promise));
        const result = c.JS_PromiseResult(engine.context, promise);
        defer engine.freeValue(result);
        try support.publish(engine, "xaiAuth", result);
        try support.run(engine,
            \\if(xaiGets!==1||xaiAuth.apiKey!==xaiAccess)throw Error("Actual Xai toAuth identity");
        );
    }
}
test "native OAuth Xai ordinary refresh retains synchronous credential getter failure" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine,
            \\const reason={controlled:"refresh getter"};let caught,returned;
            \\try{returned=selectedXai.refresh({get refresh(){throw reason}},undefined)}catch(error){caught=error}
            \\if(caught!==reason||returned!==undefined)throw Error("Ordinary Xai refresh must throw before refresh invocation");
        );
    }
}
test "native OAuth Xai same-operation private credential DATA stays ordinary" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine,
            \\let reason,caught;try{await selectedXai.toAuth({get access(){reason=oauthHooks.freshPrivateData();throw reason}})}catch(error){caught=error}
            \\if(!reason||caught!==reason||!oauthHooks.isUnmarkedPrivateData(reason))throw Error("Actual Xai DATA identity");
        );
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
test "native OAuth Xai actual fatal preempts Source catch and prior private DATA" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try support.prepareXai(engine);
    const hooks = try support.read(engine, "oauthHooks");
    defer engine.freeValue(hooks);
    const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
    defer engine.freeValue(record);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\try{await xaiNative.toAuth({get access(){const old=oauthHooks.freshPrivateData();try{oauthHooks.raiseNativeFatal()}catch(error){}throw old}})}catch(error){oauthHooks.visit(3)}
    , "actual-xai-fatal.mjs"));
    try support.retirement.verifyRecordedActualNativeFatal(engine, record);
    try std.testing.expect(engine.native_fatal_invocation == null);
}

test "native OAuth Xai completed fetch init retires child headers body and constructor roots" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine,
            \\globalThis.initReached=false;
            \\Object.defineProperty(globalThis,"URLSearchParams",{configurable:true,get(){
            \\ const constructor=function(){return {holder:oauthHooks.make(1)}};
            \\ constructor.prototype=null;constructor.holder=oauthHooks.make(2);return constructor;
            \\}});
            \\globalThis.fetch=(url,init)=>{
            \\ init.headers.holder=oauthHooks.make(0);delete init.headers;delete init.body;
            \\ initReached=oauthHooks.count(0)===1&&oauthHooks.count(1)===1&&oauthHooks.count(2)===1;
            \\ throw Error("controlled fetch stop");
            \\};
        );
        try support.run(engine,
            \\let caught=false;try{await selectedXai.refresh({refresh:"old"},{aborted:false})}catch(error){caught=error.message==="controlled fetch stop"}
            \\if(!caught||!initReached)throw Error("Actual completed fetch argument owns only its property roots");
        );
    }
}
test "native OAuth Xai live finite result retires before next verification getter" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.finiteReached=false;let calls=0;
            \\globalThis.Number={isFinite(){return ++calls===1?{holder:oauthHooks.make(0)}:true}};
            \\globalThis.URL=function(input){return {protocol:"https:",href:input}};
            \\globalThis.fetch=()=>Promise.resolve({ok:true,status:200,json(){return Promise.resolve({
            \\ interval:1,get verification_uri_complete(){finiteReached=oauthHooks.count(0)===1;return ""},
            \\ device_code:"d",user_code:"u",verification_uri:"https://verify/",expires_in:60
            \\})}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedXai.login({signal:controlledSignal,notify(){throw Error("controlled notify stop")}})}catch(error){caught=error.message==="controlled notify stop"}
            \\if(!caught||!finiteReached)throw Error("Actual finite predicate result retired before next property");
        );
    }
}
test "native OAuth Xai live finite result retires before nonpositive token Error construction" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.finiteErrorReached=false;
            \\globalThis.Number={isFinite(){return {holder:oauthHooks.make(0)}}};
            \\const OriginalError=Error;
            \\Object.defineProperty(globalThis,"Error",{configurable:true,get(){finiteErrorReached=oauthHooks.count(0)===1;return OriginalError}});
            \\globalThis.fetch=()=>Promise.resolve({ok:true,status:200,json(){return Promise.resolve({access_token:"a",refresh_token:"r",expires_in:-1})}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedXai.refresh({refresh:"old"},controlledSignal)}catch(error){caught=error.message==="Invalid xAI OAuth response field: expires_in"}
            \\if(!caught||!finiteErrorReached)throw Error("Actual finite predicate result retired before Error constructor");
        );
    }
}
test "native OAuth Xai URL constructor retires before actual protocol and href" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.urlVisits=[];let calls=0;
            \\Object.defineProperty(globalThis,"URL",{configurable:true,get(){
            \\ const slot=calls++;const constructor=function(input){return {get protocol(){urlVisits.push([slot,oauthHooks.count(slot)]);return "https:"},get href(){return input}}};
            \\ constructor.prototype=null;constructor.holder=oauthHooks.make(slot);return constructor;
            \\}});
            \\globalThis.fetch=()=>Promise.resolve({ok:true,status:200,json(){return Promise.resolve({device_code:"d",user_code:"u",verification_uri:"https://verify/",verification_uri_complete:"https://verify/complete",interval:1,expires_in:60})}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedXai.login({signal:controlledSignal,notify(){throw Error("controlled notify stop")}})}catch(error){caught=error.message==="controlled notify stop"}
            \\if(!caught||JSON.stringify(urlVisits)!=='[[0,1],[1,1]]')throw Error("Actual URL temporary retirement");
        );
    }
}
test "native OAuth Xai Date receiver and now callee retire before expiry coercion" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.expiryReached=false;
            \\Object.defineProperty(globalThis,"Date",{configurable:true,get(){
            \\ const receiver={holder:oauthHooks.make(0),now(){return {holder:oauthHooks.make(2),valueOf(){expiryReached=oauthHooks.count(0)===1&&oauthHooks.count(1)===1;return 10000}}}};
            \\ receiver.now.holder=oauthHooks.make(1);return receiver;
            \\}});
            \\globalThis.fetch=()=>Promise.resolve({ok:true,status:200,json(){return Promise.resolve({access_token:"a",refresh_token:"r",expires_in:60})}});
        );
        try support.run(engine,
            \\const token=await selectedXai.refresh({refresh:"old"},controlledSignal);
            \\if(!expiryReached||token.expires!==-230000||oauthHooks.count(2)!==1)throw Error("Actual xAI expiry temporary retirement and skew");
        );
    }
}
test "native OAuth Xai live filter arguments retire before returned join method lookup" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.joinReached=false;
            \\const originalFilter=Object.getOwnPropertyDescriptor(Array.prototype,"filter"),originalBoolean=Object.getOwnPropertyDescriptor(globalThis,"Boolean");
            \\Object.defineProperty(Array.prototype,"filter",{configurable:true,get(){
            \\ this.holder=oauthHooks.make(0);
            \\ const method=function(predicate){return {get join(){joinReached=oauthHooks.count(0)===1&&oauthHooks.count(1)===1&&oauthHooks.count(2)===1;return ()=>""}}};
            \\ method.prototype=null;method.holder=oauthHooks.make(1);return method;
            \\}});
            \\Object.defineProperty(globalThis,"Boolean",{configurable:true,get(){const predicate=function(value){return !!value};predicate.prototype=null;predicate.holder=oauthHooks.make(2);return predicate}});
            \\globalThis.restoreXaiFilter=()=>{Object.defineProperty(Array.prototype,"filter",originalFilter);Object.defineProperty(globalThis,"Boolean",originalBoolean)};
            \\globalThis.fetch=()=>Promise.resolve({ok:false,status:403,json(){return Promise.resolve({error:"denied",error_description:"detail"})}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedXai.refresh({refresh:"old"},controlledSignal)}catch(error){caught=error.message==="xAI OAuth token refresh failed (HTTP 403)"}finally{restoreXaiFilter()}
            \\if(!caught||!joinReached)throw Error("Actual filter call completed before join getter");
        );
    }
}
test "native OAuth Xai empty JSON catch retires its reason before aborted getter" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.jsonCatchReached=false;
            \\globalThis.fetch=()=>Promise.resolve({ok:true,status:500,json(){const reason=new Error("json");reason.holder=oauthHooks.make(0);throw reason}});
            \\globalThis.jsonSignal={get aborted(){jsonCatchReached=oauthHooks.count(0)===1;return true}};
        );
        try support.run(engine,
            \\let caught=false;try{await selectedXai.refresh({refresh:"old"},jsonSignal)}catch(error){caught=error.message==="Login cancelled"}
            \\if(!caught||!jsonCatchReached)throw Error("Actual empty JSON catch reason retirement");
        );
    }
}
test "native OAuth Xai fetch catch binding survives aborted getter and retires at return" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.fetchCatchReached=false;
            \\globalThis.fetch=()=>{const reason=new Error("fetch");reason.holder=oauthHooks.make(0);throw reason};
            \\globalThis.fetchSignal={get aborted(){fetchCatchReached=oauthHooks.count(0)===0;return true}};
        );
        try support.run(engine,
            \\let caught=false;try{await selectedXai.refresh({refresh:"old"},fetchSignal)}catch(error){caught=error.message==="Login cancelled"}
            \\if(!caught||!fetchCatchReached||oauthHooks.count(0)!==1)throw Error("Actual fetch catch binding lifetime");
        );
    }
}
test "native OAuth Xai invalid parsed array remains a local through final response getters" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareXai(engine);
        try support.selectXai(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.parsedStillLive=false;
            \\globalThis.fetch=()=>Promise.resolve({get ok(){parsedStillLive=oauthHooks.count(0)===0;return true},status:200,json(){const parsed=[];parsed.holder=oauthHooks.make(0);return Promise.resolve(parsed)}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedXai.refresh({refresh:"old"},controlledSignal)}catch(error){caught=error.message==="Invalid xAI OAuth response field: access_token"}
            \\if(!caught||!parsedStillLive||oauthHooks.count(0)!==1)throw Error("Actual parsed local lifetime");
        );
    }
}
