const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
fn setup(gpa: std.mem.Allocator) !*em.Engine {
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
    return engine;
}
fn unpack(engine: *em.Engine, _: em.c.JSValue, args: []const em.c.JSValue, captures: []const em.c.JSValue) !em.c.JSValue {
    var scope: @import("extensions/native_chord_host_values.zig").Scope = .{ .engine = engine };
    defer scope.deinit();
    return scope.result(try @import("extensions/native_chord_packing.zig").unpack(&scope, captures[0], if (args.len > 0) args[0] else em.c.pi_js_undefined()));
}
fn replay(engine: *em.Engine, comptime stem: []const u8, comptime global: []const u8) !void {
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
test "native latest Chord1692 compiled selected inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_LATEST_COMPILED_INVENTORY={s}\n", .{encoded});
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
            const result = engine.evalModule(owned_start ++ "\n" ++ owned_finish, "chord-latest-gpa.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
