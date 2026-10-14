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
    \\const api=nativeLatestChordApi,log=[],host=api.createHost({name:'owned',onError(e){throw e}}),schema={type:'object',properties:{},additionalProperties:false},n={type:'number'},token=api.local('owned.counter',{version:1,input:schema,members:{read:api.method(undefined,n)}});host.serve(token,(_i,_p,self)=>{const cell=self.state('n',n,4);return{read(){return cell.value}}});const ref=host.get(token,{});await ref.ready;let resolve;const pending=host.root(async ctx=>{await new Promise(r=>resolve=r);return ref.read(ctx)});globalThis.ownedLatest={host,ref,pending,resolve,log};
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
    \\const api=nativeLatestChordApi,empty={type:'object',properties:{},additionalProperties:false},n={type:'number'},host=api.createHost({name:'native',onError(e){throw e}}),token=api.local('native.resource',{version:1,input:empty,members:{read:api.method(undefined,n),owner:api.opaque('owner@1')}}),closes=[];const facet=version=>({name:'native',setup(f){f.serve(token,(_i,_p,self)=>{const cell=self.state('n',n,3,{version,migrate(v){return v+1}}),resource=self.resource('r',{version:1,open(){return{ok:true}},close(){closes.push(version)}});return{read(){return cell.value},owner:self.expose(resource)}})}});await host.install(facet(1));const local=host.get(token,{});await local.ready;const owner=local.owner;await host.reload([facet(2)]);if(await local.read()!==4||local.owner!==owner)throw Error('actual candidate migration/adoption failed');local.release();await host.close();if(closes.length!==1||closes[0]!==2||host.objects.size)throw Error('latest resource cleanup lost');
    \\const server=api.createHost({name:'server',onError(e){throw e}}),client=api.createHost({name:'client',kind:'client',onError(e){throw e}}),remote=api.remote('native.remote',{version:1,input:empty,variants:{live:{state:{n},methods:{add:api.method(n,n),echo:api.method({type:'string'},{type:'string'})}}}});server.serve(remote,(_i,_p,self)=>{const cell=self.state('n',n,1);return{variant:'live',n:cell,add(v,ctx){cell.change(ctx,x=>x+v);return cell.value},echo(v){return v}}});const[a,b]=api.memoryLinkPair();server.accept(a,{principal:{user:1},window:512});client.connect(b);const ref=client.get(remote,{}, {at:'server'});await ref.ready;const values=[],off=ref.n.subscribe(v=>values.push(v));if(await ref.add(2)!==3)throw Error('actual frame call failed');const payload='native-packing'.repeat(6000);if(await ref.echo(payload)!==payload)throw Error('actual native C packing lost bytes');off();ref.release();await client.close();await server.close();if(server.objects.size||server.connections.size||client.remotes.size||client.connections.size)throw Error('actual connection owner cleanup lost');
;
test "native latest Chord1692 full composed reload resources remote state frames packed C allocation and teardown GPA sweep" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
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
