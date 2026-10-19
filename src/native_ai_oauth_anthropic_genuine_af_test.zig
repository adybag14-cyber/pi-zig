//! Actual Anthropic c268 function bodies with controlled lexical imports.
//! Real HTTP, PKCE/environment composition and account login are separate gates.
const std = @import("std");
const x = @import("extensions/native_ai_auth_helper_values.zig");
const c = x.c;
const subject = @import("extensions/native_ai_oauth_anthropic.zig");
const functions = @import("extensions/native_node_function.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/oauth-anthropic-observer.mjs");

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
    try publish(engine, "anthropicHooks", hooks);
    const source = try engine.eval(@embedFile("extensions/fixtures/oauth-anthropic-c268-source.mjs"),
        "actual-anthropic-c268-factory.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(source);
    const actual = try functions.create(engine, "makeAnthropicNative", 1, nativeFactory, &.{});
    defer engine.freeValue(actual);
    try publish(engine, "selectedAnthropicFactory", if (native) actual else source);
    const brand = try engine.checked(c.JS_NewCFunction(engine.context, asyncBrand, "anthropicIsAsync", 1));
    defer engine.freeValue(brand);
    try publish(engine, "anthropicIsAsync", brand);
    const gc = try functions.create(engine, "anthropicCollect", 0, collect, &.{});
    defer engine.freeValue(gc);
    try publish(engine, "anthropicCollect", gc);
}
fn run(engine: *x.em.Engine, tail: []const u8) !void {
    const script = try std.mem.concat(engine.gpa, u8, &.{ observer, "\n", tail });
    defer engine.gpa.free(script);
    const namespace = try engine.evalModule(script, "actual-anthropic-body-observation.mjs");
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
    const tail = try std.fmt.allocPrint(engine.gpa, "globalThis.anthropicObservation=JSON.stringify(await {s});", .{call});
    defer engine.gpa.free(tail);
    try run(engine, tail);
    const value = try read(engine, "anthropicObservation");
    defer engine.freeValue(value);
    const result = try engine.toString(value);
    defer engine.gpa.free(result);
    try clean(engine);
    return std.testing.allocator.dupe(u8, result);
}
fn compare(comptime name: []const u8, comptime prefix: []const u8, comptime routes: anytype) !void {
    inline for (routes) |route| {
        const call = name ++ "(selectedAnthropicFactory," ++ prefix ++ "\"" ++ route ++ "\")";
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
        try run(engine, tail);
        try clean(engine);
    }
}

