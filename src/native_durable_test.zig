const std = @import("std");
const engine_module = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const native_json = @import("durable/backend/json.zig");
comptime {
    _ = @import("extensions/native_chord_json.zig");
}

test {
    _ = @import("extensions/native_durable_broker.zig");
    _ = @import("extensions/native_worker.zig");
    _ = @import("extensions/native_durable_observation.zig");
    _ = @import("extensions/native_durable_state.zig");
    _ = @import("durable/backend/sqlite_source.zig");
    _ = @import("extensions/native_durable_registry.zig");
}
test "native durable VM stores owned numeric records and serves source ordered cursors without Node" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const output = try engine.evalModule(
        \\import {MemoryStorage} from '@earendil-works/pi-durable';
        \\const store=new MemoryStorage();
        \\await store.commit([{type:'conversation',value:{id:1}},{type:'conversation',value:{id:3}}],{});
        \\const page=await store.scanConversations({order:'descending'},1,undefined,{});
        \\const before=await store.conversation(1,{});before.id=900;
        \\const detached=(await store.conversation(1,{})).id===1;
        \\if(!(store instanceof MemoryStorage)||store.constructor!==MemoryStorage)throw Error('MemoryStorage constructor identity');
        \\const id=await store.mintId();await store.close({});
        \\globalThis.result=JSON.stringify({page,detached,id});
    , "native-durable-test");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"page\":{\"items\":[{\"id\":3}],\"next\":{\"after\":3,\"order\":\"descending\"}},\"detached\":true,\"id\":4}", text);
}

test "native durable VM persistent backends preserve source request index differences after reopen" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_length = try tmp.dir.realPath(std.testing.io, &buffer);
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const global = engine_module.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "testRoot", try sdk.text(engine, buffer[0..root_length]));
    errdefer std.debug.print("Native persistent VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {MemoryStorage,createSession} from '@earendil-works/pi-durable';
        \\import {openNodeJsonlStorage} from '@earendil-works/pi-durable/storage/jsonl/node';
        \\import {openNodeSqliteStorage} from '@earendil-works/pi-durable/storage/sqlite/node';
        \\const results=[];
        \\for(const kind of ['memory','jsonl','sqlite']) {
        \\ const open=()=>kind==='memory'?new MemoryStorage():kind==='jsonl'?openNodeJsonlStorage(testRoot+'/jsonl',{}, {fsync:true}):openNodeSqliteStorage(testRoot+'/state.sqlite');
        \\ let store=await open();
        \\ await store.commit([{type:'conversation',value:{id:1}}],{});
        \\ await store.commit([2,3].map(id=>({type:'submission',value:{id,type:'input',conversationId:1,requestId:'shared',status:'queued'}})),{});
        \\ const first=(await store.submissionByRequest(1,'shared',{})).id;
        \\ await store.commit([{type:'submission',value:{id:3,type:'input',conversationId:1,requestId:'moved',status:'queued'}}],{});
        \\ const shared=(await store.submissionByRequest(1,'shared',{}))?.id??null;
        \\ if(kind!=='memory'){await store.close({});store=await open()}
        \\ const reopened=(await store.submissionByRequest(1,'shared',{}))?.id??null;
        \\ const session=createSession(store);await session.commit(tx=>tx.appendEntry(1,{kind:'persistent'}),{});
        \\ const entry=(await store.scanEntries({conversationId:1},10,undefined,{})).items[0].kind;
        \\ await session.close({});results.push({kind,first,shared,reopened,entry});
        \\}
        \\globalThis.result=JSON.stringify(results);
    , "native-durable-persistent");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("[{\"kind\":\"memory\",\"first\":3,\"shared\":null,\"reopened\":null,\"entry\":\"persistent\"},{\"kind\":\"jsonl\",\"first\":3,\"shared\":null,\"reopened\":null,\"entry\":\"persistent\"},{\"kind\":\"sqlite\",\"first\":2,\"shared\":2,\"reopened\":2,\"entry\":\"persistent\"}]", text);
}

test "native durable VM cancellation preserves reason identity before admission and settles admitted writes" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const output = try engine.evalModule(
        \\import {MemoryStorage,createSession} from '@earendil-works/pi-durable';
        \\const store=new MemoryStorage(),session=createSession(store),reason={cancel:'identity'},signal={aborted:true,reason,throwIfAborted(){if(this.aborted)throw this.reason}};
        \\let before=false,after=false,ran=false;
        \\try{await session.commit(()=>{ran=true},{abortSignal:signal})}catch(e){before=e===reason}
        \\signal.aborted=false;
        \\try{await session.commit(async tx=>{await tx.createRootConversation();signal.aborted=true},{abortSignal:signal})}catch(e){after=e===reason}
        \\const absent=await store.conversation(1,{});
        \\if(absent===undefined)await session.commit(tx=>tx.createRootConversation(),{});
        \\const created=await session.commit(tx=>tx.createConversation({ownership:{kind:'ownerless'}}),{});
        \\const entry=await session.commit(tx=>tx.appendEntry(1,{kind:'fixture'}),{});
        \\const fork=await session.commit(tx=>tx.forkConversation(1,entry.id,{ownership:{kind:'ownerless'}}),{});
        \\const inherited=(await store.scanEntries({conversationId:fork.id},10,undefined,{})).items[0].kind;
        \\await session.close({});globalThis.result=JSON.stringify({before,after,ran,absent:absent===undefined,created:created.id,fork:fork.parent,inherited});
    , "native-durable-cancel-fork");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"before\":true,\"after\":false,\"ran\":false,\"absent\":false,\"created\":2,\"fork\":{\"conversationId\":1,\"at\":3},\"inherited\":\"fixture\"}", text);
}

test "native durable VM Session serializes async callbacks rolls back failure and retires escaped transactions" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const output = try engine.evalModule(
        \\import {MemoryStorage,createSession} from '@earendil-works/pi-durable';
        \\const store=new MemoryStorage(), session=createSession(store),order=[];
        \\let retained;
        \\const first=session.commit(async tx=>{order.push('first-start');await Promise.resolve();retained=tx;await tx.createRootConversation();order.push('first-end');return {value:1}},{});
        \\const second=session.commit(async tx=>{order.push('second');return await tx.appendEntry(1,{kind:'fixture',data:'committed'})},{});
        \\const one=await first,two=await second;
        \\let closed=false;try{await retained.appendEntry(1,{kind:'bad'})}catch{closed=true}
        \\let failed=false;try{await session.commit(async tx=>{await tx.appendEntry(1,{kind:'rolled-back'});throw Error('rollback')},{})}catch{failed=true}
        \\const entries=await store.scanEntries({conversationId:1},10,undefined,{});
        \\await session.close({});
        \\globalThis.result=JSON.stringify({order,one,two:two.kind,closed,failed,entries:entries.items.map(e=>e.kind)});
    , "native-durable-session");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"order\":[\"first-start\",\"first-end\",\"second\"],\"one\":{\"value\":1},\"two\":\"fixture\",\"closed\":true,\"failed\":true,\"entries\":[\"fixture\"]}", text);
}

test "native durable VM listeners preserve context identity snapshot removal and close admission ordering" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const output = try engine.evalModule(
        \\import {MemoryStorage,createSession} from '@earendil-works/pi-durable';
        \\const store=new MemoryStorage(),session=createSession(store),context={trace:'original'},order=[];
        \\const listener=(p,c)=>order.push(`commit:${p.seq}:${c===context}:${p.changes[0].type}`);
        \\const off=session.subscribeCommits(listener);session.subscribeCommits(listener);
        \\let offLater;session.subscribeCommits(()=>{order.push('remove');offLater()});offLater=session.subscribeCommits(()=>order.push('later'));
        \\await session.commit(tx=>tx.createRootConversation(),context);off();off();
        \\session.subscribeClose(()=>order.push('close'));
        \\const admitted=session.commit(async tx=>{order.push('callback');await tx.appendEntry(1,{kind:'fixture'})},context);
        \\const closing=session.close({});
        \\let sealed=false;try{await session.commit(()=>{},context)}catch{sealed=true}
        \\await admitted;await closing;await session.close({});order.push('settled');
        \\globalThis.result=JSON.stringify({order,sealed});
    , "native-durable-listeners");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"order\":[\"commit:1:true:conversation\",\"remove\",\"later\",\"close\",\"callback\",\"remove\",\"settled\"],\"sealed\":true}", text);
}

test "native durable VM Harness creation hooks initialization forks and builtin documents match actual Source" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Native Harness fixture failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage} from '@earendil-works/pi-durable';
        \\const store=new MemoryStorage(),registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}},events=[];
        \\const harness=await Harness.open(store,{registry,models:{getModel(){return undefined}},now:()=>1234,conversationCreated:async(tx,record)=>{events.push(['created',record.id]);await tx.appendEntry(record.id,{kind:'hook'})}},{});
        \\const root=await harness.root({}, {agent:{cwd:'/fixture-Ω'},init:async(tx,id)=>{events.push(['init',id]);await tx.appendEntry(id,{kind:'init'})}});
        \\const again=await harness.root({}, {init(){throw Error('existing root must skip init')}});
        \\const rootEntries=await root.entries({},20,undefined,{});
        \\const fork=await root.fork(rootEntries.items.at(-1).id,{ownership:{kind:'ownerless'}},{});
        \\const independent=await harness.createConversation({ownership:{kind:'ownerless'}},{});
        \\const scopes={items:[]};for(const id of [root.id,fork.id,independent.id])scopes.items.push(...(await store.scanDocuments({scope:{kind:'conversation',conversationId:id},at:'current'},100,undefined,{})).items);
        \\const documents=[];
        \\for(const record of scopes.items){const current=await store.document(record.id,'current',{});documents.push({record,value:record.kind==='pi.provider'?{sessionId:typeof current.value.sessionId==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(current.value.sessionId)}:current.value,version:current.version})}
        \\const forkEntries=await fork.entries({},100,undefined,{});
        \\const independentEntries=await independent.entries({},100,undefined,{});
        \\await harness.close({});
        \\globalThis.result=JSON.stringify({root:root.id,again:again.id,fork:fork.id,independent:independent.id,events,rootEntries:rootEntries.items.map(e=>({id:e.id,kind:e.kind,conversationId:e.conversationId})),forkEntries:forkEntries.items.map(e=>({id:e.id,kind:e.kind,conversationId:e.conversationId})),independentEntries:independentEntries.items.map(e=>({id:e.id,kind:e.kind,conversationId:e.conversationId})),documents});
    , "native-durable-harness-creation");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    var actual = try native_json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var expected = try native_json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/harness-creation-7fb59f9.json"));
    defer expected.deinit();
    if (!native_json.equal(actual.value, expected.value)) std.debug.print("Native Harness actual: {s}\n", .{text});
    try std.testing.expect(native_json.equal(actual.value, expected.value));
}

test "native durable VM Harness rollback burns source IDs without publishing and escaped transactions retain their owner" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage} from '@earendil-works/pi-durable';
        \\const store=new MemoryStorage(),registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}},reason={identity:'rollback'},publications=[];
        \\let harness=await Harness.open(store,{registry,models:{},conversationCreated:async(tx,record)=>{await tx.appendEntry(record.id,{kind:'hook'})}},{});
        \\harness.subscribeCommits(p=>publications.push({seq:p.seq,types:p.changes.map(c=>c.type)}));
        \\let retained,failed=false;
        \\try{await harness.root({}, {init(tx){retained=tx;throw reason}})}catch(e){failed=e===reason}
        \\const absent=(await store.conversation(1,{}))===undefined;
        \\const root=await harness.root({});const entries=await root.entries({},20,undefined,{});
        \\const fork=await root.fork(entries.items[0].id,{ownership:{kind:'ownerless'}},{});
        \\globalThis.retained=retained;globalThis.harness=harness;harness=null;
        \\globalThis.result=JSON.stringify({failed,absent,entry:entries.items[0].id,fork:fork.id,publications});
    , "native-durable-harness-rollback");
    defer engine.freeValue(output);
    engine_module.c.JS_RunGC(engine.runtime);
    const late = try engine.evalModule(
        \\let closed=false;try{await globalThis.retained.appendEntry(1,{kind:'late'})}catch{closed=true}
        \\if(!closed)throw Error('retained transaction accepted a late write');
        \\await globalThis.harness.close({});globalThis.retained=null;globalThis.harness=null;
    , "native-durable-harness-retirement");
    defer engine.freeValue(late);
    engine_module.c.JS_RunGC(engine.runtime);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"failed\":true,\"absent\":true,\"entry\":13,\"fork\":14,\"publications\":[{\"seq\":1,\"types\":[\"conversation\",\"entry\",\"document\",\"document\",\"document\",\"document\",\"document\"]},{\"seq\":2,\"types\":[\"conversation\",\"entry\",\"document.copy\",\"document\",\"document\",\"document\",\"document\"]}]}", text);
}

