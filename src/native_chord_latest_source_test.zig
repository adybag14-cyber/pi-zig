const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
pub fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const classes = try @import("extensions/native_chord_latest.zig").classes(engine);
    defer engine.freeValue(classes.exports);
    defer engine.freeValue(classes.bindings);
    const api = try js.object(engine);
    defer engine.freeValue(api);
    try js.spreadInto(engine, api, classes.exports);
    // Source's full links caller imports the actual internal Cell export.
    try js.define(engine, api, "Cell", try js.get(engine, classes.bindings, "Cell"));
    try js.define(engine, api, "Packed", try js.get(engine, classes.bindings, "Packed"));
    const wire = try js.get(engine, classes.bindings, "Wire");
    defer engine.freeValue(wire);
    try js.define(engine, api, "isFrame", try js.get(engine, wire, "isFrame"));
    try js.define(engine, api, "unpack", try @import("extensions/native_node_function.zig").create(engine, "unpack", 1, unpack, &.{classes.bindings}));
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeLatestChordApi", em.c.JS_DupValue(engine.context, api));
    try js.define(engine, root, "nativeLatestChordBindings", em.c.JS_DupValue(engine.context, classes.bindings));
    return engine;
}
fn unpack(engine: *em.Engine, _: em.c.JSValue, args: []const em.c.JSValue, captures: []const em.c.JSValue) !em.c.JSValue {
    var scope: @import("extensions/native_chord_host_values.zig").Scope = .{ .engine = engine };
    defer scope.deinit();
    return scope.result(try @import("extensions/native_chord_packing.zig").unpack(&scope, captures[0], if (args.len > 0) args[0] else em.c.pi_js_undefined()));
}
pub fn replay(engine: *em.Engine, comptime stem: []const u8, comptime global: []const u8) !void {
    const original = @embedFile("extensions/fixtures/" ++ stem ++ ".json");
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "chordOriginal", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, "chord-1692-original.json")));
    const result = engine.evalModule("const api=nativeLatestChordApi;await(async()=>{\n" ++ @embedFile("extensions/fixtures/" ++ stem ++ ".input.txt") ++ "\n})();const actual=" ++ global ++ ";if(actual.length!==chordOriginal.cases.length)throw Error('Source case count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(chordOriginal.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:chordOriginal.cases[i]}));", "chord-1692-source.mjs") catch |err| {
        std.debug.print("Latest actual Chord Source {s}: {s}\n", .{ stem, engine.last_error orelse "no diagnostic" });
        return err;
    };
    engine.freeValue(result);
}
fn diagnoseFailure(engine: *em.Engine, gpa: std.mem.Allocator, mapped: anyerror) void {
    if (mapped == error.OutOfMemory) return;
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    std.debug.print("Latest GPA index{d} error={s}: {s}\n", .{ failing.fail_index, @errorName(mapped), engine.last_error orelse "no diagnostic" });
    if (failing.has_induced_failure) std.debug.dumpStackTrace(&.{ .return_addresses = &failing.stack_addresses, .skipped = .unknown });
    if (engine.captured_exception) |exception| {
        std.debug.print("Latest GPA allocation generation{d} captured tag{d} null{any} undefined{any}\n", .{ engine.native_allocation_generation, em.c.pi_js_native_allocation_error_generation(exception), em.c.JS_IsNull(exception), em.c.JS_IsUndefined(exception) });
        const message = engine.toString(exception) catch return;
        defer gpa.free(message);
        std.debug.print("Latest GPA captured exception: {s}\n", .{message});
    }
}
fn allocationBaseline(gpa: std.mem.Allocator, marker: []const u8) void {
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.fail_index == std.math.maxInt(usize)) std.debug.print("{s}={d}\n", .{ marker, failing.alloc_index });
}
pub fn inventory(marker: []const u8) !void {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("{s}={s}\n", .{ marker, encoded });
}
test "native latest Chord1692 compiled selected inventory" {
    try inventory("CHORD_LATEST_COMPILED_INVENTORY");
}
fn nativeAsyncFailure(ctx: ?*em.c.JSContext, _: em.c.JSValue, _: c_int, _: [*c]em.c.JSValue) callconv(.c) em.c.JSValue {
    const owner = em.Engine.fromContext(ctx.?);
    const Failure = struct {
        fn next(_: *em.Engine, _: em.c.JSValue, _: em.c.JSValue, _: bool, _: c_int) anyerror!em.c.JSValue {
            return error.OutOfMemory;
        }
    };
    return @import("extensions/native_chord_host_values.zig").wait(Failure.next, owner, em.c.pi_js_undefined(), em.c.pi_js_undefined(), 0) catch |err| @import("extensions/native_durable.zig").reject(owner, err);
}
fn plainNativeFailure(ctx: ?*em.c.JSContext, _: em.c.JSValue, _: c_int, _: [*c]em.c.JSValue) callconv(.c) em.c.JSValue {
    return em.Engine.fromContext(ctx.?).throwNativeOutOfMemory();
}
test "native latest Chord1692 private continuation fresh OOM escape preserves stale user replacement and lookalike identities" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const failure = @import("extensions/native_chord_native_failure.zig");
    try engine.bindFunction("nativeAsyncChordFailure", nativeAsyncFailure, 0);
    try engine.bindFunction("plainNativeChordFailure", plainNativeFailure, 0);
    const generation = engine.native_allocation_generation;
    const escaped = engine.evalModule("try{await nativeAsyncChordFailure()}catch(e){globalThis.nativeChordSwallowed=true}", "chord-native-fresh-escape.mjs");
    try std.testing.expectError(error.JavaScriptException, escaped);
    try std.testing.expectEqual(error.OutOfMemory, engine.nativeAllocationError(error.JavaScriptException, generation));
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const swallowed = try js.get(engine, root, "nativeChordSwallowed");
    defer engine.freeValue(swallowed);
    try std.testing.expect(em.c.JS_IsUndefined(swallowed));
    try js.define(engine, root, "oldChordNativeError", em.c.JS_DupValue(engine.context, engine.captured_exception.?));
    const stale_generation = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, engine.eval("throw oldChordNativeError", "chord-stale-native", em.c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(failure.escape(engine, error.JavaScriptException, stale_generation) == null);
    const replacement_generation = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, engine.eval("try{plainNativeChordFailure()}catch(e){throw new Error('user replacement')}", "chord-user-replacement", em.c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(failure.escape(engine, error.JavaScriptException, replacement_generation) == null);
    const lookalike_generation = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, engine.eval("globalThis.chordNativeTraps=0;throw{get name(){chordNativeTraps++;return'OutOfMemory'},get message(){chordNativeTraps++;return'out of memory'}}", "chord-user-lookalike", em.c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(failure.escape(engine, error.JavaScriptException, lookalike_generation) == null);
    const traps = try js.get(engine, root, "chordNativeTraps");
    defer engine.freeValue(traps);
    try std.testing.expect(em.c.JS_IsStrictEqual(engine.context, traps, em.c.JS_NewInt32(engine.context, 0)));
}
fn weakReference(engine: *em.Engine, target: em.c.JSValue) !em.c.JSValue {
    var args = [_]em.c.JSValue{target};
    return engine.checked(em.c.JS_CallConstructor(engine.context, engine.native_weak_ref_constructor.?, 1, &args));
}
fn weakTarget(engine: *em.Engine, reference: em.c.JSValue) !em.c.JSValue {
    return engine.checked(em.c.JS_Call(engine.context, engine.native_weak_ref_deref.?, reference, 0, null));
}
test "native latest Chord1692 inline and spilled scope roots survive GC unwind and failed spill releases its target" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const Scope = @import("extensions/native_chord_values.zig").Scope;
    const inline_target = try js.object(engine);
    const spilled_target = try js.object(engine);
    const inline_weak = try weakReference(engine, inline_target);
    defer engine.freeValue(inline_weak);
    const spilled_weak = try weakReference(engine, spilled_target);
    defer engine.freeValue(spilled_weak);
    {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        _ = try scope.keep(inline_target);
        for (0..31) |_| _ = try scope.keep(try js.object(engine));
        _ = try scope.keep(spilled_target);
        engine.finishJob();
        em.c.JS_RunGC(engine.runtime);
        const held_inline = try weakTarget(engine, inline_weak);
        defer engine.freeValue(held_inline);
        const held_spill = try weakTarget(engine, spilled_weak);
        defer engine.freeValue(held_spill);
        try std.testing.expect(em.c.JS_IsStrictEqual(engine.context, inline_target, held_inline));
        try std.testing.expect(em.c.JS_IsStrictEqual(engine.context, spilled_target, held_spill));
    }
    engine.finishJob();
    em.c.JS_RunGC(engine.runtime);
    const released_inline = try weakTarget(engine, inline_weak);
    defer engine.freeValue(released_inline);
    const released_spill = try weakTarget(engine, spilled_weak);
    defer engine.freeValue(released_spill);
    try std.testing.expect(em.c.JS_IsUndefined(released_inline) and em.c.JS_IsUndefined(released_spill));
    const failed_target = try js.object(engine);
    const failed_weak = try weakReference(engine, failed_target);
    defer engine.freeValue(failed_weak);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    {
        const original_allocator = engine.gpa;
        engine.gpa = failing.allocator();
        defer engine.gpa = original_allocator;
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        for (0..32) |_| _ = try scope.keep(try js.object(engine));
        try std.testing.expectError(error.OutOfMemory, scope.keep(failed_target));
        try std.testing.expect(failing.has_induced_failure);
    }
    engine.finishJob();
    em.c.JS_RunGC(engine.runtime);
    const released_failed = try weakTarget(engine, failed_weak);
    defer engine.freeValue(released_failed);
    try std.testing.expect(em.c.JS_IsUndefined(released_failed));
}
test "native latest Chord1692 actual Source8 object factories reload cells resource adoption signals tasks" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try replay(engine, "chord-object-reload-original-1692", "chordObjectReloadCases");
}
test "native latest Chord1692 actual Source8 full Host Connection RemoteRef RelayRef links calls state and invalidation" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try replay(engine, "chord-full-links-original-1692", "chordFullLinksCases");
}
test "native latest Chord1692 actual Source2 already closed full Host construction accept connect" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try replay(engine, "chord-full-host-closed-original-1692", "chordFullHostClosedCases");
}
test "native latest Chord1692 actual Source9 protocol2 packed bytes window acknowledgement maxCalls negatives" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    try replay(engine, "chord-v2-original-1692", "chordV2Cases");
}
const owned_start =
    \\const api=nativeLatestChordApi,log=[],host=api.createHost({name:'owned',onError(e){throw e}}),schema={type:'object',properties:{},additionalProperties:false},n={type:'number'},token=api.local('owned.counter',{version:1,input:schema,members:{read:api.method(undefined,n)}});host.serve(token,(_i,_p,self)=>{const cell=self.state('n',n,4);return{read(){return cell.value}}});const ref=host.get(token,{});await ref.ready;let resolve,started;const began=new Promise(r=>started=r),pending=host.root(async ctx=>{started();await new Promise(r=>resolve=r);return ref.read(ctx)});await Promise.race([pending,began]);globalThis.ownedLatest={host,ref,pending,resolve,log};