test "native OAuth Anthropic actual ordinary and genuine async function shapes" {
    try both(
        \\const trace=[];anthropicAmbient(trace);const s=selectedAnthropicFactory(anthropicImports(trace));
        \\const entries=[["parseAuthorizationInput",1,false],["formatErrorDetails",1,false],["postJson",3,true],["exchangeAuthorizationCode",5,true],["loginAnthropic",1,true],["loginAnthropicCopyCode",1,true],["refreshAnthropicToken",2,true]];
        \\for(const [name,length,async]of entries){const f=s[name];anthropicCheck(f.name===name&&f.length===length&&anthropicIsAsync(f)===async,"actual function identity "+name);}
        \\for(const [name,length,async]of [["login",1,true],["refresh",2,false],["toAuth",1,true]]){const f=s.anthropicOAuth[name];anthropicCheck(f.name===name&&f.length===length&&anthropicIsAsync(f)===async,"actual public method "+name);}
        \\anthropicCheck(s.anthropicOAuth.name==="Anthropic (Claude Pro/Max)"&&s.anthropicOAuth.isSubscription===true,"actual provider fields");
    );
}
test "native OAuth Anthropic postJson exact request construction Await and response order" {
    try compare("observeAnthropicToken", "\"post\",", .{"success","http-failure","body-object","url-object"});
}
test "native OAuth Anthropic postJson preserves request and response abrupt completions" {
    try compare("observeAnthropicToken", "\"post\",", .{"fetch-throw","fetch-reject","text-get-throw","text-throw","text-reject","ok-throw","status-throw","any-get-throw","timeout-throw","stringify-throw"});
}
test "native OAuth Anthropic actual exchange payload fields expiry and failures" {
    try compare("observeAnthropicToken", "\"exchange\",", .{"success","fetch-throw","fetch-reject","text-reject","http-failure","json-throw"});
}
test "native OAuth Anthropic actual token refresh payload fields expiry and failures" {
    try compare("observeAnthropicToken", "\"refresh\",", .{"success","fetch-throw","fetch-reject","text-reject","http-failure","json-throw"});
}
test "native OAuth Anthropic parser actual empty raw hash URL and query paths" {
    try compare("observeAnthropicParser", "", .{"empty","raw","hash","url","query"});
}
test "native OAuth Anthropic parser catches only the URL path and uses real iterator close" {
    try compare("observeAnthropicParser", "", .{"url-property-throw","params-throw","trim-throw","split-iterator"});
}
test "native OAuth Anthropic error details repeated fields and explicit String remain actual" {
    try compare("observeAnthropicDetails", "", .{"no-extras","non-error","recursive","errno-string-object"});
}
test "native OAuth Anthropic error templates eagerly coerce before later getters" {
    try compare("observeAnthropicDetails", "", .{"name-hint-throw","message-hint-throw","code-hint-throw","stack-hint-throw"});
}
test "native OAuth Anthropic browser login actual callback options and manual path" {
    try compare("observeAnthropicLogin", "\"browser\",", .{"success","manual","params-text-object"});
}
test "native OAuth Anthropic browser callback fallback uses preferred then ephemeral ports" {
    try compare("observeAnthropicLogin", "\"browser\",", .{"fallback-once","fallback-all"});
}
test "native OAuth Anthropic browser startup failure precedes try and final callback close" {
    try compare("observeAnthropicLogin", "\"browser\",", .{"pkce-reject","redirect-get-throw"});
}
test "native OAuth Anthropic browser finally runs for notify input state and exchange failures" {
    try compare("observeAnthropicLogin", "\"browser\",", .{"notify-throw","wait-reject","manual-mismatch","manual-missing","fetch-reject","close-throw"});
}
test "native OAuth Anthropic copy code login uses actual prompt and has no callback owner" {
    try compare("observeAnthropicLogin", "\"copy\",", .{"success","params-text-object","prompt-reject","manual-mismatch","manual-missing","fetch-reject"});
}
test "native OAuth Anthropic public login selects actual browser and copy code bodies" {
    try compare("observeAnthropicLogin", "\"public-browser\",", .{"success","unknown-method","prompt-reject"});
    try compare("observeAnthropicLogin", "\"public-copy\",", .{"success","manual-mismatch"});
}
test "native OAuth Anthropic refresh stays ordinary and throws a credential getter synchronously" {
    try both(
        \\const trace=[];anthropicAmbient(trace);const s=selectedAnthropicFactory(anthropicImports(trace));const reason={tag:"ordinary"};
        \\let caught;try{s.anthropicOAuth.refresh({get refresh(){throw reason;}},{tag:"signal"});}catch(error){caught=error;}
        \\anthropicCheck(caught===reason&&!anthropicIsAsync(s.anthropicOAuth.refresh),"ordinary refresh getter failure");
    );
}
test "native OAuth Anthropic zero Await toAuth uses intrinsic promise and raw access identity" {
    try both(
        \\const trace=[];anthropicAmbient(trace);const s=selectedAnthropicFactory(anthropicImports(trace));const IntrinsicPromise=Promise;
        \\const access={toString(){throw Error("access coerced");}};let reads=0;
        \\Object.defineProperty(globalThis,"Promise",{configurable:true,get(){throw Error("ambient Promise selected");}});
        \\const value=s.anthropicOAuth.toAuth({get access(){reads++;return access;}});
        \\anthropicCheck(Object.getPrototypeOf(value)===IntrinsicPromise.prototype,"intrinsic zero Await promise");
        \\const result=await value;anthropicCheck(result.apiKey===access&&reads===1,"actual toAuth access identity");
    );
}
test "native OAuth Anthropic template raw value retires before next substitution without concat" {
    try both("observeAnthropicTemplateRetirement(selectedAnthropicFactory,anthropicHooks);");
}
test "native OAuth Anthropic same-operation private DATA remains an ordinary rejection" {
    try both("await observeAnthropicOrdinaryData(selectedAnthropicFactory,anthropicHooks);");
}
test "native OAuth Anthropic current native fatal preempts exchange catch and guest continuation" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        const hooks = try read(engine, "anthropicHooks");
        defer engine.freeValue(hooks);
        const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
        defer engine.freeValue(record);
        try std.testing.expectError(error.JavaScriptException, run(engine,
            "await observeAnthropicActualFatal(selectedAnthropicFactory,anthropicHooks);"));
        try retirement.verifyRecordedActualNativeFatal(engine, record);
        try retirement.verifyNoVisits(record, .{3});
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native OAuth Anthropic request expression retires JSON and body owners before later work" {
    try both(
        \\const trace=[];anthropicAmbient(trace);const s=selectedAnthropicFactory(anthropicImports(trace));const h=anthropicHooks;
        \\let jsonRetired=false,bodyRetired=false;
        \\Object.defineProperty(globalThis,"JSON",{configurable:true,get(){return {holder:h.make(0),get stringify(){const f=()=>({holder:h.make(1)});f.holder=h.make(2);return f;}};}});
        \\globalThis.AbortSignal={get any(){jsonRetired=h.count(0)===1&&h.count(2)===1;return ()=>({});},timeout(){return {};}};
        \\globalThis.fetch=(url,init)=>{delete init.body;bodyRetired=h.count(1)===1;return Promise.resolve({ok:true,text(){return Promise.resolve("body");}});};
        \\const result=await s.postJson("url",{},{});anthropicCheck(result==="body"&&jsonRetired&&bodyRetired,"actual request temporary retirement");
    );
}
test "native OAuth Anthropic response text callee retires before its result is adopted" {
    try both(
        \\const trace=[];anthropicAmbient(trace);const s=selectedAnthropicFactory(anthropicImports(trace));const h=anthropicHooks;let retired=false;
        \\globalThis.fetch=()=>Promise.resolve({ok:true,get text(){const f=()=>({get then(){retired=h.count(0)===1;return resolve=>resolve("body");}});f.holder=h.make(0);return f;}});
        \\const result=await s.postJson("url",{},{tag:"signal"});anthropicCheck(result==="body"&&retired,"text callee retirement precedes Await adoption");
    );
}