test "native durable VM Harness agent selections store names from cyclic extension objects and ignore unknown fields" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage} from '@earendil-works/pi-durable';
        \\const store=new MemoryStorage(),registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const extension={name:'alpha'};extension.self=extension;
        \\const tool={name:'shell',execute(){throw Error('metadata must not execute')}};
        \\const harness=await Harness.open(store,{registry,models:{}},{});
        \\await harness.root({}, {agent:{extensions:[extension],tools:{remove:[tool]},cwd:'/owned-Ω',unknown:'ignore'},init:async(tx,id)=>{await tx.appendEntry(id,{kind:'allocate-after-normalize',data:'x'.repeat(65536)})}});
        \\const record=await store.findDocument({kind:'pi.agent',scope:{kind:'conversation',conversationId:1}},'current',{});
        \\const value=(await store.document(record.id,'current',{})).value;
        \\await harness.close({});globalThis.result=JSON.stringify(value);
    , "native-durable-harness-agent-names");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    var actual = try native_json.Owned.parse(std.testing.allocator, text);
    defer actual.deinit();
    var expected = try native_json.Owned.parse(std.testing.allocator, "{\"extensions\":[\"alpha\"],\"tools\":{\"remove\":[\"shell\"]},\"cwd\":\"/owned-Ω\"}");
    defer expected.deinit();
    try std.testing.expect(native_json.equal(actual.value, expected.value));
}

test "native durable VM public tasks execute phases on owner broker and fence escaped runtimes" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Task VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\const order=[];let retained;
        \\const Task=defineTask({name:'fixture.step',version:1,initial:input=>({phase:'one',n:input.n}),phases:{
        \\ one:async(task,runtime,context)=>{retained=runtime;order.push('one');await runtime.commit(async(tx,current)=>{await tx.appendEntry(runtime.conversationId,{kind:'phase',data:{n:current.state.checkpoint.n}});return{status:'running',checkpoint:{phase:'two',n:task.input.n+1}}},context)},
        \\ two:async(task,runtime,context)=>{order.push('two');await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:{n:task.state.checkpoint.n}}}),context)}
        \\},abort:async(task,runtime,context)=>{await runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)}});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return name==='fixture.step'?Task:{definition:{name}}},tasks(){return[Task]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{}),root=await harness.root({});
        \\const id=await root.commit(tx=>tx.createTask(Task,{n:4},{ownership:{kind:'conversation'}}),{});
        \\const settled=await harness.waitForTask(id,{});await root.waitForIdle({});
        \\let ended=false;try{await retained.commit(()=>undefined,{})}catch{ended=true}
        \\const entries=await root.entries({},20,undefined,{});await harness.close({});
        \\globalThis.result=JSON.stringify({id,order,outcome:settled.state.outcome,ended,entries:entries.items.map(e=>({kind:e.kind,data:e.data,byTaskId:e.byTaskId}))});
    , "native-durable-public-task");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"id\":7,\"order\":[\"one\",\"two\"],\"outcome\":{\"status\":\"completed\",\"result\":{\"n\":5}},\"ended\":true,\"entries\":[{\"kind\":\"phase\",\"data\":{\"n\":4},\"byTaskId\":7}]}", text);
}

test "native durable VM public task abort signals the old invocation and runs a fresh abort handler" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Abort Task VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\const order=[];let retained;const started=new Promise(resolve=>globalThis.startedTask=resolve);
        \\const Task=defineTask({name:'fixture.abort',version:1,initial:()=>({phase:'hold'}),phases:{hold:async(task,runtime,context)=>{retained=runtime;order.push('run');startedTask();await new Promise(resolve=>runtime.signal.addEventListener('abort',resolve,{once:true}));order.push('signaled')}},abort:async(task,runtime,context)=>{order.push('abort');await runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)}});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return name==='fixture.abort'?Task:{definition:{name}}},tasks(){return[Task]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{}),root=await harness.root({});
        \\const id=await root.commit(tx=>tx.createTask(Task,{}, {ownership:{kind:'conversation'}}),{});
        \\const receipt=harness.waitForTask(id,{});await started;
        \\const marked=await harness.abortTask(id,{}), settled=await receipt;
        \\const terminal=await harness.abortTask(id,{});await root.waitForIdle({});
        \\let ended=false;try{await retained.commit(()=>undefined,{})}catch{ended=true}
        \\await harness.close({});globalThis.result=JSON.stringify({id,order,marked,terminal,outcome:settled.state.outcome,ended,signal:retained.signal.aborted});
    , "native-durable-public-task-abort");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"id\":7,\"order\":[\"run\",\"signaled\",\"abort\"],\"marked\":\"marked\",\"terminal\":\"terminal\",\"outcome\":{\"status\":\"aborted\"},\"ended\":true,\"signal\":true}", text);
}

test "native durable VM public task memos use durable winners and lifecycle timestamps follow the harness clock" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Memo VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\let observed;const Task=defineTask({name:'fixture.memo',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{
        \\ const first=await runtime.memo('key',{winner:'first'},context),second=await runtime.memo('key',{winner:'second'},context);first.winner='detached';
        \\ const read=await runtime.memo('key',context),record=await runtime.getTask(runtime.taskId,context),entry=await runtime.entry(999,context);
        \\ observed={second,read,running:record.state.status,absent:entry===undefined,now:runtime.now()};
        \\ await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:'done'}}),context)
        \\}},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return name==='fixture.memo'?Task:{definition:{name}}},tasks(){return[Task]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{},now:()=>123},{}),root=await harness.root({});
        \\const id=await root.commit(tx=>tx.createTask(Task,{}, {ownership:{kind:'conversation'}}),{}),receipt=await harness.waitForTask(id,{});
        \\await harness.close({});globalThis.result=JSON.stringify({observed,memos:receipt.memos,startedAt:receipt.startedAt,endedAt:receipt.endedAt,outcome:receipt.state.outcome});
    , "native-durable-public-task-memo");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"observed\":{\"second\":{\"winner\":\"first\"},\"read\":{\"winner\":\"first\"},\"running\":\"running\",\"absent\":true,\"now\":123},\"startedAt\":123,\"endedAt\":123,\"outcome\":{\"status\":\"completed\",\"result\":\"done\"}}", text);
}

test "native durable VM public task recovery preserves startedAt and fences runtime handles through forced GC" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Recovery VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\const store=new MemoryStorage();await store.commit([{type:'conversation',value:{id:1}},{type:'task',value:{id:7,kind:'fixture.recover',version:1,conversationId:1,input:{n:9},background:false,abortRequested:false,startedAt:17,state:{status:'running',checkpoint:{phase:'go'}}}}],{});
        \\let retained;const Task=defineTask({name:'fixture.recover',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{retained=runtime;await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:task.input.n}}),context)}},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return name==='fixture.recover'?Task:{definition:{name}}},tasks(){return[Task]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const harness=await Harness.open(store,{registry,models:{},now:()=>22},{});
        \\const recovered=(await harness.getTask(7,{})).state.status,receipt=await harness.waitForTask(7,{});
        \\await harness.close({});globalThis.runtimeAfterClose=retained;
        \\globalThis.result=JSON.stringify({recovered,startedAt:receipt.startedAt,endedAt:receipt.endedAt,outcome:receipt.state.outcome});
    , "native-durable-public-task-recovery");
    defer engine.freeValue(output);
    engine_module.c.JS_RunGC(engine.runtime);
    const late = try engine.evalModule(
        \\let ended=false;try{await runtimeAfterClose.getTask(7,{})}catch{ended=true}if(!ended)throw Error('runtime outlived invocation');globalThis.runtimeAfterClose=null;
    , "native-durable-public-task-recovery-gc");
    defer engine.freeValue(late);
    engine_module.c.JS_RunGC(engine.runtime);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"recovered\":\"pending\",\"startedAt\":17,\"endedAt\":22,\"outcome\":{\"status\":\"completed\",\"result\":9}}", text);
}

test "native durable VM public tasks create owned children wait and read ordered outcomes" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Child task VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\const order=[];
        \\const abort=async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context);
        \\const Child=defineTask({name:'fixture.child',version:1,initial:input=>({phase:'go',n:input.n}),phases:{go:async(task,runtime,context)=>{order.push('child');await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:task.input.n}}),context)}},abort});
        \\const Parent=defineTask({name:'fixture.parent',version:1,initial:()=>({phase:'start'}),phases:{
        \\ start:async(task,runtime,context)=>{order.push('parent');await runtime.commit(async tx=>{const child=await tx.createTask(Child,{n:8},{ownership:{kind:'task',taskId:runtime.taskId}});return{status:'waiting',checkpoint:{phase:'join',child},on:[child],policy:'allSettled'}},context)},
        \\ join:async(task,runtime,context)=>{order.push('join');const [outcome]=await runtime.outcomes([task.state.checkpoint.child],context);await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:outcome.result+1}}),context)}
        \\},abort});
        \\const all=[Parent,Child],registry={subscribe(){return()=>{}},snapshot(){return{task(name){return all.find(t=>t.definition.name===name)??{definition:{name}}},tasks(){return all},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{},now:()=>41},{}),root=await harness.root({});
        \\const id=await root.commit(tx=>tx.createTask(Parent,{}, {ownership:{kind:'conversation'}}),{}),receipt=await harness.waitForTask(id,{});
        \\await harness.waitForIdle({});const page=await store.scanTasks({conversationId:1},10,undefined,{});
        \\await harness.close({});globalThis.result=JSON.stringify({id,order,result:receipt.state.outcome.result,tasks:page.items.map(t=>({id:t.id,owner:t.owner,status:t.state.status,outcome:t.state.outcome}))});
    , "native-durable-public-task-children");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"id\":7,\"order\":[\"parent\",\"child\",\"join\"],\"result\":9,\"tasks\":[{\"id\":7,\"status\":\"terminal\",\"outcome\":{\"status\":\"completed\",\"result\":9}},{\"id\":8,\"owner\":7,\"status\":\"terminal\",\"outcome\":{\"status\":\"completed\",\"result\":8}}]}", text);
}

test "native durable VM registry replacement switches phase snapshots without invoking stale handlers" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Registry task VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\const order=[];let current;
        \\const abort=async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context);
        \\const New=defineTask({name:'fixture.replace',version:1,initial:()=>({phase:'next'}),phases:{next:async(task,runtime,context)=>{order.push('new');await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:'updated'}}),context)}},abort});
        \\const Old=defineTask({name:'fixture.replace',version:1,initial:()=>({phase:'start'}),phases:{start:async(task,runtime,context)=>{order.push('old');await runtime.commit(()=>({status:'running',checkpoint:{phase:'next'}}),context);current=New},next(){throw Error('stale handler ran')}},abort});current=Old;
        \\const registry={subscribe(){return()=>{}},snapshot(){const task=current;return{task(name){return name==='fixture.replace'?task:{definition:{name}}},tasks(){return[task]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{}),root=await harness.root({});
        \\const id=await root.commit(tx=>tx.createTask(Old,{}, {ownership:{kind:'conversation'}}),{}),receipt=await harness.waitForTask(id,{});
        \\await harness.close({});globalThis.result=JSON.stringify({id,order,outcome:receipt.state.outcome});
    , "native-durable-public-task-registry");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"id\":7,\"order\":[\"old\",\"new\"],\"outcome\":{\"status\":\"completed\",\"result\":\"updated\"}}", text);
}

test "native durable VM public task migrations execute on owner before native reservation" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Migration VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\const calls=[],store=new MemoryStorage();await store.commit([{type:'conversation',value:{id:1}},{type:'task',value:{id:7,kind:'fixture.migrate',version:1,conversationId:1,input:{n:3},background:false,abortRequested:false,state:{status:'pending',checkpoint:{phase:'legacy',extra:4}}}}],{});
        \\const Task=defineTask({name:'fixture.migrate',version:2,initial:()=>({phase:'go'}),migrate(input,checkpoint,from){calls.push({input,checkpoint,from});return{input:{n:input.n+checkpoint.extra},checkpoint:{phase:'go'}}},phases:{go:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:task.input.n}}),context)},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return name==='fixture.migrate'?Task:{definition:{name}}},tasks(){return[Task]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const harness=await Harness.open(store,{registry,models:{},now:()=>66},{}),receipt=await harness.waitForTask(7,{});
        \\await harness.close({});globalThis.result=JSON.stringify({calls,version:receipt.version,input:receipt.input,outcome:receipt.state.outcome});
    , "native-durable-public-task-migration");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"calls\":[{\"input\":{\"n\":3},\"checkpoint\":{\"phase\":\"legacy\",\"extra\":4},\"from\":1}],\"version\":2,\"input\":{\"n\":7},\"outcome\":{\"status\":\"completed\",\"result\":7}}", text);
}

