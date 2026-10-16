//! Authored composition regressions; source-only until separately admitted.
const std = @import("std");
const em = @import("extensions/engine.zig");
const web = @import("extensions/native_node_stream_web.zig");
const c = em.c;
fn evaluate(source: []const u8) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try web.install(engine);
    const value = try engine.evalModule(source, "native-stream-web-assembly.mjs");
    engine.freeValue(value);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native stream web actual seventeen classes namespace and shared queue size callbacks" {
    try evaluate(
        \\import web,*as ns from'node:stream/web';
        \\const names=['ReadableStream','ReadableStreamDefaultReader','ReadableStreamBYOBReader','ReadableStreamBYOBRequest','ReadableByteStreamController','ReadableStreamDefaultController','TransformStream','TransformStreamDefaultController','WritableStream','WritableStreamDefaultWriter','WritableStreamDefaultController','ByteLengthQueuingStrategy','CountQueuingStrategy','TextEncoderStream','TextDecoderStream','CompressionStream','DecompressionStream'];
        \\if(JSON.stringify(Object.keys(web))!==JSON.stringify(names))throw Error('Builtin seventeen insertion order');if(Object.keys(ns).length!==18||Object.getPrototypeOf(ns)!==null)throw Error('ESM namespace');for(const name of names){if(ns[name]!==web[name]||web[name]!==globalThis[name])throw Error('Captured identity '+name);const descriptor=Object.getOwnPropertyDescriptor(web,name);if(!descriptor.enumerable||!descriptor.configurable||!descriptor.writable)throw Error('Builtin descriptor '+name)}
        \\let reads=0;const q=new web.CountQueuingStrategy({get highWaterMark(){return ++reads}}),q2=new web.CountQueuingStrategy({highWaterMark:-1});if(reads!==2||q.highWaterMark!==2||q.size!==q2.size||q.size.call(null,Symbol())!==1||q2.highWaterMark!==-1)throw Error('Queue conversion/read order/shared callback');const b=new web.ByteLengthQueuingStrategy({highWaterMark:Infinity}),b2=new web.ByteLengthQueuingStrategy({highWaterMark:NaN}),reason={};if(b.size!==b2.size||b.size({byteLength:reason})!==reason||b.highWaterMark!==Infinity||!Number.isNaN(b2.highWaterMark))throw Error('Byte size raw value');try{b.size({get byteLength(){throw reason}});throw Error('Missing failure')}catch(e){if(e!==reason)throw e}export const done=true;
    );
}
test "native stream web encoder cross chunk carry empty chunks symbols and EOF replacement" {
    try evaluate(
        \\import{TextEncoderStream,ReadableStream,WritableStream}from'node:stream/web';
        \\async function encode(chunks){const t=new TextEncoderStream();if(!(t.readable instanceof ReadableStream)||!(t.writable instanceof WritableStream)||t.encoding!=='utf-8')throw Error('Genuine pair');const reader=t.readable.getReader(),writer=t.writable.getWriter(),out=[];const drain=(async()=>{for(;;){const r=await reader.read();if(r.done)break;out.push(Array.from(r.value))}})();writer.closed.catch(()=>{});reader.closed.catch(()=>{});for(const chunk of chunks)await writer.write(chunk);await writer.close();await drain;return out}
        \\const carried=await encode(['\ud800','','\udc00','a\ud800','X','\udc00\udbff']);if(JSON.stringify(carried)!==JSON.stringify([[240,144,128,128],[97],[239,191,189,88],[239,191,189],[239,191,189]]))throw Error('Carry chunks '+JSON.stringify(carried));const symbol=await encode([Symbol('x')]);if(new TextDecoder().decode(Uint8Array.from(symbol.flat()))!=='Symbol(x)')throw Error('String Symbol conversion');export const done=true;
    );
}
test "native stream web decoder genuine streaming BOM UTF16 and flush termination" {
    try evaluate(
        \\import{TextDecoderStream}from'node:stream/web';
        \\async function decode(label,chunks,options){const t=new TextDecoderStream(label,options),reader=t.readable.getReader(),writer=t.writable.getWriter(),out=[];const drain=(async()=>{for(;;){const r=await reader.read();if(r.done)break;out.push(r.value)}})();writer.closed.catch(()=>{});reader.closed.catch(()=>{});for(const chunk of chunks)await writer.write(Uint8Array.from(chunk));await writer.close();await drain;return out}
        \\if(JSON.stringify(await decode('utf8',[[239],[187],[191,240,159],[140],[141,65],[226]]))!==JSON.stringify(['🌍A','�']))throw Error('UTF8/BOM/EOF');if(JSON.stringify(await decode('utf-16le',[[255],[254,60],[216,13],[223]]))!==JSON.stringify(['🌍']))throw Error('UTF16 carry');const d=new TextDecoderStream('utf8',{fatal:true,ignoreBOM:true});if(!d.fatal||!d.ignoreBOM||d.encoding!=='utf-8')throw Error('Decoder attributes');const reader=d.readable.getReader(),writer=d.writable.getWriter();reader.closed.catch(()=>{});writer.closed.catch(()=>{});const read=reader.read().catch(e=>e);await writer.write(Uint8Array.of(226));const closing=await writer.close().then(()=>null,e=>e),reading=await read;if(!(closing instanceof TypeError)||reading!==closing)throw Error('Fatal flush reason ownership');export const done=true;
    );
}
test "native stream web retained decoder and stream constructors survive guest mutation and GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try web.install(engine);
    const before = try engine.evalModule(
        \\import web from'node:stream/web';globalThis.originalWeb=web;for(const name of Object.keys(web)){globalThis[name]=function guest(){};web[name].prototype.constructor=function guestPrototype(){}}TextDecoder.prototype.decode=function(){throw Error('Guest decoder')};Object.defineProperty(TextDecoder.prototype,'encoding',{get(){throw Error('Guest encoding')},configurable:true});globalThis.TextDecoder=function guestDecoder(){};export const ready=true;
    , "stream-web-mutation-prepare.mjs");
    engine.freeValue(before);
    c.JS_RunGC(engine.runtime);
    const after = try engine.evalModule(
        \\import web from'node:stream/web';if(web!==originalWeb)throw Error('Builtin captured object');const t=new web.TextDecoderStream();if(t.encoding!=='utf-8'||!(t.readable instanceof web.ReadableStream))throw Error('Retained decoder');const reader=t.readable.getReader(),writer=t.writable.getWriter();reader.closed.catch(()=>{});writer.closed.catch(()=>{});const read=reader.read();await writer.write(Uint8Array.of(65));if((await read).value!=='A')throw Error('Retained decode');const final=reader.read();await writer.close();if(!(await final).done)throw Error('Native termination');delete globalThis.originalWeb;export const done=true;
    , "stream-web-mutation-complete.mjs");
    engine.freeValue(after);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
