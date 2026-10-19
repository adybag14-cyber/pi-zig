//! Actual c268 Radius OAuth declarations with controlled lexical imports.
//! Physical HTTP/callback/PKCE composition is a separate application gate.
const std = @import("std");
const x = @import("extensions/native_ai_auth_helper_values.zig");
const c = x.c;
const subject = @import("extensions/native_ai_oauth_radius_genuine.zig");
const functions = @import("extensions/native_node_function.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/radius-oauth-observer.mjs");

fn publish(engine: *x.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
fn nativeFactory(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return subject.createTestWithImports(engine, x.arg(args, 0));
}
fn collect(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    c.JS_RunGC(engine.runtime);
    return engine.checked(c.pi_js_undefined());
}
fn asyncBrand(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
fn prepare(engine: *x.em.Engine, native: bool) !void {
    engine.native_io = std.testing.io;
    const hooks = try retirement.createNativeRetirementHooks(engine);
    defer engine.freeValue(hooks);
    try publish(engine, "roHooks", hooks);
    const source = try engine.eval(@embedFile("extensions/fixtures/radius-oauth-c268-source.mjs"),
        "actual-radius-oauth-c268-factory.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(source);
    const actual = try functions.create(engine, "makeRadiusOAuthNative", 1, nativeFactory, &.{});
    defer engine.freeValue(actual);
    try publish(engine, "roMake", if (native) actual else source);
    const brand = try engine.checked(c.JS_NewCFunction(engine.context, asyncBrand, "roIsAsync", 1));
    defer engine.freeValue(brand);
    try publish(engine, "roIsAsync", brand);
    const gc = try functions.create(engine, "roCollect", 0, collect, &.{});
    defer engine.freeValue(gc);
    try publish(engine, "roCollect", gc);
}
fn run(engine: *x.em.Engine, tail: []const u8) !void {
    const script = try std.mem.concat(engine.gpa, u8, &.{ observer, "\n", tail });
    defer engine.gpa.free(script);
    const namespace = try engine.evalModule(script, "actual-radius-oauth-body-observation.mjs");
    engine.freeValue(namespace);
}
fn clean(engine: *x.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn observe(native: bool, call: []const u8) ![]u8 {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
    defer engine.deinit();
    try prepare(engine, native);
    const tail = try std.fmt.allocPrint(engine.gpa, "globalThis.roObservation=JSON.stringify(await {s});", .{call});
    defer engine.gpa.free(tail);
    run(engine, tail) catch |err| {
        std.debug.print("Radius OAuth observer native={any} call={s}: {s}; captured={s}\n",
            .{native, call, @errorName(err), engine.last_error orelse "<no captured diagnostic>"});
        return err;
    };
    const value = try read(engine, "roObservation");
    defer engine.freeValue(value);
    const result = try engine.toString(value);
    defer engine.gpa.free(result);
    try clean(engine);
    return std.testing.allocator.dupe(u8, result);
}
fn compare(comptime name: []const u8, comptime prefix: []const u8, comptime routes: anytype) !void {
    inline for (routes) |route| {
        const call = name ++ "(" ++ prefix ++ "\"" ++ route ++ "\")";
        const expected = try observe(false, call);
        defer std.testing.allocator.free(expected);
        const actual = try observe(true, call);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    }
}
fn both(comptime tail: []const u8) !void {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        run(engine, tail) catch |err| {
            std.debug.print("Radius OAuth observer native={any} body={s}: {s}; captured={s}\n",
                .{native, tail, @errorName(err), engine.last_error orelse "<no captured diagnostic>"});
            return err;
        };
        try clean(engine);
    }
}


test "native OAuth Radius actual ordinary class and AsyncFunction shapes" {
    try both(
        \\const trace=[];roAmbient(trace);const s=roMake(roImports(trace));
        \\for(const [name,length]of [["loadRadiusOAuthDiscovery",2],["readOAuthResponseError",2],["requestOAuthToken",3],["loginWithBrowser",3],["requestDeviceAuthorization",2],["loginWithDeviceCode",2]]){
        \\ const f=s[name];roCheck(f.name===name&&f.length===length&&roIsAsync(f)&&!Object.hasOwn(f,"prototype"),"genuine declaration "+name);
        \\}
        \\const f=s.createRadiusOAuth;roCheck(f.name==="createRadiusOAuth"&&f.length===1&&!roIsAsync(f)&&Object.hasOwn(f,"prototype"),"ordinary factory");
        \\const oauth=new f({name:"Radius",gateway:"https://gateway.example"});
        \\for(const [name,length]of [["login",1],["refresh",2],["toAuth",1]]){const method=oauth[name];roCheck(method.name===name&&method.length===length&&roIsAsync(method)&&!Object.hasOwn(method,"prototype"),"genuine method "+name);}
        \\roCheck(s.OAuthResponseError.name==="OAuthResponseError"&&s.OAuthResponseError.length===4&&Object.getPrototypeOf(s.OAuthResponseError.prototype)===Error.prototype,"actual Error subclass");
    );
}
test "native OAuth Radius factory option and normalization operations preserve Source order" {
    try compare("observeRadiusOAuthPublic", "", .{"gateway-throw","normalize-throw","name-throw","changing-name"});
}
test "native OAuth Radius factory keeps its actual required formal and raw name value" {
    try both(
        \\const trace=[];roAmbient(trace);const s=roMake(roImports(trace));let count=0;
        \\for(const options of [null,undefined]){let caught=false;try{s.createRadiusOAuth(options);}catch(error){caught=error instanceof TypeError;}roCheck(caught,"missing required options fails");}
        \\const name={opaque:true};const p=s.createRadiusOAuth({gateway:"g",get name(){count++;return name;}});roCheck(p.name===name&&count===1,"name is raw DATA");
    );
}
test "native OAuth Radius discovery keeps request and genuine Await ordering" {
    try compare("observeRadiusOAuthHttp", "\"discovery\",", .{"success","changing-endpoint","url-throw","fetch-throw","fetch-reject"});
}
test "native OAuth Radius discovery HTTP error keeps suspended constructor and text operands" {
    try compare("observeRadiusOAuthHttp", "\"discovery\",", .{"http-error","text-get-throw","text-throw","text-reject","status-throw","ok-throw"});
}
test "native OAuth Radius discovery JSON validation and repeated endpoint getter remain exact" {
    try compare("observeRadiusOAuthHttp", "\"discovery\",", .{"json-get-throw","json-throw","json-reject","invalid-endpoint","missing-authorizationEndpoint","data-authorizationEndpoint-throw"});
}
test "native OAuth Radius Error subclass chooses exact detail branches and template coercion" {
    try compare("observeRadiusOAuthClass", "", .{"normal","no-description","description-only","status-only","detail-object","detail-throw","status-object"});
}
test "native OAuth Radius Error class heritage rejects nonconstructors before prototype lookup" {
    try both(
        \\const trace=[];roAmbient(trace);const imports=roImports(trace),original=Error;let reads=0;
        \\const invalid=()=>{};Object.defineProperty(invalid,"prototype",{get(){reads++;throw "must not read";}});
        \\globalThis.Error=invalid;let caught;try{roMake(imports);}catch(error){caught=error;}
        \\globalThis.Error=original;roCheck(reads===0&&caught instanceof TypeError&&caught.message==="parent class must be constructor","constructor validation order");
        \\globalThis.Error=null;const s=roMake(imports);globalThis.Error=original;
        \\roCheck(Object.getPrototypeOf(s.OAuthResponseError.prototype)===null&&Object.getPrototypeOf(s.OAuthResponseError)===Function.prototype,"actual null heritage");
    );
}
test "native OAuth Radius error reader parses actual repeated fields and catches parse-body failures" {
    try compare("observeRadiusOAuthReadError", "", .{"normal","empty","wrong-types","changing-error","field-throw","parse-throw"});
}
test "native OAuth Radius error reader preserves text catch lookup call and Await failures" {
    try compare("observeRadiusOAuthReadError", "", .{"text-get-throw","text-call-throw","text-reject","catch-get-throw","catch-call-throw","status-throw"});
}
test "native OAuth Radius token request preserves field order expiry arithmetic and raw data" {
    try compare("observeRadiusOAuthHttp", "\"token\",", .{"success","expiry-coerce","date-object","date-throw","expiry-throw"});
}
test "native OAuth Radius token catch reads cancellation only for actual fetch failure" {
    try compare("observeRadiusOAuthHttp", "\"token\",", .{"url-throw","fetch-throw","fetch-reject","cancelled","aborted-throw","ok-throw"});
}
test "native OAuth Radius token HTTP failure throws the genuine awaited Error value" {
    try compare("observeRadiusOAuthHttp", "\"token\",", .{"http-error","text-get-throw","text-throw","text-reject","status-throw"});
}
test "native OAuth Radius token JSON and property failures stop at the actual expression" {
    try compare("observeRadiusOAuthHttp", "\"token\",", .{"json-get-throw","json-throw","json-reject","data-access_token-throw","data-refresh_token-throw","data-expires_in-throw","data-scope-throw"});
}
test "native OAuth Radius device request validates truthy fields in Source short circuit order" {
    try compare("observeRadiusOAuthHttp", "\"device\",", .{"success","missing-device_code","missing-user_code","missing-verification_uri","missing-expires_in","data-device_code-throw","data-interval-throw"});
}
test "native OAuth Radius device request preserves construction cancellation and HTTP error paths" {
    try compare("observeRadiusOAuthHttp", "\"device\",", .{"url-throw","params-throw","fetch-throw","fetch-reject","cancelled","aborted-throw","http-error"});
}
test "native OAuth Radius browser preserves callback options notices and wait return ordering" {
    try compare("observeRadiusOAuthBrowser", "", .{"success","falsy","wait-throw","wait-reject"});
}
test "native OAuth Radius browser notifications remain outside callback finally" {
    try compare("observeRadiusOAuthBrowser", "", .{"progress-throw","auth-notice-throw"});
}
test "native OAuth Radius browser finally overrides ordinary pending returns and throws" {
    try compare("observeRadiusOAuthBrowser", "", .{"close-throw","wait-and-close","falsy-and-close"});
}
test "native OAuth Radius browser preserves abrupt PKCE URL and listener operations" {
    try compare("observeRadiusOAuthBrowser", "", .{"pkce-throw","pkce-reject","pkce-null","verifier-get-throw","uuid-throw","url-throw","params-throw","params-text-throw","start-throw","start-reject"});
}
test "native OAuth Radius escaped complete arrow constructs exact token form and signal" {
    const expected = try observe(false, "observeRadiusOAuthComplete()");
    defer std.testing.allocator.free(expected);
    const actual = try observe(true, "observeRadiusOAuthComplete()");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}
test "native OAuth Radius device poll uses actual Error class and selected OAuth status cases" {
    try compare("observeRadiusOAuthDevice", "", .{"success","pending","slow","expired","denied","unknown"});
}
test "native OAuth Radius device notice and token failures retain their actual boundary" {
    try compare("observeRadiusOAuthDevice", "", .{"notify-throw","token-throw","token-reject"});
}
test "native OAuth Radius public login has real prompt Await and selected branch adoption" {
    try compare("observeRadiusOAuthPublic", "", .{"browser","device","unknown","method-object","prompt-throw","prompt-reject"});
}
test "native OAuth Radius refresh and zero Await toAuth preserve genuine outer Promises" {
    try compare("observeRadiusOAuthPublic", "", .{"refresh","to-auth","to-auth-throw"});
}
test "native OAuth Radius completed callback options release a removed complete arrow immediately" {
    try both(
        \\const h=roHooks,trace=[];roAmbient(trace);const imports=roImports(trace);let released=false;
        \\imports.startOAuthCallbackServer=function(options){options.complete.holder=h.make(0);delete options.complete;released=h.count(0)===1;return {wait(){return true;},close(){}};};
        \\await roMake(imports).loginWithBrowser("g","a",{signal:{},notify(){}});
        \\roCheck(released&&h.count(0)===1,"completed callback argument owns the sole arrow");
    );
}
test "native OAuth Radius completed polling options release a removed poll arrow immediately" {
    try both(
        \\const h=roHooks,trace=[];roAmbient(trace);const imports=roImports(trace);let released=false;
        \\imports.pollOAuthDeviceCodeFlow=function(options){options.poll.holder=h.make(0);delete options.poll;released=h.count(0)===1;return "done";};
        \\globalThis.fetch=()=>({ok:true,json(){return {device_code:"d",user_code:"u",verification_uri:"v",expires_in:1,interval:1};}});
        \\const result=await roMake(imports).loginWithDeviceCode("g",{signal:{},notify(){}});
        \\roCheck(result==="done"&&released&&h.count(0)===1,"completed polling argument owns the sole arrow");
    );
}
test "native OAuth Radius terminal complete closure retains verifier and releases unrelated challenge" {
    try both(
        \\const h=roHooks,trace=[];roAmbient(trace);const imports=roImports(trace);let retained;
        \\imports.generatePKCE=()=>({verifier:{holder:h.make(0),toString(){return "v";}},challenge:{holder:h.make(1),toString(){return "c";}}});
        \\imports.startOAuthCallbackServer=options=>{retained=options.complete;return {wait(){return true;},close(){}};};
        \\await roMake(imports).loginWithBrowser("g","a",{signal:{},notify(){}});
        \\roCheck(h.count(0)===0&&h.count(1)===1,"closed verifier cell excludes challenge");
        \\retained=null;roCheck(h.count(0)===1,"last complete closure releases verifier once");
    );
}
test "native OAuth Radius sole refresh closure retains gateway but releases options" {
    try both(
        \\const h=roHooks,trace=[];roAmbient(trace);let refresh;
        \\(function(){const imports=roImports(trace);imports.normalizeRadiusGatewayUrl=()=>({holder:h.make(1)});refresh=roMake(imports).createRadiusOAuth({name:"n",gateway:"g",holder:h.make(0)}).refresh;})();
        \\roCheck(h.count(0)===1&&h.count(1)===0,"refresh captures gateway only");
        \\refresh=null;roCheck(h.count(1)===1,"last shared gateway capture retires");
    );
}
test "native OAuth Radius sole toAuth closure releases all unrelated factory captures" {
    try both(
        \\const h=roHooks,trace=[];roAmbient(trace);let toAuth;
        \\(function(){const imports=roImports(trace);imports.normalizeRadiusGatewayUrl=()=>({holder:h.make(1)});toAuth=roMake(imports).createRadiusOAuth({name:"n",gateway:"g",holder:h.make(0)}).toAuth;})();
        \\roCheck(h.count(0)===1&&h.count(1)===1,"toAuth captures neither options nor gateway");
        \\const result=await toAuth({access:"token"});roCheck(result.apiKey==="token","surviving actual method");
    );
}
test "native OAuth Radius same operation private DATA remains an ordinary catch rethrow" {
    try both(
        \\const h=roHooks,trace=[];roAmbient(trace);const s=roMake(roImports(trace));let original,caught,aborted=0;
        \\globalThis.fetch=()=>{original=h.freshPrivateData();throw original;};
        \\try{await s.requestOAuthToken("g","body",{get aborted(){aborted++;return false;}});}catch(reason){caught=reason;}
        \\roCheck(caught===original&&h.isUnmarkedPrivateData(caught)&&aborted===1,"actual ordinary catch and explicit rethrow");
    );
}
test "native OAuth Radius actual native fatal preempts cancellation getter and guest catch" {
    inline for (.{false,true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        const hooks = try read(engine, "roHooks");
        defer engine.freeValue(hooks);
        const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
        defer engine.freeValue(record);
        try std.testing.expectError(error.JavaScriptException, run(engine, "await observeRadiusOAuthActualFatal();"));
        try retirement.verifyRecordedActualNativeFatal(engine, record);
        try retirement.verifyNoVisits(record, .{3});
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native OAuth Radius explicit throws promote returned flagged Error DATA only at throw" {
    inline for (.{"discovery","cancelled","device-required","public-unknown","browser-falsy","http-error"}) |route| {
        inline for (.{false,true}) |native| {
            const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
            defer engine.deinit();
            try prepare(engine, native);
            _ = engine.throwNativeOutOfMemory();
            const original = c.JS_GetException(engine.context);
            defer engine.freeValue(original);
            c.JS_SetUncatchableError(engine.context, original);
            try publish(engine, "roExplicitReason", original);
            const setup = try engine.eval("globalThis.roExplicitProgress={constructed:0,guestReached:false,closed:false};",
                "radius-oauth-explicit-throw-setup.js", c.JS_EVAL_TYPE_GLOBAL);
            engine.freeValue(setup);
            const progress = try read(engine, "roExplicitProgress");
            defer engine.freeValue(progress);
            try std.testing.expectError(error.JavaScriptException, run(engine,
                "await observeRadiusOAuthExplicitThrow(\"" ++ route ++ "\",roExplicitReason,roExplicitProgress);"));
            const reason = engine.captured_exception orelse return error.MissingActualRadiusExplicitThrow;
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, reason));
            try std.testing.expect(c.JS_IsUncatchableError(reason));
            try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
            // Post-fatal inspection reads only this retained control data property.
            const count = c.JS_GetPropertyStr(engine.context, progress, "constructed");
            defer engine.freeValue(count);
            try std.testing.expect(c.JS_IsNumber(count));
            var number: u32 = 0;
            try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(engine.context, &number, count));
            try std.testing.expectEqual(@as(u32, 1), number);
            inline for (.{"guestReached","closed"}) |field| {
                const reached = c.JS_GetPropertyStr(engine.context, progress, field);
                defer engine.freeValue(reached);
                try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(engine.context, reached));
            }
            try std.testing.expect(engine.native_fatal_invocation == null);
        }
    }
}
test "native OAuth Radius error reader returns flagged Error DATA without an invented throw" {
    inline for (.{false,true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        _ = engine.throwNativeOutOfMemory();
        const original = c.JS_GetException(engine.context);
        defer engine.freeValue(original);
        c.JS_SetUncatchableError(engine.context, original);
        try publish(engine, "roExplicitReason", original);
        try run(engine,
            \\const trace=[];roAmbient(trace);const OriginalError=Error;let constructed=0;
            \\globalThis.Error=function(){constructed++;return roExplicitReason;};globalThis.Error.prototype=OriginalError.prototype;
            \\const s=roMake(roImports(trace));globalThis.Error=OriginalError;
            \\const actual=await s.readOAuthResponseError({status:401,text(){return Promise.resolve('{"error":"denied"}');}},"prefix");
            \\roCheck(actual===roExplicitReason&&constructed===1&&actual.status===401&&actual.oauthError==="denied","flagged Error DATA returns successfully");
        );
        try clean(engine);
    }
}
