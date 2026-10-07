const std = @import("std");
const engine_module = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const native_json = @import("durable/backend/json.zig");
test {
    _ = @import("extensions/native_durable_broker.zig");
    _ = @import("extensions/native_worker.zig");
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
