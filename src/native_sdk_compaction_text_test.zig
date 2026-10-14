const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "compactionTextAPI", try @import("extensions/native_sdk_compaction_text.zig").exports(engine));
}
test "native SDK compaction text matches30 original serialization truncation getter and failure observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-compaction-text-1692.json");
    try sdk.put(engine, global, "compactionTextSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-compaction-text-1692.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-compaction-text-1692.input.txt") ++
        "\nif(compactionTextSource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b'||compactionTextRows.length!==30||compactionTextSource.rows.length!==30)throw Error('30 original observations required');for(let i=0;i<30;i++)if(JSON.stringify(compactionTextRows[i])!==JSON.stringify(compactionTextSource.rows[i]))throw Error(JSON.stringify({case:i,actual:compactionTextRows[i],expected:compactionTextSource.rows[i]}));", "native-sdk-compaction-text-source.mjs") catch |err| {
        std.debug.print("Compaction text Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK compaction text retains ordinary exports across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.retainedText=compactionTextAPI;delete globalThis.compactionTextAPI;export const prepared=true;
    , "native-sdk-compaction-text-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(retainedText.serializeConversation([{role:'user',content:'hello'}])!=='[User]: hello'||retainedText.getSummarizationFailure({stopReason:'error'},'Summary')!=='Summary failed: Unknown error'||!(new retainedText.serializeConversation([]) instanceof retainedText.serializeConversation))throw Error('retained text functions');delete globalThis.retainedText;export const completed=true;
    , "native-sdk-compaction-text-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK compaction text every native allocation releases iterators destructured arguments formatting and failure roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const t=compactionTextAPI,result=t.serializeConversation([{role:'user',content:[{type:'text',text:'request'}]},{role:'assistant',content:[{type:'thinking',thinking:'omitted'},{type:'toolCall',name:'read',arguments:{path:'a',missing:undefined}},{type:'text',text:'answer'}]},{role:'toolResult',content:'x'.repeat(2001)}]);if(!result.includes('read(path="a", missing=undefined)')||!result.includes('1 more characters truncated')||result.includes('omitted')||t.getSummarizationFailure({stopReason:'length'},'Summary')!=='Summary failed: generation hit the token cap and the summary is incomplete')throw Error('serialization graph');const marker={},messages={*[Symbol.iterator](){try{yield{get role(){throw marker;}};}finally{}}};try{t.serializeConversation(messages);throw Error('expected getter failure');}catch(error){if(error!==marker)throw error;}export const proof=true;
            , "native-sdk-compaction-text-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
