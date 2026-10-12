const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const context = @import("extensions/native_durable_context.zig");
const c = em.c;
test "native Chord Context actual19cb classes live values cancellation and waiter executor outcomes" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try context.install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/chord-context-original-19cb.json");
    try sdk.put(engine, root, "contextSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "chord-context-original-19cb.json")));
    const result = engine.evalModule("import*as ctx from'@earendil-works/chord/context';\n" ++ @embedFile("extensions/fixtures/chord-context-original-19cb.input.txt") ++
        "\nif(chordContextCases.length!==contextSource.cases.length)throw Error('Chord Context Source case count');for(let i=0;i<chordContextCases.length;i++)if(JSON.stringify(chordContextCases[i])!==JSON.stringify(contextSource.cases[i]))throw Error(JSON.stringify({case:i,actual:chordContextCases[i],expected:contextSource.cases[i]}));", "chord-context-source.mjs") catch |err| {
        std.debug.print("Native Chord Context Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord Context private state keeps parent key and value alive across owner collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try context.install(engine);
    const first = try engine.evalModule(
        \\import{BACKGROUND_CONTEXT,createContextKey,withContextValue,withCancel,withoutAbortSignal}from'@earendil-works/chord/context';
        \\const key=createContextKey('retained'),value={alive:71},parent=withContextValue(key,value,BACKGROUND_CONTEXT),child=withCancel(parent),clean=withoutAbortSignal(child.context);
        \\globalThis.contextRetained={key,child,clean};
    , "chord-context-retention.mjs");
    engine.freeValue(first);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.eval(
        \\const r=contextRetained;r.child.cancel(new Error('stop'));if(r.clean.abortSignal!==undefined||r.clean.value(r.key).alive!==71||r.child.context.value(r.key)!==r.clean.value(r.key))throw Error('private context roots lost');delete globalThis.contextRetained;
    , "chord-context-retention-check.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
test "native Chord Context constructors installation and private roots release every allocator failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{});
            defer engine.deinit();
            engine.native_io = std.testing.io;
            try context.install(engine);
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\import{BACKGROUND_CONTEXT,createContextKey,withContextValue,withCancel,withoutAbortSignal}from'@earendil-works/chord/context';
                \\const key=createContextKey('owner'),value={n:1},child=withCancel(withContextValue(key,value,BACKGROUND_CONTEXT));const clean=withoutAbortSignal(child.context);if(clean.value(key)!==value)throw Error('context changed');child.cancel();
            , "chord-context-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
test {
    _ = @import("extensions/native_durable_storage_context_test.zig");
}
