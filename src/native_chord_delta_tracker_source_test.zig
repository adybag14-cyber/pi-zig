const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
fn setup(allocator: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(allocator, .{});
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const api = try js.object(engine);
    defer engine.freeValue(api);
    try js.define(engine, api, "track", try @import("extensions/native_chord_delta_tracker.zig").function(engine));
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeDeltaTracker", c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord tracker full original Source60 classes proxies mutations and23negative cases" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const source = @embedFile("extensions/fixtures/chord-delta-tracker-original-19cb.json");
    try js.define(engine, root, "trackerSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "chord-delta-tracker-original-19cb.json")));
    const result = engine.evalModule("const api=nativeDeltaTracker;\n" ++ @embedFile("extensions/fixtures/chord-delta-tracker-original-19cb.input.txt") ++
        "\nif(deltaTrackerCases.length!==trackerSource.cases.length)throw Error('tracker case count');for(let i=0;i<deltaTrackerCases.length;i++)if(JSON.stringify(deltaTrackerCases[i])!==JSON.stringify(trackerSource.cases[i]))throw Error(JSON.stringify({case:i,actual:deltaTrackerCases[i],expected:trackerSource.cases[i]}));", "chord-delta-tracker-source.mjs") catch |err| {
        std.debug.print("Native Chord tracker Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord tracker retained graph and shared class identities survive collection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const initial = try engine.evalModule(
        \\const a=nativeDeltaTracker.track({list:[{x:1},{x:2}],kept:{y:3}}),b=nativeDeltaTracker.track({});if(Object.getPrototypeOf(a)!==Object.getPrototypeOf(b))throw Error('tracker shared prototype');const change=a.beginChange(),other=b.beginChange();if(Object.getPrototypeOf(change)!==Object.getPrototypeOf(other))throw Error('change shared prototype');const draft=change.state;draft.list.reverse();draft.list[0].x=9;globalThis.trackerGraph={a,change,draft,held:draft.list[0]};other.abort();
    , "tracker-gc-open.mjs");
    engine.freeValue(initial);
    c.JS_RunGC(engine.runtime);
    const prepare = try engine.evalModule(
        \\const r=trackerGraph;if(r.held.x!==9||r.draft.list[1].x!==1)throw Error('open graph roots');r.prepared=r.change.prepare();if(r.prepared.base.list[0].x!==1||r.prepared.value.list[0].x!==9)throw Error('materialization');let caught;try{r.held.x}catch(e){caught=e}if(!(caught instanceof TypeError))throw Error('settled holder');
    , "tracker-gc-prepared.mjs");
    engine.freeValue(prepare);
    c.JS_RunGC(engine.runtime);
    const adopt = try engine.evalModule(
        \\const r=trackerGraph;r.a.adopt(r.prepared);if(r.a.revision!==1||r.a.value!==r.prepared.value||r.a.value.list[1].x!==1)throw Error('adopt graph roots');delete globalThis.trackerGraph;
    , "tracker-gc-adopt.mjs");
    engine.freeValue(adopt);
    c.JS_RunGC(engine.runtime);
}
test "native Chord tracker all native allocation failures release full proxy graph" {
    const Probe = struct {
        fn run(allocator: std.mem.Allocator) !void {
            const engine = try setup(allocator);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const t=nativeDeltaTracker.track({items:[{x:3},{x:1},{x:2}],text:'abcdef',kept:{a:1}}),c=t.beginChange(),s=c.state;s.items.splice(1,1,{x:4},{x:5});s.items.reverse();s.items[0].x=9;s.text='defghi';const p=c.prepare();t.adopt(p);if(t.value.items.length!==4||t.value.items[0].x!==9||t.revision!==1)throw Error('tracker result');
            , "tracker-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

test "native Chord tracker failed array initialization leaves no published storage graph" {
    const tracker = @import("extensions/native_chord_delta_tracker.zig");
    for (0..2) |offset| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try setup(failing.allocator());
        defer engine.deinit();
        const change = try engine.eval("globalThis.failedArrayChange=nativeDeltaTracker.track([1,2,3]).beginChange()", "tracker-array-init-regression", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(change);
        const binding = try tracker.bindings(engine);
        const instance = try tracker.getInstance(engine, change, binding, .change);
        const context = try tracker.contextOf(engine, instance.data.change.context, binding);
        const node = context.root.?;
        try std.testing.expect(node.array == null);
        failing.fail_index = failing.alloc_index + offset;
        try std.testing.expectError(error.OutOfMemory, @import("extensions/native_chord_delta_tracker_array.zig").getArray(node));
        failing.fail_index = std.math.maxInt(usize);
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expect(node.array == null);
        c.JS_RunGC(engine.runtime);
    }
}
