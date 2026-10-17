//! Prepared native consumer controls. No source observation is accepted here
//! until the genuine Node Source20 packet state explicitly says accepted.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { c.JS_RunGC(em.Engine.fromContext(context.?).runtime); return c.pi_js_undefined(); }
fn original(engine: *em.Engine, scope: *Scope, global: c.JSValue, key: [*:0]const u8, source: []const u8, filename: [:0]const u8) !void {
    const transformed = try @import("extensions/typescript.zig").transform(engine.gpa, source); defer engine.gpa.free(transformed);
    const namespace = try scope.own(try engine.evalModule(transformed, filename)); try scope.put(global, key, namespace);
}
fn replay(case_name: []const u8, assertion: []const u8, compare_source: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-node-stream-classic-control"});
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    try @import("extensions/native_node_stream_web.zig").install(engine);
    try original(engine, &scope, global, "originalJsonl", @embedFile("extensions/fixtures/node-stream-classic-source/jsonl.ts"), "classic-original-jsonl.mjs");
    try original(engine, &scope, global, "originalChildWait", @embedFile("extensions/fixtures/node-stream-classic-source/wait-for-child-process.excerpt.ts"), "classic-original-child-wait.mjs");
    try scope.put(global, "caseName", try scope.text(case_name)); try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    if (compare_source) {
        const state = @embedFile("extensions/fixtures/node-stream-classic-node24.capture-pending.json");
        try scope.put(global, "source20State", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, state.ptr, state.len, "classic-source20-capture-state.json"))));
        const accepted = try scope.get(try scope.get(global, "source20State"), "captureAccepted");
        if (!scope.truthy(accepted)) return error.GenuineNodeClassicSource20NotCapturedOrAccepted;
    }
    const trailer = if (compare_source) "\nif(JSON.stringify(packet)!==JSON.stringify(source20State.expectedPackets[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:source20State.expectedPackets[caseName]}));" else assertion;
    const input = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/node-stream-classic-node24.input.txt"), trailer, "\nexport const proof=true;" }); defer engine.gpa.free(input);
    const value = engine.evalModule(input, "native-node-classic-stream-control.mjs") catch |err| { std.debug.print("Classic stream {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" }); return err; }; engine.freeValue(value);
    engine.finishJob(); c.JS_RunGC(engine.runtime);
}
test "native classic stream draft original JSONL consumer" {
    try replay("from-sync-jsonl-original", "\nconst lines=packet.rows[0];if(lines.length!==3||JSON.parse(lines[0]).text!=='a\\u2028b\\u2029c'||lines[1]!=='{\"a\":1}'||lines[2]!=='{\"b\":2}')throw Error('original strict LF consumer lost input');", false);
}
test "native classic stream draft preserves child tail after exit without manufacturing EOF" {
    try replay("original-child-exit-tail", "\nif(packet.rows[0]!==false||packet.rows[1]!==false||packet.rows[2]!==0||packet.rows[3]!=='HEAD\\nTICK1\\nTICK2\\nTICK3\\nTAIL\\n'||packet.rows[4]!==true||packet.rows[5]!==true||packet.rows[6]!==0||packet.rows[7]!==0)throw Error('original child stream lifetime or cleanup changed');", false);
}
test "native classic stream draft asynchronous write retains actual completion and drain" {
    try replay("write-async-backpressure", "\nif(packet.rows[0]!==false||packet.rows[1]!==false||packet.rows[2].writableLength!==3||packet.rows[3].writableLength!==1||packet.rows[5].writableLength!==0)throw Error('actual write completion did not own queue/backpressure');", false);
}
test "native classic stream draft genuine Web reader cancellation" {
    try replay("from-web-cancel", "\nif(JSON.stringify(packet.rows[0])!==JSON.stringify([['cancel',true],['destroyed',true],['error',true]]))throw Error('actual reader cancel/error identity or ordering lost');", false);
}
test "native classic stream Source20 complete original packets required" {
    const cases = [_][]const u8{ "constructor-metadata", "write-sync-order", "write-async-backpressure", "cork-writev", "final-finish-close", "destroy-once", "duplex-half-open", "readable-read-unshift", "pipe-pause-drain-unpipe", "decoder-utf8-carry-bom", "decoder-utf16-base64", "from-sync-jsonl-original", "from-async-values-order", "from-async-iterator-close", "from-web-real-reader", "from-web-cancel", "passthrough-readable-backpressure", "pipeline-node-and-end-false", "finished-premature-close", "original-child-exit-tail" };
    for (cases) |case_name| try replay(case_name, "", true);
}