test "native durable VM document drafts revoke nested handles and preserve committed snapshots on rollback" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const Doc=defineDoc({kind:'fixture.doc',version:1,scope:'conversation',history:'rewindable',fork:'asOf',initial:()=>({nested:{n:0},items:[]}),checkpointWhen:()=>true});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{}),root=await harness.root({});let draft,nested,same=false;
        \\await root.commit(async tx=>{draft=await tx.doc(Doc,root.id);same=draft===await tx.doc(Doc,root.id);nested=draft.nested;draft.nested.n=2;draft.items.push('Ω')},{});
        \\let ended=false;try{nested.n=99}catch{ended=true}
        \\const first=await harness.snapshot(Doc,root.id,{});let readonly=false;try{first.nested.n=99}catch{readonly=true}
        \\const reason={original:true};let failed=false;try{await root.commit(async tx=>{const value=await tx.doc(Doc,root.id);value.nested.n=3;throw reason},{})}catch(e){failed=e===reason}
        \\const second=await harness.snapshot(Doc,root.id,{});await harness.close({});
        \\globalThis.result=JSON.stringify({same,ended,readonly,failed,first,second});
    , "native-durable-document-draft");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"same\":true,\"ended\":true,\"readonly\":false,\"failed\":true,\"first\":{\"nested\":{\"n\":99},\"items\":[\"Ω\"]},\"second\":{\"nested\":{\"n\":99},\"items\":[\"Ω\"]}}", text);
}

test "native durable VM document families migrate and retain historical fork values" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document family VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineDocFamily} from '@earendil-works/pi-durable';
        \\const common={kind:'fixture.family',scope:'conversation',history:'rewindable',fork:'asOf',family:true,checkpointWhen:()=>true};
        \\const V1=defineDocFamily({...common,version:1,initial:seed=>({n:seed.n})}), V2=defineDocFamily({...common,version:2,initial:()=>({n:0,label:'new'}),migrate:(value,from)=>({...value,label:'migrated-'+from})});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{}),root=await harness.root({});
        \\let anchor;await root.commit(async tx=>{const value=await tx.doc(V1,root.id,'key',{n:5});value.n+=1;anchor=await tx.appendEntry(root.id,{kind:'anchor'})},{});
        \\const migrated=await harness.snapshot(V2,root.id,'key',{});
        \\await root.commit(async tx=>{const value=await tx.doc(V2,root.id,'key',{});value.n=9},{});
        \\const record=await store.findDocument({kind:'fixture.family',scope:{kind:'conversation',conversationId:root.id},key:'key'},'current',{}), stored=await store.document(record.id,'current',{});
        \\const fork=await root.fork(anchor.id,{ownership:{kind:'ownerless'}},{}), inherited=await harness.snapshot(V2,fork.id,'key',{}),historical=await harness.snapshotAsOf(V2,root.id,'key',anchor.id,{});
        \\await harness.close({});globalThis.result=JSON.stringify({migrated,current:stored.value,version:stored.version,inherited,historical});
    , "native-durable-document-family");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"migrated\":{\"n\":6,\"label\":\"migrated-1\"},\"current\":{\"n\":9,\"label\":\"migrated-1\"},\"version\":2,\"inherited\":{\"n\":6,\"label\":\"migrated-1\"},\"historical\":{\"n\":6,\"label\":\"migrated-1\"}}", text);
}

test "native durable VM document retirement preserves final history and replacement uses a fresh identity" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document retirement VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const Doc=defineDoc({kind:'fixture.retire',version:1,scope:'conversation',history:'rewindable',fork:'asOf',initial:()=>({n:1}),checkpointWhen:()=>true});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{}),root=await harness.root({});
        \\await root.commit(async tx=>{(await tx.doc(Doc,root.id)).n=2},{});
        \\const address={kind:'fixture.retire',scope:{kind:'conversation',conversationId:root.id}},old=await store.findDocument(address,'current',{});
        \\await root.commit(async tx=>{const doc=await tx.doc(Doc,root.id);doc.n=3;await tx.retireDoc(Doc,root.id);const replacement=await tx.doc(Doc,root.id);replacement.n=4},{});
        \\const current=await store.findDocument(address,'current',{}),value=await harness.snapshot(Doc,root.id,{}),history=await store.document(old.id,2,{});
        \\await harness.close({});globalThis.result=JSON.stringify({old:old.id,current:current.id,distinct:old.id!==current.id,value,history:history.value});
    , "native-durable-document-retirement");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"old\":7,\"current\":8,\"distinct\":true,\"value\":{\"n\":4},\"history\":{\"n\":2}}", text);
}

test "native durable VM document deltas and checkpoint predicates preserve source counters" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document checkpoint VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const calls=[],Doc=defineDoc({kind:'fixture.delta',version:1,scope:'conversation',history:'rewindable',fork:'asOf',initial(){calls.push({initial:arguments.length});return{n:0,nested:{x:1},text:'A',items:[]}},checkpointWhen(value,ops,info){calls.push({ops,info});return info.deltasSinceBase===1}});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{}),root=await harness.root({});
        \\await root.commit(async tx=>{await tx.doc(Doc,root.id)},{});
        \\const record=await store.findDocument({kind:'fixture.delta',scope:{kind:'conversation',conversationId:root.id}},'current',{});
        \\await root.commit(async tx=>{const d=await tx.doc(Doc,root.id);d.n=2;d.text+='Ω';d.items.push(7)},{});const first=await store.document(record.id,'current',{});
        \\await root.commit(async tx=>{const d=await tx.doc(Doc,root.id);d.nested.x=3},{});const second=await store.document(record.id,'current',{});
        \\await root.commit(async tx=>{await tx.doc(Doc,root.id)},{});
        \\await harness.close({});globalThis.result=JSON.stringify({calls,first:{value:first.value,deltas:first.deltasSinceBase},second:{value:second.value,deltas:second.deltasSinceBase}});
    , "native-durable-document-checkpoint");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"calls\":[{\"initial\":0},{\"ops\":[[\"s\",[\"n\"],2],[\"a\",[\"text\"],\"Ω\"],[\"p\",[\"items\"],0,0,[7]]],\"info\":{\"deltasSinceBase\":0}},{\"ops\":[[\"s\",[\"nested\",\"x\"],3]],\"info\":{\"deltasSinceBase\":1}}],\"first\":{\"value\":{\"n\":2,\"nested\":{\"x\":1},\"text\":\"AΩ\",\"items\":[7]},\"deltas\":1},\"second\":{\"value\":{\"n\":2,\"nested\":{\"x\":3},\"text\":\"AΩ\",\"items\":[7]},\"deltas\":0}}", text);
}

test "native durable VM document unloading cold reads storage and checkpoint preparation revokes every draft access" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document cache VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\let captured,ended=[];const Doc=defineDoc({kind:'fixture.unload',version:1,scope:'session',initial:()=>({nested:{n:1}}),checkpointWhen(){for(const read of [()=>captured.nested,()=>Object.keys(captured),()=>('nested' in captured),()=>Object.getOwnPropertyDescriptor(captured,'nested')]){try{read();ended.push(false)}catch{ended.push(true)}}return false}});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{});
        \\await harness.commit(async tx=>{await tx.doc(Doc)},{});await harness.commit(async tx=>{captured=await tx.doc(Doc);captured.nested.n=2},{});
        \\const first=await harness.snapshot(Doc,{});first.nested.n=99;const same=first===await harness.snapshot(Doc,{});await harness.unloadDocuments();const second=await harness.snapshot(Doc,{});await harness.close({});
        \\globalThis.result=JSON.stringify({ended,same,distinct:first!==second,first,second});
    , "native-durable-document-unload");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"ended\":[true,true,true,true],\"same\":true,\"distinct\":true,\"first\":{\"nested\":{\"n\":99}},\"second\":{\"nested\":{\"n\":2}}}", text);
}

test "native durable VM document watch serializes pending frames and stop settles while callback remains owned" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document watch VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const Doc=defineDoc({kind:'fixture.watch',version:1,scope:'session',initial:()=>({n:1})});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{});await harness.commit(async tx=>{await tx.doc(Doc)},{});
        \\const watch=await harness.watchDoc(Doc,{}),initial=watch.value.n,calls=[];for(const n of [2,3])await harness.commit(async tx=>{(await tx.doc(Doc)).n=n},{tag:n});const beforeStart=watch.value.n;
        \\let release,entered;const gate=new Promise(r=>release=r),started=new Promise(r=>entered=r);watch.start(async(value,ops,context)=>{calls.push({value,ops,tag:context.tag});entered();await gate});await started;const running=watch.value.n;
        \\await harness.commit(async tx=>{(await tx.doc(Doc)).n=4},{tag:4});const stopped=await watch.stop(),closed=await watch.closed;release();await Promise.resolve();await Promise.resolve();await harness.close({});
        \\globalThis.result=JSON.stringify({initial,beforeStart,running,calls,stopped,closed,sameEnd:stopped===closed});
    , "native-durable-document-watch-stop");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"initial\":1,\"beforeStart\":1,\"running\":2,\"calls\":[{\"value\":{\"n\":2},\"ops\":[[\"s\",[\"n\"],2]]}],\"stopped\":{\"reason\":\"stopped\"},\"closed\":{\"reason\":\"stopped\"},\"sameEnd\":true}", text);
}

test "native durable VM document watches preserve checkpoint ops retire cancel and normalize listener failure" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document watch lifecycle VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\import {BACKGROUND_CONTEXT,createContextKey,withContextValue,withAbortSignal} from '@earendil-works/chord/context';
        \\const Doc=defineDoc({kind:'fixture.watch.lifecycle',version:1,scope:'session',initial:()=>({n:1}),checkpointWhen:()=>true}),key=createContextKey('trace'),context=withContextValue(key,17,BACKGROUND_CONTEXT),controller=new AbortController(),cancelContext=withAbortSignal(controller.signal,context);
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks(){return[]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},context);await harness.commit(async tx=>{await tx.doc(Doc)},context);
        \\const watch=await harness.watchDoc(Doc,context),cancelled=await harness.watchDoc(Doc,cancelContext),failed=await harness.watchDoc(Doc,context),events=[];
        \\watch.start(async(value,ops,delivery)=>{events.push({value,ops,key:delivery.value(key),uncancelled:delivery.abortSignal===undefined})});failed.start(async()=>{throw 'bad-listener'});
        \\await harness.commit(async tx=>{(await tx.doc(Doc)).n=2},cancelContext);const failure=await failed.closed;controller.abort();const cancellation=await cancelled.closed;
        \\await harness.commit(async tx=>{await tx.retireDoc(Doc)},context);const retirement=await watch.closed;
        \\const missing=await harness.watchDoc(Doc,context);await harness.commit(async tx=>{await tx.doc(Doc)},context);const closing=await harness.watchDoc(Doc,context);await harness.close(context);const closed=await closing.closed;
        \\globalThis.result=JSON.stringify({events,failure:{reason:failure.reason,error:failure.error instanceof Error,message:failure.error.message},cancellation,retirement,missing:missing===undefined,closed});
    , "native-durable-document-watch-lifecycle");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"events\":[{\"value\":{\"n\":2},\"ops\":[[\"s\",[\"n\"],2]],\"key\":17,\"uncancelled\":true},{\"value\":null,\"ops\":[[\"r\",null]],\"key\":17,\"uncancelled\":true}],\"failure\":{\"reason\":\"listener_error\",\"error\":true,\"message\":\"bad-listener\"},\"cancellation\":{\"reason\":\"cancelled\"},\"retirement\":{\"reason\":\"retired\"},\"missing\":true,\"closed\":{\"reason\":\"session_closed\"}}", text);
}

test "native durable VM document watch overflow replaces the bounded pending queue" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document watch overflow VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const Doc=defineDoc({kind:'fixture.watch.overflow',version:1,scope:'session',initial:()=>({n:0})}),store=new MemoryStorage(),session=createSession(store);await session.commit(async tx=>{await tx.doc(Doc)},{});
        \\const watch=await session.watchDoc(Doc,{}),initial=watch.value.n,frames=[];for(let n=1;n<=102;n++)await session.commit(async tx=>{(await tx.doc(Doc)).n=n},{});
        \\watch.start(async(value,ops)=>{frames.push({value,ops});if(frames.length===2)await watch.stop()});const end=await watch.closed;await session.close({});globalThis.result=JSON.stringify({initial,frames,end,value:watch.value});
    , "native-durable-document-watch-overflow");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"initial\":0,\"frames\":[{\"value\":{\"n\":101},\"ops\":[[\"r\",{\"n\":101}]]},{\"value\":{\"n\":102},\"ops\":[[\"s\",[\"n\"],102]]}],\"end\":{\"reason\":\"stopped\"},\"value\":{\"n\":102}}", text);
}

