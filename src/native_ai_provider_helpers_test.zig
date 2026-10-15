const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn install(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const text = try scope.own(try @import("extensions/native_ai_text.zig").create(engine));
    const estimate = try scope.own(try @import("extensions/native_ai_estimate.zig").create(engine));
    const thinking = try scope.own(try @import("extensions/native_ai_thinking.zig").create(engine));
    const simple = try scope.own(try @import("extensions/native_ai_simple_options.zig").create(engine, try scope.get(thinking, "clampThinkingLevel"), try scope.get(estimate, "estimateContextTokens")));
    try scope.put(global, "aiTextAPI", text);
    try scope.put(global, "aiEstimateAPI", estimate);
    try scope.put(global, "aiThinkingAPI", thinking);
    try scope.put(global, "aiSimpleAPI", simple);
}
test "native AI provider helpers match112 actual original text estimate thinking and simple-options observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/ai-provider-helpers-b45.json");
    try sdk.put(engine, global, "aiHelperSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "ai-provider-helpers-b45.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-provider-helpers-b45.input.txt") ++
        "\nif(aiHelperRows.length!==112||aiHelperSource.rows.length!==112||aiHelperSource.sourceHead!=='b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb')throw Error('all112 required');for(let i=0;i<112;i++)if(JSON.stringify(aiHelperRows[i])!==JSON.stringify(aiHelperSource.rows[i]))throw Error(JSON.stringify({case:i,actual:aiHelperRows[i],expected:aiHelperSource.rows[i]}));", "native-ai-provider-helpers-original.mjs") catch |err| {
        std.debug.print("AI helpers Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI provider helpers private OpenAI compat detection retains Source-audited branches and overrides" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const Adapter = struct {
        fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return @import("extensions/native_ai_openai_compat_options.zig").resolve(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "detectOpenAICompat", try @import("extensions/native_node_function.zig").create(engine, "detectOpenAICompat", 1, Adapter.call, &.{}));
    const result = try engine.evalModule(
        \\const model={id:'model',provider:'openai',baseUrl:'http://127.0.0.1:1/v1'},a=detectOpenAICompat(model);if(!a.supportsStore||!a.supportsDeveloperRole||a.maxTokensField!=='max_completion_tokens'||a.thinkingFormat!=='openai'||a.supportsStrictMode)throw Error('original default flags');
        \\const d=detectOpenAICompat({...model,provider:'deepseek'});if(d.supportsStore||d.supportsDeveloperRole||d.maxTokensField!=='max_tokens'||d.thinkingFormat!=='deepseek'||!d.requiresReasoningContentOnAssistantMessages)throw Error('DeepSeek flags');
        \\const r=detectOpenAICompat({...model,provider:'openrouter',id:'anthropic/model'});if(!r.supportsDeveloperRole||r.cacheControlFormat!=='anthropic'||r.sessionAffinityFormat!=='openrouter')throw Error('OpenRouter flags');
        \\const override={supportsStore:false,maxTokensField:'caller',vllmPriority:0},o=detectOpenAICompat({...model,compat:override});if(o.supportsStore||o.maxTokensField!=='caller'||o.vllmPriority!==0)throw Error('explicit overrides');export const proof=true;
    , "native-ai-provider-helpers-controlled-compat.mjs");
    engine.freeValue(result);
}
test "native AI provider helpers retained lexical bindings and mutable budget export survive collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule("globalThis.keptSimple=aiSimpleAPI;globalThis.keptEstimate=aiEstimateAPI;delete globalThis.aiTextAPI;delete globalThis.aiEstimateAPI;delete globalThis.aiThinkingAPI;delete globalThis.aiSimpleAPI;export const ready=true;", "native-ai-provider-helpers-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const result = try engine.evalModule(
        \\const model={reasoning:true,contextWindow:32000,maxTokens:8192},context={messages:[{role:'user',content:'hello',timestamp:0}]};if(keptSimple.buildBaseOptions(model,context).maxTokens!==8192||keptEstimate.estimateContextTokens(context).tokens!==2)throw Error('retained dependencies');keptSimple.DEFAULT_THINKING_BUDGETS.low=321;if(keptSimple.thinkingBudgetForLevel('low')!==321)throw Error('shared budget');delete globalThis.keptSimple;delete globalThis.keptEstimate;export const done=true;
    , "native-ai-provider-helpers-gc-complete.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI provider helpers every host allocation releases text sections context usage clamping and options graph" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const model={reasoning:true,contextWindow:32000,maxTokens:8192,thinkingLevelMap:{max:'max'},samplingParams:{top_p:0.8}},context={messages:[{role:'system',content:'base',sections:{one:'first',gone:null},toolsAdded:[{name:'read',parameters:{type:'object'}}],timestamp:0},{role:'user',content:'hello',timestamp:1},{role:'assistant',content:[{type:'text',text:'answer'}],usage:{input:10,output:3,cacheRead:2,cacheWrite:0,totalTokens:15},stopReason:'stop',timestamp:2},{role:'user',content:'tail',timestamp:3}]};
                \\if(aiTextAPI.getSystemMessageText(context.messages[0])!=='base\n\nfirst'||aiEstimateAPI.estimateMessageTokens(context.messages[0])<=0||aiEstimateAPI.estimateContextTokens(context).tokens!==17||aiThinkingAPI.clampThinkingLevel(model,'max')!=='max'||aiSimpleAPI.buildBaseOptions(model,context,{reasoning:'low',samplingParams:{top_p:0.9}}).samplingParams.top_p!==0.9)throw Error('provider helper owner graph');const cyclic={};cyclic.self=cyclic;if(aiEstimateAPI.estimateMessageTokens({role:'assistant',content:[{type:'toolCall',name:'read',arguments:cyclic}]})!==6)throw Error('safe serialization fallback');export const proof=true;
            , "native-ai-provider-helpers-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
