//! Root-intake source-only diagnostic. Missing real methods are failures.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const assembly = @import("native_sdk_registry_private_assembly.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn run(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    assembly.setup(engine, &environment) catch |err| return engine.nativeAllocationError(err, generation);
    const replayed = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-registry-b45.input.txt"), "registry-b45-original64.mjs") catch |err| {
        std.debug.print("Real private constructor/registry64 failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return engine.nativeAllocationError(err, generation);
    };
    engine.freeValue(replayed);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const actual = try engine.stringify(try scope.get(global, "sdkSessionRegistryRows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-session-registry-b45.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "registry-b45-original64.json")));
    const raw = try engine.stringify(expected);
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual full private registry64:\n{s}\nExpected genuine b45:\n{s}\n", .{ actual, raw });
        return error.NativeRegistry64OriginalMismatch;
    }
    const disposed = engine.evalModule(
        \\if(nativeRegistryFactoryCount!==64||registryCaseReceivers.length!==64)throw Error('Full64 real native constructor inventory absent');for(const receiver of registryCaseReceivers)receiver.dispose();registryCaseReceivers.length=0;delete globalThis.sdkSessionRegistryRows;
    , "registry-private-dispose.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(disposed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = engine.eval("nativeRegistryWeak.every(ref=>ref.deref()===undefined)", "registry-private-gc.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(collected);
    if (c.JS_ToBool(engine.context, collected) != 1) return error.NativeRegistrySessionGraphRetained;
}
test "native private registry full constructor matches actual b45 Original64 and releases complete session graphs" {
    try run(std.testing.allocator);
}
test "native private registry full constructor Original64 complete allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-registry-full64", run, .{});
}
test "native private registry strict Source166 descriptors report every missing method without placeholders" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try assembly.setup(engine, &environment);
    const checked = engine.evalModule(
        \\const proto=registryNative.AgentSession.prototype,summarize=f=>({name:f.name,length:f.length,async:Object.getPrototypeOf(f)===Object.getPrototypeOf(async()=>{}),ownPrototype:Object.hasOwn(f,'prototype')}),actual=Reflect.ownKeys(proto).map(key=>{const d=Object.getOwnPropertyDescriptor(proto,key);return 'value'in d?{key,kind:'data',enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,valueType:typeof d.value,...(typeof d.value==='function'?{function:summarize(d.value)}:{})}:{key,kind:'accessor',enumerable:d.enumerable,configurable:d.configurable,...(d.get?{get:summarize(d.get)}:{}),...(d.set?{set:summarize(d.set)}:{})};});if(nativeRegistryMissingMethods.length||actual.length!==166||JSON.stringify(actual)!==JSON.stringify(registryNativePrototypeSource.descriptors))throw Error(JSON.stringify({missing:nativeRegistryMissingMethods,actual,expected:registryNativePrototypeSource.descriptors}));
    , "registry-private-strict166.mjs") catch |err| {
        std.debug.print("Strict Source166 real composition gap: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(checked);
}
