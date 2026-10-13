const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const classes = try @import("extensions/native_chord_host.zig").classes(engine);
    defer engine.freeValue(classes.bindings);
    defer engine.freeValue(classes.exports);
    try js.define(engine, classes.exports, "isSource", try js.get(engine, classes.bindings, "isSource"));
    try js.define(engine, root, "nativeHostApi", em.c.JS_DupValue(engine.context, classes.exports));
    return engine;
}
fn replay(engine: *em.Engine, comptime fixture: [:0]const u8, comptime input: []const u8, comptime cases: []const u8) !void {
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile(fixture);
    try js.define(engine, root, "hostSource", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, fixture.ptr)));
    const result = engine.evalModule("const api=nativeHostApi;\n" ++ @embedFile(input) ++ "\nconst actual=" ++ cases ++ ";if(actual.length!==hostSource.cases.length)throw Error('Host Source count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(hostSource.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:hostSource.cases[i]}));", "chord-host-source.mjs") catch |err| {
        std.debug.print("Native Chord Host Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord Host genuine Source six local ownership transactions" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try replay(engine, "extensions/fixtures/chord-host-original-19cb.json", "extensions/fixtures/chord-host-original-19cb.input.txt", "chordHostCases");
}
test "native Chord Host actual constructors own fields methods brands Source nine" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try replay(engine, "extensions/fixtures/chord-host-metadata-original-19cb.json", "extensions/fixtures/chord-host-metadata-original-19cb.input.txt", "chordHostMetadataCases");
}
test "native Chord Host genuine Source readable listener task cancellation and forced disposal" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try replay(engine, "extensions/fixtures/chord-host-runtime-original-19cb.json", "extensions/fixtures/chord-host-runtime-original-19cb.input.txt", "chordHostRuntimeCases");
}
test "native Chord Host pending activation retains graph through explicit collection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const initial = try engine.evalModule(
        \\const api=nativeHostApi,host=api.createHost({onError(){}}),token=api.local('gc.owner',{version:1,input:{type:'object'},members:{value:api.opaque('value@1')}});let release;const gate=new Promise(resolve=>release=resolve),value={alive:33};host.serve(token,(_i,_p,self)=>{const r=self.resources({value:api.resource({rev:1,open(){return gate}})});return{value:self.expose(r.value)}});const hold=host.get(token,{});globalThis.hostPending={host,hold,release,value};
    , "chord-host-gc-start.mjs");
    engine.freeValue(initial);
    em.c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const p=hostPending;p.release(p.value);await p.hold.ready;if(p.hold.value!==p.value)throw Error('activation graph lost');await p.host.close();if(p.hold.status!=='gone')throw Error('forced status lost');delete globalThis.hostPending;
    , "chord-host-gc-complete.mjs");
    engine.freeValue(completed);
    em.c.JS_RunGC(engine.runtime);
}
test "native Chord Host latest real Cell Derived load roots and retirement Source composition" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try @import("extensions/native_url.zig").install(engine);
    try replay(engine, "extensions/fixtures/chord-composition-original-e622.json", "extensions/fixtures/chord-composition-original-e622.input.txt", "chordCompositionCases");
}
test "native Chord Host links replay latest memory IPC structural WebSocket and close failures" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try replay(engine, "extensions/fixtures/chord-links-original-e622.json", "extensions/fixtures/chord-links-original-e622.input.txt", "chordLinksCases");
}
test "native Chord Host transport callbacks retain graph through GC and release every induced allocation failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const started = engine.evalModule(
                \\const api=nativeHostApi,[a,b]=api.memoryLinkPair(),frames=[];b.receive(frame=>frames.push(frame));a.send({t:'ping',n:1});const events=new Map(),socket={readyState:0,addEventListener(name,fn){events.set(name,fn)},send(){},close(){this.readyState=3}},link=api.webSocketLink(socket);link.send({t:'ping',n:2});const listeners=new Map(),channel={connected:true,on(name,fn){listeners.set(name,fn)},off(name,fn){if(listeners.get(name)===fn)listeners.delete(name)},send(){}},ipc=api.ipcLink(channel);globalThis.pendingTransports={a,b,frames,events,socket,link,listeners,ipc};
            , "chord-transports-gc-start.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(started);
            em.c.JS_RunGC(engine.runtime);
            const completed = engine.evalModule(
                \\const p=pendingTransports;for(let i=0;i<6;i++)await Promise.resolve();if(JSON.stringify(p.frames)!=='[{"t":"ping","n":1}]')throw Error('memory graph lost');p.socket.readyState=1;p.events.get('open')();p.listeners.get('disconnect')();if(!p.ipc.closed||p.listeners.size!==0)throw Error('ipc graph lost');p.link.close();p.a.close();for(let i=0;i<6;i++)await Promise.resolve();if(!p.a.closed||!p.b.closed||!p.link.closed)throw Error('close graph lost');delete globalThis.pendingTransports;
            , "chord-transports-gc-finish.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(completed);
            em.c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
test "native Chord Host construction activation and disposal release induced allocation failures" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const api=nativeHostApi,host=api.createHost({onError(){}}),token=api.local('allocation.owner',{version:1,input:{type:'object'},members:{value:api.opaque('value@1'),echo:api.method({type:'number'},{type:'number'})}});host.serve(token,(_i,_p,self)=>{const r=self.resources({value:api.resource({rev:1,open(){return{alive:1}},close(){}})});return{value:self.expose(r.value),echo(value){return value+1}}});const hold=host.get(token,{});await hold.ready;if(hold.value.alive!==1||await hold.echo(2)!==3)throw Error('native ownership probe changed');await host.close();
            , "chord-host-allocation.mjs") catch |err| {
                if (err == error.JavaScriptPromiseUnsettled) {
                    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    std.debug.print("Host allocation unsettled at {d}: {f}\n", .{ failing.fail_index, std.debug.FormatStackTrace{ .stack_trace = failing.getStackTrace() } });
                }
                return engine.nativeAllocationError(err, generation);
            };
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
