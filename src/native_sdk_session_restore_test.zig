const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn setup(engine: *em.Engine) !void {
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_session_restore.zig").install(engine, prototype);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sessionRestoreMethod", try sdk.get(engine, prototype, "_restoreToolsFromTranscript"));
}
test "native SDK transcript restore matches22 original modifiers method metadata live callbacks and failures" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-session-restore-1692.json");
    try sdk.put(engine, global, "sessionRestoreSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-restore-1692.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-restore-1692.input.txt") ++
        "\nif(sessionRestoreRows.length!==22||sessionRestoreSource.rows.length!==22)throw Error('all22 required');for(let i=0;i<22;i++)if(JSON.stringify(sessionRestoreRows[i])!==JSON.stringify(sessionRestoreSource.rows[i]))throw Error(JSON.stringify({case:i,actual:sessionRestoreRows[i],expected:sessionRestoreSource.rows[i]}));", "native-sdk-session-restore-source.mjs") catch |err| {
        std.debug.print("Session restore Source: {s}\n", .{engine.last_error orelse "none"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK transcript restore retained method and allowed callback keep live receiver across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const result = try engine.evalModule(
        \\globalThis.restoreRetained=sessionRestoreMethod;delete globalThis.sessionRestoreMethod;const messages=[{role:'system',content:'',toolsAdded:[{name:'read'}],timestamp:0}],session={_pendingToolNames:new Set(['old']),sessionManager:{buildSessionContext:()=>({messages})},_isAllowedTool(name){return this.allowed===name;},allowed:'read',_setActiveTools(names){this.names=names;}};let held;const filter=Array.prototype.filter;Array.prototype.filter=function(callback){held=callback;return filter.call(this,callback);};try{restoreRetained.call(session,['+write']);}finally{Array.prototype.filter=filter;}globalThis.restoreHeld=held;globalThis.restoreSession=session;if(session.names.join(',')!=='read,write'||[...session._pendingToolNames].join(',')!=='read')throw Error('restore graph');export const ready=true;
    , "native-sdk-session-restore-gc-prepare.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\restoreSession.allowed='write';if(restoreHeld('read')||!restoreHeld('write'))throw Error('live captured receiver');delete globalThis.restoreRetained;delete globalThis.restoreHeld;delete globalThis.restoreSession;export const completed=true;
    , "native-sdk-session-restore-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK transcript restore all host allocation failures release modifiers iterators and pending roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const messages=[{role:'system',content:'',toolsAdded:[{name:'read'},{name:'write'}],timestamp:0}],session={_pendingToolNames:new Set(['old']),sessionManager:{buildSessionContext:()=>({messages})},_isAllowedTool(name){return name!=='write';},_setActiveTools(names){this.names=names;}};sessionRestoreMethod.call(session,{*[Symbol.iterator](){yield'-read';yield'+bash';}});if(session.names.join(',')!=='write,bash'||[...session._pendingToolNames].join(',')!=='bash')throw Error('restore owner graph');const marker={};try{sessionRestoreMethod.call({...session,_setActiveTools(){throw marker;}},[]);throw Error('expected marker');}catch(error){if(error!==marker)throw error;}export const proof=true;
            , "native-sdk-session-restore-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
