//! Actual c268 device-code exports: source-bound Await, timer, lifetime and fatal controls.
const std = @import("std");
const x = @import("extensions/native_ai_auth_helper_values.zig");
const c = x.c;
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
fn publish(engine: *x.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn prepare(engine: *x.em.Engine) !void {
    engine.native_io = std.testing.io;
    const native = try @import("extensions/native_ai_oauth_device_code.zig").create(engine);
    defer engine.freeValue(native);
    try publish(engine, "deviceNative", native);
    const source = try engine.evalModule(@embedFile("extensions/fixtures/oauth-device-code-c268-source.mjs"), "actual-source-device-code-c268.mjs");
    defer engine.freeValue(source);
    try publish(engine, "deviceSource", source);
    const hooks = try retirement.createNativeRetirementHooks(engine);
    defer engine.freeValue(hooks);
    try publish(engine, "deviceHooks", hooks);
}
fn run(engine: *x.em.Engine, source: []const u8) !void {
    const namespace = try engine.evalModule(source, "actual-device-code-caller.mjs");
    engine.freeValue(namespace);
}
fn observer(engine: *x.em.Engine, tail: []const u8) !void {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/oauth-device-code-genuine-af-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    try run(engine, source);
}
fn read(engine: *x.em.Engine, name: [*:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return engine.checked(c.JS_GetPropertyStr(engine.context, global, name));
}
fn select(engine: *x.em.Engine, native: bool) !void {
    try run(engine, if (native) "globalThis.selectedDevice=deviceNative;" else "globalThis.selectedDevice=deviceSource;");
}
test "native OAuth device code actual ordinary sleep and genuine polling declaration metadata" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    var scope: x.Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "deviceSource", "deviceNative" }) |name| {
        const exports = try scope.global(name);
        const sleep = try scope.get(exports, "abortableSleep");
        const poll = try scope.get(exports, "pollOAuthDeviceCodeFlow");
        try std.testing.expect(!c.JS_IsAsyncFunction(sleep));
        try std.testing.expect(c.JS_IsConstructor(engine.context, sleep));
        try std.testing.expect(scope.equal(try scope.get(sleep, "length"), c.JS_NewInt32(engine.context, 3)));
        try std.testing.expect(scope.equal(try scope.get(sleep, "name"), try scope.text("abortableSleep")));
        try std.testing.expect(c.JS_IsAsyncFunction(poll));
        try std.testing.expect(!c.JS_IsConstructor(engine.context, poll));
        try std.testing.expect(scope.equal(try scope.get(poll, "length"), c.JS_NewInt32(engine.context, 1)));
        try std.testing.expect(scope.equal(try scope.get(poll, "name"), try scope.text("pollOAuthDeviceCodeFlow")));
    }
}
test "native OAuth device code exact Source polling deadline slow down thenable and getter traces" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try observer(engine,
        \\export const rows=await compareDevicePoll(deviceNative.pollOAuthDeviceCodeFlow,deviceSource.pollOAuthDeviceCodeFlow,[
        \\ "complete","finite","pending","wait-first","slow-increment","slow-server","slow-infinite","slow-timeout",
        \\ "failed","status-sequence","timeout","aborted","reject","poll-thenable","tail-thenable","intrinsic-promise"
        \\]);
        \\if(rows.length!==16)throw Error("All actual device poll routes required");
    );
}
test "native OAuth device code exact Source sleep callbacks live Promise constructor and timeout TDZ" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try prepare(engine);
    try observer(engine,
        \\export const rows=await compareDeviceSleep(deviceNative.abortableSleep,deviceSource.abortableSleep,[
        \\ "elapsed","constructible","already-aborted","abort-register","tdz","live-constructor","constructor-throws"
        \\]);
        \\if(rows.length!==7)throw Error("All actual sleep routes required");
    );
}
test "native OAuth device code zero Await timeout rejects immediately while poll completion awaits" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try select(engine, native);
        // eval intentionally observes the actual immediate state before host job draining.
        const timeout = try engine.eval("(() => { const promise=selectedDevice.pollOAuthDeviceCodeFlow({expiresInSeconds:0}); promise.catch(()=>{}); return promise })()", "device-zero-await-timeout.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(timeout);
        try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, timeout));
        const complete = try engine.eval("selectedDevice.pollOAuthDeviceCodeFlow({signal:{aborted:false},poll(){return {status:'complete',value:9}}})", "device-actual-poll-await.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(complete);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, complete));
        _ = try engine.drainReadyJobs();
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, complete));
    }
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    _ = x.em.Engine.fromContext(context.?).throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn actualFatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?);
    _ = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch {};
    const global = c.JS_GetGlobalObject(context);
    defer engine.freeValue(global);
    _ = c.JS_DefinePropertyValueStr(context, global, "deviceObservedB", c.JS_DupValue(context, engine.captured_exception.?), c.JS_PROP_C_W_E);
    return c.pi_js_undefined();
}
test "native OAuth device code same-operation private DATA getter call and constructor throws remain ordinary" {
    inline for (.{ "getter", "call", "constructor" }) |mode| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try engine.bindFunction("devicePrivateData", privateData, 0);
        const setup = if (std.mem.eql(u8, mode, "getter"))
            "globalThis.deviceOptions={get expiresInSeconds(){deviceA=devicePrivateData();throw deviceA}};"
        else if (std.mem.eql(u8, mode, "call"))
            "globalThis.deviceOptions={signal:{aborted:false},poll(){deviceA=devicePrivateData();throw deviceA}};"
        else
            "globalThis.deviceOptions={expiresInSeconds:0};globalThis.Error=function(){deviceA=devicePrivateData();throw deviceA};";
        const source = try std.mem.concat(engine.gpa, u8, &.{
            "const NativeError=Error;globalThis.deviceA=undefined;globalThis.deviceCaught=undefined;", setup,
            "try{await deviceNative.pollOAuthDeviceCodeFlow(deviceOptions)}catch(error){deviceCaught=error}if(deviceCaught!==deviceA||!deviceA)throw new NativeError('Device DATA identity');",
        });
        defer engine.gpa.free(source);
        try run(engine, source);
        const reason = try read(engine, "deviceA");
        defer engine.freeValue(reason);
        try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native OAuth device code captured actual B precedes later thrown DATA A" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    try engine.bindFunction("devicePrivateData", privateData, 0);
    try engine.bindFunction("deviceActualFatal", actualFatal, 0);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\globalThis.deviceA=undefined;
        \\const options={get expiresInSeconds(){deviceA=devicePrivateData();deviceActualFatal();throw deviceA}};
        \\try{await deviceNative.pollOAuthDeviceCodeFlow(options)}catch(error){globalThis.deviceCaught=error}
    , "actual-device-fatal-priority.mjs"));
    const selected = engine.captured_exception orelse return error.RequiredDeviceFatal;
    const reason = try read(engine, "deviceObservedB");
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, selected, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "native OAuth device code successful flagged Error constructor DATA rejects through Source throw and reject" {
    inline for (.{ false, true }) |sleep| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try engine.bindFunction("devicePrivateData", privateData, 0);
        try run(engine,
            \\const ActualError=Error;globalThis.deviceA=undefined;globalThis.deviceCaught=undefined;
            \\globalThis.Error=function(){deviceA=devicePrivateData();return deviceA};
        );
        try run(engine, if (sleep)
            "try{await deviceNative.abortableSleep(1,{aborted:true},'cancel')}catch(error){deviceCaught=error}"
        else
            "try{await deviceNative.pollOAuthDeviceCodeFlow({expiresInSeconds:0})}catch(error){deviceCaught=error}");
        const original = try read(engine, "deviceA");
        defer engine.freeValue(original);
        const caught = try read(engine, "deviceCaught");
        defer engine.freeValue(caught);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, caught));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(original) != 0);
        try std.testing.expect(!c.JS_IsUncatchableError(original));
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
fn gc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(x.em.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
test "native OAuth device code options and loop result survive their actual Await and retire before next Date" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try select(engine, native);
        try engine.bindFunction("deviceGc", gc, 0);
        try run(engine,
            \\globalThis.deviceWeak=[];globalThis.deviceAfterTimer=false;
            \\globalThis.Date={now(){if(deviceAfterTimer){deviceGc();if(deviceWeak[1].deref()!==undefined)throw Error("Loop result retained into next Date.now")}return 0}};
            \\globalThis.setTimeout=(callback)=>{globalThis.deviceTimer=callback;return 1};
            \\globalThis.clearTimeout=()=>{};
            \\globalThis.devicePending=(()=>{
            \\ let first=true;
            \\ const options={signal:{aborted:false,addEventListener(){},removeEventListener(){}},poll(){
            \\  if(!first)return {status:"complete",value:42};first=false;
            \\  return new Promise(resolve=>{globalThis.deviceRelease=()=>{const result={status:"pending"};deviceWeak.push(new WeakRef(result));resolve(result)}});
            \\ }};
            \\ deviceWeak.push(new WeakRef(options));
            \\ return selectedDevice.pollOAuthDeviceCodeFlow(options);
            \\})();
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        c.JS_RunGC(engine.runtime);
        try run(engine,
            \\if(deviceWeak[0].deref()===undefined)throw Error("Options retired during poll Await");
            \\deviceRelease();delete globalThis.deviceRelease;
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        c.JS_RunGC(engine.runtime);
        try run(engine,
            \\if(deviceWeak.length!==2||deviceWeak.some(ref=>ref.deref()===undefined))throw Error("Loop state retired during sleep Await");
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine,
            \\deviceAfterTimer=true;deviceTimer();delete globalThis.deviceTimer;
            \\if(await devicePending!==42)throw Error("Actual resumed result");delete globalThis.devicePending;
        );
    }
}
test "native OAuth device code status comparison holders retire before the next actual getter" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try select(engine, native);
        try run(engine,
            \\let statusValue=deviceHooks.make(0),calls=0;
            \\globalThis.deviceOptions={signal:{aborted:false},poll(){return {get status(){
            \\ if(calls++===0){const selected=statusValue;statusValue=undefined;return selected}
            \\ if(deviceHooks.count(0)!==1)throw Error("Status comparison retained into next getter");
            \\ return "failed";
            \\},message:"expected status failure"}}};
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine,
            \\let caught=false;try{await selectedDevice.pollOAuthDeviceCodeFlow(deviceOptions)}catch(error){if(error.message!=="expected status failure")throw error;caught=true}
            \\if(!caught||deviceHooks.count(0)!==1)throw Error("Actual status holder control required");
        );
    }
}
test "native OAuth device code replaced slow interval holder retires before subsequent Date" {
    inline for (.{ false, true }) |native| {
        const engine = try x.em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try prepare(engine);
        try select(engine, native);
        try run(engine,
            \\const math=Math;let maximumCalls=0,polls=0,interval;
            \\interval={holder:deviceHooks.make(0),valueOf(){return 1000}};
            \\globalThis.Math={floor:math.floor,min:math.min,max(...args){
            \\ if(maximumCalls++===0){const value=interval;interval=undefined;return value}
            \\ return math.max(...args);
            \\}};
            \\globalThis.Date={now(){if(maximumCalls>1&&deviceHooks.count(0)!==1)throw Error("Replaced interval retained into Date.now");return 0}};
            \\globalThis.setTimeout=(callback)=>{globalThis.deviceTimer=callback;return 1};globalThis.clearTimeout=()=>{};
            \\globalThis.devicePending=selectedDevice.pollOAuthDeviceCodeFlow({
            \\ signal:{aborted:false,addEventListener(){},removeEventListener(){}},
            \\ poll(){return polls++===0?{status:"slow_down"}:{status:"complete",value:7}}
            \\});
        );
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
        try run(engine,
            \\if(deviceHooks.count(0)!==1)throw Error("Prior interval was not released after assignment");
            \\deviceTimer();delete globalThis.deviceTimer;if(await devicePending!==7)throw Error("Actual interval resume");
        );
    }
}
test "native OAuth device code actual status retirement fatal stops the next getter" {
    const engine = try x.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    const hooks = try read(engine, "deviceHooks");
    defer engine.freeValue(hooks);
    const record = try engine.checked(c.JS_GetPropertyStr(engine.context, hooks, "record"));
    defer engine.freeValue(record);
    try run(engine,
        \\let doomed=deviceHooks.make(0),calls=0;
        \\globalThis.deviceOptions={signal:{aborted:false},poll(){return {get status(){
        \\ if(calls++===0){const value=doomed;doomed=undefined;return value}
        \\ deviceHooks.visit(2);return "failed";
        \\},message:"must not reach"}}};
        \\deviceHooks.armFatal(0);
    );
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        "await deviceNative.pollOAuthDeviceCodeFlow(deviceOptions);", "actual-device-status-retirement.mjs"));
    try retirement.verifyActualRetirementFatal(engine, record, 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
