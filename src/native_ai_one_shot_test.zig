const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn install(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/native_url.zig").install(engine);
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/native_headers.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const apis = try scope.object();
    try scope.put(apis, "image", try scope.own(try @import("extensions/native_ai_images_factory.zig").create(engine)));
    inline for (.{ "typesafe", "cloudflare", "decisions" }) |name| try scope.put(apis, name, try scope.own(try @import("extensions/native_ai_classifier_factory.zig").create(engine, @field(@import("extensions/native_ai_classifier_factory.zig").Kind, name))));
    try scope.put(apis, "llama", try scope.own(try @import("extensions/native_ai_llama_classifier_factory.zig").create(engine)));
    try scope.put(apis, "shared", try scope.own(try @import("extensions/native_ai_classifier_shared.zig").create(engine)));
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "oneShotAPIs", apis);
}
fn evaluate(engine: *em.Engine, source: []const u8, name: [:0]const u8) !void {
    const result = engine.evalModule(source, name) catch |err| {
        std.debug.print("One-shot APIs: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
}
test "native AI one shot source-controlled requests outputs billed malformed answers and llama cache" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 10000000 });
    defer engine.deinit();
    try install(engine);
    try evaluate(engine, @embedFile("extensions/fixtures/ai-one-shot-5ab.input.txt") ++
        \\if(oneShotRows.length!==80)throw Error('complete80 control set');const row=(kind,mode)=>oneShotRows.find(value=>value.kind===kind&&value.mode===mode),image=row('image','valid').result;if(image.stopReason!=='stop'||image.output.length!==3||image.output[0].text!=='rendered'||image.output[1].mimeType!=='image/png'||image.output[2].data!=='BB=='||image.usage.input!==12||image.usage.cacheRead!==5||image.usage.cacheWrite!==3||image.usage.cost.input!==.000024)throw Error('image output and flat catalog cost');for(const kind of ['typesafe','cloudflare','decisions']){const valid=row(kind,'valid');if(valid.result.stopReason!=='stop'||valid.result.answers.bool.probability!==.8||valid.result.answers.choice.choice!=='a'||valid.result.usage.cost.input!==.00006)throw Error(kind+' output');const malformed=row(kind,'malformed-answer').result;if(malformed.stopReason!=='error'||Object.keys(malformed.answers).length||malformed.usage.input!==12)throw Error('billed malformed answer');if(row(kind,'retry').requests.length!==2||row(kind,'no-key').requests.length!==0)throw Error('auth/retry');}if(row('decisions','gateway504').requests.length!==1||!row('decisions','gateway504').result.errorMessage.includes('timed out at the gateway'))throw Error('Decisions 504 no-retry');if(row('llama','no-key').result.stopReason!=='stop'||row('llama','valid').result.usage!==undefined||row('llama','cache-reuse').requests.some(value=>value.path==='/tokenize'))throw Error('local auth/cache');if(row('llama','escalate').requests.filter(value=>value.path==='/completion').map(value=>value.body.n_probs).join(',')!=='256,4096'||row('llama','missing-label').requests.filter(value=>value.path==='/completion').map(value=>value.body.n_probs).join(',')!=='256,4096,32768')throw Error('readout depths');if(row('llama','choice-question').result.answers.choice.choice!=='a'||!(row('llama','score-question').result.answers.score.score>0&&row('llama','score-question').result.answers.score.score<1)||Object.keys(row('llama','multi-questions').result.answers).length!==3)throw Error('answer types');const diagnostic=oneShotRawHeaders.find(value=>value.kind==='image'&&value.mode==='valid').requests[0],headers=Object.fromEntries(diagnostic);if(headers['x-pi-runtime']!=='zig'||headers['x-pi-engine']!=='quickjs-ng'||!headers['user-agent'].startsWith('pi-zig (Zig ')||headers['x-stainless-lang']==='js'||headers['x-stainless-runtime']==='node')throw Error('native runtime identity');if(row('image','header-override').requests[0].headers['user-agent']!=='explicit-caller')throw Error('strict caller override');
    , "native-ai-one-shot-controls.mjs");
    c.JS_RunGC(engine.runtime);
}
test "native AI one shot retained classifier and image dependency graphs survive GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try evaluate(engine,
        \\globalThis.keptOneShot=oneShotAPIs;delete globalThis.oneShotAPIs;for(const kind of ['image','typesafe','cloudflare','decisions','llama']){const fn=keptOneShot[kind][kind==='image'?'generateImages':'classify'];if(fn.length!==3||Object.hasOwn(fn,'prototype'))throw Error('arrow metadata')}const a=keptOneShot.llama.renderQuestion({state:{},questions:{q:{type:'bool',instructions:'q',criteria:{}}}},'q'),b=keptOneShot.llama.renderQuestion({state:{},questions:{q:{type:'bool',instructions:'q',criteria:{}}}},'q');if(a.labels!==b.labels)throw Error('private boolean label identity');
    , "native-ai-one-shot-gc-before.mjs");
    c.JS_RunGC(engine.runtime);
    try evaluate(engine,
        \\const model={id:'m',api:'typesafe-system-one',provider:'p',baseUrl:'https://fixture.invalid/',cost:{input:1,output:1,cacheRead:1,cacheWrite:1}},result=await keptOneShot.typesafe.classify(model,{state:{},questions:{}});if(result.errorMessage!=='No API key for provider: p'||result.stopReason!=='error')throw Error('retained auth failure');if(keptOneShot.llama.llamaServerRoot('https://fixture.invalid/v1///')!=='https://fixture.invalid')throw Error('retained root helper');delete globalThis.keptOneShot;
    , "native-ai-one-shot-gc-after.mjs");
    c.JS_RunGC(engine.runtime);
}
test "native AI one shot every pure classifier helper allocation releases maps pricing and callback roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            sdk.put(engine, global, "llamaHelpers", try @import("extensions/native_ai_llama_classifier_helpers.zig").create(engine)) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const context={state:{value:1},questions:{q:{type:'choice',instructions:'pick',criteria:{a:'Alpha',b:'Beta'}}}},rendered=llamaHelpers.renderQuestion(context,'q'),distribution=llamaHelpers.labelProbabilities([-.2,-1.5],1),answer=llamaHelpers.answerFromProbabilities(context.questions.q,rendered.keys,distribution);if(answer.choice!=='a'||!(answer.confidence>0&&answer.confidence<1)||!rendered.content.includes('A. a: Alpha'))throw Error('helper semantics');
            , "native-ai-one-shot-pure-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