test "native OAuth Anthropic escaped retry retains the actual suspended activation through GC" {
    try both("await observeAnthropicEscapedRetry(selectedAnthropicFactory,anthropicHooks,false);");
}
test "native OAuth Anthropic terminal retry cells retain only their closed captured bindings" {
    try both("await observeAnthropicEscapedRetry(selectedAnthropicFactory,anthropicHooks,true);");
}


test "native OAuth Anthropic explicit throws turn retained flagged Error constructor DATA into a pending event" {
    inline for (.{ "post", "exchange-request", "exchange-json", "refresh-request", "refresh-json", "browser-state", "browser-code", "copy-state", "copy-code", "public-method" }) |route| {
        inline for (.{ false, true }) |native| {
            const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
            defer engine.deinit();
            try prepare(engine, native);
            // Create retained DATA before the tested invocation. Marking this
            // successful value is not itself a pending native fatal event.
            _ = engine.throwNativeOutOfMemory();
            const original = c.JS_GetException(engine.context);
            defer engine.freeValue(original);
            c.JS_SetUncatchableError(engine.context, original);
            try publish(engine, "anthropicExplicitThrowReason", original);
            const setup = try engine.eval("globalThis.anthropicExplicitThrowProgress={constructed:0,guestReached:false,closed:false,message:null};",
                "anthropic-explicit-throw-setup.js", c.JS_EVAL_TYPE_GLOBAL);
            engine.freeValue(setup);
            const progress = try read(engine, "anthropicExplicitThrowProgress");
            defer engine.freeValue(progress);
            try std.testing.expectError(error.JavaScriptException, run(engine,
                "await observeAnthropicExplicitErrorThrow(selectedAnthropicFactory,\"" ++ route ++ "\",anthropicExplicitThrowReason,anthropicExplicitThrowProgress);"));
            const reason = engine.captured_exception orelse return error.MissingActualExplicitThrowReason;
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, reason));
            try std.testing.expect(c.JS_IsUncatchableError(reason));
            try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
            try std.testing.expect(engine.native_fatal_invocation == null);
            const constructed = c.JS_GetPropertyStr(engine.context, progress, "constructed");
            defer engine.freeValue(constructed);
            try std.testing.expect(c.JS_IsNumber(constructed));
            var count: u32 = 0;
            try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(engine.context, &count, constructed));
            try std.testing.expectEqual(@as(u32, 1), count);
            if (comptime std.mem.eql(u8, route, "browser-state") or std.mem.eql(u8, route, "copy-state")) {
                const message = c.JS_GetPropertyStr(engine.context, progress, "message");
                defer engine.freeValue(message);
                try std.testing.expect(c.JS_IsString(message));
                const actual = try engine.toString(message);
                defer engine.gpa.free(actual);
                try std.testing.expectEqualStrings("OAuth state mismatch", actual);
            }
            inline for (.{ "guestReached", "closed" }) |field| {
                const reached = c.JS_GetPropertyStr(engine.context, progress, field);
                defer engine.freeValue(reached);
                try std.testing.expect(c.JS_IsBool(reached));
                try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(engine.context, reached));
            }
        }
    }
}