test "native classic stream and decoder brands cannot be redirected to another native opaque class" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-stream-brand-control"});
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    const owner = try @import("extensions/native_node_stream.zig").owner(engine); const opaque_function = try scope.get(owner, "Stream");
    try scope.put(global, "streamBrandOwner", owner);
    try scope.put(global, "decoderBrandOwner", engine.native_module_values.get("pi-native:node-string-decoder").?);
    try scope.put(global, "differentNativeOpaque", opaque_function); try scope.put(global, "differentNativeClass", c.JS_NewUint32(engine.context, c.JS_GetClassID(opaque_function)));
    const result = try engine.evalModule(
        "import {Readable} from 'node:stream';import {StringDecoder} from 'node:string_decoder';import {Buffer} from 'node:buffer';"
        ++ "for(const [owner,names]of [[streamBrandOwner,['readStateClass','writeStateClass']],[decoderBrandOwner,['stateClass','stateSymbol']]])for(const name of names){const before=owner[name],d=Object.getOwnPropertyDescriptor(owner,name);if(d.writable||d.configurable||Reflect.set(owner,name,differentNativeClass)||Reflect.deleteProperty(owner,name)||owner[name]!==before)throw Error('native brand admission is mutable')}"
        ++ "const r=new Readable({read(){}}),real=r._readableState;r._readableState=differentNativeOpaque;let readRejected=false;try{r.read(0)}catch(e){readRejected=true}if(!readRejected)throw Error('wrong opaque readable accepted');r._readableState=real;const get=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(real),'length').get;let getterRejected=false;try{get.call(differentNativeOpaque)}catch(e){getterRejected=true}if(!getterRejected)throw Error('wrong opaque state getter accepted');"
        ++ "const d=new StringDecoder('utf8'),symbol=decoderBrandOwner.stateSymbol;const forged={[symbol]:differentNativeOpaque};let decoderRejected=false;try{d.write.call(forged,Buffer.from([65]))}catch(e){decoderRejected=true}if(!decoderRejected||d.write(Buffer.from([65]))!=='A')throw Error('decoder native brand lost');export const proof=true;",
        "native-stream-native-brand-boundary.mjs",
    ); engine.freeValue(result);
}

test "native classic writableBuffer exposes real queued entries for Socket byte accounting" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-writable-buffer-control"});
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    const result = try engine.evalModule(
        "import {Writable,Duplex} from 'node:stream';import {finished} from 'node:stream/promises';import {Buffer} from 'node:buffer';"
        ++ "const pending=[],seen=[];let original=0,replacement=0;const w=new Writable({decodeStrings:false,write(chunk,encoding,cb){seen.push([chunk,encoding]);pending.push(cb)}});const first=Buffer.from([1,2]);w.write(first);w.write('é','utf8',()=>original++);const a=w.writableBuffer,b=w.writableBuffer;if(a===b||a.length!==1||a[0]!==b[0]||a[0].chunk!=='é'||a[0].encoding!=='utf8'||typeof a[0].callback!=='function'||w._writableState.getBuffer()[0]!==a[0])throw Error('real pending entry snapshot');a[0].chunk='ø';a[0].callback=()=>replacement++;nativeCollect();pending.shift()();if(seen.length!==2||seen[1][0]!=='ø'||seen[1][1]!=='utf8'||w.writableBuffer.length!==0)throw Error('queued entry was copied or active item exposed');w.end();pending.shift()();await finished(w);if(original!==0||replacement!==1||w.writableBuffer.length!==0)throw Error('queued callback identity');"
        ++ "let vector,complete;const v=new Writable({write(c,e,cb){cb()},writev(entries,cb){vector=entries;complete=cb}});v.cork();v.write(Buffer.from([3]));v.write(Buffer.from([4]));const q=v.writableBuffer;v.uncork();if(vector[0]!==q[0]||vector[1]!==q[1]||v.writableBuffer.length!==0)throw Error('writev copied actual queue entries');v.end();complete();await finished(v);"
        ++ "let release,terminal,encodingReads=0;const marker={};const failed=new Writable({write(c,e,cb){release=cb}});failed.on('error',()=>{});failed.write(Buffer.from([1]));failed.write(Buffer.from([2]),e=>terminal=e);Object.defineProperty(failed.writableBuffer[0],'encoding',{get(){encodingReads++;throw Error('terminal path read encoding')}});const settled=finished(failed).catch(e=>e);failed.destroy(marker);release();await settled;if(terminal!==marker||encodingReads!==0)throw Error('queued terminal callback read wrong fields');"
        ++ "for(const type of [Writable,Duplex]){const d=Object.getOwnPropertyDescriptor(type.prototype,'writableBuffer');if(d.configurable||d.enumerable||d.set!==undefined)throw Error('writableBuffer descriptor');const marker={};if(d.get.call({_writableState:{getBuffer(){return marker}}})!==marker||d.get.call({_writableState:null})!==null||d.get.call({})!==undefined)throw Error('live getBuffer lookup/falsy result')}export const proof=true;",
        "native-writable-buffer-socket-seam.mjs",
    ); engine.freeValue(result); engine.finishJob(); c.JS_RunGC(engine.runtime);
}

