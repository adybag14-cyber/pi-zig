const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "transcriptContextAPI", try @import("extensions/native_ai_transcript_context.zig").exports(engine));
}
test "native AI transcript context matches20 original normalization identity getters and spread observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/ai-transcript-context-1692.json");
    try sdk.put(engine, global, "transcriptContextSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "ai-transcript-context-1692.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-transcript-context-1692.input.txt") ++
        "\nif(transcriptContextSource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b'||transcriptContextRows.length!==20||transcriptContextSource.rows.length!==20)throw Error('20 original observations required');for(let i=0;i<20;i++)if(JSON.stringify(transcriptContextRows[i])!==JSON.stringify(transcriptContextSource.rows[i]))throw Error(JSON.stringify({case:i,actual:transcriptContextRows[i],expected:transcriptContextSource.rows[i]}));", "native-ai-transcript-context-source.mjs") catch |err| {
        std.debug.print("Transcript context Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI transcript context retained exports preserve array and tool identity across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.retainedTranscript=transcriptContextAPI;delete globalThis.transcriptContextAPI;globalThis.retainedMessages=[{role:'user',content:'hello'}];globalThis.retainedTools=[{name:'read'}];export const prepared=true;
    , "native-ai-transcript-context-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const a=retainedTranscript.normalizeContext({messages:retainedMessages}),b=new retainedTranscript.normalizeContext({systemPrompt:'system',tools:retainedTools,messages:retainedMessages});if(a.messages!==retainedMessages||b.messages[1]!==retainedMessages[0]||b.messages[0].toolsAdded!==retainedTools)throw Error('retained transcript identity');delete globalThis.retainedTranscript;delete globalThis.retainedMessages;delete globalThis.retainedTools;export const completed=true;
    , "native-ai-transcript-context-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native AI transcript context every allocation releases ordinary exports array spreads system and tool roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const f=transcriptContextAPI,messages=[{role:'user',content:'hello'}],tools=[{name:'read'}],a=f.normalizeContext({messages}),b=f.normalizeContext({systemPrompt:'system',tools,messages});if(a.messages!==messages||b.messages[1]!==messages[0]||b.messages[0].toolsAdded!==tools||f.createInitialSystemMessage('',[])!==undefined)throw Error('normalization graph');const marker={},bad={[Symbol.iterator](){return{next(){throw marker;},return(){throw Error('must not close');}};}};try{f.normalizeContext({systemPrompt:'system',messages:bad});throw Error('expected iterator failure');}catch(error){if(error!==marker)throw error;}export const proof=true;
            , "native-ai-transcript-context-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
