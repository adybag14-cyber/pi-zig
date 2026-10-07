const std = @import("std");
const engine_module = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const native_json = @import("durable/backend/json.zig");
test {
    _ = @import("extensions/native_durable_broker.zig");
    _ = @import("extensions/native_worker.zig");
    _ = @import("extensions/native_durable_observation.zig");
    _ = @import("extensions/native_durable_state.zig");
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
