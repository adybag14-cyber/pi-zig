const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sessionProjectionAPI", try @import("extensions/native_sdk_session_projection_live.zig").exports(engine));
}
test "native SDK live projection matches30 original path getter edit identity and context observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-session-projection-live-1692.json");
    try sdk.put(engine, global, "projectionSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-projection-live-1692.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-projection-live-1692.input.txt") ++
        "\nif(projectionSource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b'||projectionRows.length!==30||projectionSource.rows.length!==30)throw Error('30 original observations required');for(let i=0;i<30;i++)if(JSON.stringify(projectionRows[i])!==JSON.stringify(projectionSource.rows[i]))throw Error(JSON.stringify({case:i,actual:projectionRows[i],expected:projectionSource.rows[i]}));", "native-sdk-session-projection-live-source.mjs") catch |err| {
        std.debug.print("Live session projection Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK live projection retained ordinary exports survive collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.retainedProjection=sessionProjectionAPI;delete globalThis.sessionProjectionAPI;globalThis.retainedEntry={type:'message',id:'a',parentId:null,message:{role:'user',content:'hello'}};export const prepared=true;
    , "native-sdk-session-projection-live-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const p=new retainedProjection.buildSessionProjection([retainedEntry]);if(p.entries[0].sourceEntry!==retainedEntry||p.messages[0]!==retainedEntry.message)throw Error('retained projection identity');delete globalThis.retainedProjection;delete globalThis.retainedEntry;export const completed=true;
    , "native-sdk-session-projection-live-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK live projection cyclic parent chains remain interruptible instead of returning a truncated path" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 2 });
    defer engine.deinit();
    try install(engine);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\sessionProjectionAPI.buildContextEntries([{type:'message',id:'a',parentId:'a',message:{role:'user',content:'hello'}}]);export const unreachable=true;
    , "native-sdk-session-projection-live-cycle.mjs"));
    try std.testing.expect(engine.interrupts > engine.options.interrupt_budget);
    c.JS_RunGC(engine.runtime);
}
test "native SDK live projection every native allocation releases maps iterators callbacks edits and compaction roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const f=sessionProjectionAPI,a={type:'message',id:'a',parentId:null,message:{role:'assistant',content:[],provider:'p',model:'m'}},b={type:'custom_message',id:'b',parentId:'a',customType:'x',content:null,display:false,timestamp:0},c={type:'compaction',id:'c',parentId:'b',firstKeptEntryId:'a',summary:'summary',tokensBefore:2,timestamp:0,systemMessage:{role:'system',content:'base'}},e={type:'context_edit',id:'e',parentId:'c',targetId:'a',replacement:{content:'replacement'}},p=f.buildSessionProjection([a,b,c,e]);if(p.entries.length!==4||p.messages.length!==4||p.messages[2].content[0].text!=='replacement'||p.entries[1].sourceEntry!==a)throw Error('projected retained range');const marker={},entries={*[Symbol.iterator](){try{yield{get id(){throw marker;}};}finally{}}};try{f.buildContextEntries(entries,null);throw Error('expected index failure');}catch(error){if(error!==marker)throw error;}export const proof=true;
            , "native-sdk-session-projection-live-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