test "native durable VM runtime document reads and watches live across phases then stop at invocation end" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Runtime document watch VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineDoc,defineTask} from '@earendil-works/pi-durable';
        \\const Doc=defineDoc({kind:'fixture.runtime.doc',version:1,scope:'session',initial:()=>({n:1}),checkpointWhen:()=>true}),events=[];let watch,retained,firstContext;
        \\const Task=defineTask({name:'fixture.runtime.doc.task',version:1,initial:()=>({phase:'start'}),phases:{
        \\ start:async(task,runtime,context)=>{retained=runtime;firstContext=context;watch=await runtime.watchDoc(Doc,context);watch.start(async(value,ops)=>{events.push({value,ops})});await runtime.commit(async tx=>{(await tx.doc(Doc)).n=2;return{status:'running',checkpoint:{phase:'next'}}},context)},
        \\ next:async(task,runtime,context)=>{const prior=await retained.snapshot(Doc,context),value=await runtime.snapshot(Doc,context);await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:{sameContext:context===firstContext,sameSignal:context.abortSignal===firstContext.abortSignal,prior,value}}}),context)}
        \\},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return name===Task.definition.name?Task:{definition:{name}}},tasks(){return[Task]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const store=new MemoryStorage(),harness=await Harness.open(store,{registry,models:{}},{}),root=await harness.root({});await harness.commit(async tx=>{await tx.doc(Doc)},{});let id;await root.commit(async tx=>{id=await tx.createTask(Task,{},{ownership:{kind:'conversation'}});},{});const done=await harness.waitForTask(id,{}),end=await watch.closed;let fenced=false;try{await retained.snapshot(Doc,{})}catch{fenced=true}await harness.close({});globalThis.result=JSON.stringify({events,outcome:done.state.outcome,end,fenced});
    , "native-durable-runtime-document-watch");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"events\":[{\"value\":{\"n\":2},\"ops\":[[\"s\",[\"n\"],2]]}],\"outcome\":{\"status\":\"completed\",\"result\":{\"sameContext\":true,\"sameSignal\":true,\"prior\":{\"n\":2},\"value\":{\"n\":2}}},\"end\":{\"reason\":\"stopped\"},\"fenced\":true}", text);
}

test "native durable VM context keys cancellation and waiters preserve source identities and underlying work" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Native Context VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {BACKGROUND_CONTEXT,TODO_CONTEXT,createContextKey,withContextValue,withAbortSignal,withoutAbortSignal,withCancel,awaitWithContext} from '@earendil-works/chord/context';
        \\const key=createContextKey('trace'),other=createContextKey('trace'),value={owned:true},base=withContextValue(key,value,BACKGROUND_CONTEXT),child=withCancel(base),reason=new Error('original');let resolve;
        \\const pending=new Promise(r=>resolve=r),waiter=awaitWithContext(pending,child.context);child.cancel(reason);let rejectIdentity=false;try{await waiter}catch(error){rejectIdentity=error===reason}resolve(7);const late=await pending;
        \\const promise=Promise.resolve(8),same=awaitWithContext(promise,BACKGROUND_CONTEXT)===promise,clean=withoutAbortSignal(child.context),aborted=new AbortController();aborted.abort('raw');let plain;try{await awaitWithContext(Promise.resolve(1),withAbortSignal(aborted.signal,base))}catch(error){plain={name:error.name,message:error.message,error:error instanceof Error}}
        \\globalThis.result=JSON.stringify({keyUnique:key.token!==other.token,frozen:Object.isFrozen(key),valueIdentity:clean.value(key)===value,missing:clean.value(other)===undefined,rootName:String(BACKGROUND_CONTEXT),todoName:String(TODO_CONTEXT),childName:String(child.context),same,rejectIdentity,late,removed:clean.abortSignal===undefined,plain,parentActive:base.abortSignal===undefined});
    , "native-durable-context-lifetime");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"keyUnique\":true,\"frozen\":true,\"valueIdentity\":true,\"missing\":true,\"rootName\":\"[Context BACKGROUND_CONTEXT]\",\"todoName\":\"[Context TODO_CONTEXT]\",\"childName\":\"[Context BACKGROUND_CONTEXT].WithValue(trace).WithValue(chord.abortSignal)\",\"same\":true,\"rejectIdentity\":true,\"late\":7,\"removed\":true,\"plain\":{\"name\":\"AbortError\",\"message\":\"The operation was aborted\",\"error\":true},\"parentActive\":true}", text);
}

test "native durable VM queued document watch cancellation normalizes raw reasons and readonly accessors survive stop" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Queued watch VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const session=createSession(new MemoryStorage()),Doc=defineDoc({kind:'fixture.queued.watch',version:1,scope:'session',initial:()=>({n:1})});await session.commit(async tx=>{await tx.doc(Doc)},{});
        \\let enter,leave;const entered=new Promise(r=>enter=r),gate=new Promise(r=>leave=r),controller=new AbortController();const commit=session.commit(async()=>{enter();await gate},{});await entered;const pending=session.watchDoc(Doc,{abortSignal:controller.signal});controller.abort('plain');leave();await commit;let failure;try{await pending}catch(error){failure={name:error.name,message:error.message,error:error instanceof Error}}
        \\const watch=await session.watchDoc(Doc,{});let valueReadonly=false,closedReadonly=false;try{watch.value={n:9}}catch{valueReadonly=true}try{watch.closed=Promise.resolve({reason:'bad'})}catch{closedReadonly=true}const keys=Object.keys(watch),end=await watch.stop();await session.close({});globalThis.result=JSON.stringify({failure,valueReadonly,closedReadonly,keys,end,value:watch.value});
    , "native-durable-document-watch-queued");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"failure\":{\"name\":\"AbortError\",\"message\":\"The operation was aborted\",\"error\":true},\"valueReadonly\":true,\"closedReadonly\":true,\"keys\":[],\"end\":{\"reason\":\"stopped\"},\"value\":{\"n\":1}}", text);
}

test "native durable VM adopts documents before listeners and preserves noop snapshot and observation identity" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document adoption VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const session=createSession(new MemoryStorage()),Doc=defineDoc({kind:'fixture.adoption',version:1,scope:'session',initial:()=>({n:1}),checkpointWhen:()=>true});await session.commit(async tx=>{await tx.doc(Doc)},{});
        \\const first=await session.snapshot(Doc,{});await session.commit(async tx=>{await tx.doc(Doc)},{});const sameNoop=first===await session.snapshot(Doc,{}),watch=await session.watchDoc(Doc,{});let observed,published,during;
        \\watch.start(async value=>{observed=value});session.subscribeCommits(publication=>{const change=publication.changes.find(c=>c.type==='document'&&c.record.kind==='fixture.adoption');if(change){published=change.value;during=session.snapshot(Doc,{})}});
        \\await session.commit(async tx=>{(await tx.doc(Doc)).n=2},{});const current=await session.snapshot(Doc,{}),inside=await during;await watch.stop();await session.close({});globalThis.result=JSON.stringify({sameNoop,during:inside.n,watchIdentity:observed===current,publicationIdentity:published===current});
    , "native-durable-document-adoption");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"sameNoop\":true,\"during\":2,\"watchIdentity\":true,\"publicationIdentity\":true}", text);
}

test "native durable VM documentState hydrates synchronously isolates subscriber progress and preserves disposed value" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document state VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\import {BACKGROUND_CONTEXT,createContextKey,withContextValue} from '@earendil-works/chord/context';
        \\const session=createSession(new MemoryStorage()),Doc=defineDoc({kind:'fixture.state',version:1,scope:'session',initial:()=>({n:1}),checkpointWhen:()=>true}),key=createContextKey('trace'),context=withContextValue(key,7,BACKGROUND_CONTEXT);await session.commit(async tx=>{await tx.doc(Doc)},context);
        \\const state=await session.documentState(Doc,context),slow=[],fast=[],order=[];let release;const gate=new Promise(r=>release=r);
        \\const unsubscribeSlow=state.subscribe(async(value,deliveryContext,delivery)=>{slow.push({n:value.n,delivery});order.push('hydrate');await gate});order.push('after');const unsubscribeFast=state.subscribe((value,deliveryContext,delivery)=>{fast.push({n:value.n,delivery,background:deliveryContext===BACKGROUND_CONTEXT,key:deliveryContext.value(key)})});
        \\for(const n of [2,3])await session.commit(async tx=>{(await tx.doc(Doc)).n=n},context);const latest=state.value,same=latest===await session.snapshot(Doc,context);state.dispose();state.dispose();await session.commit(async tx=>{(await tx.doc(Doc)).n=4},context);const after=state.value;unsubscribeSlow();release();await Promise.resolve();await Promise.resolve();unsubscribeFast();await session.close(context);let late;state.subscribe((value,c,delivery)=>{late={n:value.n,delivery,background:c===BACKGROUND_CONTEXT}})();globalThis.result=JSON.stringify({order,slow,fast,same,latest,after,late});
    , "native-durable-document-state");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"order\":[\"hydrate\",\"after\"],\"slow\":[{\"n\":1,\"delivery\":{\"kind\":\"hydrate\",\"sequence\":0}}],\"fast\":[{\"n\":1,\"delivery\":{\"kind\":\"hydrate\",\"sequence\":0},\"background\":true},{\"n\":2,\"delivery\":{\"kind\":\"update\",\"sequence\":1},\"background\":false,\"key\":7},{\"n\":3,\"delivery\":{\"kind\":\"update\",\"sequence\":2},\"background\":false,\"key\":7}],\"same\":true,\"latest\":{\"n\":3},\"after\":{\"n\":3},\"late\":{\"n\":3,\"delivery\":{\"kind\":\"hydrate\",\"sequence\":2},\"background\":true}}", text);
}

test "native durable VM documentState retirement retains null and recreation stays a separate incarnation" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document state retirement VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const session=createSession(new MemoryStorage()),Doc=defineDoc({kind:'fixture.state.retire',version:1,scope:'session',initial:()=>({n:1})});await session.commit(async tx=>{await tx.doc(Doc)},{});const state=await session.documentState(Doc,{}),events=[];state.subscribe((value,context,delivery)=>{events.push({value,delivery})});
        \\await session.commit(async tx=>{await tx.retireDoc(Doc)},{});const missing=await session.documentState(Doc,{});await session.commit(async tx=>{(await tx.doc(Doc)).n=5},{});const replacement=await session.documentState(Doc,{});await session.close({});let hydration;state.subscribe((value,context,delivery)=>{hydration={value,delivery}})();state.dispose();replacement.dispose();globalThis.result=JSON.stringify({events,missing:missing===undefined,value:state.value,replacement:replacement.value,hydration});
    , "native-durable-document-state-retirement");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"events\":[{\"value\":{\"n\":1},\"delivery\":{\"kind\":\"hydrate\",\"sequence\":0}},{\"value\":null,\"delivery\":{\"kind\":\"update\",\"sequence\":1}}],\"missing\":true,\"value\":null,\"replacement\":{\"n\":5},\"hydration\":{\"value\":null,\"delivery\":{\"kind\":\"hydrate\",\"sequence\":1}}}", text);
}

test "native durable VM documentState bounded pending deliveries preserve slow hydration and newest sequence" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document state overflow VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const session=createSession(new MemoryStorage()),Doc=defineDoc({kind:'fixture.state.overflow',version:1,scope:'session',initial:()=>({n:0})});await session.commit(async tx=>{await tx.doc(Doc)},{});const state=await session.documentState(Doc,{}),slow=[],fast=[];let release,complete;const gate=new Promise(r=>release=r),done=new Promise(r=>complete=r);
        \\const cancelSlow=state.subscribe(async(value,context,delivery)=>{slow.push({n:value.n,delivery});if(delivery.kind==='hydrate')await gate;if(value.n===102)complete()}),cancelFast=state.subscribe((value,context,delivery)=>{fast.push(delivery.sequence)});for(let n=1;n<=102;n++)await session.commit(async tx=>{(await tx.doc(Doc)).n=n},{});const before=state.value.n;release();await done;cancelSlow();cancelFast();state.dispose();await session.close({});globalThis.result=JSON.stringify({slow,fastCount:fast.length,first:fast[0],last:fast.at(-1),before});
    , "native-durable-document-state-overflow");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"slow\":[{\"n\":0,\"delivery\":{\"kind\":\"hydrate\",\"sequence\":0}},{\"n\":101,\"delivery\":{\"kind\":\"update\",\"sequence\":101}},{\"n\":102,\"delivery\":{\"kind\":\"update\",\"sequence\":102}}],\"fastCount\":103,\"first\":0,\"last\":102,\"before\":102}", text);
}