;
const owned_finish =
    \\const o=ownedLatest;o.resolve();if(await o.pending!==4)throw Error('owned graph lost');o.ref.release();await o.host.close();if(o.host.objects.size||o.host.connections.size)throw Error('owned teardown incomplete');delete globalThis.ownedLatest;
;
test "native latest Chord1692 actual object refs root signals and declarations survive GC then teardown" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const started = try engine.evalModule(owned_start, "chord-latest-gc-start.mjs");
    engine.freeValue(started);
    em.c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(owned_finish, "chord-latest-gc-finish.mjs");
    engine.freeValue(completed);
    em.c.JS_RunGC(engine.runtime);
}
test "native latest Chord1692 complete actual object factory root call and teardown GPA sweep" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            defer allocationBaseline(gpa, "CHORD_OBJECT_GPA_BASELINE_ALLOCATIONS");
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            const result = engine.evalModule(owned_start ++ "\n" ++ owned_finish, "chord-latest-gpa.mjs") catch |err| {
                const mapped = engine.nativeAllocationError(err, generation);
                diagnoseFailure(engine, gpa, mapped);
                return mapped;
            };
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
const composed_owned =
    \\const api=nativeLatestChordApi,empty={type:'object',properties:{},additionalProperties:false},n={type:'number'},host=api.createHost({name:'native',onError(e){throw e}}),token=api.local('native.resource',{version:1,input:empty,members:{read:api.method(undefined,n),owner:api.opaque('owner@1')}}),closes=[];const facet=version=>({name:'native',setup(f){f.serve(token,(_i,_p,self)=>{const cell=self.state('n',n,3,{version,migrate(v){return v+1}}),resource=self.resource('r',{version:1,open(){return{ok:true}},close(){closes.push(version)}});return{read(){return cell.value},owner:self.expose(resource)}})}});await host.install(facet(1));const local=host.get(token,{});await local.ready;const owner=local.owner;await host.reload([facet(2)]);if(await local.read()!==4||local.owner!==owner)throw Error('actual candidate migration/adoption failed');await host.close();local.release();if(closes.length!==1||closes[0]!==2||host.objects.size)throw Error('latest resource cleanup lost');
    \\const server=api.createHost({name:'server',onError(e){throw e}}),client=api.createHost({name:'client',kind:'client',onError(e){throw e}}),remote=api.remote('native.remote',{version:1,input:empty,variants:{live:{state:{n},methods:{add:api.method(n,n),echo:api.method({type:'string'},{type:'string'})}}}});server.serve(remote,(_i,_p,self)=>{const cell=self.state('n',n,1);return{variant:'live',n:cell,add(v,ctx){cell.change(ctx,x=>x+v);return cell.value},echo(v){return v}}});const[a,b]=api.memoryLinkPair();server.accept(a,{principal:{user:1},window:512});client.connect(b);const ref=client.get(remote,{}, {at:'server'});await ref.ready;const values=[],off=ref.n.subscribe(v=>values.push(v));if(await ref.add(2)!==3)throw Error('actual frame call failed');const payload='native-packing'.repeat(6000);if(await ref.echo(payload)!==payload)throw Error('actual native C packing lost bytes');off();await client.close();await server.close();ref.release();if(server.objects.size||server.connections.size||client.remotes.size||client.connections.size)throw Error('actual connection owner cleanup lost');
;
test "native latest Chord1692 full composed reload resources remote state frames packed C allocation and teardown GPA sweep" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            defer allocationBaseline(gpa, "CHORD_COMPOSED_GPA_BASELINE_ALLOCATIONS");
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            const result = engine.evalModule(composed_owned, "chord-latest-composed-gpa.mjs") catch |err| {
                const mapped = engine.nativeAllocationError(err, generation);
                diagnoseFailure(engine, gpa, mapped);
                return mapped;
            };
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
