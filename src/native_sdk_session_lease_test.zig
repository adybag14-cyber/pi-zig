const std = @import("std");
const sdk = @import("extensions/native_sdk.zig");
const bridge = @import("extensions/native_sdk_model_bridge.zig");
const engine_mod = @import("extensions/engine.zig");
const c = engine_mod.c;
const Input = struct { schemaVersion: u32, sourceCommit: []const u8, inputSha256: []const u8, input: []const u8 };
fn induced(gpa: std.mem.Allocator, probe: bool) !void {
    if (!probe) return;
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (failing.has_induced_failure) return error.OutOfMemory;
}
fn retired(engine: *engine_mod.Engine, gpa: std.mem.Allocator, lease: bridge.Lease, flag: *const std.atomic.Value(bool)) !void {
    const bytes = bridge.dispatchJson(engine, gpa, lease, .query, "{\"method\":\"getModels\",\"args\":[\"lease\"]}", .{ .abort_flag = flag }) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.RetiredNativeSDKModelLease, err);
        return;
    };
    defer gpa.free(bytes);
    return error.StaleSDKSessionLeaseAccepted;
}
fn evaluate(engine: *engine_mod.Engine, source: []const u8, name: [:0]const u8) !void {
    const evaluation = try engine.evalModule(source, name);
    defer engine.freeValue(evaluation);
    const settled = try engine.awaitValue(evaluation);
    engine.freeValue(settled);
}
fn exercise(gpa: std.mem.Allocator, directory: []const u8, probe: bool) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PI_AGENT_DIR", directory);
    try environment.put("HOME", directory);
    try environment.put("USERPROFILE", directory);
    try environment.put("PI_OFFLINE", "1");
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "pi-sdk-test", "session-lease.mjs" });
    try @import("extensions/native_stream.zig").install(engine);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-coding-agent", exports);
    var input = try std.json.parseFromSlice(Input, gpa, @embedFile("extensions/fixtures/sdk-session-lease-6fb2e78.input.json"), .{});
    defer input.deinit();
    try std.testing.expectEqual(@as(u32, 1), input.value.schemaVersion);
    try std.testing.expectEqualStrings("6fb2e7815167e6b19006fc526d1a5d0f5f998787", input.value.sourceCommit);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input.value.input, &hash, .{});
    try std.testing.expectEqualStrings(&std.fmt.bytesToHex(hash, .lower), input.value.inputSha256);
    try evaluate(engine, input.value.input, "sdk-session-lease-source.mjs");
    try induced(gpa, probe);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const a = try sdk.get(engine, global, "leaseSessionA");
    defer engine.freeValue(a);
    const b = try sdk.get(engine, global, "leaseSessionB");
    defer engine.freeValue(b);
    const state_a = try sdk.state(engine, a);
    const state_b = try sdk.state(engine, b);
    const lease_a = try sdk.sessionModelLease(state_a);
    const lease_b = try sdk.sessionModelLease(state_b);
    try std.testing.expect(lease_a.runtime_id != lease_b.runtime_id and lease_a.generation != lease_b.generation);
    try std.testing.expectEqual(lease_a, try sdk.sessionDataModelLease(engine, state_a.data));
    var flag: std.atomic.Value(bool) = .init(false);
    inline for (.{ .{ lease_a, "A" }, .{ lease_b, "B" } }) |case| {
        const bytes = try bridge.dispatchJson(engine, gpa, case[0], .query, "{\"method\":\"getModels\",\"args\":[\"lease\"]}", .{ .abort_flag = &flag });
        defer gpa.free(bytes);
        try induced(gpa, probe);
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
        defer parsed.deinit();
        try std.testing.expectEqualStrings("complete", parsed.value.object.get("status").?.string);
        const models = parsed.value.object.get("result").?.array.items;
        try std.testing.expectEqual(@as(usize, 1), models.len);
        try std.testing.expectEqualStrings(case[1], models[0].object.get("name").?.string);
    }
    const fresh = try sdk.invoke(engine, a, "newSession", &.{});
    defer engine.freeValue(fresh);
    const fresh_done = try engine.awaitValue(fresh);
    defer engine.freeValue(fresh_done);
    try induced(gpa, probe);
    const next_a = try sdk.sessionModelLease(state_a);
    try std.testing.expectEqual(lease_a.runtime_id, next_a.runtime_id);
    try std.testing.expect(lease_a.generation != next_a.generation);
    try retired(engine, gpa, lease_a, &flag);
    const disposed = try sdk.invoke(engine, a, "dispose", &.{});
    engine.freeValue(disposed);
    try induced(gpa, probe);
    _ = sdk.sessionModelLease(state_a) catch |err| {
        try std.testing.expectEqual(error.NativeSDKDisposed, err);
        try retired(engine, gpa, next_a, &flag);
        try runtimeReplacement(engine, gpa, &flag, probe);
        try gcCycle(engine, gpa, &flag, probe);
        return;
    };
    return error.DisposedSDKSessionGetterAccepted;
}
fn noDispose(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn runtimeReplacement(engine: *engine_mod.Engine, gpa: std.mem.Allocator, flag: *const std.atomic.Value(bool), probe: bool) !void {
    try evaluate(engine,
        \\import {createAgentSessionRuntime,createAgentSession,SettingsManager,SessionManager,DefaultResourceLoader} from '@earendil-works/pi-coding-agent';
        \\const r=globalThis.leaseSessionB.modelRuntime;const factory=async target=>{const loader=new DefaultResourceLoader({cwd:process.cwd(),agentDir:process.env.PI_AGENT_DIR,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true,systemPromptOverride:()=>''});await loader.reload();return {...await createAgentSession({modelRuntime:r,model:r.getModel('lease','m'),settingsManager:SettingsManager.inMemory(),sessionManager:target.sessionManager,resourceLoader:loader,tools:[]}),services:{cwd:process.cwd(),agentDir:process.env.PI_AGENT_DIR},diagnostics:[]}};globalThis.sessionLeaseOwner=await createAgentSessionRuntime(factory,{cwd:process.cwd(),agentDir:process.env.PI_AGENT_DIR,sessionManager:SessionManager.inMemory()});globalThis.sessionLeaseOwner.setBeforeSessionInvalidate(()=>{throw new Error('keep previous lease')});
    , "sdk-session-lease-runtime.mjs");
    try induced(gpa, probe);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const runtime = try sdk.get(engine, global, "sessionLeaseOwner");
    defer engine.freeValue(runtime);
    const previous = try sdk.get(engine, runtime, "session");
    defer engine.freeValue(previous);
    const old_state = try sdk.state(engine, previous);
    const lease = try sdk.sessionModelLease(old_state);
    const invalid = sdk.invoke(engine, runtime, "newSession", &.{}) catch |err| blocked: {
        try induced(gpa, probe);
        if (err != error.JavaScriptException) return err;
        break :blocked c.pi_js_undefined();
    };
    engine.freeValue(invalid);
    try std.testing.expectEqual(lease, try sdk.sessionModelLease(old_state));
    const cleared = try sdk.invoke(engine, runtime, "setBeforeSessionInvalidate", &.{c.pi_js_undefined()});
    engine.freeValue(cleared);
    try sdk.put(engine, previous, "dispose", try engine.checked(c.JS_NewCFunction(engine.context, noDispose, "overriddenDispose", 0)));
    const replacing = try sdk.invoke(engine, runtime, "newSession", &.{});
    defer engine.freeValue(replacing);
    const replacement = try engine.awaitValue(replacing);
    engine.freeValue(replacement);
    try induced(gpa, probe);
    try retired(engine, gpa, lease, flag);
    const next = try sdk.get(engine, runtime, "session");
    defer engine.freeValue(next);
    const next_lease = try sdk.sessionModelLease(try sdk.state(engine, next));
    try std.testing.expect(next_lease.generation != lease.generation and next_lease.runtime_id == lease.runtime_id);
    const stopped = try sdk.invoke(engine, runtime, "dispose", &.{});
    engine.freeValue(stopped);
    try induced(gpa, probe);
    try retired(engine, gpa, next_lease, flag);
}
fn gcCycle(engine: *engine_mod.Engine, gpa: std.mem.Allocator, flag: *const std.atomic.Value(bool), probe: bool) !void {
    try evaluate(engine,
        \\import {ModelRuntime,createAgentSession,SessionManager,SettingsManager,DefaultResourceLoader} from '@earendil-works/pi-coding-agent';
        \\await (async()=>{const r=await ModelRuntime.create({modelsPath:null,refreshOnCreate:false,credentials:{read:async()=>undefined,list:async()=>[]}}),m={id:'m',provider:'gc',name:'GC',api:'fixture',baseUrl:'https://fixture.invalid',reasoning:false,input:['text'],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:4096,maxTokens:512};const loader=new DefaultResourceLoader({cwd:process.cwd(),agentDir:process.env.PI_AGENT_DIR,noExtensions:true,noSkills:true,noPromptTemplates:true,noThemes:true,noContextFiles:true,systemPromptOverride:()=>''});await loader.reload();const {session}=await createAgentSession({modelRuntime:r,model:m,settingsManager:SettingsManager.inMemory(),sessionManager:SessionManager.inMemory(),resourceLoader:loader,tools:[]});r.registerNativeProvider({id:'gc',auth:{},getModels(){return session.model ? [m] : []}});await r.refresh({providers:['gc'],allowNetwork:false});globalThis.gcLeaseSession=session})();globalThis.gcMapDeleteCalls=0;const original=Map.prototype.delete;globalThis.restoreLeaseMap=()=>{Map.prototype.delete=original};Map.prototype.delete=function(...args){globalThis.gcMapDeleteCalls++;return original.apply(this,args)};
    , "sdk-session-lease-gc.mjs");
    try induced(gpa, probe);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const actor = try sdk.get(engine, global, "gcLeaseSession");
    const owner = try sdk.state(engine, actor);
    const lease = try sdk.sessionModelLease(owner);
    try sdk.put(engine, global, "gcLeaseSession", c.pi_js_undefined());
    engine.freeValue(actor);
    c.JS_RunGC(engine.runtime);
    const calls = try sdk.get(engine, global, "gcMapDeleteCalls");
    defer engine.freeValue(calls);
    var count: i32 = -1;
    if (c.JS_ToInt32(engine.context, &count, calls) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 0), count);
    const restored = try sdk.invoke(engine, global, "restoreLeaseMap", &.{});
    engine.freeValue(restored);
    try retired(engine, gpa, lease, flag);
}
test "SDK session model lease binds exact Source runtime rotates disposes and finalizes cycles without JS" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    try exercise(std.testing.allocator, path[0..count], false);
}
test "SDK session model lease every host allocation releases factory anchor rotation retirement and GC" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &path);
    const Probe = struct {
        fn run(gpa: std.mem.Allocator, directory: []const u8) !void {
            exercise(gpa, directory, true) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.JavaScriptException)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try @import("test_support/sdk_allocation_shards.zig").check("session-model-lease", Probe.run, .{path[0..count]});
}