test "native durable VM ended invocation errors and cancellation reason preserve source task identity" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Invocation error VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\let retained,context;const Task=defineTask({name:'fixture.ended.error',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,ctx)=>{retained=runtime;context=ctx;await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:1}}),ctx)}},abort:async(task,runtime,ctx)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),ctx)});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return name===Task.definition.name?Task:{definition:{name}}},tasks(){return[Task]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const harness=await Harness.open(new MemoryStorage(),{registry,models:{}},{}),root=await harness.root({}),id=await root.commit(tx=>tx.createTask(Task,{},{ownership:{kind:'conversation'}}),{});await harness.waitForTask(id,{});await root.waitForIdle({});await new Promise(resolve=>{if(context.abortSignal.aborted)resolve();else context.abortSignal.addEventListener('abort',resolve,{once:true})});let error;try{await retained.getTask(id,{})}catch(value){error=value}const reason=context.abortSignal.reason;await harness.close({});globalThis.result=JSON.stringify({aborted:context.abortSignal.aborted,error:{name:error.name,error:error instanceof Error,message:error.message===`Task ${id} invocation has ended`},reason:{name:reason.name,error:reason instanceof Error,message:reason.message===`Task ${id} invocation has ended`},distinct:error!==reason});
    , "native-durable-invocation-ended-error");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"aborted\":true,\"error\":{\"name\":\"Error\",\"error\":true,\"message\":true},\"reason\":{\"name\":\"Error\",\"error\":true,\"message\":true},\"distinct\":true}", text);
}

test "native durable VM public SQLite allocation persists only at commit and ignores storage caller cancellation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const global = engine_module.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "testRoot", try sdk.text(engine, buffer[0..length]));
    errdefer std.debug.print("SQLite allocation VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {openNodeSqliteStorage} from '@earendil-works/pi-durable/storage/sqlite/node';
        \\const context={abortSignal:AbortSignal.abort('ignored')},path=testRoot+'/allocation.sqlite';let store=await openNodeSqliteStorage(path,{walAutoCheckpointPages:0,busyTimeoutMs:50});const reserved=await store.mintId();await store.close(context);store=await openNodeSqliteStorage(path);const reused=await store.mintId(),seq=await store.commit([{type:'conversation',value:{id:1}}],context),record=await store.conversation(1,context);await store.close(context);store=await openNodeSqliteStorage(path);const next=await store.mintId();await store.close(context);globalThis.result=JSON.stringify({reserved,reused,seq,record,next});
    , "native-durable-sqlite-allocation-policy");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"reserved\":2,\"reused\":2,\"seq\":1,\"record\":{\"id\":1},\"next\":3}", text);
}

test "native durable VM cold document reads follow original ignored storage Context cancellation policy" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Cold document Context VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const session=createSession(new MemoryStorage()),Doc=defineDoc({kind:'fixture.read.context',version:1,scope:'conversation',history:'rewindable',fork:'asOf',initial:()=>({n:1})});let anchor;await session.commit(async tx=>{const root=await tx.createRootConversation();await tx.doc(Doc,root.id);anchor=await tx.appendEntry(root.id,{kind:'anchor'})},{});
        \\const reason={raw:true},context={abortSignal:AbortSignal.abort(reason)};await session.unloadDocuments();let cold,historical,state;try{cold=await session.snapshot(Doc,1,context)}catch(error){cold={failed:error===reason}}try{historical=await session.snapshotAsOf(Doc,1,anchor.id,context)}catch(error){historical={failed:error===reason}}await session.unloadDocuments();try{const value=await session.documentState(Doc,1,context);state=value.value;value.dispose()}catch(error){state={failed:error===reason}}await session.close({});globalThis.result=JSON.stringify({cold,historical,state});
    , "native-durable-cold-context");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"cold\":{\"n\":1},\"historical\":{\"n\":1},\"state\":{\"n\":1}}", text);
}

test "native durable VM document object undefined deletes while array undefined and sparse growth are rejected" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document mutation VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const calls=[],Doc=defineDoc({kind:'fixture.undefined',version:1,scope:'session',initial:()=>({remove:1,arr:[1,2]}),checkpointWhen(value,ops){calls.push(ops);return false}}),session=createSession(new MemoryStorage());await session.commit(async tx=>{await tx.doc(Doc)},{});
        \\let objectDeleted=false,arrayRejected=false,sparseRejected=false,lengthRejected=false;await session.commit(async tx=>{const doc=await tx.doc(Doc);doc.remove=undefined;objectDeleted=!Object.hasOwn(doc,'remove');try{doc.arr[0]=undefined}catch{arrayRejected=true}try{doc.arr[4]=9}catch{sparseRejected=true}try{doc.arr.length=5}catch{lengthRejected=true}},{});const value=await session.snapshot(Doc,{});await session.close({});globalThis.result=JSON.stringify({objectDeleted,arrayRejected,sparseRejected,lengthRejected,value,calls});
    , "native-durable-document-undefined");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"objectDeleted\":true,\"arrayRejected\":true,\"sparseRejected\":true,\"lengthRejected\":false,\"value\":{\"arr\":[1,2,null,null,null]},\"calls\":[[[\"d\",[\"remove\"]],[\"p\",[\"arr\"],2,0,[null,null,null]]]]}", text);
}

test "native durable VM reserved document properties remain own data and fold unsafe delta paths" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Reserved document VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const calls=[],Doc=defineDoc({kind:'fixture.reserved',version:1,scope:'session',initial:()=>({normal:1}),checkpointWhen(value,ops){calls.push(ops);return false}}),session=createSession(new MemoryStorage());await session.commit(async tx=>{await tx.doc(Doc)},{});let own,prototype;
        \\await session.commit(async tx=>{const doc=await tx.doc(Doc);const prior=Object.getPrototypeOf(doc);doc.__proto__={safe:true};doc.constructor=null;own=Object.hasOwn(doc,'__proto__')&&Object.hasOwn(doc,'constructor');prototype=Object.getPrototypeOf(doc)===prior},{});const first=await session.snapshot(Doc,{});await session.commit(async tx=>{(await tx.doc(Doc)).constructor=undefined},{});const second=await session.snapshot(Doc,{});await session.close({});globalThis.result=JSON.stringify({own,prototype,first,second,calls});
    , "native-durable-document-reserved");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"own\":true,\"prototype\":true,\"first\":{\"normal\":1,\"__proto__\":{\"safe\":true},\"constructor\":null},\"second\":{\"normal\":1,\"__proto__\":{\"safe\":true}},\"calls\":[[[\"r\",{\"normal\":1,\"__proto__\":{\"safe\":true},\"constructor\":null}]],[[\"r\",{\"normal\":1,\"__proto__\":{\"safe\":true}}]]]}", text);
}

test "native durable VM document owner validation and failed initializers precede ID allocation" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Document owner VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,defineDoc} from '@earendil-works/pi-durable';
        \\const store=new MemoryStorage(),session=createSession(store),reason={initializer:true},calls=[];const Failing=defineDoc({kind:'fixture.init.fail',version:1,scope:'session',initial(){calls.push('fail');throw reason}}),Conversation=defineDoc({kind:'fixture.owner.conv',version:1,scope:'conversation',history:'latest',fork:'current',initial(){calls.push('conversation');return{n:1}}}),Task=defineDoc({kind:'fixture.owner.task',version:1,scope:'task',initial(){calls.push('task');return{n:1}}});
        \\await session.commit(tx=>tx.createRootConversation(),{});let failed=false,conversation,task;try{await session.commit(tx=>tx.doc(Failing),{})}catch(error){failed=error===reason}try{await session.commit(tx=>tx.doc(Conversation,99),{})}catch(error){conversation=error.message}try{await session.commit(tx=>tx.doc(Task,99),{})}catch(error){task=error.message}const next=await store.mintId();await session.close({});globalThis.result=JSON.stringify({failed,conversation,task,calls,next});
    , "native-durable-document-owner");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"failed\":true,\"conversation\":\"Conversation 99 does not exist\",\"task\":\"Task 99 does not exist\",\"calls\":[\"fail\"],\"next\":2}", text);
}

test "native durable VM checkpoint predicates run after final Runtime state validation" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Predicate ordering VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineDoc,defineTask} from '@earendil-works/pi-durable';
        \\let calls=0;const Doc=defineDoc({kind:'fixture.predicate.order',version:1,scope:'session',initial:()=>({n:1}),checkpointWhen(){calls++;return true}}),Task=defineTask({name:'fixture.predicate.task',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{let failed=false;try{await runtime.commit(async tx=>{(await tx.doc(Doc)).n=2;return{status:'waiting',checkpoint:{phase:'go'},on:[runtime.taskId],policy:'allSettled'}},context)}catch{failed=true}const value=await runtime.snapshot(Doc,context);await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:{failed,calls,value}}}),context)}},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)});
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return name===Task.definition.name?Task:{definition:{name}}},tasks(){return[Task]},installed(){return[]},sections(){return[]},tools(){return[]}}}};
        \\const harness=await Harness.open(new MemoryStorage(),{registry,models:{}},{}),root=await harness.root({});await harness.commit(async tx=>{await tx.doc(Doc)},{});const id=await root.commit(tx=>tx.createTask(Task,{},{ownership:{kind:'conversation'}}),{}),done=await harness.waitForTask(id,{});await harness.close({});globalThis.result=JSON.stringify(done.state.outcome);
    , "native-durable-predicate-order");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"status\":\"completed\",\"result\":{\"failed\":true,\"calls\":0,\"value\":{\"n\":1}}}", text);
}

test "native durable VM registry core publishes stable snapshots retains code identity and rejects collisions atomically" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    // Executable input task tokens supply the Registry core's injected builtin lane.
    // This fixture does not certify production builtin workflows.
    const builtins = try engine.eval("['pi.generation','pi.tool','pi.compaction'].map(name=>({definition:{name,version:1,initial(){return{phase:'go'}},phases:{go(){}},abort(){}}}))", "registry-builtin-token-input-fixture", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(builtins);
    const registry = try @import("extensions/native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const global = engine_module.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "registry", engine_module.c.JS_DupValue(engine.context, registry));
    errdefer std.debug.print("Registry core VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\const first=registry.snapshot(),events=[],listener=()=>events.push(registry.snapshot().installed().map(e=>e.name));registry.subscribe(listener);registry.subscribe(listener);
        \\const schema={type:'object',[Symbol.for('fixture.schema')]:true},tool={name:'echo',parameters:schema,execute:()=>7},section={key:'details',render:()=>''},task={definition:{name:'fixture.task',version:1,initial:()=>({phase:'go'}),phases:{go(){}},abort(){}}},extension={name:'fixture',tools:[tool],sections:[section],tasks:[task]};
        \\registry.install(extension);const second=registry.snapshot(),same=second===registry.snapshot(),identity=second.extension('fixture')===extension&&second.task('fixture.task')===task&&second.tools()[0].tool===tool&&second.tools()[0].tool.parameters===schema&&second.sections()[0].section===section;let collision;try{registry.install({name:'conflict',tasks:[task]})}catch(error){collision=error.message}const unchanged=registry.snapshot()===second;
        \\const replacement={name:'fixture',tools:[{name:'echo',parameters:schema,execute:()=>8}]};registry.install(replacement);registry.uninstall({name:'missing'});const third=registry.snapshot();registry.uninstall(extension);const builtinNames=registry.snapshot().tasks().map(task=>task.definition.name);globalThis.result=JSON.stringify({first:first.installed().length,same,identity,collision,unchanged,old:first!==second&&second.extension('fixture')===extension,replaced:third.extension('fixture')===replacement,events,builtinNames});
    , "native-durable-registry-core");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"first\":0,\"same\":true,\"identity\":true,\"collision\":\"Task fixture.task of extension conflict is already installed\",\"unchanged\":true,\"old\":true,\"replaced\":true,\"events\":[[\"fixture\"],[\"fixture\"],[]],\"builtinNames\":[\"pi.generation\",\"pi.tool\",\"pi.compaction\"]}", text);
}

