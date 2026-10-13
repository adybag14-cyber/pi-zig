const std = @import("std");
const em = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;
fn createTool(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("extensions/native_durable_codemode_tool.zig").createTool(engine, engine.native_module_values.get("@earendil-works/pi-durable").?, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
fn createModelTools(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable").?;
    const docs = @import("extensions/native_durable_codemode_journal.zig").createDocuments(engine, exports) catch |err| return durable.reject(engine, err);
    defer engine.freeValue(docs);
    return @import("extensions/native_durable_codemode_model_tools.zig").create(engine, exports, docs, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
test "native durable default CodeMode model catalog actual Source program" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_stream.zig").install(engine);
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    const sandbox_exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(sandbox_exports);
    try @import("extensions/native_codemode_sandbox.zig").install(engine, sandbox_exports);
    try engine.registerValueModule("@earendil-works/pi-codemode", sandbox_exports);
    const models_exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(models_exports);
    try @import("extensions/native_models.zig").populateExports(engine, models_exports);
    try engine.registerValueModule("native-model-catalog-registry", models_exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeCreateCodemodeTool", try engine.checked(c.JS_NewCFunctionData2(engine.context, createTool, "", 1, 0, 0, null)));
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-codemode-models-source.json"));
    defer fixture.deinit();
    try sdk.put(engine, global, "modelsSourceFixture", try durable.jsValue(engine, fixture.value));
    const proof = engine.evalModule(
        \\import * as M from'@earendil-works/pi-durable';import{CodemodeSandbox}from'@earendil-works/pi-codemode';import{BACKGROUND_CONTEXT as ctx}from'@earendil-works/chord/context';import{createModels}from'native-model-catalog-registry';
        \\const input=modelsSourceFixture.cases[0],models=createModels(),COST={input:0,output:0,cacheRead:0,cacheWrite:0};const judge={id:'judge',name:'Judge',api:'test-classifier',provider:'test',baseUrl:'https://example.invalid',input:['text'],cost:COST,headers:{authorization:'secret'},type:'classifier',contextWindow:1000},painter={id:'painter',name:'Painter',api:'test-images',provider:'test',baseUrl:'https://example.invalid',input:['text'],cost:COST,type:'image',output:['image']},held={id:'held',provider:'held',api:'held-chat',type:'chat',input:['text'],cost:COST,contextWindow:100000,maxTokens:100};
        \\models.setProvider({id:'test',auth:{apiKey:{async check(){return{type:'api_key'}}}},getModels:()=>[],getAllModels:()=>[judge,painter]});models.setProvider({id:'held',auth:{apiKey:{async check(){return{type:'api_key'}}}},getModels:()=>[held],getAllModels:()=>[held]});let requests=0;const usage={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{...COST,total:0}};models.streamSimple=()=>{requests++;const result={role:'assistant',provider:'held',model:'held',content:requests===1?[{type:'toolCall',id:'c1',name:'codemode',arguments:{code:input.code}}]:[{type:'text',text:'done'}],stopReason:requests===1?'toolUse':'stop',usage,timestamp:123};return{async*[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>result}};
        \\const sandbox=new CodemodeSandbox({memoryLimitBytes:67108864}),registry=M.createRegistry();registry.install(M.defineExtension({name:'default-catalog',tools:[nativeCreateCodemodeTool({sandbox})]}));const documents=new Map(),harness=await M.Harness.open(new M.MemoryStorage(),{models,registry,settings:{compaction:{enabled:false},retry:{enabled:false}}},ctx);const stop=harness.subscribeCommits(publication=>{for(const change of publication.changes)if(change.type==='document'&&change.value!==null)documents.set(change.record.kind,JSON.parse(JSON.stringify(change.value)))});
        \\try{const root=await harness.root(ctx,{agent:{model:{provider:'held',modelId:'held'}}});harness.resume();const receipt=await(await root.submit({type:'input',content:'go'},ctx)).wait(ctx);const result=documents.get('pi.codemode.run')?.result;if(receipt.status!=='done'||!result||result.isError)throw Error(JSON.stringify({receipt,result,requests}));const text=result.output.filter(item=>item.type==='text').map(item=>item.text).join('').replace(/^Script (completed|failed)\nWall time [\d.]+ seconds\nOutput:\n/,'');if(JSON.stringify(JSON.parse(text))!==JSON.stringify(input.expected))throw Error(JSON.stringify({expected:input.expected,text}))}finally{stop();await harness.close(ctx);await sandbox.close()}export const proof=true;
    , "native-default-model-catalog-source") catch |err| {
        std.debug.print("Native default model catalog {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(proof);
}

test "native durable default CodeMode model calls Source usage errors hidden tools and four slots" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_stream.zig").install(engine);
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    const sandbox_exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(sandbox_exports);
    try @import("extensions/native_codemode_sandbox.zig").install(engine, sandbox_exports);
    try engine.registerValueModule("@earendil-works/pi-codemode", sandbox_exports);
    const models_exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(models_exports);
    try @import("extensions/native_models.zig").populateExports(engine, models_exports);
    try engine.registerValueModule("native-model-catalog-registry", models_exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeCreateCodemodeTool", try engine.checked(c.JS_NewCFunctionData2(engine.context, createTool, "", 1, 0, 0, null)));
    try sdk.put(engine, global, "nativeCreateModelTools", try engine.checked(c.JS_NewCFunctionData2(engine.context, createModelTools, "", 1, 0, 0, null)));
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-codemode-models-source.json"));
    defer fixture.deinit();
    try sdk.put(engine, global, "modelsSourceFixture", try durable.jsValue(engine, fixture.value));
    var latency_probe: @import("native_latency_probe.zig").Probe = .{};
    try latency_probe.install(engine);
    defer latency_probe.detach(engine);
    // The actual native query/availability registry is used here. Its typed AI
    // service adapter is a separate prerequisite; these local service callbacks
    // are the original Source test provider's controlled replies at API ingress.
    const proof = engine.evalModule(
        \\import * as M from'@earendil-works/pi-durable';import{CodemodeSandbox}from'@earendil-works/pi-codemode';import{BACKGROUND_CONTEXT as ctx}from'@earendil-works/chord/context';import{createModels}from'native-model-catalog-registry';
        \\for(const input of modelsSourceFixture.cases.slice(1)){const caseIndex=modelsSourceFixture.cases.indexOf(input)-1;nativeLatencyMark('case-begin',caseIndex);const models=createModels(),COST={input:0,output:0,cacheRead:0,cacheWrite:0},USAGE={input:10,output:2,cacheRead:0,cacheWrite:0,totalTokens:12,cost:{input:.001,output:.0002,cacheRead:0,cacheWrite:0,total:.0012}},judge={id:'judge',name:'Judge',api:'test-classifier',provider:'test',baseUrl:'https://example.invalid',input:['text'],cost:COST,headers:{authorization:'secret'},type:'classifier',contextWindow:1000},painter={id:'painter',name:'Painter',api:'test-images',provider:'test',baseUrl:'https://example.invalid',input:['text'],cost:COST,type:'image',output:['image']},held={id:'held',provider:'held',api:'held-chat',type:'chat',input:['text'],cost:COST,contextWindow:100000,maxTokens:100};
        \\models.setProvider({id:'test',auth:{apiKey:{async check(){return{type:'api_key'}}}},getModels:()=>[],getAllModels:()=>[judge,painter]});models.setProvider({id:'held',auth:{apiKey:{async check(){return{type:'api_key'}}}},getModels:()=>[held],getAllModels:()=>[held]});const calls={classify:0,inFlight:0,maxInFlight:0};let release,requests=0;const gate=input.hold?new Promise(resolve=>release=resolve):Promise.resolve();
        \\models.classify=async(model,context,options)=>{if(model!==judge||model.baseUrl!=='https://example.invalid'||!options.signal)throw Error('selected service model or context changed');calls.classify++;if(context.state.fail===true)return{api:model.api,provider:model.provider,model:model.id,answers:{},stopReason:'error',errorMessage:'quota exceeded',timestamp:0};calls.inFlight++;calls.maxInFlight=Math.max(calls.maxInFlight,calls.inFlight);if(input.hold&&calls.inFlight===4)setTimeout(release,50);await gate;calls.inFlight--;return{api:model.api,provider:model.provider,model:model.id,answers:{good:{value:true}},usage:USAGE,stopReason:'stop',timestamp:0}};
        \\const usage={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{...COST,total:0}};models.streamSimple=()=>{requests++;const result={role:'assistant',provider:'held',model:'held',content:requests===1?[{type:'toolCall',id:'c1',name:'codemode',arguments:{code:input.code}}]:[{type:'text',text:'done'}],stopReason:requests===1?'toolUse':'stop',usage,timestamp:123};return{async*[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>result}};
        \\const sandbox=new CodemodeSandbox({memoryLimitBytes:67108864}),registry=M.createRegistry();registry.install(M.defineExtension({name:'default-model-tools',tools:[nativeCreateCodemodeTool({sandbox}),...nativeCreateModelTools(modelsSourceFixture.modelToolMetadata)]}));const documents=new Map(),harness=await M.Harness.open(new M.MemoryStorage(),{models,registry,settings:{compaction:{enabled:false},retry:{enabled:false}}},ctx);const stop=harness.subscribeCommits(publication=>{for(const change of publication.changes)if(change.type==='document'&&change.value!==null)documents.set(change.record.kind,JSON.parse(JSON.stringify(change.value)))});
        \\nativeLatencyMark('open',caseIndex);try{const root=await harness.root(ctx,{agent:{model:{provider:'held',modelId:'held'}}});harness.resume();nativeLatencyMark('submit-wait',caseIndex);const receipt=await(await root.submit({type:'input',content:'go'},ctx)).wait(ctx);nativeLatencyMark('receipt',caseIndex);const result=documents.get('pi.codemode.run')?.result;if(receipt.status!=='done'||!result||result.isError)throw Error(JSON.stringify({input,receipt,result,calls}));const text=result.output.filter(item=>item.type==='text').map(item=>item.text).join('').replace(/^Script (completed|failed)\nWall time [\d.]+ seconds\nOutput:\n/,'');if(JSON.stringify(JSON.parse(text))!==JSON.stringify(input.expected)||calls.classify!==input.calls||input.hold&&calls.maxInFlight!==4)throw Error(JSON.stringify({input,text,calls}));const rows=result.details.calls;if(rows.length!==input.calls||rows.some(row=>row.name!=='models.classify'||row.status!==(input.errorCall?'error':'ok')))throw Error(JSON.stringify({rows,input}));if(!input.errorCall){const usage=await harness.snapshot(M.UsageDoc,root.id,ctx);if(Math.abs(usage.tools['pi.codemode.models.classify'].cost.total-.0012*input.calls)>1e-12)throw Error(JSON.stringify({usage,input}))}}finally{nativeLatencyMark('close-begin',caseIndex);stop();await harness.close(ctx);await sandbox.close();nativeLatencyMark('case-end',caseIndex)}}export const proof=true;
    , "native-default-model-calls-source") catch |err| {
        std.debug.print("Native default model calls {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(proof);
}

test "native durable default CodeMode model images Source file bytes and unshown warning" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &path);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_stream.zig").install(engine);
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    const sandbox_exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(sandbox_exports);
    try @import("extensions/native_codemode_sandbox.zig").install(engine, sandbox_exports);
    try engine.registerValueModule("@earendil-works/pi-codemode", sandbox_exports);
    const models_exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(models_exports);
    try @import("extensions/native_models.zig").populateExports(engine, models_exports);
    try engine.registerValueModule("native-model-catalog-registry", models_exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeCreateCodemodeTool", try engine.checked(c.JS_NewCFunctionData2(engine.context, createTool, "", 1, 0, 0, null)));
    try sdk.put(engine, global, "nativeCreateModelTools", try engine.checked(c.JS_NewCFunctionData2(engine.context, createModelTools, "", 1, 0, 0, null)));
    try sdk.put(engine, global, "nativeOutputEnvironment", try @import("extensions/native_durable_file_environment.zig").create(engine, path[0..length]));
    var model_fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-codemode-models-source.json"));
    defer model_fixture.deinit();
    try sdk.put(engine, global, "modelsSourceFixture", try durable.jsValue(engine, model_fixture.value));
    var image_fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-codemode-model-images-source.json"));
    defer image_fixture.deinit();
    try sdk.put(engine, global, "modelImagesSourceFixture", try durable.jsValue(engine, image_fixture.value));
    const proof = engine.evalModule(
        \\import * as M from'@earendil-works/pi-durable';import{CodemodeSandbox}from'@earendil-works/pi-codemode';import{BACKGROUND_CONTEXT as ctx}from'@earendil-works/chord/context';import{createModels}from'native-model-catalog-registry';import fs from'node:fs';
        \\const sourceBlock=modelImagesSourceFixture.rows[0].result.output.find(item=>item.type==='image');for(const source of modelImagesSourceFixture.rows){const input=source.input,models=createModels(),COST={input:0,output:0,cacheRead:0,cacheWrite:0},painter={id:'painter',name:'Painter',api:'test-images',provider:'test',baseUrl:'https://example.invalid',input:['text'],cost:COST,type:'image',output:['image']},held={id:'held',provider:'held',api:'held-chat',type:'chat',input:['text'],cost:COST,contextWindow:100000,maxTokens:100};models.setProvider({id:'test',auth:{apiKey:{async check(){return{type:'api_key'}}}},getModels:()=>[],getAllModels:()=>[painter]});models.setProvider({id:'held',auth:{apiKey:{async check(){return{type:'api_key'}}}},getModels:()=>[held],getAllModels:()=>[held]});let requests=0,images=0;const writes=[],documents=new Map();
        \\models.generateImages=async(model,context,options)=>{if(model!==painter||!options.signal||context.input[0]?.text!=='hi')throw Error('image service selection/context');images++;return{api:model.api,provider:model.provider,model:model.id,output:[{type:'image',data:sourceBlock.data,mimeType:sourceBlock.mimeType}],stopReason:'stop',timestamp:0}};
        \\const usage={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{...COST,total:0}};models.streamSimple=()=>{requests++;const result={role:'assistant',provider:'held',model:'held',content:requests===1?[{type:'toolCall',id:'c1',name:'codemode',arguments:{code:input.code}}]:[{type:'text',text:'done'}],stopReason:requests===1?'toolUse':'stop',usage,timestamp:123};return{async*[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>result}};
        \\const base=nativeOutputEnvironment,env={createTempDir:(prefix,context)=>base.createTempDir(prefix,context),writeFile:async(path,data,context)=>{const run=documents.get('pi.codemode.run');if(typeof run?.outputDir!=='string'||!path.startsWith(run.outputDir+'/'))throw Error('image directory not committed');const result=await base.writeFile(path,data,context);writes.push({path,result});return result}},sandbox=new CodemodeSandbox({memoryLimitBytes:67108864}),registry=M.createRegistry();registry.install(M.defineExtension({name:'default-model-images',tools:[nativeCreateCodemodeTool({sandbox}),...nativeCreateModelTools(modelsSourceFixture.modelToolMetadata)]}));const harness=await M.Harness.open(new M.MemoryStorage(),{models,registry,...(input.show?{env:()=>env}:{}),settings:{compaction:{enabled:false},retry:{enabled:false}}},ctx);const stop=harness.subscribeCommits(publication=>{for(const change of publication.changes)if(change.type==='document'&&change.value!==null)documents.set(change.record.kind,JSON.parse(JSON.stringify(change.value)))});
        \\try{const root=await harness.root(ctx,{agent:{model:{provider:'held',modelId:'held'}}});harness.resume();const receipt=await(await root.submit({type:'input',content:'go'},ctx)).wait(ctx),result=documents.get('pi.codemode.run')?.result;if(receipt.status!=='done'||!result||result.isError||images!==1)throw Error(JSON.stringify({input,receipt,result,images}));const blocks=result.output.filter(item=>item.type==='image'),text=result.output.filter(item=>item.type==='text').map(item=>item.text).join('');if(blocks.length!==(input.show?1:0)||writes.length!==source.imageWrites.length||!text.includes('done'))throw Error(JSON.stringify({input,result,writes}));if(input.show){if(blocks[0].data!==sourceBlock.data||blocks[0].mimeType!==sourceBlock.mimeType||JSON.stringify([...fs.readFileSync(writes[0].path)])!==JSON.stringify(source.imageWrites[0].bytes)||!writes[0].result.ok)throw Error('actual generated PNG differs')}else{const note='Note: models.generateImages() returned 1 image that the script did not show. Show each image block of result.output with image(block).';if(!text.includes(note)||documents.get('pi.codemode.run').outputDir!==undefined)throw Error('unshown image warning/directory changed')}if(result.details.calls.length!==1||result.details.calls[0].name!=='models.generateImages'||result.details.calls[0].status!=='ok')throw Error(JSON.stringify(result.details))}finally{stop();await harness.close(ctx);await sandbox.close()}}export const proof=true;
    , "native-default-model-images-source") catch |err| {
        std.debug.print("Native default model images {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(proof);
}
