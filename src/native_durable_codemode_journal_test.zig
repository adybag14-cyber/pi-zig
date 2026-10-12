//! Exercises the compiled journal body through actual Harness tool execution,
//! ToolExecutionApi.commit, native document drafts and real MemoryStorage.
const std = @import("std");
const em = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const awaiting = @import("extensions/native_durable_await.zig");
const journal = @import("extensions/native_durable_codemode_journal.zig");
const json = @import("durable/backend/json.zig");
const c = em.c;
fn data(scope: *Scope, encoded: []const u8) !c.JSValue {
    var owned = try json.Owned.parse(scope.engine.gpa, encoded);
    defer owned.deinit();
    return scope.own(try durable.jsValue(scope.engine, owned.value));
}
fn next(scope: *Scope, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    const docs = try scope.get(state, "documents");
    var intrinsics: awaiting.Intrinsics = .{ .constructor = try scope.get(docs, "promiseConstructor"), .resolve = try scope.get(docs, "promiseResolve"), .then_function = try scope.get(docs, "promiseThen") };
    return awaiting.continueWith(advance, scope.engine, &intrinsics, state, pending, stage);
}
fn execute(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    std.debug.print("Native journal probe actual execute argc={d}\n", .{argc});
    return start(engine, captures[0], args[0..@intCast(argc)]) catch |err| {
        std.debug.print("Native journal probe start {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no diagnostic" });
        return durable.reject(engine, err);
    };
}
fn start(engine: *em.Engine, docs: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (args.len != 3) return error.InvalidJournalProbeArguments;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "documents", docs);
    try scope.put(state, "api", args[1]);
    try scope.put(state, "context", args[2]);
    const draft = try data(&scope, "{\"version\":2,\"startedAt\":123,\"seed\":456,\"tools\":[],\"namespaces\":[],\"globals\":[],\"maxOutputTokens\":4096}");
    const pending = try scope.own(try journal.initialize(engine, docs, args[1], args[2], draft));
    return next(&scope, state, pending, 0);
}
fn advance(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    if (rejected) {
        const text = engine.toString(value) catch null;
        defer if (text) |bytes| engine.gpa.free(bytes);
        std.debug.print("Native journal probe rejected stage={d}: {s}\n", .{ stage, text orelse "unprintable original rejection" });
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    }
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const docs = try scope.get(state, "documents");
    const api = try scope.get(state, "api");
    const context = try scope.get(state, "context");
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const pending = switch (stage) {
        0 => blk: {
            try scope.put(global, "nativeJournalProbeFound", value);
            break :blk try scope.own(try journal.fingerprint(engine, docs, api, context, try scope.text("transaction-probe-identity")));
        },
        1 => try scope.own(try journal.batch(engine, docs, api, context, try data(&scope, "{\"acks\":[[0,2]],\"entries\":[{\"id\":1,\"at\":123,\"global\":{\"name\":\"probe\",\"args\":[1],\"outcome\":{\"ok\":true,\"value\":4}}}]}"))),
        2 => try scope.own(try journal.batch(engine, docs, api, context, try data(&scope, "{\"acks\":[[0,999],[1,2]],\"entries\":[]}"))),
        3 => try scope.own(try journal.complete(engine, docs, api, context, try data(&scope, "{\"result\":{\"output\":[{\"type\":\"text\",\"text\":\"core\"}],\"isError\":false},\"writes\":{\"set\":{\"kept\":{\"n\":1}},\"delete\":[]}}"))),
        4 => try scope.own(try journal.initialize(engine, docs, api, context, try data(&scope, "{\"version\":2,\"startedAt\":999,\"seed\":999}"))),
        5 => blk: {
            try scope.put(global, "nativeJournalProbeSecond", value);
            break :blk try scope.own(try journal.complete(engine, docs, api, context, try data(&scope, "{\"result\":{\"output\":[],\"isError\":true},\"writes\":{\"set\":{\"ignored\":4},\"delete\":[\"kept\"]}}")));
        },
        6 => blk: {
            try scope.put(global, "nativeJournalProbeRetained", value);
            break :blk try scope.own(try journal.outputDirectory(engine, docs, api, context, try scope.text("recorded-output")));
        },
        7 => try scope.own(try journal.outputDirectory(engine, docs, api, context, try scope.text("ignored-output"))),
        8 => blk: {
            if (!scope.equal(value, try scope.text("recorded-output"))) return error.OutputDirectoryChanged;
            break :blk try scope.own(try journal.decide(engine, docs, api, context, try data(&scope, "{\"output\":[],\"isError\":true}")));
        },
        9 => return c.JS_DupValue(engine.context, try data(&scope, "{\"output\":[{\"type\":\"text\",\"text\":\"core\"}]}")),
        else => return error.InvalidJournalProbeStage,
    };
    return next(&scope, state, pending, stage + 1);
}
test "native durable CodeMode journal real tool API transaction start fingerprint batches and atomic store result" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_stream.zig").install(engine);
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableModuleMissing;
    const docs = try journal.createDocuments(engine, exports);
    defer engine.freeValue(docs);
    var captures = [_]c.JSValue{docs};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, execute, "", 3, 0, captures.len, &captures));
    defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeJournalProbe", c.JS_DupValue(engine.context, function));
    const result = engine.evalModule(
        \\import * as M from '@earendil-works/pi-durable';import{BACKGROUND_CONTEXT as ctx}from'@earendil-works/chord/context';
        \\const Probe=M.defineTool({name:'journal_probe',description:'journal probe',parameters:{type:'object',properties:{}},replay:'safe',execute:nativeJournalProbe});
        \\const registry=M.createRegistry();registry.install(M.defineExtension({name:'journal-probe',tools:[Probe]}));
        \\const usage={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};let requests=0;
        \\const models={getModel:()=>({id:'held',maxTokens:100,contextWindow:100000}),streamSimple:()=>{requests++;const result={role:'assistant',provider:'held',model:'held',content:requests===1?[{type:'toolCall',id:'c1',name:'journal_probe',arguments:{}}]:[{type:'text',text:'done'}],stopReason:requests===1?'toolUse':'stop',usage,timestamp:123};return{async*[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>result}}};
        \\const harness=await M.Harness.open(new M.MemoryStorage(),{models,registry,settings:{compaction:{enabled:false},retry:{enabled:false}}},ctx);const documents=new Map(),published=[];let atomic=0;
        \\const stop=harness.subscribeCommits(publication=>{published.push(JSON.parse(JSON.stringify(publication)));for(const change of publication.changes)if(change.type==='document'&&change.value!==null)documents.set(change.record.kind,JSON.parse(JSON.stringify(change.value)));if(publication.changes.some(change=>change.type==='document'&&change.record.kind==='pi.codemode.run'&&change.value?.result)&&publication.changes.some(change=>change.type==='document'&&change.record.kind==='pi.codemode.store'&&change.value?.values.kept))atomic++});
        \\try{const root=await harness.root(ctx,{agent:{model:{provider:'held',modelId:'held'}}});harness.resume();const receipt=await(await root.submit({type:'input',content:'go'},ctx)).wait(ctx);if(receipt.status!=='done'||requests!==2)throw Error('probe generation failed');
        \\const run=documents.get('pi.codemode.run'),journal=documents.get('pi.codemode.journal'),store=documents.get('pi.codemode.store');if(!globalThis.nativeJournalProbeFound)throw Error(JSON.stringify({documents:Object.fromEntries(documents),published}));
        \\if(nativeJournalProbeFound.rerun!==false||nativeJournalProbeFound.start.seed!==456||nativeJournalProbeFound.journal.length!==0||nativeJournalProbeSecond.done?.output[0].text!=='core')throw Error('stored start/result changed');
        \\if(nativeJournalProbeRetained.then!==undefined||await Promise.resolve(nativeJournalProbeRetained)!==nativeJournalProbeRetained)throw Error('settled draft must remain non-thenable');let revokedReads=0;for(const operation of[()=>nativeJournalProbeRetained.output,()=>{nativeJournalProbeRetained.isError=true},()=>Object.keys(nativeJournalProbeRetained)]){try{operation()}catch{revokedReads++}}if(revokedReads!==3)throw Error('settled result draft reopened');
        \\if(run.start.fingerprint!=='transaction-probe-identity'||run.outputDir!=='recorded-output'||run.result.isError!==false||journal.firstIssued!==2||journal.entries.length!==1||journal.entries[0].issuedAfter!==2||journal.entries[0].global.outcome.value!==4||store.values.kept.n!==1||store.values.ignored!==undefined||atomic!==1)throw Error(JSON.stringify({run,journal,store,atomic}));
        \\}finally{stop();await harness.close(ctx)}export const proof=true;
    , "native-codemode-real-journal-core") catch |err| {
        std.debug.print("CodeMode journal core {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(result);
}

fn executeCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return beginCall(engine, captures[0], args[0..@intCast(argc)]) catch |err| durable.reject(engine, err);
}
fn beginCall(engine: *em.Engine, docs: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    return @import("extensions/native_durable_codemode_call.zig").execute(engine, docs, args[1], args[2], try scope.get(global, "journalSandbox"), try scope.get(args[0], "code"), try scope.get(global, "journalDraft"), try scope.get(global, "journalGlobals"));
}
fn createCodemodeTool(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("extensions/native_durable_codemode_tool.zig").createTool(engine, engine.native_module_values.get("@earendil-works/pi-durable").?, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
test "native durable CodeMode journal real tool API actual sandbox original Source6 commit ordering" {
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
    const docs = try journal.createDocuments(engine, engine.native_module_values.get("@earendil-works/pi-durable").?);
    defer engine.freeValue(docs);
    var captures = [_]c.JSValue{docs};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, executeCall, "", 3, 0, captures.len, &captures));
    defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeJournalCall", c.JS_DupValue(engine.context, function));
    try sdk.put(engine, global, "nativeCreateCodemodeTool", try engine.checked(c.JS_NewCFunctionData2(engine.context, createCodemodeTool, "", 1, 0, 0, null)));
    var source_cases = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-ee-codemode-journal-programs-source.json"));
    defer source_cases.deinit();
    try sdk.put(engine, global, "journalSourceFixture", try durable.jsValue(engine, source_cases.value));
    const proof = engine.evalModule(
        \\import * as M from'@earendil-works/pi-durable';import{CodemodeSandbox}from'@earendil-works/pi-codemode';import{BACKGROUND_CONTEXT as ctx}from'@earendil-works/chord/context';
        \\const cases=journalSourceFixture.cases;
        \\for(const input of cases){const documents=new Map(),madeCalls=new Map(),deliveries=[],starts=[];let launched=0,globalCalls=0,requests=0,atomic=false;const require=(value,message)=>{if(!value)throw Error(input.name+': '+message)};
        \\const activeRun=()=>documents.get('pi.codemode.run'),activeJournal=()=>documents.get('pi.codemode.journal');const durableIssued=()=>Math.max(activeJournal()?.firstIssued??0,...(activeJournal()?.entries??[]).map(entry=>entry.issuedAfter??0));
        \\globalThis.journalDraft={version:2,startedAt:Date.now(),seed:456,tools:[{name:'echo',jsName:'echo',description:'echo'}],namespaces:[],globals:[{name:'probeGlobal',spread:false}],maxOutputTokens:4096};
        \\const sandbox=globalThis.journalSandbox=new CodemodeSandbox({memoryLimitBytes:67108864});const originalStart=sandbox.start.bind(sandbox);sandbox.start=(code,options)=>{require(activeRun()?.start!==undefined,'start must precede VM');require(activeRun().start.seed===options.seed&&activeRun().start.startedAt===options.startedAt,'stored clock and seed');starts.push(code);const run=originalStart(code,{...options,onCall(call){madeCalls.set(call.id,call);options.onCall(call)}});const deliver=run.deliver.bind(run);run.deliver=(seq,at,id,outcome)=>{const entry=activeJournal()?.entries[seq-1];require(entry?.id===id&&entry.at===at,'journal must precede delivery');deliveries.push(id);return deliver(seq,at,id,outcome)};return run};
        \\const admitted=(id)=>{require(typeof activeRun()?.start?.fingerprint==='string','fingerprint must precede admission');require(durableIssued()>=id,'issued must precede admission')};
        \\const echo=M.defineTool({name:'echo',description:'echo',parameters:{type:'object',properties:{i:{type:'number'}},required:['i']},replay:'safe',execute:async args=>{const call=[...madeCalls.values()].find(call=>call.target==='tool'&&call.args.i===args.i);require(call!==undefined,'actual VM call');admitted(call.id);launched++;return{output:[{type:'text',text:`echo ${args.i}`}]}}});
        \\globalThis.journalGlobals=[{name:'probeGlobal',execute:async args=>{const call=[...madeCalls.values()].find(call=>call.target==='global');require(call!==undefined,'actual global VM call');admitted(call.id);globalCalls++;return{echo:args.n}}}];
        \\const codemode=nativeCreateCodemodeTool({sandbox,models:false,globals:journalGlobals});const registry=M.createRegistry();registry.install(M.defineExtension({name:'journal-call',tools:[echo,codemode]}));
        \\const usage={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};const models={getModel:()=>({id:'held',maxTokens:100,contextWindow:100000}),streamSimple:()=>{requests++;const result={role:'assistant',provider:'held',model:'held',content:requests===1?[{type:'toolCall',id:'c1',name:'codemode',arguments:{code:input.code}}]:[{type:'text',text:'done'}],stopReason:requests===1?'toolUse':'stop',usage,timestamp:123};return{async*[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>result}}};
        \\const harness=await M.Harness.open(new M.MemoryStorage(),{models,registry,settings:{compaction:{enabled:false},retry:{enabled:false}}},ctx);const stop=harness.subscribeCommits(publication=>{for(const change of publication.changes)if(change.type==='document'&&change.value!==null)documents.set(change.record.kind,JSON.parse(JSON.stringify(change.value)));if(publication.changes.some(change=>change.type==='document'&&change.record.kind==='pi.codemode.run'&&change.value?.result)&&publication.changes.some(change=>change.type==='document'&&change.record.kind==='pi.codemode.store'&&change.value?.values.kept))atomic=true});
        \\try{const root=await harness.root(ctx,{agent:{model:{provider:'held',modelId:'held'}}});harness.resume();require((await(await root.submit({type:'input',content:'go'},ctx)).wait(ctx)).status==='done','generation complete');require(starts.length===1&&launched===(input.calls??0)&&globalCalls===(input.globals??0),'actual execution counts');require(activeRun()?.result!==undefined&&activeRun().result.isError===!!input.error,'stored script outcome');for(const key of['tools','namespaces','globals','maxOutputTokens'])require(JSON.stringify(activeRun().start[key])===JSON.stringify(journalSourceFixture.startData[key]),'actual Source start '+key);require(deliveries.length===(input.calls??0)+(input.globals??0),'delivery count');require((activeJournal()?.entries??[]).filter(entry=>entry.global!==undefined).length===(input.globals??0),'global journal');require(!input.store||atomic,'atomic successful writes');require(documents.get('pi.codemode.store')?.values.ignored===undefined,'failed write absent')}finally{stop();await harness.close(ctx);await sandbox.close()}}
        \\export const proof=true;
    , "native-codemode-journal-source6") catch |err| {
        std.debug.print("CodeMode real journal Source6 {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(proof);
}

test "native durable CodeMode journal real tool API original restart3 and host close no outcome" {
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
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    try @import("extensions/native_codemode_sandbox.zig").install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-codemode", exports);
    const docs = try journal.createDocuments(engine, engine.native_module_values.get("@earendil-works/pi-durable").?);
    defer engine.freeValue(docs);
    var captures = [_]c.JSValue{docs};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, executeCall, "", 3, 0, captures.len, &captures));
    defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeJournalCall", c.JS_DupValue(engine.context, function));
    try sdk.put(engine, global, "nativeCreateCodemodeTool", try engine.checked(c.JS_NewCFunctionData2(engine.context, createCodemodeTool, "", 1, 0, 0, null)));
    try sdk.put(engine, global, "journalDocumentTokens", c.JS_DupValue(engine.context, docs));
    try sdk.put(engine, global, "testRoot", try sdk.text(engine, path[0..length]));
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-148622-codemode-restart-source.json"));
    defer fixture.deinit();
    try sdk.put(engine, global, "journalRestartFixture", try durable.jsValue(engine, fixture.value));
    const proof = engine.evalModule(@embedFile("durable/fixtures/durable-codemode-native-restart-harness.input.txt"), "native-codemode-journal-restart3") catch |err| {
        std.debug.print("Native journal restart {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(proof);
}

fn discoveryCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("extensions/native_durable_codemode_discovery.zig").invoke(engine, captures[0], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| durable.reject(engine, err);
}
test "native durable CodeMode journal real tool API Source discovery9 exact values errors and own undefined" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-codemode-discovery-source.json"));
    defer fixture.deinit();
    const value = try durable.jsValue(engine, fixture.value);
    defer engine.freeValue(value);
    const recorded_start = try engine.checked(c.JS_GetPropertyStr(engine.context, value, "start"));
    defer engine.freeValue(recorded_start);
    var captures = [_]c.JSValue{recorded_start};
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "discoverySourceFixture", c.JS_DupValue(engine.context, value));
    try sdk.put(engine, global, "nativeDiscoveryCall", try engine.checked(c.JS_NewCFunctionData2(engine.context, discoveryCall, "", 1, 0, captures.len, &captures)));
    const proof = engine.evalModule(
        \\const fixture=discoverySourceFixture;for(const call of fixture.calls){let outcome;try{outcome={ok:true,value:nativeDiscoveryCall(call)}}catch(error){outcome={ok:false,message:error.message}}const expected=fixture.deliveries.find(delivery=>delivery.id===call.id);if(JSON.stringify(outcome)!==JSON.stringify(expected.outcome)||JSON.stringify(Object.keys(outcome))!==JSON.stringify(expected.outcomeKeys)||Object.hasOwn(outcome,'value')!==expected.hasValue||typeof outcome.value!==expected.valueType)throw Error(JSON.stringify({call,expected,actual:outcome,keys:Object.keys(outcome)}))}export const proof=true;
    , "native-codemode-discovery-source9") catch |err| {
        std.debug.print("Native discovery Source9 {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        return err;
    };
    engine.freeValue(proof);
}

test "native durable CodeMode journal real tool API Source replay negatives6 refuse new admissions" {
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
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    try @import("extensions/native_codemode_sandbox.zig").install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-codemode", exports);
    const docs = try journal.createDocuments(engine, engine.native_module_values.get("@earendil-works/pi-durable").?);
    defer engine.freeValue(docs);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeCreateCodemodeTool", try engine.checked(c.JS_NewCFunctionData2(engine.context, createCodemodeTool, "", 1, 0, 0, null)));
    try sdk.put(engine, global, "journalDocumentTokens", c.JS_DupValue(engine.context, docs));
    try sdk.put(engine, global, "testRoot", try sdk.text(engine, path[0..length]));
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-codemode-replay-negatives-source.json"));
    defer fixture.deinit();
    try sdk.put(engine, global, "journalReplayNegativesFixture", try durable.jsValue(engine, fixture.value));
    const proof = engine.evalModule(@embedFile("durable/fixtures/durable-codemode-native-replay-negatives-harness.input.txt"), "native-codemode-journal-replay-negatives6") catch |err| {
        std.debug.print("Native journal replay negatives {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(proof);
}

test "native durable CodeMode journal real tool API Source output files4 actual bytes and durable directory" {
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
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    try @import("extensions/native_codemode_sandbox.zig").install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-codemode", exports);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeCreateCodemodeTool", try engine.checked(c.JS_NewCFunctionData2(engine.context, createCodemodeTool, "", 1, 0, 0, null)));
    try sdk.put(engine, global, "nativeOutputEnvironment", try @import("extensions/native_durable_file_environment.zig").create(engine, path[0..length]));
    var fixture = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-19cb534-codemode-output-files-source.json"));
    defer fixture.deinit();
    try sdk.put(engine, global, "outputFilesSourceFixture", try durable.jsValue(engine, fixture.value));
    const proof = engine.evalModule(
        \\import * as M from'@earendil-works/pi-durable';import{CodemodeSandbox}from'@earendil-works/pi-codemode';import{BACKGROUND_CONTEXT as ctx}from'@earendil-works/chord/context';import fs from'node:fs';
        \\for(const source of outputFilesSourceFixture.rows){const input=source.input,documents=new Map(),ioEvents=[];let requests=0;const require=(value,message)=>{if(!value)throw Error(input.name+': '+message)},sandbox=new CodemodeSandbox({memoryLimitBytes:67108864}),base=nativeOutputEnvironment;const env={createTempDir:async(prefix,context)=>{const result=await base.createTempDir(prefix,context);ioEvents.push({type:'create',prefix,result});return result},writeFile:async(path,content,context)=>{const run=documents.get('pi.codemode.run');require(typeof run?.outputDir==='string'&&path.startsWith(run.outputDir+'/'),'write before committed directory');const result=await base.writeFile(path,content,context);ioEvents.push({type:'write',path,content:typeof content==='string'?{text:content}:{bytes:[...content]},result});return result}};
        \\const codemode=nativeCreateCodemodeTool({sandbox,models:false}),registry=M.createRegistry();registry.install(M.defineExtension({name:'file-output',tools:[codemode]}));const usage={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};const models={getModel:()=>({id:'held',maxTokens:100,contextWindow:100000}),streamSimple:()=>{requests++;const result={role:'assistant',provider:'held',model:'held',content:requests===1?[{type:'toolCall',id:'c1',name:'codemode',arguments:{code:input.code}}]:[{type:'text',text:'done'}],stopReason:requests===1?'toolUse':'stop',usage,timestamp:123};return{async*[Symbol.asyncIterator](){yield{type:'start',partial:{content:[]}}},result:async()=>result}}};
        \\const harness=await M.Harness.open(new M.MemoryStorage(),{models,registry,...(input.noEnv?{}:{env:()=>env}),settings:{compaction:{enabled:false},retry:{enabled:false}}},ctx);const stop=harness.subscribeCommits(publication=>{for(const change of publication.changes)if(change.type==='document'&&change.value!==null)documents.set(change.record.kind,JSON.parse(JSON.stringify(change.value)))});
        \\try{const root=await harness.root(ctx,{agent:{model:{provider:'held',modelId:'held'}}});harness.resume();require((await(await root.submit({type:'input',content:'go'},ctx)).wait(ctx)).status==='done','generation complete');require(documents.get('pi.codemode.run')?.result?.isError===false,'script outcome');const writes=ioEvents.filter(event=>event.type==='write'),expected=source.ioEvents.filter(event=>event.type==='write');require(writes.length===input.files&&writes.length===expected.length,'file count');require(ioEvents.filter(event=>event.type==='create').length===(input.files?1:0),'shared directory');for(let i=0;i<writes.length;i++){const actual=writes[i],original=expected[i];require(actual.result.ok&&JSON.stringify(actual.content)===JSON.stringify(original.content),'Source payload bytes');require(actual.path.split(/[\\/]/).at(-1)===original.path.split(/[\\/]/).at(-1),'Source fixed file name');if(actual.content.text!==undefined)require(fs.readFileSync(actual.path,'utf8')===original.content.text,'actual text file');else require(JSON.stringify([...fs.readFileSync(actual.path)])===JSON.stringify(original.content.bytes),'actual image file')}if(input.files===0)require(documents.get('pi.codemode.run').outputDir===undefined,'no environment created directory')}finally{stop();await harness.close(ctx);await sandbox.close()}}
        \\export const proof=true;
    , "native-codemode-output-files-source4") catch |err| {
        std.debug.print("Native output file Source4 {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "none" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        return err;
    };
    engine.freeValue(proof);
}