test "native durable VM public registry helpers retain unrestricted callbacks schemas and hook references" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const output = try engine.evalModule(
        \\import {defineTask,defineExtension,defineTool,section,hook,wrapTool,wrapSection} from '@earendil-works/pi-durable';
        \\const callback=()=>17,schema={type:'object',[Symbol.for('fixture.schema')]:true},tool={name:'tool',parameters:schema,execute:callback},extension={name:'extension',tools:[tool]},task=defineTask({name:'task',version:1,initial:()=>({phase:'go'}),phases:{go:callback},abort:callback}),handlers={before:callback},one=section('details',callback),two=section('plain',callback,{tag:false}),registered=hook(task,handlers),wrappedTool=wrapTool(tool,callback),wrappedSection=wrapSection('details',callback);
        \\globalThis.result=JSON.stringify({tool:defineTool(tool)===tool,extension:defineExtension(extension)===extension,schema:defineTool(tool).parameters===schema,section:one.render===callback&&!Object.hasOwn(one,'tag'),tag:two.tag,hook:registered.task==='task'&&registered.handlers===handlers,wrapTool:wrappedTool.tool==='tool'&&wrappedTool.wrap===callback,wrapSection:wrappedSection.section==='details'&&wrappedSection.wrap===callback});
    , "native-durable-registry-helpers");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"tool\":true,\"extension\":true,\"schema\":true,\"section\":true,\"tag\":false,\"hook\":true,\"wrapTool\":true,\"wrapSection\":true}", text);
}

test "native durable VM public AgentDoc configure normalizes extension names clears nulls and retains fork history" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Agent configure VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {createSession,MemoryStorage,AgentDoc,configure,defineExtension,defineTool} from '@earendil-works/pi-durable';
        \\const session=createSession(new MemoryStorage()),extension=defineExtension({name:'fixture',hooks:[{handlers:{cycle:null}}]}),tool=defineTool({name:'echo',execute:()=>1});extension.hooks[0].handlers.cycle=extension;let root,anchor;
        \\await session.commit(async tx=>{root=await tx.createRootConversation();await configure(tx,root.id,{model:{provider:'fixture',modelId:'model'},thinkingLevel:'low',extensions:[extension],tools:[tool],instructions:'first',cwd:'/Ω'});anchor=await tx.appendEntry(root.id,{kind:'anchor'})},{});
        \\const first=await session.snapshot(AgentDoc,root.id,{});await session.commit(async tx=>{await configure(tx,root.id,{model:null,thinkingLevel:undefined,extensions:{add:[extension],remove:[]},tools:{remove:[tool]},instructions:null})},{});const second=await session.snapshot(AgentDoc,root.id,{}),historical=await session.snapshotAsOf(AgentDoc,root.id,anchor.id,{});await session.close({});globalThis.result=JSON.stringify({first,second,historical});
    , "native-durable-agent-configure");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"first\":{\"model\":{\"provider\":\"fixture\",\"modelId\":\"model\"},\"thinkingLevel\":\"low\",\"extensions\":[\"fixture\"],\"tools\":[\"echo\"],\"instructions\":\"first\",\"cwd\":\"/Ω\"},\"second\":{\"thinkingLevel\":\"low\",\"extensions\":{\"add\":[\"fixture\"],\"remove\":[]},\"tools\":{\"remove\":[\"echo\"]},\"cwd\":\"/Ω\"},\"historical\":{\"model\":{\"provider\":\"fixture\",\"modelId\":\"model\"},\"thinkingLevel\":\"low\",\"extensions\":[\"fixture\"],\"tools\":[\"echo\"],\"instructions\":\"first\",\"cwd\":\"/Ω\"}}", text);
}

test "native durable VM Runtime settings merge defaults preserve explicit undefined and remain passive after end" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Runtime settings VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask,DEFAULT_RETRY_POLICY,DEFAULT_COMPACTION_POLICY,DEFAULT_PROGRESS_POLICY} from '@earendil-works/pi-durable';
        \\let retained;const Task=defineTask({name:'fixture.settings',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{retained=runtime;await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:runtime.settings}}),context)}},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)}),extension={name:'fixture'},settings={extensions:[extension],stream:{temperature:0},retry:{maxRetries:undefined},compaction:{reserveTokens:99},progress:{partialIntervalMs:undefined,outputIntervalMs:0},toolExecution:'sequential',contextRetentionMs:0};
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return name===Task.definition.name?Task:{definition:{name}}},tasks(){return[Task]},installed(){return[]},sections(){return[]},tools(){return[]}}}},harness=await Harness.open(new MemoryStorage(),{registry,models:{},settings},{}),root=await harness.root({}),id=await root.commit(tx=>tx.createTask(Task,{},{ownership:{kind:'conversation'}}),{}),done=await harness.waitForTask(id,{});await root.waitForIdle({});const first=retained.settings,second=retained.settings;const output={result:done.state.outcome.result,settings:first,fresh:first!==second,extension:first.extensions[0]===extension,undefined:Object.hasOwn(first.retry,'maxRetries')&&first.retry.maxRetries===undefined,defaults:{retry:DEFAULT_RETRY_POLICY,compaction:DEFAULT_COMPACTION_POLICY,progress:DEFAULT_PROGRESS_POLICY}};await harness.close({});globalThis.result=JSON.stringify(output);
    , "native-durable-runtime-settings");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"result\":{\"extensions\":[{\"name\":\"fixture\"}],\"stream\":{\"temperature\":0},\"retry\":{\"enabled\":true,\"baseDelayMs\":2000,\"maxAgentDelayMs\":60000},\"compaction\":{\"enabled\":true,\"reserveTokens\":99,\"keepRecentTokens\":20000,\"backgroundTokens\":32768},\"progress\":{\"partialIntervalMs\":100,\"outputIntervalMs\":0},\"toolExecution\":\"sequential\",\"steeringMode\":\"one-at-a-time\",\"followUpMode\":\"one-at-a-time\",\"contextRetentionMs\":0},\"settings\":{\"extensions\":[{\"name\":\"fixture\"}],\"stream\":{\"temperature\":0},\"retry\":{\"enabled\":true,\"baseDelayMs\":2000,\"maxAgentDelayMs\":60000},\"compaction\":{\"enabled\":true,\"reserveTokens\":99,\"keepRecentTokens\":20000,\"backgroundTokens\":32768},\"progress\":{\"partialIntervalMs\":100,\"outputIntervalMs\":0},\"toolExecution\":\"sequential\",\"steeringMode\":\"one-at-a-time\",\"followUpMode\":\"one-at-a-time\",\"contextRetentionMs\":0},\"fresh\":true,\"extension\":true,\"undefined\":true,\"defaults\":{\"retry\":{\"enabled\":true,\"maxRetries\":3,\"baseDelayMs\":2000,\"maxAgentDelayMs\":60000},\"compaction\":{\"enabled\":true,\"reserveTokens\":16384,\"keepRecentTokens\":20000,\"backgroundTokens\":32768},\"progress\":{\"partialIntervalMs\":100,\"outputIntervalMs\":100}}}", text);
}

test "native durable VM public agent selections wrappers cached phase resolution and mutable policy defaults match source" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer {
        const step = engine.eval("globalThis.stage", "stage", engine_module.c.JS_EVAL_TYPE_GLOBAL) catch unreachable;
        defer engine.freeValue(step);
        const value = engine.toString(step) catch unreachable;
        defer std.testing.allocator.free(value);
        std.debug.print("Agent resolution VM failure at {s}: {s}\n", .{ value, engine.last_error orelse "no VM diagnostic" });
    }
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask,DEFAULT_PROGRESS_POLICY,DEFAULT_RETRY_POLICY,configure} from '@earendil-works/pi-durable';
        \\const events=[],reports=[],schema={type:'object'},one={name:'echo',parameters:schema,execute:()=>1},two={name:'echo',parameters:schema,execute:()=>2},gone={name:'gone',parameters:schema,execute:()=>3};
        \\const a={name:'a',tools:[one,gone],sections:[{key:'base',render:()=> 'a'}]},b={name:'b',tools:[two],sections:[{key:'base',render:()=> 'b'}]},w={name:'w',wraps:[{tool:'echo',wrap(tool){events.push(['wrap',this===w.wraps[0],tool===two]);return {...tool,execute:()=>tool.execute()+10}}},{tool:'gone',wrap(){throw new Error('drop gone')}},{section:'base',wrap(section){return {...section,key:'renamed'}}},{tool:'absent',wrap(){throw new Error('unused')}}]};
        \\let retained;
        \\const Task=defineTask({name:'fixture.agent',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{retained=runtime;const first=await runtime.agent(context);await runtime.commit(async tx=>{await configure(tx,runtime.conversationId,{instructions:'later'})},context);const second=await runtime.agent(context);await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:{same:first===second,instructions:second.instructions,tool:second.tools[0].execute()}}}),context)}},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)});
        \\const extensions=[a,b,w],builtins=['pi.generation','pi.tool','pi.compaction'].map(name=>({definition:{name}})),tasks=[...builtins,Task];let current={installed:()=>extensions,extension:name=>extensions.find(e=>e.name===name),tools:()=>[],sections:()=>[],tasks:()=>[Task],task:name=>tasks.find(t=>t.definition.name===name)};const registry={subscribe(){return()=>{}},snapshot(){return current}};
        \\const harness=await Harness.open(new MemoryStorage(),{registry,models:{},onReport:error=>reports.push(error.message)},{}),root=await harness.root({});
        \\globalThis.stage="configure";await root.configure({extensions:[b,a,b,w],tools:[gone,one,one],instructions:'hello',model:{provider:'p',modelId:'m'},cwd:'/Ω'},{});
        \\globalThis.stage="initial";const initial=await root.agent({});
        \\await root.configure({extensions:{add:[b,w],remove:[a]},tools:null,instructions:'phase'},{});
        \\globalThis.stage="selected";const selected=await root.agent({}),id=await root.commit(tx=>tx.createTask(Task,{},{ownership:{kind:'conversation'}}),{}),done=await harness.waitForTask(id,{});await root.waitForIdle({});
        \\const later=await root.agent({});DEFAULT_PROGRESS_POLICY.partialIntervalMs=17;DEFAULT_PROGRESS_POLICY.extra=99;DEFAULT_RETRY_POLICY.maxRetries=8;const dynamic=retained.settings;await new Promise(resolve=>{if(retained.signal.aborted)resolve();else retained.signal.addEventListener('abort',resolve,{once:true})});let ended;try{await retained.agent({})}catch(error){ended={name:error.name,message:error.message===`Task ${id} invocation has ended`}}await harness.close({});
        \\globalThis.result=JSON.stringify({initial:{extensions:initial.extensions.map(e=>e.name),tools:initial.tools.map(t=>t.name),tool:initial.tools[0].execute(),sections:initial.sections.map(s=>s.key),render:initial.sections.at(-1).render(),thinking:initial.thinkingLevel,model:initial.model,cwd:initial.cwd},selected:{extensions:selected.extensions.map(e=>e.name),tools:selected.tools.map(t=>t.name)},done:done.state.outcome.result,later:later.instructions,events,reports,dynamic:{progress:dynamic.progress,retry:dynamic.retry.maxRetries},ended});
        \\
        \\
    , "native-durable-agent-resolution-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"initial\":{\"extensions\":[\"b\",\"a\",\"w\"],\"tools\":[\"echo\"],\"tool\":11,\"sections\":[\"instructions\"],\"render\":\"hello\",\"thinking\":\"off\",\"model\":{\"provider\":\"p\",\"modelId\":\"m\"},\"cwd\":\"/Ω\"},\"selected\":{\"extensions\":[\"b\",\"w\"],\"tools\":[\"echo\"]},\"done\":{\"same\":true,\"instructions\":\"phase\",\"tool\":12},\"later\":\"later\",\"events\":[[\"wrap\",true,false],[\"wrap\",true,true],[\"wrap\",true,true],[\"wrap\",true,true]],\"reports\":[\"drop gone\",\"Wrapper renamed base to renamed\",\"Wrapper renamed base to renamed\",\"Wrapper renamed base to renamed\",\"Wrapper renamed base to renamed\"],\"dynamic\":{\"progress\":{\"partialIntervalMs\":17,\"outputIntervalMs\":100},\"retry\":8},\"ended\":{\"name\":\"Error\",\"message\":true}}", text);
}

