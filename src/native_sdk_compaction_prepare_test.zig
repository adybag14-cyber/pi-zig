const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const api = try sdk.object(engine);
    defer engine.freeValue(api);
    try sdk.put(engine, api, "prepareCompaction", try @import("extensions/native_sdk_compaction_prepare.zig").create(engine));
    try sdk.put(engine, global, "compactionPrepareAPI", c.JS_DupValue(engine.context, api));
}
test "native SDK compaction prepare matches30 original canonical cut recovery split and file observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-compaction-prepare-1692.json");
    try sdk.put(engine, global, "compactionPrepareSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-compaction-prepare-1692.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-compaction-prepare-1692.input.txt") ++
        "\nif(compactionPrepareSource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b'||compactionPrepareRows.length!==30||compactionPrepareSource.rows.length!==30)throw Error('30 original observations required');for(let i=0;i<30;i++)if(JSON.stringify(compactionPrepareRows[i])!==JSON.stringify(compactionPrepareSource.rows[i]))throw Error(JSON.stringify({case:i,actual:compactionPrepareRows[i],expected:compactionPrepareSource.rows[i]}));", "native-sdk-compaction-prepare-source.mjs") catch |err| {
        std.debug.print("Compaction preparation Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK compaction prepare retains lexical callbacks and ordinary constructor across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.retainedPrepare=compactionPrepareAPI.prepareCompaction;delete globalThis.compactionPrepareAPI;const original=Array.prototype.some;Array.prototype.some=function(fn,...args){if(fn.name==='isCutPointMessage')globalThis.retainedCut=fn;return original.call(this,fn,...args);};try{retainedPrepare([{type:'message',id:'a',parentId:null,message:{role:'user',content:'old'}},{type:'message',id:'b',parentId:'a',message:{role:'user',content:'new'}}],{keepRecentTokens:1});}finally{Array.prototype.some=original;}export const prepared=true;
    , "native-sdk-compaction-prepare-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(!retainedCut({role:'assistant'})||retainedCut({role:'toolResult'})||!(new retainedCut({role:'user'}) instanceof retainedCut))throw Error('retained original lexical callback');const settings={keepRecentTokens:1},result=new retainedPrepare([{type:'message',id:'a',parentId:null,message:{role:'user',content:'old'}},{type:'message',id:'b',parentId:'a',message:{role:'user',content:'new'}}],settings);if(result.firstKeptEntryId!=='b'||result.settings!==settings)throw Error('retained preparation');delete globalThis.retainedPrepare;delete globalThis.retainedCut;export const completed=true;
    , "native-sdk-compaction-prepare-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK compaction prepare every allocation releases projection cut callback prefix file and recovery roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const p=compactionPrepareAPI.prepareCompaction,rows=[{type:'message',id:'a',parentId:null,message:{role:'user',content:'request'}},{type:'message',id:'b',parentId:'a',message:{role:'assistant',content:[{type:'toolCall',name:'read',arguments:{path:'file'}}]}},{type:'message',id:'c',parentId:'b',message:{role:'assistant',content:[{type:'text',text:'continuation'}]}}],prepared=p(rows,{keepRecentTokens:1});if(!prepared||!prepared.isSplitTurn||prepared.firstKeptEntryId!=='c'||!prepared.fileOps.read.has('file'))throw Error('split preparation');const recovery=p([{type:'message',id:'x',parentId:null,message:{role:'user',content:'old'}},{type:'message',id:'y',parentId:'x',message:{role:'user',content:'request'}},{type:'message',id:'z',parentId:'y',message:{role:'assistant',content:[{type:'text',text:'failed'}],stopReason:'error'}},{type:'context_edit',id:'edit',parentId:'z',targetId:'z',replacement:null}],{keepRecentTokens:1});if(!recovery)throw Error('recovery preparation');export const proof=true;
            , "native-sdk-compaction-prepare-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
