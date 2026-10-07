const std = @import("std");
const engine_module = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const native_json = @import("durable/backend/json.zig");
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