test "native durable VM runtime hooks await selected handlers bind receivers report errors and env reads committed cwd" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Runtime hooks env VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask,configure} from '@earendil-works/pi-durable';
        \\const order=[],reports=[],trace={},envs=[];let retained,harness;
        \\const one={label:'one',async before(value){await Promise.resolve();order.push([this===one,value]);return 7}},two={before(){throw trace}},three={before:'ignored',after(){order.push('after')}};
        \\const Task=defineTask({name:'fixture.hooks',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{retained=runtime;await runtime.hooks.each('before',handler=>handler('call'));await runtime.hooks.each('after',handler=>handler());const first=await runtime.env(context);await runtime.commit(async tx=>{await configure(tx,runtime.conversationId,{cwd:'/next'})},context);const second=await runtime.env(context);await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:{first:first.cwd,second:second.cwd,same:first===second}}}),context)}},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)});
        \\const extension={name:'hooks',hooks:[{task:'fixture.other',handlers:two},{task:Task.definition.name,handlers:one},{task:Task.definition.name,handlers:two},{task:Task.definition.name,handlers:three}]},builtins=['pi.generation','pi.tool','pi.compaction'].map(name=>({definition:{name}})),registry={subscribe(){return()=>{}},snapshot(){return{installed:()=>[extension],extension:name=>name===extension.name?extension:undefined,tasks:()=>[Task],task:name=>name===Task.definition.name?Task:builtins.find(t=>t.definition.name===name)}}};
        \\harness=await Harness.open(new MemoryStorage(),{registry,models:{},onReport:error=>reports.push(error===trace),env:async(request,context)=>{envs.push({id:request.conversationId,cwd:request.cwd,read:request.read===harness,signal:context.abortSignal instanceof AbortSignal});await Promise.resolve();return{cwd:request.cwd}}},{});
        \\const root=await harness.root({}, {agent:{cwd:'/first'}}),id=await root.commit(tx=>tx.createTask(Task,{},{ownership:{kind:'conversation'}}),{}),done=await harness.waitForTask(id,{});await root.waitForIdle({});await new Promise(resolve=>{if(retained.signal.aborted)resolve();else retained.signal.addEventListener('abort',resolve,{once:true})});let ended;try{await retained.hooks.each('before',handler=>handler('late'))}catch(error){ended=error.message===`Task ${id} invocation has ended`}await harness.close({});globalThis.result=JSON.stringify({order,reports,envs,done:done.state.outcome.result,ended});
        \\
        \\
    , "native-durable-runtime-hooks-env-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"order\":[[true,\"call\"],\"after\"],\"reports\":[true],\"envs\":[{\"id\":1,\"cwd\":\"/first\",\"read\":true,\"signal\":true},{\"id\":1,\"cwd\":\"/next\",\"read\":true,\"signal\":true}],\"done\":{\"first\":\"/first\",\"second\":\"/next\",\"same\":false},\"ended\":true}", text);
}

test "native durable VM committed context derives cutoff edits resets fork visibility tool order and runtime immutability" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Context view VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\const summarize=view=>({keys:Object.keys(view),kinds:view.entries.map(e=>e.kind),head:view.head?.kind,contributions:view.contributions.map(m=>m.map(x=>x.role)),messages:view.messages.map(m=>({role:m.role,content:m.content,toolCallId:m.toolCallId,details:m.details})),frozen:view.entries.every(Object.isFrozen)&&view.contributions.every(c=>Object.isFrozen(c)&&c.every(Object.isFrozen)),outer:!Object.isFrozen(view.entries)&&!Object.isFrozen(view.messages),alias:view.contributions.flat().every(m=>view.messages.includes(m)||m.role==='toolResult')});
        \\const Task=defineTask({name:'fixture.context',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{const view=await runtime.context(runtime.conversationId,context),same=await runtime.context(runtime.conversationId,context);await runtime.commit(async tx=>{await tx.appendEntry(runtime.conversationId,{kind:'added',model:[{role:'user',content:'added',timestamp:10}]})},context);const extended=await runtime.context(runtime.conversationId,context);await runtime.commit(async tx=>{await tx.appendEntry(runtime.conversationId,{kind:'omit',edits:[{target:view.entries[0].id,action:'omit'}]})},context);const edited=await runtime.context(runtime.conversationId,context),backward=await runtime.context(runtime.conversationId,context,{at:view.entries.at(-1).id});await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:{view:summarize(view),sameEntry:view.entries[0]===same.entries[0],sameMessage:view.messages[0]===same.messages[0],sameContribution:view.contributions[0]===same.contributions[0],extendedEntry:view.entries[0]===extended.entries[0],extendedContribution:view.contributions[0]===extended.contributions[0],editedContribution:edited.contributions[0]!==extended.contributions[0],edited:summarize(edited),backward:summarize(backward)}}}),context)}},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)}),builtins=['pi.generation','pi.tool','pi.compaction'].map(name=>({definition:{name}})),registry={subscribe(){return()=>{}},snapshot(){return{installed:()=>[],extension(){},tasks:()=>[Task],task:name=>name===Task.definition.name?Task:builtins.find(t=>t.definition.name===name)}}};
        \\const harness=await Harness.open(new MemoryStorage(),{registry,models:{}},{}),root=await harness.root({}),empty=summarize(await root.context({}));let user,assistant,tail;
        \\await root.commit(async tx=>{user=await tx.appendEntry(root.id,{kind:'pi.user',model:[{role:'user',content:'first',timestamp:1}]});assistant=await tx.appendEntry(root.id,{kind:'pi.assistant',model:[{role:'assistant',content:[{type:'toolCall',id:'a',name:'echo',arguments:{}},{type:'toolCall',id:'b',name:'echo',arguments:{}}],stopReason:'toolUse',timestamp:2}]});await tx.appendEntry(root.id,{kind:'pi.tool-result',model:[{role:'toolResult',toolCallId:'b',toolName:'echo',content:[{type:'text',text:'B'}],isError:false,timestamp:3}]});await tx.appendEntry(root.id,{kind:'pi.tool-result',model:[{role:'toolResult',toolCallId:'a',toolName:'echo',content:[{type:'text',text:'A'}],isError:false,timestamp:4}]});await tx.appendEntry(root.id,{kind:'orphan',model:[{role:'toolResult',toolCallId:'x',toolName:'echo',content:[],isError:false,timestamp:5}]});await tx.appendEntry(root.id,{kind:'error',model:[{role:'assistant',content:[],stopReason:'error',timestamp:6}]});tail=await tx.appendEntry(root.id,{kind:'edit',edits:[{target:user.id,action:'replace',messages:[{role:'user',content:'edited',timestamp:7}]}]})},{});
        \\const cutoff=summarize(await root.context({}, {at:assistant.id})),full=summarize(await root.context({}));const fork=await root.fork(assistant.id,{ownership:{kind:'ownerless'}},{}),forked=summarize(await fork.context({}));
        \\await root.commit(async tx=>{await tx.appendEntry(root.id,{kind:'reset',head:'self',model:[{role:'user',content:'new',timestamp:8}]});await tx.appendEntry(root.id,{kind:'system',model:[{role:'system',content:'instructions',timestamp:9}]})},{});const reset=summarize(await root.context({})),id=await root.commit(tx=>tx.createTask(Task,{},{ownership:{kind:'conversation'}}),{}),done=await harness.waitForTask(id,{});await root.waitForIdle({});let invalid;try{await root.context({}, {at:99999})}catch(error){invalid=error.message===`Entry 99999 is not visible from conversation ${root.id}`}await harness.close({});globalThis.result=JSON.stringify({empty,cutoff,full,forked,reset,runtime:done.state.outcome.result,invalid});
        \\
        \\
    , "native-durable-context-view-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"empty\":{\"keys\":[\"head\",\"entries\",\"contributions\",\"messages\"],\"kinds\":[],\"contributions\":[],\"messages\":[],\"frozen\":true,\"outer\":true,\"alias\":true},\"cutoff\":{\"keys\":[\"head\",\"entries\",\"contributions\",\"messages\"],\"kinds\":[\"pi.user\",\"pi.assistant\"],\"contributions\":[[\"user\"],[\"assistant\"]],\"messages\":[{\"role\":\"user\",\"content\":\"first\"},{\"role\":\"assistant\",\"content\":[{\"type\":\"toolCall\",\"id\":\"a\",\"name\":\"echo\",\"arguments\":{}},{\"type\":\"toolCall\",\"id\":\"b\",\"name\":\"echo\",\"arguments\":{}}]},{\"role\":\"toolResult\",\"content\":[{\"type\":\"text\",\"text\":\"Tool result unavailable: history ends before this call completed.\"}],\"toolCallId\":\"a\",\"details\":{\"reason\":\"missing_result\"}},{\"role\":\"toolResult\",\"content\":[{\"type\":\"text\",\"text\":\"Tool result unavailable: history ends before this call completed.\"}],\"toolCallId\":\"b\",\"details\":{\"reason\":\"missing_result\"}}],\"frozen\":false,\"outer\":true,\"alias\":true},\"full\":{\"keys\":[\"head\",\"entries\",\"contributions\",\"messages\"],\"kinds\":[\"pi.user\",\"pi.assistant\",\"pi.tool-result\",\"pi.tool-result\",\"orphan\",\"error\",\"edit\"],\"contributions\":[[\"user\"],[\"assistant\"],[\"toolResult\"],[\"toolResult\"],[\"toolResult\"],[],[]],\"messages\":[{\"role\":\"user\",\"content\":\"edited\"},{\"role\":\"assistant\",\"content\":[{\"type\":\"toolCall\",\"id\":\"a\",\"name\":\"echo\",\"arguments\":{}},{\"type\":\"toolCall\",\"id\":\"b\",\"name\":\"echo\",\"arguments\":{}}]},{\"role\":\"toolResult\",\"content\":[{\"type\":\"text\",\"text\":\"A\"}],\"toolCallId\":\"a\"},{\"role\":\"toolResult\",\"content\":[{\"type\":\"text\",\"text\":\"B\"}],\"toolCallId\":\"b\"}],\"frozen\":false,\"outer\":true,\"alias\":true},\"forked\":{\"keys\":[\"head\",\"entries\",\"contributions\",\"messages\"],\"kinds\":[\"pi.user\",\"pi.assistant\"],\"contributions\":[[\"user\"],[\"assistant\"]],\"messages\":[{\"role\":\"user\",\"content\":\"first\"},{\"role\":\"assistant\",\"content\":[{\"type\":\"toolCall\",\"id\":\"a\",\"name\":\"echo\",\"arguments\":{}},{\"type\":\"toolCall\",\"id\":\"b\",\"name\":\"echo\",\"arguments\":{}}]},{\"role\":\"toolResult\",\"content\":[{\"type\":\"text\",\"text\":\"Tool result unavailable: history ends before this call completed.\"}],\"toolCallId\":\"a\",\"details\":{\"reason\":\"missing_result\"}},{\"role\":\"toolResult\",\"content\":[{\"type\":\"text\",\"text\":\"Tool result unavailable: history ends before this call completed.\"}],\"toolCallId\":\"b\",\"details\":{\"reason\":\"missing_result\"}}],\"frozen\":false,\"outer\":true,\"alias\":true},\"reset\":{\"keys\":[\"head\",\"entries\",\"contributions\",\"messages\"],\"kinds\":[\"reset\",\"system\"],\"head\":\"reset\",\"contributions\":[[\"user\"],[\"system\"]],\"messages\":[{\"role\":\"system\",\"content\":\"instructions\"},{\"role\":\"user\",\"content\":\"new\"}],\"frozen\":false,\"outer\":true,\"alias\":true},\"runtime\":{\"view\":{\"keys\":[\"head\",\"entries\",\"contributions\",\"messages\"],\"kinds\":[\"reset\",\"system\"],\"head\":\"reset\",\"contributions\":[[\"user\"],[\"system\"]],\"messages\":[{\"role\":\"system\",\"content\":\"instructions\"},{\"role\":\"user\",\"content\":\"new\"}],\"frozen\":true,\"outer\":true,\"alias\":true},\"sameEntry\":true,\"sameMessage\":true,\"sameContribution\":true,\"extendedEntry\":true,\"extendedContribution\":true,\"editedContribution\":true,\"edited\":{\"keys\":[\"head\",\"entries\",\"contributions\",\"messages\"],\"kinds\":[\"reset\",\"system\",\"added\",\"omit\"],\"head\":\"reset\",\"contributions\":[[],[\"system\"],[\"user\"],[]],\"messages\":[{\"role\":\"system\",\"content\":\"instructions\"},{\"role\":\"user\",\"content\":\"added\"}],\"frozen\":true,\"outer\":true,\"alias\":true},\"backward\":{\"keys\":[\"head\",\"entries\",\"contributions\",\"messages\"],\"kinds\":[\"reset\",\"system\"],\"head\":\"reset\",\"contributions\":[[\"user\"],[\"system\"]],\"messages\":[{\"role\":\"system\",\"content\":\"instructions\"},{\"role\":\"user\",\"content\":\"new\"}],\"frozen\":true,\"outer\":true,\"alias\":true}},\"invalid\":true}", text);
}

