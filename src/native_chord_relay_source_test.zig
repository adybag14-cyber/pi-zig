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
    inline for (.{ "RelayHold", "RelayCall" }) |name| try js.define(engine, api, name, try js.get(engine, classes.bindings, name));
    try js.define(engine, api, "ChordError", try js.get(engine, classes.exports, "ChordError"));
    try js.define(engine, root, "nativeRelayApi", em.c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord relay actual Source20 ownership forwarding and negative settlement outcomes" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const original = @embedFile("extensions/fixtures/chord-relay-original-e622.json");
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "relaySource", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, "relay-original.json")));
    const result = engine.evalModule("const api=nativeRelayApi;\n" ++ @embedFile("extensions/fixtures/chord-relay-original-e622.input.txt") ++ "\nconst actual=chordRelayCases;if(actual.length!==relaySource.cases.length)throw Error('relay Source count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(relaySource.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:relaySource.cases[i]}));", "chord-relay-source.mjs") catch |err| {
        std.debug.print("Native Chord relay Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
const retained_start =
    \\const api=nativeRelayApi,log=[],origin={generation:2,open:true,served:new Map(),relaySubs:new Map(),send(frame){log.push(frame)}},frame={t:'hold',id:7,at:'dest',token:{},input:{}},relay=new api.RelayHold(origin,frame,{user:'a'},false);origin.served.set(7,{kind:'relay',relay});const waiting=relay.ready(),down={relayedHolds:new Map(),relayedCalls:new Map(),relayedSubs:new Map(),nextId(){return this.next++},next:40,send(frame){log.push(frame)}};relay.subscribe(10,'count');relay.open(down);const settled=[];new api.RelayCall(relay,20,80,{resolve(value){settled.push(value)},reject(error){settled.push(error)}});globalThis.relayPending={relay,waiting,down,origin,log,settled};
;
const retained_finish =
    \\const p=relayPending;if(await p.waiting!==p.down||p.down.relayedHolds.get(40)!==p.relay)throw Error('relay retained graph lost');const failure=new nativeRelayApi.ChordError('gone','revoked');p.relay.close(failure,{releaseDown:true,notify:true});if(p.settled[0]!==failure||p.relay.calls.size||p.relay.subs.size||p.down.relayedHolds.size||p.down.relayedCalls.size||p.down.relayedSubs.size||p.origin.served.size||p.origin.relaySubs.size)throw Error('relay ownership did not settle');let error;try{await p.relay.ready()}catch(value){error=value}if(error?.code!=='gone')throw Error('closed ready did not reject');delete globalThis.relayPending;
;
test "native Chord relay live waiters calls channels and subscriptions remain rooted through GC" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const started = try engine.evalModule(retained_start, "chord-relay-gc-start.mjs");
    engine.freeValue(started);
    em.c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(retained_finish, "chord-relay-gc-finish.mjs");
    engine.freeValue(completed);
    em.c.JS_RunGC(engine.runtime);
}
test "native Chord relay complete constructors waiters forwarding teardown and errors allocation sweep" {
    const Probe = struct {
        fn exercise(engine: *em.Engine, generation: u64) !void {
            const result = try engine.evalModule(retained_start ++
                \\const p=relayPending;if(await p.waiting!==p.down||p.down.relayedHolds.get(40)!==p.relay)throw Error('relay retained graph lost');const failure=new nativeRelayApi.ChordError('gone','revoked');p.relay.close(failure,{releaseDown:true,notify:true});if(p.settled[0]!==failure||p.relay.calls.size||p.relay.subs.size||p.down.relayedHolds.size||p.down.relayedCalls.size||p.down.relayedSubs.size||p.origin.served.size||p.origin.relaySubs.size)throw Error('relay ownership did not settle');
            , "chord-relay-allocation.mjs");
            engine.freeValue(result);
            // Inspect the original rejected value at this private host boundary.
            // A guest expected-error catch must not replace an injected native OOM.
            const root = em.c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(root);
            const retained = try js.get(engine, root, "relayPending");
            defer engine.freeValue(retained);
            const relay = try js.get(engine, retained, "relay");
            defer engine.freeValue(relay);
            const pending = try js.invoke(engine, relay, "ready", &.{});
            defer engine.freeValue(pending);
            const value = engine.awaitValue(pending) catch |err| {
                const mapped = engine.nativeAllocationError(err, generation);
                if (mapped == error.OutOfMemory) return mapped;
                if (err != error.JavaScriptException) return err;
                const code = try js.get(engine, engine.captured_exception orelse return err, "code");
                defer engine.freeValue(code);
                const expected = try engine.checked(em.c.JS_NewString(engine.context, "gone"));
                defer engine.freeValue(expected);
                if (!em.c.JS_IsStrictEqual(engine.context, code, expected)) return err;
                return;
            };
            engine.freeValue(value);
            return error.ClosedRelayReadyDidNotReject;
        }
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            exercise(engine, generation) catch |err| {
                const mapped = engine.nativeAllocationError(err, generation);
                if (mapped != error.OutOfMemory) {
                    const failed: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    std.debug.print("Relay GPA index{d}: {s}\n", .{ failed.fail_index, engine.last_error orelse "no diagnostic" });
                }
                return mapped;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
