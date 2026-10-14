const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn setup(engine: *em.Engine) !void {
    try @import("native_sdk_complete_summarization_test.zig").setup(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const request_api = try sdk.get(engine, global, "summaryAPI");
    defer engine.freeValue(request_api);
    const request = try sdk.get(engine, request_api, "completeSummarization");
    defer engine.freeValue(request);
    try sdk.put(engine, global, "summaryGenerationAPI", try @import("extensions/native_sdk_summary_generation.zig").exports(engine, request));
    const file_api = try @import("extensions/native_sdk_compaction_files.zig").exports(engine);
    defer engine.freeValue(file_api);
    try sdk.put(engine, global, "createSummaryFileOps", try sdk.get(engine, file_api, "createFileOps"));
}
test "native summary generation matches45 original prompts budgets usage split turns errors and live getters" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-summary-generation-b45.json");
    try sdk.put(engine, global, "summaryGenerationSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-summary-generation-b45.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-summary-generation-b45.input.txt") ++
        "\nif(summaryGenerationRows.length!==45||summaryGenerationSource.rows.length!==45)throw Error('all45 required');for(let i=0;i<45;i++)if(JSON.stringify(summaryGenerationRows[i])!==JSON.stringify(summaryGenerationSource.rows[i]))throw Error(JSON.stringify({case:i,actual:summaryGenerationRows[i],expected:summaryGenerationSource.rows[i]}));", "native-summary-generation-source.mjs") catch |err| {
        std.debug.print("Summary generation Source: {s}\n", .{engine.last_error orelse "none"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native summary generation pending stream retains full generated prompt response and usage across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const prepared = try engine.evalModule(
        \\globalThis.generationUsage={input:1},globalThis.generationResponse={role:'assistant',content:[{type:'text',text:'kept'}],stopReason:'stop',usage:generationUsage};globalThis.generationPending=summaryGenerationAPI.generateSummaryWithUsage([{role:'user',content:'request',timestamp:0}],{maxTokens:50,reasoning:true},100,'fixture',undefined,undefined,'focus','previous','high',(m,c,o)=>{globalThis.generationRequest={m,c,o};return new Promise(resolve=>{globalThis.generationRelease=resolve;});},undefined,undefined,undefined,'owned');delete globalThis.summaryGenerationAPI;export const ready=true;
    , "native-summary-generation-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\generationRelease({result(){return generationResponse;}});const result=await generationPending;if(result.text!=='kept'||result.usage!==generationUsage||generationRequest.o.maxTokens!==50||generationRequest.o.reasoning!=='high'||!generationRequest.c.messages[1].content[0].text.includes('<previous-summary>'))throw Error('generation retained graph');delete globalThis.generationUsage;delete globalThis.generationResponse;delete globalThis.generationPending;delete globalThis.generationRequest;delete globalThis.generationRelease;export const completed=true;
    , "native-summary-generation-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native summary generation complete host allocation graph covers history prefix usage and file tracking" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const api=summaryGenerationAPI,usage={input:1,output:2,cacheRead:3,cacheWrite:4,totalTokens:10,cost:{input:1,output:2,cacheRead:3,cacheWrite:4,total:10}},model={maxTokens:100,reasoning:true},messages=[{role:'user',content:'request',timestamp:0}],stream=(m,c,o)=>({result:()=>Promise.resolve({role:'assistant',content:[{type:'text',text:'checkpoint'}],stopReason:'stop',usage})});const text=await api.generateSummary(messages,model,100,'fixture',undefined,undefined,'focus','previous','high',stream,undefined,undefined,undefined,'owned');if(text!=='checkpoint')throw Error('history wrapper');const fileOps=createSummaryFileOps();fileOps.read.add('read-only');fileOps.edited.add('changed');const result=await api.compact({firstKeptEntryId:'kept',messagesToSummarize:messages,turnPrefixMessages:messages,isSplitTurn:true,tokensBefore:50,fileOps,settings:{reserveTokens:100}},model,'fixture',undefined,undefined,undefined,'high',stream,undefined,undefined,undefined,'owned');if(!result.summary.includes('Turn Context (split turn)')||result.usage.totalTokens!==20||result.details.readFiles[0]!=='read-only'||result.details.modifiedFiles[0]!=='changed')throw Error('split usage files graph');export const proof=true;
            , "native-summary-generation-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