test "native writable buffered entry mutation releases replaced queued values before dispatch" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-writable-entry-gc-control"});
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    const setup = try engine.evalModule("import {Writable} from 'node:stream';globalThis.gcWriter=new Writable({objectMode:true,write(c,e,cb){cb()}});gcWriter.cork();globalThis.replacedChunk={};globalThis.replacedEncoding={};globalThis.replacedCallback=function(){};globalThis.chunkWeak=new WeakRef(replacedChunk);globalThis.encodingWeak=new WeakRef(replacedEncoding);globalThis.callbackWeak=new WeakRef(replacedCallback);gcWriter.write(replacedChunk,replacedEncoding,replacedCallback);const entry=gcWriter.writableBuffer[0];entry.chunk={current:true};entry.encoding='utf8';entry.callback=()=>{};replacedChunk=null;replacedEncoding=null;replacedCallback=null;export const proof=true;", "native-writable-entry-gc-setup.mjs"); engine.freeValue(setup);
    // Real VM weak-reference retirement, independent of finalizer callback
    // scheduling. Only the mutable queued entry may retain these old values.
    c.JS_ClearKeptObjects(engine.runtime); c.JS_RunGC(engine.runtime);
    const check = try engine.evalModule("if(chunkWeak.deref()!==undefined||encodingWeak.deref()!==undefined||callbackWeak.deref()!==undefined)throw Error('replaced queued values retain duplicate native roots');if(gcWriter.writableBuffer.length!==1||!gcWriter.writableBuffer[0].chunk.current)throw Error('current queued entry retired');export const proof=true;", "native-writable-entry-gc-check.mjs"); engine.freeValue(check);
}

test "native scalar buffer slot retires before throwing chunk length and preserves null snapshot" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-writable-null-slot-control"});
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    const result = try engine.evalModule("import {Writable} from 'node:stream';const marker={};let snapshot,writes=0;const w=new Writable({decodeStrings:false,write(c,e,cb){writes++;cb()}});w.cork();w.write('aa');w.writableBuffer[0].chunk={get length(){snapshot=w.writableBuffer;throw marker}};let caught;try{w.uncork()}catch(e){caught=e}const after=w.writableBuffer;if(caught!==marker||writes!==0||snapshot.length!==1||snapshot[0]!==null||after.length!==1||after[0]!==null||w._writableState.bufferedIndex!==0||!w._writableState.bufferProcessing)throw Error('scalar retirement/throw boundary differs from Source');export const proof=true;", "native-writable-null-before-length.mjs"); engine.freeValue(result);
}

test "native terminal buffered callbacks observe all entries until reset after callback loop" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-writable-terminal-buffer-control"});
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try @import("extensions/native_node_stream.zig").install(engine, try scope.get(global, "process"));
    const result = try engine.evalModule("import {Writable} from 'node:stream';import {finished} from 'node:stream/promises';import {Buffer} from 'node:buffer';const marker={},seen=[];let release;const w=new Writable({write(c,e,cb){release=cb}});w.on('error',()=>{});w.write(Buffer.from([1]));w.write(Buffer.from([2]),e=>seen.push([e,w.writableBuffer]));w.write(Buffer.from([3]),e=>seen.push([e,w.writableBuffer]));const original=w.writableBuffer;w.end(e=>seen.push([e,w.writableBuffer]));const completion=finished(w).catch(e=>e);w.destroy(marker);release();await completion;if(seen.length!==3)throw Error('terminal callbacks lost');for(const [e,buffer]of seen)if(e!==marker||buffer.length!==2||buffer[0]!==original[0]||buffer[1]!==original[1])throw Error('terminal callback observed prematurely retired buffer');if(w.writableBuffer.length!==0||w._writableState.bufferedIndex!==0)throw Error('terminal buffer did not reset after callbacks');export const proof=true;", "native-writable-terminal-array-retention.mjs"); engine.freeValue(result); engine.finishJob();
}
