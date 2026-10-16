//! Proposal only: copy to src/native_async_from_sync_api_test.zig after peer
//! review and Root composition approval. Requires the qualified AF C packet
//! plus proposed JS_PiGetAsyncIterator; not part of any active build target.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const af = @import("extensions/native_async_function.zig");
const body = @import("extensions/native_async_body.zig");
const Stage = enum(c_int) { next, visit, close };
fn finish(scope: *Scope, job: c.JSValue, kind: c.JSValue) !af.Action {
    const result = try scope.object();
    try scope.put(result, "kind", kind);
    try scope.put(result, "values", try scope.get(job, "values"));
    return .{ .returned = c.JS_DupValue(scope.engine.context, result) };
}
fn closed(scope: *Scope, job: c.JSValue) !af.Action {
    if (scope.truthy(try scope.get(job, "closeThrow"))) return .{ .thrown = c.JS_DupValue(scope.engine.context, try scope.get(job, "closeReason")) };
    return finish(scope, job, try scope.get(job, "closeKind"));
}
fn wait(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !af.Action {
    try body.wait(scope, job, value, @intFromEnum(stage));
    return body.action(scope, job);
}
fn next(scope: *Scope, job: c.JSValue) !af.Action {
    try scope.put(job, "phase", try scope.text("step"));
    return wait(scope, job, try scope.call(try scope.get(job, "nextMethod"), try scope.get(job, "iterator"), &.{}), .next);
}
fn close(scope: *Scope, job: c.JSValue, reason: c.JSValue, thrown: bool, kind: []const u8) anyerror!af.Action {
    try scope.put(job, "phase", try scope.text("close"));
    try scope.put(job, "closeThrow", c.JS_NewBool(scope.engine.context, thrown));
    try scope.put(job, "closeReason", reason);
    try scope.put(job, "closeKind", try scope.text(kind));
    const iterator = try scope.get(job, "iterator");
    const method = try scope.get(iterator, "return");
    if (v.nullish(method)) return closed(scope, job);
    return wait(scope, job, try scope.call(method, iterator, &.{}), .close);
}
fn consume(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    return step(engine, args, slot, completion, input) catch |err| {
        const failure = try body.failure(engine, err);
        if (!c.JS_IsObject(slot.*)) return failure;
        const reason = switch (failure) { .thrown => |value| value, else => unreachable };
        defer engine.freeValue(reason);
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const phase = try scope.get(slot.*, "phase");
        if (try v.eq(&scope, phase, "body")) return close(&scope, slot.*, reason, true, "normal") catch |close_err| {
            const close_failure = try body.failure(engine, close_err);
            switch (close_failure) { inline else => |value| engine.freeValue(value) }
            return closed(&scope, slot.*);
        };
        if (try v.eq(&scope, phase, "close") and scope.truthy(try scope.get(slot.*, "closeThrow"))) return closed(&scope, slot.*);
        return .{ .thrown = c.JS_DupValue(engine.context, reason) };
    };
}
fn step(engine: *v.em.Engine, args: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const job = try body.init(&scope, slot);
        try scope.put(job, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
        try scope.put(job, "values", try scope.array());
        try scope.put(job, "phase", try scope.text("acquire"));
        const iterator = try scope.own(try engine.checked(c.JS_PiGetAsyncIterator(engine.context, args[0])));
        try scope.put(job, "iterator", iterator);
        try scope.put(job, "nextMethod", try scope.get(iterator, "next"));
        return next(&scope, job);
    }
    const job = slot.*;
    if (completion == .rejected) {
        var generation: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &generation, try scope.get(job, "generation")) < 0) return v.js.capture(engine);
        try body.rethrowRecognizedAllocation(engine, input, generation);
    }
    const stage: Stage = @enumFromInt(try body.stage(&scope, job));
    if (stage == .close) {
        if (scope.truthy(try scope.get(job, "closeThrow"))) return closed(&scope, job);
        if (completion == .rejected) return .{ .thrown = c.JS_DupValue(engine.context, input) };
        if (!c.JS_IsObject(input)) return v.js.typeError(engine, "Iterator close result is not an object");
        return closed(&scope, job);
    }
    if (completion == .rejected) {
        if (stage == .visit) return close(&scope, job, input, true, "normal");
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    if (stage == .next) {
        if (!c.JS_IsObject(input)) return v.js.typeError(engine, "Iterator result is not an object");
        if (scope.truthy(try scope.get(input, "done"))) return finish(&scope, job, try scope.text("normal"));
        const value = try scope.get(input, "value");
        try scope.put(job, "phase", try scope.text("body"));
        const values = try scope.get(job, "values");
        _ = try scope.invoke(values, "push", &.{value});
        return wait(&scope, job, try scope.call(args[2], c.pi_js_undefined(), &.{ value, try scope.get(values, "length") }), .visit);
    }
    if (try v.eq(&scope, args[1], "throw")) return close(&scope, job, args[3], true, "normal");
    if (try v.eq(&scope, args[1], "break")) return close(&scope, job, c.pi_js_undefined(), false, "normal");
    if (try v.eq(&scope, args[1], "return")) return close(&scope, job, c.pi_js_undefined(), false, "return");
    return next(&scope, job);
}
fn acquire(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_PiGetAsyncIterator(engine.context, args[0]));
}
fn collect(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
fn install(engine: *v.em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "nativeConsume", try scope.own(try af.createResumable(engine, "consume", 4, consume, &.{})));
    try scope.put(global, "nativeAcquire", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "getAsyncIterator", 1, acquire, &.{})));
    try scope.put(global, "nativeCollectGC", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "collectGC", 0, collect, &.{})));
}
test "proposed genuine async iterator acquisition matches native language for await controls" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const result = try engine.evalModule(@embedFile("extensions/fixtures/async-from-sync-language-consumer.input.txt") ++ @embedFile("extensions/fixtures/async-from-sync-for-await-callers.input.txt") ++
        \\const language=await observeForAwait(consume),native=await observeForAwait(nativeConsume);globalThis.proposedAsyncFromSync={language,native};if(JSON.stringify(language)!==JSON.stringify(native))throw Error(JSON.stringify({language,native}));export const checked=true;
    , "proposed-async-from-sync-for-await-controls.mjs");
    engine.freeValue(result);
}
fn ownership(engine: *v.em.Engine) !void {
    const result = try engine.evalModule(
        \\let expected;const wrapper=(()=>{const marker={owned:'retained'},iterator={get next(){return function(){return {done:false,value:marker}}}};expected=marker;const source={[Symbol.iterator](){return iterator}},retained=nativeAcquire(source);Object.defineProperty(iterator,'next',{value(){throw Error('must use retained next')}});return retained})();nativeCollectGC();const item=await wrapper.next();if(item.value!==expected||item.done)throw Error('GC must mark retained next and sync iterator');let wrong;try{await wrapper.next.call({})}catch(error){wrong=error}if(!(wrong instanceof TypeError))throw Error('Real AsyncFromSync receiver brand');let release;const value={owned:'pending'},pendingWrapper=nativeAcquire({[Symbol.iterator](){return {next(){return {done:false,value:new Promise(resolve=>release=resolve)}}}}}),pending=pendingWrapper.next();nativeCollectGC();release(value);if((await pending).value!==value)throw Error('GC pending intrinsic Promise unwrap');nativeCollectGC();export const retained=true;
    , "proposed-async-from-sync-retained-roots.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "proposed actual engine async from sync roots survive GC and host allocation failures" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try v.em.Engine.init(gpa, .{});
            defer engine.deinit();
            const start = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, start);
            ownership(engine) catch |err| return engine.nativeAllocationError(err, start);
        }
    };
    try Probe.run(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
