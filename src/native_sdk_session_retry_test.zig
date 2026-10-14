const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

fn helper(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const first = if (argc > 0) argv[0] else c.pi_js_undefined();
    const second = if (argc > 1) argv[1] else c.pi_js_undefined();
    return switch (magic) {
        0 => @import("extensions/native_durable_retry.zig").delay(engine, first, second) catch |err| sdk.fail(engine, err),
        1 => @import("extensions/native_sdk_sleep.zig").sleep(engine, first, second) catch |err| sdk.fail(engine, err),
        2 => c.pi_js_bool(engine.context, @intFromBool(@import("extensions/native_ai_error_classification.zig").overflow(engine, first, second) catch |err| return sdk.fail(engine, err))),
        3 => c.pi_js_bool(engine.context, @intFromBool(@import("extensions/native_ai_error_classification.zig").recoverableLength(engine, first, second) catch |err| return sdk.fail(engine, err))),
        4 => c.pi_js_bool(engine.context, @intFromBool(@import("extensions/native_ai_error_classification.zig").retryable(engine, first) catch |err| return sdk.fail(engine, err))),
        5 => @import("extensions/native_ai_error_classification.zig").getOverflowPatterns(engine) catch |err| sdk.fail(engine, err),
        else => unreachable,
    };
}
fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    try @import("native_sdk_session_prompt_handlers_test.zig").setup(engine, environment);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const namespace = try sdk.get(engine, global, "constructorPhaseSDK");
    defer engine.freeValue(namespace);
    const constructor = try sdk.get(engine, namespace, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    const dependencies = try sdk.object(engine);
    defer engine.freeValue(dependencies);
    try @import("extensions/native_sdk_chat_transport.zig").install(engine, dependencies);
    try sdk.put(engine, dependencies, "convertToLlm", try @import("extensions/native_sdk_messages.zig").create(engine));
    try @import("extensions/native_sdk_session_request_auth.zig").install(engine, prototype, dependencies);
    try @import("extensions/native_sdk_session_retry.zig").install(engine, prototype);
    const helpers = try sdk.object(engine);
    defer engine.freeValue(helpers);
    inline for (.{ "retryDelayMs", "sleep", "isContextOverflow", "isRecoverableLength", "isRetryableAssistantError", "getOverflowPatterns" }, 0..) |name, magic| {
        try sdk.put(engine, helpers, name, try engine.checked(c.pi_js_function_magic(engine.context, helper, name, if (magic == 5) 0 else if (magic == 4) 1 else 2, magic)));
    }
    // Private test bindings invoke native helpers directly. Public export/module
    // metadata and complete SDK factory composition require separate gates.
    try sdk.put(engine, global, "retryHelperAPI", c.JS_DupValue(engine.context, helpers));
    const source = @embedFile("extensions/fixtures/sdk-session-retry-1692.json");
    try sdk.put(engine, global, "sessionRetrySource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-retry-1692.json")));
    const adapter = try engine.evalModule(
        \\globalThis.createRetryCase=async()=>createNativeConstructorPhase();
    , "native-sdk-session-retry-adapter.mjs");
    engine.freeValue(adapter);
}

test "native SDK session retry matches31 original factory callback omission and abortable backoff observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-retry-1692.input.txt") ++
        "\nif(sessionRetrySource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b'||sessionRetryRows.length!==31||sessionRetrySource.rows.length!==31||sessionRetrySource.factoryCount!==31)throw Error('31 original latest retry cases required');for(let i=0;i<31;i++)if(JSON.stringify(sessionRetryRows[i])!==JSON.stringify(sessionRetrySource.rows[i]))throw Error(JSON.stringify({case:i,actual:sessionRetryRows[i],expected:sessionRetrySource.rows[i]}));", "native-sdk-session-retry-corpus.mjs") catch |err| {
        std.debug.print("Session retry corpus: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session retry classifier executes30 original overflow provider identity and model fallback cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-retry-classifier-1692.input.txt") ++
        "\nif(sessionRetryClassifierRows.length!==30)throw Error('30 classifier cases must execute');", "native-sdk-session-retry-classifier-corpus.mjs") catch |err| {
        std.debug.print("Session retry classifier corpus: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session retry classifier retained some callback owns its message across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\(()=>{const message={stopReason:'error',errorMessage:'prompt too long'},original=Array.prototype.some;let callback;Array.prototype.some=function(value,...args){callback=value;return original.call(this,value,...args);};try{if(!retryHelperAPI.isContextOverflow(message))throw Error('expected overflow');}finally{Array.prototype.some=original;}globalThis.classifierRetained={callback,pattern:retryHelperAPI.getOverflowPatterns()[0]};})();export const prepared=true;
    , "native-sdk-session-retry-classifier-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(classifierRetained.callback(classifierRetained.pattern)!==true)throw Error('classifier callback message lost');delete globalThis.classifierRetained;export const completed=true;
    , "native-sdk-session-retry-classifier-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session retry retains callback source timer controller and promise owners across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createRetryCase(),events=[],source={source:'compaction',reason:'manual'};state.session._emit=event=>events.push(event);state.settings.getRetrySettings=()=>({enabled:true,maxRetries:2,baseDelayMs:100});state.session._omitRecoveryAttempt=()=>{};const callbacks=state.session._summarizationRetryCallbacks(source),pending=state.session._prepareRetry({errorMessage:'failure'});globalThis.retryRetained={state,events,source,callbacks,pending};export const prepared=true;
    , "native-sdk-session-retry-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const r=retryRetained;r.source.reason='threshold';r.callbacks.onRetryAttemptStart.call({});if(r.events[1].reason!=='threshold')throw Error('live callback source lost');r.state.session._retryAbortController.abort();if(await r.pending!==false||r.state.session._retryAttempt!==0||r.state.session._retryAbortController!==undefined||r.events[2].type!=='auto_retry_end')throw Error('retry roots lost');r.state.dispose();delete globalThis.retryRetained;export const completed=true;
    , "native-sdk-session-retry-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session retry every allocation failure releases patterns callbacks sleep and omission owner graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            const generation = engine.native_allocation_generation;
            setup(engine, &environment) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const state=await createRetryCase(),events=[];state.session._emit=event=>events.push(event);state.settings.getRetrySettings=()=>({enabled:true,maxRetries:2,baseDelayMs:0});state.session._findPersistedMessageEntryId=()=>undefined;state.session._refreshFinalizedContext=()=>{};if(await state.session._prepareRetry({errorMessage:'failure'})!==true||events.length!==1)throw Error('retry allocation result');const callbacks=state.session._summarizationRetryCallbacks({source:'branchSummary'});callbacks.onRetryScheduled(1,2,0,'failure');callbacks.onRetryAttemptStart();callbacks.onRetryFinished();if(!retryHelperAPI.isContextOverflow({stopReason:'error',errorMessage:'prompt is too long'}))throw Error('overflow classifier');if(!retryHelperAPI.isRetryableAssistantError({stopReason:'error',errorMessage:'unable to forward upstream'}))throw Error('retry classifier');state.dispose();export const proof=true;
            , "native-sdk-session-retry-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