test "native durable VM live parent admits and joins newly created child sleep cancellation and typed entry guards match source" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 15000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Live child sleep VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask,defineEntry,UserEntry,AssistantEntry,SystemEntry,ToolResultEntry,ResetEntry,CompactionEntry} from '@earendil-works/pi-durable';
        \\const order=[];let now=0,retained;
        \\const abort=async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context),Child=defineTask({name:'fixture.live-child',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{order.push('child');await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:9}}),context)}},abort});
        \\const Parent=defineTask({name:'fixture.live-parent',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{retained=runtime;order.push('parent');const typed=await runtime.entry(UserEntry,task.input.entryId,context),wrong=await runtime.entry(ResetEntry,task.input.entryId,context);await runtime.sleep(-1,context);const pending=runtime.sleep(1,context);now=2;await pending;const controller=new AbortController(),reason={raw:'reason'},canceled=runtime.sleep(10000,{abortSignal:controller.signal});controller.abort(reason);let identity;try{await canceled}catch(error){identity=error===reason}let child;await runtime.commit(async tx=>{child=await tx.createTask(Child,{},{ownership:{kind:'task',taskId:runtime.taskId}})},context);const waitController=new AbortController(),waitReason={wait:'raw'},interrupted=runtime.waitForTask(child,{abortSignal:waitController.signal});waitController.abort(waitReason);let waitIdentity;try{await interrupted}catch(error){waitIdentity=error===waitReason}const done=await runtime.waitForTask(child,context);order.push('joined');await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:{child:done.state.outcome.result,identity,waitIdentity,typed:typed.data.n,wrong:wrong===undefined}}}),context)}},abort});
        \\const Recursive=defineTask({name:'fixture.recursive',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{let value=0;if(task.input.depth>0){let child;await runtime.commit(async tx=>{child=await tx.createTask(Recursive,{depth:task.input.depth-1},{ownership:{kind:'task',taskId:runtime.taskId}})},context);value=(await runtime.waitForTask(child,context)).state.outcome.result+1}await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:value}}),context)}},abort});
        \\const tasks=[Parent,Child,Recursive],builtins=['pi.generation','pi.tool','pi.compaction'].map(name=>({definition:{name}})),registry={subscribe(){return()=>{}},snapshot(){return{installed:()=>[],extension(){},tasks:()=>tasks,task:name=>[...tasks,...builtins].find(t=>t.definition.name===name)}}},harness=await Harness.open(new MemoryStorage(),{registry,models:{},now:()=>now},{}),root=await harness.root({}),typed=await root.commit(async tx=>{const a=await tx.appendEntry(UserEntry,root.id,{kind:'overridden',data:{n:1}}),b=await tx.appendEntry(ResetEntry,root.id,{head:'self'});return{a,b}},{}),id=await root.commit(tx=>tx.createTask(Parent,{entryId:typed.a.id},{ownership:{kind:'conversation'}}),{}),done=await harness.waitForTask(id,{});await root.waitForIdle({});await new Promise(resolve=>{if(retained.signal.aborted)resolve();else retained.signal.addEventListener('abort',resolve,{once:true})});let ended;try{await retained.sleep(0,{})}catch(error){ended=error.message===`Task ${id} invocation has ended`}
        \\const recursive=await root.commit(tx=>tx.createTask(Recursive,{depth:8},{ownership:{kind:'conversation'}}),{}),chain=(await harness.waitForTask(recursive,{})).state.outcome.result;await root.waitForIdle({});let missing;try{await harness.waitForTask(99999,{})}catch(error){missing={name:error.name,message:error.message}}const token=defineEntry('fixture.entry'),entry={kind:'fixture.entry'},guards=[token.is(),token.is(entry),token.is({kind:'other'}),token.is(7)],invalid=[];for(const value of [undefined,null,'',17])try{defineEntry(value)}catch(error){invalid.push({name:error.name,message:error.message})}let nullable;try{token.is(null)}catch(error){nullable=error instanceof TypeError}const builtinsKinds=[UserEntry,AssistantEntry,SystemEntry,ToolResultEntry,ResetEntry,CompactionEntry].map(token=>token.kind);await harness.close({});globalThis.result=JSON.stringify({order,result:done.state.outcome.result,ended,chain,missing,typed:{kind:typed.a.kind,reset:typed.b.kind,head:typed.b.head===typed.b.id},guards,invalid,nullable,builtinsKinds});
        \\
        \\
    , "native-durable-live-child-sleep-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"order\":[\"parent\",\"child\",\"joined\"],\"result\":{\"child\":9,\"identity\":true,\"waitIdentity\":true,\"typed\":1,\"wrong\":true},\"ended\":true,\"chain\":8,\"missing\":{\"name\":\"Error\",\"message\":\"Task 99999 does not exist\"},\"typed\":{\"kind\":\"pi.user\",\"reset\":\"pi.reset\",\"head\":true},\"guards\":[false,true,false,false],\"invalid\":[{\"name\":\"TypeError\",\"message\":\"Entry kind must be a non-empty string\"},{\"name\":\"TypeError\",\"message\":\"Entry kind must be a non-empty string\"},{\"name\":\"TypeError\",\"message\":\"Entry kind must be a non-empty string\"},{\"name\":\"TypeError\",\"message\":\"Entry kind must be a non-empty string\"}],\"nullable\":true,\"builtinsKinds\":[\"pi.user\",\"pi.assistant\",\"pi.system\",\"pi.tool-result\",\"pi.reset\",\"pi.compaction\"]}", text);
}

test "native durable VM executable builtin document predicates and initial forks retain agent and refresh provider identity" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Builtin documents VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,LiveDoc,InboxDoc,UsageDoc,ProviderDoc,AgentDoc,UserEntry} from '@earendil-works/pi-durable';
        \\const tokens=[LiveDoc,InboxDoc,UsageDoc,ProviderDoc],definitions=tokens.map(token=>({kind:token.definition.kind,version:token.definition.version,scope:token.definition.scope,history:token.definition.history,fork:token.definition.fork})),predicates={live:[{}, {generation:{}}, {tools:[{status:'running'}]}, {tools:[{status:'done'}]}, {tools:null}].map(value=>LiveDoc.definition.checkpointWhen(value)),inbox:[[],[{}]].map(items=>InboxDoc.definition.checkpointWhen({items})),usage:UsageDoc.definition.checkpointWhen({}),provider:ProviderDoc.definition.checkpointWhen({})};
        \\const registry={subscribe(){return()=>{}},snapshot(){return{task(name){return{definition:{name}}},tasks:()=>[]}}},harness=await Harness.open(new MemoryStorage(),{registry,models:{}},{}),root=await harness.root({});let anchor;
        \\await root.commit(async tx=>{(await tx.doc(LiveDoc,root.id)).tools=[{callId:'a',name:'echo',status:'running',output:'partial'}];(await tx.doc(InboxDoc,root.id)).items=[{id:99,mode:'steer',content:{content:'queued'}}];(await tx.doc(UsageDoc,root.id)).models={'p/m':{input:1}};(await tx.doc(AgentDoc,root.id)).cwd='/parent';anchor=await tx.appendEntry(UserEntry,root.id,{model:[{role:'user',content:'fork',timestamp:1}]})},{});
        \\const parent=await Promise.all(tokens.map(token=>harness.snapshot(token,root.id,{}))),fork=await root.fork(anchor.id,{ownership:{kind:'ownerless'}},{}),children=await Promise.all(tokens.map(token=>harness.snapshot(token,fork.id,{}))),agent=await harness.snapshot(AgentDoc,fork.id,{}),uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;await harness.close({});globalThis.result=JSON.stringify({definitions,predicates,parent:parent.slice(0,3),children:children.slice(0,3),provider:{parent:uuid.test(parent[3].sessionId),child:uuid.test(children[3].sessionId),fresh:parent[3].sessionId!==children[3].sessionId},agent});
        \\
        \\
    , "native-durable-builtin-documents-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"definitions\":[{\"kind\":\"pi.live\",\"version\":1,\"scope\":\"conversation\",\"history\":\"latest\",\"fork\":\"initial\"},{\"kind\":\"pi.inbox\",\"version\":1,\"scope\":\"conversation\",\"history\":\"latest\",\"fork\":\"initial\"},{\"kind\":\"pi.usage\",\"version\":1,\"scope\":\"conversation\",\"history\":\"latest\",\"fork\":\"initial\"},{\"kind\":\"pi.provider\",\"version\":1,\"scope\":\"conversation\",\"history\":\"latest\",\"fork\":\"initial\"}],\"predicates\":{\"live\":[true,false,false,true,true],\"inbox\":[true,false],\"usage\":true,\"provider\":true},\"parent\":[{\"tools\":[{\"callId\":\"a\",\"name\":\"echo\",\"status\":\"running\",\"output\":\"partial\"}]},{\"items\":[{\"id\":99,\"mode\":\"steer\",\"content\":{\"content\":\"queued\"}}]},{\"models\":{\"p/m\":{\"input\":1}},\"tools\":{}}],\"children\":[{},{\"items\":[]},{\"models\":{},\"tools\":{}}],\"provider\":{\"parent\":true,\"child\":true,\"fresh\":true},\"agent\":{\"cwd\":\"/parent\"}}", text);
}
comptime {
    _ = @import("extensions/native_structured_clone.zig");
}
comptime {
    _ = @import("extensions/native_tool_validation.zig");
}
comptime {
    _ = @import("extensions/native_schema_formats.zig");
}
comptime {
    _ = @import("extensions/native_tool_info.zig");
    _ = @import("extensions/native_tool_catalog.zig");
}

test "native durable VM null reporter coalesces callbacks and missing report memo and task args reject without native traps" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    errdefer std.debug.print("Null reporter args VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import {Harness,MemoryStorage,defineTask} from '@earendil-works/pi-durable';
        \\const reason={owned:true},Task=defineTask({name:'fixture.arguments',version:1,initial:()=>({phase:'go'}),phases:{go:async(task,runtime,context)=>{runtime.report();let memo,create;try{await runtime.memo()}catch(error){memo=error.name}await runtime.commit(async tx=>{try{await tx.createTask()}catch(error){create=error.name}},context);await runtime.hooks.each('before',handler=>handler());const agent=await runtime.agent(context);await runtime.commit(()=>({status:'terminal',outcome:{status:'completed',result:{memo,create,tools:agent.tools.length}}}),context)}},abort:async(task,runtime,context)=>runtime.commit(()=>({status:'terminal',outcome:{status:'aborted'}}),context)}),extension={name:'fixture',tools:[{name:'echo',parameters:{type:'object'},execute(){}}],wraps:[{tool:'echo',wrap(){throw reason}}],hooks:[{task:Task.definition.name,handlers:{before(){throw reason}}}]},registry={subscribe(){return()=>{}},snapshot(){return{installed:()=>[extension],extension:()=>extension,tasks:()=>[Task],task(name){return name===Task.definition.name?Task:{definition:{name}}}}}},harness=await Harness.open(new MemoryStorage(),{registry,models:{},onReport:null},{}),root=await harness.root({}),id=await root.commit(tx=>tx.createTask(Task,{},{ownership:{kind:'conversation'}}),{}),done=await harness.waitForTask(id,{});await root.waitForIdle({});await harness.close({});const reports=[],other=await Harness.open(new MemoryStorage(),{registry,models:{},onReport:error=>reports.push(error===undefined?'missing':error===reason?'reason':'wrong')},{}),otherRoot=await other.root({}),otherId=await otherRoot.commit(tx=>tx.createTask(Task,{},{ownership:{kind:'conversation'}}),{}),otherDone=await other.waitForTask(otherId,{});await otherRoot.waitForIdle({});await other.close({});globalThis.result=JSON.stringify({first:done.state.outcome,second:otherDone.state.outcome,reports});
        \\
    , "native-durable-null-reporter-args-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-durable-result", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"first\":{\"status\":\"completed\",\"result\":{\"memo\":\"TypeError\",\"create\":\"TypeError\",\"tools\":0}},\"second\":{\"status\":\"completed\",\"result\":{\"memo\":\"TypeError\",\"create\":\"TypeError\",\"tools\":0}},\"reports\":[\"missing\",\"reason\",\"reason\"]}", text);
}

test "native durable VM String normalization C allocator callback preserves all four Unicode forms" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const output = try engine.eval("JSON.stringify(['e\\u0301'.normalize('NFC'),'\\u00e9'.normalize('NFD'),'\\ufb01'.normalize('NFKC'),'\\u2460'.normalize('NFKD'),'\\u1100\\u1161'.normalize(),''.normalize()])", "native-string-normalization-abi", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(output);
    const text = try engine.toString(output);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("[\"\xc3\xa9\",\"e\xcc\x81\",\"fi\",\"1\",\"\xea\xb0\x80\",\"\"]", text);
}
test "native durable VM String locale comparison normalizes both operands through correctly typed allocator callbacks" {
    const engine = try engine_module.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const result = try engine.eval("'\\u00e9'.localeCompare('e\\u0301') === 0 && 'e\\u0301'.localeCompare('\\u00e9') === 0", "native-string-locale-normalization-abi", engine_module.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    try std.testing.expect(engine_module.c.JS_ToBool(engine.context, result) != 0);
}
