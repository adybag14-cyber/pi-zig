//! Radius configuration Source comparisons through the linked C runtime.
//! Ambient fetch is controlled here; physical networking remains an application gate.
const std = @import("std");
const x = @import("extensions/native_ai_auth_helper_values.zig");
const c = x.c;
const subject = @import("extensions/native_ai_radius_config.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/radius-config-observer.mjs");

fn publish(engine: *x.em.Engine, name: [*:0]const u8, input: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, input));
}
fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
fn asyncBrand(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(ctx, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
fn prepare(engine: *x.em.Engine, native: bool) !void {
    engine.native_io = std.testing.io;
    const hooks = try retirement.createNativeRetirementHooks(engine);
    defer engine.freeValue(hooks);
    try publish(engine, "radiusConfigHooks", hooks);
    const source = try engine.eval(@embedFile("extensions/fixtures/radius-config-c268-source.mjs"),
        "actual-radius-config-source-factory.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(source);
    const selected = if (native) try subject.createTestInternals(engine)
        else try engine.checked(c.JS_Call(engine.context, source, c.pi_js_undefined(), 0, null));
    defer engine.freeValue(selected);
    try publish(engine, "radiusConfig", selected);
    const brand = try engine.checked(c.JS_NewCFunction(engine.context, asyncBrand, "radiusConfigIsAsync", 1));
    defer engine.freeValue(brand);
    try publish(engine, "radiusConfigIsAsync", brand);
}
fn run(engine: *x.em.Engine, tail: []const u8) !void {
    const script = try std.mem.concat(engine.gpa, u8, &.{observer, "\n", tail});
    defer engine.gpa.free(script);
    const namespace = try engine.evalModule(script, "actual-radius-config-observation.mjs");
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
    const tail = try std.fmt.allocPrint(engine.gpa, "globalThis.radiusConfigObservation=JSON.stringify(await {s});", .{call});
    defer engine.gpa.free(tail);
    try run(engine, tail);
    const result = try read(engine, "radiusConfigObservation");
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer engine.gpa.free(text);
    try clean(engine);
    return std.testing.allocator.dupe(u8, text);
}
fn compare(comptime observer_name: []const u8, comptime routes: anytype) !void {
    inline for (routes) |route| {
        const call = observer_name ++ "(radiusConfig,\"" ++ route ++ "\")";
        const expected = try observe(false, call);
        defer std.testing.allocator.free(expected);
        const actual = try observe(true, call);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    }
}
fn both(comptime tail: []const u8) !void {
    inline for (.{false, true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        try run(engine, tail);
        try clean(engine);
    }
}
test "native Radius config actual ordinary declarations and genuine async shape" {
    try both(
        \\for(const [name,length,async] of [["isRadiusGatewayModel",1,false],["sanitizeRadiusGatewayConfig",1,false],["normalizeRadiusGatewayUrl",1,false],["getRadiusCredentialConfig",1,false],["getRadiusModelsFromConfig",2,false],["getRadiusModels",2,false],["truncateHttpBody",1,false],["loadRadiusGatewayConfig",3,true]]) {
        \\ const f=radiusConfig[name];radiusConfigCheck(f.name===name&&f.length===length&&radiusConfigIsAsync(f)===async,"actual function shape "+name);
        \\ radiusConfigCheck(Object.hasOwn(f,"prototype")===!async,"actual declaration constructability "+name);
        \\}
        \\radiusConfigCheck(radiusConfig.DEFAULT_RADIUS_GATEWAY==="https://radius.pi.dev","default gateway");
    );
}
test "native Radius config normalization keeps intrinsic RegExp and string conversion" {
    try compare("observeRadiusNormalize", .{"values","symbol","coercion"});
}
test "native Radius config normalization preserves live test replace and getter failures" {
    try compare("observeRadiusNormalize", .{"live-methods","test-get-throw","replace-get-throw","stringify-throw"});
}
test "native Radius config model predicate preserves repeated getters and live Array order" {
    try compare("observeRadiusModel", .{"valid","changing-cost","array-order"});
}
test "native Radius config model predicate stops at exact Source failed operand" {
    try compare("observeRadiusModel", .{"invalid-values","id-throw","input-throw","cost-throw","maxTokens-throw"});
}
test "native Radius config sanitizer preserves destructuring and filter map order" {
    try compare("observeRadiusSanitize", .{"ordered","filter-throw","map-throw","base-throw","models-throw"});
}
test "native Radius config sanitizer retains genuine shared predicate and shallow copy" {
    try compare("observeRadiusSanitize", .{"identity","spread","invalid"});
}
test "native Radius config mapping keeps spread keys overrides and live config getter" {
    try compare("observeRadiusModels", .{"mapping","spread-throw","base-throw","escaped-map"});
}
test "native Radius config credential optional access and legacy model fallbacks" {
    try compare("observeRadiusModels", .{"credential","legacy","credential-throw"});
}
test "native Radius config body truncation follows UTF16 slice boundaries" {
    try compare("observeRadiusTruncate", .{"strings","unicode","exact-limit"});
}
test "native Radius config body truncation preserves live trim length slice and intrinsic coercion" {
    try compare("observeRadiusTruncate", .{"live","length-throw","slice-throw","hint-throw"});
}
test "native Radius config load retains real request construction and Await order" {
    try compare("observeRadiusLoad", .{"success","no-key","signal-identity","authorization-setter","getter-order"});
}
test "native Radius config load forwards exact request failures" {
    try compare("observeRadiusLoad", .{"fetch-get-throw","url-get-throw","url-throw","fetch-throw","fetch-reject"});
}
test "native Radius config load forwards exact response and JSON failures" {
    try compare("observeRadiusLoad", .{"ok-throw","json-get-throw","json-throw","json-reject","sanitize-throw"});
}
test "native Radius config load rejects malformed config after actual sanitization" {
    try compare("observeRadiusLoad", .{"invalid-config","invalid-models","invalid-base"});
}
test "native Radius config HTTP error captures constructor and prefix before body Await" {
    try compare("observeRadiusLoad", .{"http-failure","error-rebound","gateway-hint","status-hint","long-body"});
}
test "native Radius config HTTP error preserves exact text and truncation failures" {
    try compare("observeRadiusLoad", .{"text-get-throw","text-throw","text-reject","trim-throw","status-throw"});
}
test "native Radius config explicit throw uses the actual returned Error constructor value" {
    try compare("observeRadiusLoad", .{"error-data","invalid-error-data","error-constructor-throw"});
}

test "native Radius config filter callee retires before the following map lookup" {
    try both(
        \\const h=radiusConfigHooks,model=radiusModel();let observed=false;
        \\const selected={get map(){observed=h.count(0)===1;return function(mapper){radiusConfigCheck(this===selected,"map receiver");return [mapper(model)];};}};
        \\const models=[];Object.defineProperty(models,"filter",{get(){const f=function(predicate){radiusConfigCheck(predicate.name==="isRadiusGatewayModel","actual predicate");return selected;};f.holder=h.make(0);return f;}});
        \\const value=radiusConfig.sanitizeRadiusGatewayConfig({baseUrl:"base",models});
        \\radiusConfigCheck(observed&&value.models.length===1&&value.models[0]!==model,"filter retirement before map");
    );
}
test "native Radius config slice callee retires before actual string coercion" {
    try both(
        \\const h=radiusConfigHooks;let observed=false;
        \\const trimmed={length:513,get slice(){const f=function(start,end){radiusConfigCheck(this===trimmed&&start===0&&end===512,"actual slice call");return {holder:h.make(1),[Symbol.toPrimitive](hint){observed=hint==="string"&&h.count(0)===1;return "cut";}};};f.holder=h.make(0);return f;}};
        \\const result=radiusConfig.truncateHttpBody({trim(){return trimmed;}});
        \\radiusConfigCheck(result==="cut…"&&observed&&h.count(1)===1,"slice callable and string operand retire");
    );
}
test "native Radius config URL constructor retires before the subsequent fetch call" {
    try both(
        \\const h=radiusConfigHooks;let observed=false;
        \\Object.defineProperty(globalThis,"URL",{configurable:true,get(){const f=function(path,base){return {path,base};};f.prototype=null;f.holder=h.make(0);return f;}});
        \\globalThis.fetch=function(){observed=h.count(0)===1;return Promise.resolve({ok:true,json(){return Promise.resolve({baseUrl:"base",models:[]});}});};
        \\const value=await radiusConfig.loadRadiusGatewayConfig("gateway");
        \\radiusConfigCheck(observed&&value.baseUrl==="base","URL expression retirement before fetch");
    );
}
test "native Radius config truncated body retires before the selected Error constructor" {
    try both(
        \\const h=radiusConfigHooks,RealError=Error;let observed=false,caught;
        \\globalThis.URL=function(){return {};};
        \\globalThis.fetch=()=>Promise.resolve({ok:false,status:503,text(){return Promise.resolve({trim(){return {length:4,holder:h.make(0),[Symbol.toPrimitive](hint){radiusConfigCheck(hint==="string","body string hint");return "body";}};}});}});
        \\globalThis.Error=function(message){observed=h.count(0)===1;return new RealError(message);};
        \\try{await radiusConfig.loadRadiusGatewayConfig("gateway");}catch(error){caught=error;}
        \\radiusConfigCheck(observed&&caught.message==="Could not load Radius config from gateway: 503: body","truncate result retirement before Error");
    );
}
test "native Radius config same-operation private DATA remains an ordinary rejection" {
    try both(
        \\const h=radiusConfigHooks;let reason,caught;globalThis.URL=function(){return {};};
        \\globalThis.fetch=()=>{reason=h.freshPrivateData();throw reason;};
        \\try{await radiusConfig.loadRadiusGatewayConfig("gateway");}catch(error){caught=error;}
        \\radiusConfigCheck(caught===reason&&h.isUnmarkedPrivateData(caught),"same-operation DATA remains ordinary");
    );
}
test "native Radius config actual native fatal preempts response and guest catch" {
    inline for (.{false,true}) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
        defer engine.deinit();
        try prepare(engine, native);
        const hooks = try read(engine, "radiusConfigHooks");
        defer engine.freeValue(hooks);
        const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
        defer engine.freeValue(record);
        try std.testing.expectError(error.JavaScriptException, run(engine,
            "await observeRadiusActualFatal(radiusConfig,radiusConfigHooks);"));
        try retirement.verifyRecordedActualNativeFatal(engine, record);
        try retirement.verifyNoVisits(record, .{3});
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native Radius config explicit throws promote retained flagged constructor DATA to an event" {
    inline for (.{ "http", "invalid" }) |route| {
        inline for (.{ false, true }) |native| {
            const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 3_000_000 });
            defer engine.deinit();
            try prepare(engine, native);
            _ = engine.throwNativeOutOfMemory();
            const original = c.JS_GetException(engine.context);
            defer engine.freeValue(original);
            c.JS_SetUncatchableError(engine.context, original);
            try publish(engine, "radiusExplicitThrowReason", original);
            const setup = try engine.eval("globalThis.radiusExplicitThrowProgress={constructed:0,guestReached:false};",
                "radius-explicit-throw-setup.js", c.JS_EVAL_TYPE_GLOBAL);
            engine.freeValue(setup);
            const progress = try read(engine, "radiusExplicitThrowProgress");
            defer engine.freeValue(progress);
            try std.testing.expectError(error.JavaScriptException, run(engine,
                "await observeRadiusExplicitErrorThrow(radiusConfig,\"" ++ route ++ "\",radiusExplicitThrowReason,radiusExplicitThrowProgress);"));
            const reason = engine.captured_exception orelse return error.MissingActualExplicitThrowReason;
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, reason));
            try std.testing.expect(c.JS_IsUncatchableError(reason));
            try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
            try std.testing.expect(engine.native_fatal_invocation == null);
            const constructed = c.JS_GetPropertyStr(engine.context, progress, "constructed");
            defer engine.freeValue(constructed);
            var count: u32 = 0;
            try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(engine.context, &count, constructed));
            try std.testing.expectEqual(@as(u32, 1), count);
            const reached = c.JS_GetPropertyStr(engine.context, progress, "guestReached");
            defer engine.freeValue(reached);
            try std.testing.expect(c.JS_IsBool(reached));
            try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(engine.context, reached));
        }
    }
}
