const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

test "native SDK private session lifecycle matches actual Source custom run and settlement phases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    const constructor = try sdk.get(engine, exports, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    // Bind actual native component bodies only in this owned test context.
    // Production factory activation still requires all session dependencies.
    try @import("extensions/native_sdk_custom_message.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_run.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_settled.zig").install(engine, prototype);
    try engine.registerValueModule("sdk-private-session-lifecycle", exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/sdk-session-lifecycle-19cb.json");
    try sdk.put(engine, root, "lifecycleSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-session-lifecycle-19cb.json")));
    const observed = engine.evalModule("import{AgentSession,SessionManager}from'sdk-private-session-lifecycle';\n" ++
        @embedFile("extensions/fixtures/sdk-session-custom-19cb.input.txt") ++ "\n" ++
        @embedFile("extensions/fixtures/sdk-session-run-19cb.input.txt") ++ "\n" ++
        @embedFile("extensions/fixtures/sdk-session-settled-19cb.input.txt") ++ "\n" ++
        @embedFile("extensions/fixtures/sdk-session-transcript-19cb.input.txt") ++
        "\nfor(const [key,actual]of[['custom',sdkCustomRows],['run',sdkSessionRunRows],['settled',sdkSessionSettledRows],['transcript',sdkSessionTranscriptRows]])if(JSON.stringify(actual)!==JSON.stringify(lifecycleSource[key]))throw Error(JSON.stringify({key,actual,expected:lifecycleSource[key]}));", "sdk-session-lifecycle-source.mjs") catch |err| {
        std.debug.print("Session lifecycle Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
}

test "native SDK private session lifecycle post-run retry compaction and boundary decisions match original Source" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    const constructor = try sdk.get(engine, exports, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_session_post_run.zig").install(engine, prototype);
    try engine.registerValueModule("sdk-private-post-run", exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/sdk-session-post-run-19cb.json");
    try sdk.put(engine, root, "postRunSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-session-post-run-19cb.json")));
    const observed = engine.evalModule("import{AgentSession}from'sdk-private-post-run';\n" ++
        @embedFile("extensions/fixtures/sdk-session-post-run-19cb.input.txt") ++
        "\nfor(const[key,actual]of[['post',sdkPostRows],['boundary',sdkBoundaryRows]])if(JSON.stringify(actual)!==JSON.stringify(postRunSource[key]))throw Error(JSON.stringify({key,actual,expected:postRunSource[key]}));", "sdk-session-post-run-source.mjs") catch |err| {
        std.debug.print("Session post-run Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}

fn lifecycleAllocations(failing: *std.testing.FailingAllocator, offset: ?usize, operation: usize) !usize {
    const engine = try em.Engine.init(failing.allocator(), .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    const constructor = try sdk.get(engine, exports, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_custom_message.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_run.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_post_run.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_settled.zig").install(engine, prototype);
    try engine.registerValueModule("sdk-lifecycle-allocation", exports);
    const setup = try engine.evalModule(
        \\import{AgentSession,SessionManager}from'sdk-lifecycle-allocation';
        \\const receiver=Object.create(AgentSession.prototype),manager=SessionManager.inMemory('/lifecycle-allocation');Object.defineProperty(receiver,'isStreaming',{value:false});
        \\Object.assign(receiver,{sessionManager:manager,_entryIdsByMessage:new Map(),_pendingCustomMessages:[],_pendingNextTurnMessages:[],_deferredSettledActions:[],_pendingToolNames:new Set(),_lastAssistantToolResults:[],_agentRunAbortRequested:false,_isEmittingAgentSettled:false,
        \\_extensionRunner:{hasHandlers(){return false},async emit(){}},_cacheWarmer:{onAgentSettled(){}},_emit(){},_resolveIdleWaitIfIdle(){},_flushPendingBashMessages(){},_recordSelection(){},async _prepareRun(trigger){return[trigger.message??{role:'user',content:'prompt',timestamp:1}]},
        \\agent:{state:{isStreaming:false,messages:[]},hasQueuedMessages(){return false},async prompt(){await Promise.resolve()},async continue(){await Promise.resolve()}}});globalThis.lifecycleAllocationReceiver=receiver;
    , "sdk-lifecycle-allocation-setup.mjs");
    engine.freeValue(setup);
    const before = failing.alloc_index;
    if (offset) |index| failing.fail_index = before + index;
    const generation = engine.native_allocation_generation;
    const programs = [_][]const u8{
        "await lifecycleAllocationReceiver._startRun({messageType:'user',text:'hello'});if(lifecycleAllocationReceiver._isAgentRunActive||lifecycleAllocationReceiver._isEmittingAgentSettled)throw Error('run flags');",
        "await lifecycleAllocationReceiver.sendCustomMessage({customType:'probe',content:[{type:'text',text:'hello'}],display:true},{triggerTurn:true});if(lifecycleAllocationReceiver._isAgentRunActive)throw Error('custom flags');",
        "lifecycleAllocationReceiver._deferredSettledActions.push(async()=>{await Promise.resolve()},async()=>{await Promise.resolve()});await lifecycleAllocationReceiver._emitAgentSettled();if(lifecycleAllocationReceiver._isEmittingAgentSettled||lifecycleAllocationReceiver._deferredSettledActions.length)throw Error('settled flags');",
    };
    const result = engine.evalModule(programs[operation], "sdk-lifecycle-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    return failing.alloc_index - before;
}

test "native SDK private session lifecycle releases induced run custom and settlement allocations" {
    for (0..3) |operation| {
        var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const total = try lifecycleAllocations(&baseline, null, operation);
        try std.testing.expect(total > 0);
        try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
        for (0..total) |index| {
            var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
            try std.testing.expectError(error.OutOfMemory, lifecycleAllocations(&failing, index, operation));
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        }
        std.debug.print("SDK_LIFECYCLE_ALLOCATION_COMPLETE operation={d} indices={d}\n", .{ operation, total });
    }
}
