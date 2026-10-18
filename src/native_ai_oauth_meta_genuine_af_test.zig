//! Actual Meta provider Source comparisons and causal C retirement controls.
const std = @import("std");
const support = @import("native_ai_oauth_meta_test_support.zig");
const x = support.x;
const c = support.c;
fn observe(engine: *x.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/oauth-meta-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    try support.run(engine, source);
}
test "native OAuth Meta actual public async and ordinary function declarations" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try support.prepareMeta(engine);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "metaSource", "metaNative" }) |name| {
        const namespace = try scope.global(name);
        inline for (.{ "login", "refresh", "toAuth" }, .{ "loginMeta", "refresh", "toAuth" }, .{ 1, 2, 1 }, .{ true, false, true }) |key, expected_name, length, is_async| {
            const callable = try scope.get(namespace, key);
            try std.testing.expectEqual(is_async, c.JS_IsAsyncFunction(callable));
            try std.testing.expect(!c.JS_IsConstructor(engine.context, callable));
            try std.testing.expect(scope.equal(try scope.get(callable, "name"), try scope.text(expected_name)));
            try std.testing.expect(scope.equal(try scope.get(callable, "length"), c.JS_NewInt32(engine.context, length)));
        }
        try std.testing.expect(scope.equal(try scope.get(namespace, "name"), try scope.text("Meta (Muse subscription)")));
        try std.testing.expect(scope.equal(try scope.get(namespace, "loginLabel"), try scope.text("Sign in with Meta")));
        try std.testing.expect(c.JS_ToBool(engine.context, try scope.get(namespace, "isSubscription")) == 1);
    }
}
test "native OAuth Meta actual Source device polling cancellation and login traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
    defer engine.deinit();
    try support.prepareMeta(engine);
    try observe(engine,
        \\const routes=["login-complete","login-pending","login-slow","login-denied","login-expired","login-token-http","login-token-empty","login-token-json","login-aborted","login-abort-poll","login-fetch-throw","login-fetch-reject","login-fetch-abort","login-notify-throw","login-progress-throw","login-mint-401","device-http","device-error-fallback","device-empty-code","device-nonstring-user","device-fallback-url","device-untrusted-url","device-malformed-url","device-default-numbers","device-json-reject","device-json-throw"];
        \\export const rows=await compareMeta(metaNative,metaSource,routes);
        \\if(rows.length!==routes.length)throw Error("Every requested Meta Source login route must execute");
    );
}
test "native OAuth Meta actual Source identity mint refresh validation and error traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
    defer engine.deinit();
    try support.prepareMeta(engine);
    try observe(engine,
        \\const routes=["mint-complete","mint-401","mint-403","mint-http","mint-missing","mint-action","mint-untrusted-action","mint-empty-key","mint-nonstring-key","mint-json-reject","mint-json-throw","mint-fetch-throw","mint-fetch-reject"];
        \\export const rows=await compareMeta(metaNative,metaSource,routes);
        \\if(rows.length!==routes.length)throw Error("Every requested Meta Source mint route must execute");
    );
}
test "native OAuth Meta zero Await toAuth preserves value identity and intrinsic Promise" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareMeta(engine);
        try support.selectMeta(engine, native);
        try support.run(engine,
            \\globalThis.metaAccess={toString(){throw Error("Access must not coerce")}};
            \\globalThis.metaGets=0;globalThis.metaCredential={get access(){metaGets++;return metaAccess}};
            \\Object.defineProperty(globalThis,"Promise",{configurable:true,get(){throw Error("Ambient Promise consulted")}});
        );
        const promise = try engine.eval("selectedMeta.toAuth(metaCredential)", "actual-meta-zero-await.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(promise);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, promise));
        const result = c.JS_PromiseResult(engine.context, promise);
        defer engine.freeValue(result);
        try support.publish(engine, "metaAuth", result);
        try support.run(engine,
            \\if(metaGets!==1||metaAuth.apiKey!==metaAccess)throw Error("Actual Meta toAuth identity");
        );
    }
}
test "native OAuth Meta ordinary refresh retains synchronous credential getter failure" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareMeta(engine);
        try support.selectMeta(engine, native);
        try support.run(engine,
            \\const reason={controlled:"refresh getter"};let caught,returned;
            \\try{returned=selectedMeta.refresh({get refresh(){throw reason}},undefined)}catch(error){caught=error}
            \\if(caught!==reason||returned!==undefined)throw Error("Ordinary Meta refresh must throw before mint invocation");
        );
    }
}
test "native OAuth Meta same-operation private credential DATA stays ordinary" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareMeta(engine);
        try support.selectMeta(engine, native);
        try support.run(engine,
            \\let reason,caught;try{await selectedMeta.toAuth({get access(){reason=oauthHooks.freshPrivateData();throw reason}})}catch(error){caught=error}
            \\if(!reason||caught!==reason||!oauthHooks.isUnmarkedPrivateData(reason))throw Error("Actual Meta DATA identity");
        );
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
test "native OAuth Meta actual fatal preempts Source catch and prior private DATA" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try support.prepareMeta(engine);
    const hooks = try support.read(engine, "oauthHooks");
    defer engine.freeValue(hooks);
    const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
    defer engine.freeValue(record);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\try{await metaNative.toAuth({get access(){const old=oauthHooks.freshPrivateData();try{oauthHooks.raiseNativeFatal()}catch(error){}throw old}})}catch(error){oauthHooks.visit(3)}
    , "actual-meta-fatal.mjs"));
    try support.retirement.verifyRecordedActualNativeFatal(engine, record);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "native OAuth Meta request constructor and fields retire before method lookup" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareMeta(engine);
        try support.selectMeta(engine, native);
        try support.run(engine,
            \\globalThis.formReached=false;globalThis.fetch=()=>{throw Error("Unexpected fetch")};
            \\let constructor=function(fields){fields.holder=oauthHooks.make(1);return {get toString(){formReached=oauthHooks.count(0)===1&&oauthHooks.count(1)===1;throw Error("controlled form stop")}}};
            \\constructor.prototype=null;constructor.holder=oauthHooks.make(0);
            \\Object.defineProperty(globalThis,"URLSearchParams",{configurable:true,get(){const result=constructor;constructor=undefined;return result}});
            \\globalThis.controlledSignal={aborted:false};
        );
        try support.run(engine,
            \\let caught=false;try{await selectedMeta.login({signal:controlledSignal})}catch(error){caught=error.message==="controlled form stop"}
            \\if(!caught||!formReached)throw Error("Actual Meta constructor/argument retirement");
        );
    }
}
test "native OAuth Meta trusted URL constructor retires before protocol and href" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareMeta(engine);
        try support.selectMeta(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.urlReached=false;
            \\Object.defineProperty(globalThis,"URL",{configurable:true,get(){
            \\ const constructor=function(input){return {get protocol(){urlReached=oauthHooks.count(0)===1;return "https:"},get href(){return input}}};
            \\ constructor.prototype=null;constructor.holder=oauthHooks.make(0);return constructor;
            \\}});
            \\globalThis.fetch=()=>Promise.resolve({ok:true,json(){return Promise.resolve({device_code:"d",user_code:"u",verification_uri_complete:"https://verify/",interval:1,expires_in:60})}});
        );
        try support.run(engine,
            \\let caught=false;try{await selectedMeta.login({signal:controlledSignal,notify(){throw Error("controlled notification stop")}})}catch(error){caught=error.message==="controlled notification stop"}
            \\if(!caught||!urlReached||oauthHooks.count(0)!==1)throw Error("Actual Meta URL temporary retirement");
        );
    }
}
test "native OAuth Meta Date receiver and callee retire before expiry coercion" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareMeta(engine);
        try support.selectMeta(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.expiryReached=false;
            \\Object.defineProperty(globalThis,"Date",{configurable:true,get(){
            \\ const receiver={holder:oauthHooks.make(0),now(){return {valueOf(){expiryReached=oauthHooks.count(0)===1&&oauthHooks.count(1)===1;return 10000}}}};
            \\ receiver.now.holder=oauthHooks.make(1);return receiver;
            \\}});
            \\globalThis.fetch=()=>Promise.resolve({ok:true,status:200,json(){return Promise.resolve({api_key:"minted"})}});
        );
        try support.run(engine,
            \\const token=await selectedMeta.refresh({refresh:"identity"},controlledSignal);
            \\if(!expiryReached||token.expires!==86410000||token.refresh!=="identity")throw Error("Actual Meta expiry retirement");
        );
    }
}
test "native OAuth Meta error detail normal IteratorClose preserves head and retires call" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareMeta(engine);
        try support.selectMeta(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.closeReached=false;
            \\const original=Array.prototype[Symbol.iterator];
            \\Array.prototype[Symbol.iterator]=function(){
            \\ if(this.length!==4||this[0]!=="error_description")return original.call(this);
            \\ let count=0;return {next(){return ++count===1?{done:false,value:{holder:oauthHooks.make(0),[Symbol.toPrimitive](hint){if(hint!=="string")throw Error("Actual property hint");return "error_description"}}}:{done:true}},
            \\ get return(){const method=function(){closeReached=oauthHooks.count(0)===0;return {holder:oauthHooks.make(2)}};method.prototype=null;method.holder=oauthHooks.make(1);return method}};
            \\};
            \\globalThis.restoreMetaIterator=()=>{Array.prototype[Symbol.iterator]=original};
            \\globalThis.fetch=()=>Promise.resolve({ok:false,status:418,json(){return Promise.resolve({error_description:" selected detail "})}});
        );
        try support.run(engine,
            \\let caught;try{await selectedMeta.refresh({refresh:"identity"},controlledSignal)}catch(error){caught=error}finally{restoreMetaIterator()}
            \\if(caught?.message!=="Meta API key mint failed with status 418: selected detail"||!closeReached||oauthHooks.count(0)!==1||oauthHooks.count(1)!==1||oauthHooks.count(2)!==1)throw Error("Actual Meta normal IteratorClose ownership");
        );
    }
}
test "native OAuth Meta error detail rejects nonobject normal iterator return" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareMeta(engine);
        try support.selectMeta(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\const original=Array.prototype[Symbol.iterator];let returned=0;
            \\Array.prototype[Symbol.iterator]=function(){if(this.length!==4||this[0]!=="error_description")return original.call(this);return {next(){return {done:false,value:"error_description"}},return(){returned++;return 7}}};
            \\globalThis.restoreMetaIterator=()=>{Array.prototype[Symbol.iterator]=original};globalThis.metaReturns=()=>returned;
            \\globalThis.fetch=()=>Promise.resolve({ok:false,status:418,json(){return Promise.resolve({error_description:"detail"})}});
        );
        try support.run(engine,
            \\let caught;try{await selectedMeta.refresh({refresh:"identity"},controlledSignal)}catch(error){caught=error}finally{restoreMetaIterator()}
            \\if(caught?.name!=="TypeError"||caught.message!=="not an object"||metaReturns()!==1)throw Error("Actual Meta normal iterator return validation");
        );
    }
}
test "native OAuth Meta abrupt IteratorClose preserves ordinary private DATA" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try support.prepareMeta(engine);
        try support.selectMeta(engine, native);
        try support.run(engine, support.requestAmbient);
        try support.run(engine,
            \\globalThis.metaReason=undefined;const original=Array.prototype[Symbol.iterator];let returned=0;
            \\Array.prototype[Symbol.iterator]=function(){if(this.length!==4||this[0]!=="error_description")return original.call(this);return {next(){return {done:false,value:"error_description"}},return(){returned++;throw Error("displaced close error")}}};
            \\globalThis.restoreMetaIterator=()=>{Array.prototype[Symbol.iterator]=original};globalThis.metaReturns=()=>returned;
            \\globalThis.fetch=()=>Promise.resolve({ok:false,status:418,json(){return Promise.resolve({get error_description(){metaReason=oauthHooks.freshPrivateData();throw metaReason}})}});
        );
        try support.run(engine,
            \\let caught;try{await selectedMeta.refresh({refresh:"identity"},controlledSignal)}catch(error){caught=error}finally{restoreMetaIterator()}
            \\if(!metaReason||caught!==metaReason||!oauthHooks.isUnmarkedPrivateData(metaReason)||metaReturns()!==1)throw Error("Actual Meta abrupt IteratorClose DATA priority");
        );
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
