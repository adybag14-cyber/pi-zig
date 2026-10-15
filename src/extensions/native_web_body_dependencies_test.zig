const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const blob = @import("native_web_blob.zig");
const form = @import("native_web_form_data.zig");
const idl = @import("native_web_idl.zig");
const c = em.c;
fn responseInit(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try idl.responseInit(&scope, if (args.len > 0) args[0] else c.pi_js_undefined()));
}
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    try blob.install(engine);
    try form.install(engine);
    const adapter = try @import("native_node_function.zig").createArrow(engine, "convertResponseInit", 1, responseInit, &.{});
    defer engine.freeValue(adapter);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "convertResponseInit", c.JS_DupValue(engine.context, adapter));
    return engine;
}
fn evaluate(engine: *em.Engine, program: []const u8, name: [:0]const u8) !void {
    const result = engine.evalModule(program, name) catch |err| {
        if (engine.last_error) |message| std.debug.print("Web Body dependency: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
}
test "Web Body dependency genuine Source176 mapped Blob File FormData WebIDL observations" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const expected = @embedFile("fixtures/web-body-node24.json");
    try js.define(engine, global, "bodySource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "genuine-body176.json")));
    try evaluate(engine,
        \\const observed=name=>{const row=bodySource.rows.find(r=>r.name===name);if(!row)throw Error('Missing genuine Source row '+name);return row};
        \\let mapped=0;const equal=(actual,expected,name)=>{if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({name,actual,expected}));mapped++};
        \\const descriptor=(object,key)=>{const d=Object.getOwnPropertyDescriptor(object,key);return{key:typeof key==='symbol'?String(key):key,enumerable:d.enumerable,configurable:d.configurable,...('value'in d?{writable:d.writable,value:typeof d.value==='function'?{type:'function',name:d.value.name,length:d.value.length}:typeof d.value==='symbol'?String(d.value):d.value!==null&&typeof d.value==='object'?{type:'object',tag:Object.prototype.toString.call(d.value)}:d.value}:{get:d.get?{name:d.get.name,length:d.get.length}:undefined,set:d.set?{name:d.set.name,length:d.set.length}:undefined})}};
        \\for(const name of ['Blob','File','FormData'])equal(descriptor(globalThis,name),observed('global descriptor '+name).value,'global '+name);
        \\for(const method of ['text','arrayBuffer','bytes']){const b=new Blob(['blob 😀'],{type:'TEXT/CUSTOM'}),value=await b[method]();equal(method==='text'?value:[...new Uint8Array(value instanceof ArrayBuffer?value:value.buffer,value.byteOffset??0,value.byteLength)],observed('Response binary 6/'+method).value.value,'shared Blob bytes '+method);if(b.type!==observed('Response binary 6/'+method).value.before.headers.find(p=>p[0]==='content-type')[1])throw Error('Blob MIME observation');}
        \\const original=new Uint8Array([65,66]),copy=new Blob([original]);original[0]=90;equal({text:await copy.text(),source:[...original]},observed('Response binary source mutation ownership').value,'shared BufferSource ownership');
        \\equal({malformed:await new Blob([new Uint8Array([0x61,0xc3,0x28,0xff])]).text(),bom:await new Blob([new Uint8Array([0xef,0xbb,0xbf,0x61])]).text()},observed('Response text UTF8 replacement and BOM').value,'shared UTF8 decode');
        \\const fd=new FormData();fd.append('a','one');fd.append('a','é');fd.append('file',new File(['owned bytes'],'sample.txt',{type:'text/plain'}));const entries=[];for(const[k,v]of fd)entries.push([k,typeof v==='string'?v:{name:v.name,type:v.type,size:v.size,text:await v.text()}]);equal(entries,observed('Response FormData actual multipart roundtrip').value.entries,'FormData original fields and File bytes only');
        \\const errorShape=e=>({name:e?.name,message:e?.message,code:e?.code,typeError:e instanceof TypeError});
        \\for(const[index,input]of [[3,0],[4,false],[5,'x'],[14,{status:200,statusText:'Ā'}],[18,{headers:null}]] ){let caught;try{convertResponseInit(input)}catch(e){caught=e}equal(errorShape(caught),observed('Response init '+index).error,'ResponseInit conversion '+index)}
        \\for(const[name,input]of [['Response invalid header sequence conversion before invalid status',{status:600,headers:[1]}],['Response header ByteString conversion before invalid status',{status:600,headers:[['x',Symbol('value')]]}],['Response statusText Symbol',{statusText:Symbol('statusText')}]] ){let caught;try{convertResponseInit(input)}catch(e){caught=e}equal(errorShape(caught),observed(name).error,name)}
        \\if(mapped!==17)throw Error('Source dependency mapping count '+mapped);
    , "genuine-body176-dependency-mapping.mjs");
}
test "Web Body dependency genuine private brands immutable data and explicit missing stream graph" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try std.testing.expectError(error.NativeWebReadableStreamUnavailable, @import("native_web_body.zig").require(engine));
    try evaluate(engine,
        \\const b=new Blob(['bytes']),f=new File([b],'name.txt',{lastModified:123,type:'TEXT/PLAIN'});if(!(b instanceof Blob)||!(f instanceof Blob)||!(f instanceof File)||f.name!=='name.txt'||f.lastModified!==123||f.type!=='text/plain')throw Error('actual Blob/File hierarchy');let missing;try{b.stream()}catch(e){missing=e}if(!missing?.message.includes('NativeWebReadableStreamUnavailable'))throw Error('stream dependency must fail explicitly');
    , "native-body-dependency-brands.mjs");
}
const ownership_program =
    \\const b=new Blob(['bytes',new Uint8Array([65,66])],{type:'TEXT/PLAIN'}),f=new File([b],'name',{lastModified:123}),fd=new FormData();fd.append('file',f);fd.append('same','one');fd.append('same','two');fd.set('same','replacement');const i=fd.entries();i.next();fd.delete('same');i.next();await b.text();await b.arrayBuffer();await f.bytes();await b.slice(1,4).text();
;
fn ownership(engine: *em.Engine) !void {
    const generation = engine.native_allocation_generation;
    evaluate(engine, ownership_program, "native-body-dependency-ownership.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    c.JS_RunGC(engine.runtime);
}
test "Web Body dependency selected actual allocation failures release all bytes" {
    var measured = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const baseline = try setup(measured.allocator());
    const start_index = measured.alloc_index;
    try ownership(baseline);
    const count = measured.alloc_index - start_index;
    baseline.deinit();
    try std.testing.expect(count > 0);
    try std.testing.expectEqual(measured.allocated_bytes, measured.freed_bytes);
    for ([_]usize{ 0, count / 4, count / 2, count * 3 / 4, count - 1 }) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try setup(failing.allocator());
        failing.fail_index = failing.alloc_index + offset;
        const result = ownership(engine);
        engine.deinit();
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectError(error.OutOfMemory, result);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        std.debug.print("Body dependency operation allocation offset={d}/{d} all-bytes-freed=true\n", .{ offset, count });
    }
}
