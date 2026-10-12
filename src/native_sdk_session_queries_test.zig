const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

test "native SDK session queries callable tools match actual latest factory loadouts" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("PI_AGENT_DIR", path[0..count]);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "pi-sdk-test", "callable.mjs" });
    try @import("extensions/native_stream.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-session-queries", exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    inline for (.{ .{ "ownedAuthPath", "auth.json" }, .{ "ownedModelsPath", "models.json" } }) |entry| {
        const filename = try std.fs.path.join(engine.gpa, &.{ path[0..count], entry[1] });
        defer engine.gpa.free(filename);
        try sdk.put(engine, root, entry[0], try sdk.text(engine, filename));
    }
    const original = @embedFile("extensions/fixtures/sdk-callable-19cb.json");
    try sdk.put(engine, root, "callableSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-callable-19cb.json")));
    const hooks = @embedFile("extensions/fixtures/sdk-callable-hooks-19cb.json");
    try sdk.put(engine, root, "callableHookSource", try engine.checked(c.JS_ParseJSON(engine.context, hooks.ptr, hooks.len, "sdk-callable-hooks-19cb.json")));
    const observed = engine.evalModule("import{AgentSession,createAgentSession,ModelRuntime,SessionManager,SettingsManager,DefaultResourceLoader}from'sdk-session-queries';\n" ++ @embedFile("extensions/fixtures/sdk-callable-19cb.input.txt") ++
        "\nif(JSON.stringify(sdkCallableRows)!==JSON.stringify(callableSource.rows))throw Error(JSON.stringify({actual:sdkCallableRows,expected:callableSource.rows}));\n" ++
        @embedFile("extensions/fixtures/sdk-callable-hooks-19cb.input.txt") ++
        "\nif(JSON.stringify(sdkCallableHookRows)!==JSON.stringify(callableHookSource.rows))throw Error(JSON.stringify({actual:sdkCallableHookRows,expected:callableHookSource.rows}));", "sdk-callable-source.mjs") catch |err| {
        std.debug.print("SDK callable Source replay: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
}

test "native SDK session queries fork messages match actual Source iterators text and errors" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-fork-query", exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/sdk-fork-query-19cb.json");
    try sdk.put(engine, root, "forkSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "sdk-fork-query-19cb.json")));
    const observed = engine.evalModule("import{AgentSession,SessionManager}from'sdk-fork-query';\n" ++ @embedFile("extensions/fixtures/sdk-fork-query-19cb.input.txt") ++
        "\nif(JSON.stringify(sdkForkRows)!==JSON.stringify(forkSource.rows))throw Error(JSON.stringify({actual:sdkForkRows,expected:forkSource.rows}));", "sdk-fork-query-source.mjs") catch |err| {
        std.debug.print("SDK fork query Source replay: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
}

fn queryAllocations(failing: *std.testing.FailingAllocator, offset: ?usize, directory: []const u8) !usize {
    const engine = try em.Engine.init(failing.allocator(), .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(failing.allocator());
    defer environment.deinit();
    try environment.put("PI_AGENT_DIR", directory);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "pi-sdk-test", "queries-gpa.mjs" });
    try @import("extensions/native_stream.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("sdk-query-allocation", exports);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try sdk.put(engine, root, "queryDirectory", try sdk.text(engine, directory));
    const setup = try engine.evalModule(
        \\import{createAgentSession,ModelRuntime,SessionManager,SettingsManager,DefaultResourceLoader}from'sdk-query-allocation';
        \\const runtime=await ModelRuntime.create({authPath:queryDirectory+'/auth.json',modelsPath:queryDirectory+'/models.json',refreshOnCreate:false});
        \\const model={id:'m',provider:'fixture',api:'fixture',type:'chat',reasoning:false,input:['text'],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:8192,maxTokens:512};
        \\const settings=SettingsManager.inMemory(),loader=new DefaultResourceLoader({cwd:queryDirectory,agentDir:queryDirectory,settingsManager:settings,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true});await loader.reload();
        \\const customTools=['direct','codemode','deferred'].map((exposure,index)=>({name:'probe'+index,label:'probe',description:'probe',exposure,parameters:{type:'object'},execute:async()=>({content:[]})}));
        \\const{session}=await createAgentSession({cwd:queryDirectory,agentDir:queryDirectory,model,modelRuntime:runtime,sessionManager:SessionManager.inMemory(queryDirectory),settingsManager:settings,resourceLoader:loader,tools:['*'],customTools});
        \\session.sessionManager.appendMessage({role:'user',content:[{type:'text',text:'one'},{type:'text',text:'two'}],timestamp:1});globalThis.queryProbeSession=session;
    , "sdk-query-allocation-setup.mjs");
    engine.freeValue(setup);
    const before = failing.alloc_index;
    if (offset) |index| failing.fail_index = before + index;
    const generation = engine.native_allocation_generation;
    const observed = engine.evalModule(
        \\const names=queryProbeSession.getCallableToolNames();if(!names.includes('probe0')||!names.includes('probe1')||!names.includes('probe2'))throw Error('callable tools');
        \\const rows=queryProbeSession.getUserMessagesForForking();if(rows.length!==1||rows[0].text!=='onetwo')throw Error('fork query');
    , "sdk-query-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
    return failing.alloc_index - before;
}

test "native SDK session queries release every induced query-phase host allocation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const total = try queryAllocations(&baseline, null, path[0..count]);
    try std.testing.expect(total > 0);
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    for (0..total) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        try std.testing.expectError(error.OutOfMemory, queryAllocations(&failing, index, path[0..count]));
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
    std.debug.print("SDK_QUERY_ALLOCATION_COMPLETE indices={d}\n", .{total});
}
