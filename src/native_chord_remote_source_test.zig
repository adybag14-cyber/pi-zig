const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const classes = try @import("extensions/native_chord_host.zig").classes(engine);
    defer engine.freeValue(classes.bindings);
    defer engine.freeValue(classes.exports);
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const api = try js.object(engine);
    defer engine.freeValue(api);
    inline for (.{ "RemoteHandle", "holdsByProxy" }) |name| try js.define(engine, api, name, try js.get(engine, classes.bindings, name));
    const codec = try js.get(engine, classes.bindings, "DeltaCodec");
    defer engine.freeValue(codec);
    try js.define(engine, api, "encoder", try js.get(engine, codec, "encoder"));
    try js.define(engine, root, "nativeRemoteApi", em.c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord remote actual Source30 lifecycle dispatch reconnect and9negative outcomes" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const original = @embedFile("extensions/fixtures/chord-remote-original-e622.json");
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "remoteSource", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, "remote-original.json")));
    const result = engine.evalModule("const api=nativeRemoteApi;\n" ++ @embedFile("extensions/fixtures/chord-remote-original-e622.input.txt") ++ "\nconst actual=chordRemoteCases;if(actual.length!==remoteSource.cases.length)throw Error('remote Source count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(remoteSource.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:remoteSource.cases[i]}));", "chord-remote-source.mjs") catch |err| {
        std.debug.print("Native Chord remote Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
const retained_start =
    \\const contract={description:{variants:{active:{run:{kind:'method',args:{type:'object',properties:{n:{type:'number'}},required:['n'],additionalProperties:false}},count:{kind:'state'}}}}},reports=[],log=[],host={inFactory:0,report(value){reports.push(value)},forgetRemote(value){log.push(value.status)}},fields={contract,at:'peer',input:{},principal:undefined,owner:{},address:'peer/test'},handle=new nativeRemoteApi.RemoteHandle(host,fields),read=handle.proxy.count,values=[];read.subscribe(value=>values.push(value));let sink;const channel={sub(id,name,next){sink=next;return 8},unsub(id){log.push(id)},call(id,name,args,root,signal){return Promise.resolve(args.n)},release(id){log.push(id)}};handle.bound(channel,4);handle.shaped({kind:'active'});sink({snap:{n:1}});globalThis.remotePending={handle,read,values,channel,sink,log,reports};
;
const retained_finish =
    \\const p=remotePending,ctx={rootId:'root',epoch:2,signal:new AbortController().signal};const value=await p.handle.proxy.run({n:4,drop:true},ctx);const encoder=nativeRemoteApi.encoder();p.sink({ops:encoder.encode([['s',['n'],2]])});if(value!==4||p.read.value.n!==2||p.values.length!==3||p.reports.length)throw Error('remote graph lost');p.handle.detached();if(p.read.value.n!==2)throw Error('detached value lost');p.handle.bound(p.channel,5);p.handle.shaped({kind:'active'});p.sink({reset:{n:9}});p.handle.release();if(p.handle.status!=='released'||p.read.value!==undefined)throw Error('release did not stop graph');delete globalThis.remotePending;
;
test "native Chord remote private handle readable channels and caller survive GC" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const started = try engine.evalModule(retained_start, "chord-remote-gc-start.mjs");
    engine.freeValue(started);
    em.c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(retained_finish, "chord-remote-gc-finish.mjs");
    engine.freeValue(completed);
    em.c.JS_RunGC(engine.runtime);
}
test "native Chord remote complete handle subscribed state dispatch and reconnect allocation sweep" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(retained_start ++ "\n" ++ retained_finish, "chord-remote-allocation.mjs") catch |err| {
                if (err != error.OutOfMemory and engine.native_allocation_generation == generation) {
                    const failed: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    std.debug.print("Remote GPA index{d}: {s}\n", .{ failed.fail_index, engine.last_error orelse "no diagnostic" });
                }
                return engine.nativeAllocationError(err, generation);
            };
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
